import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/decode.dart';
import '../../engine/geometry.dart';
import '../../engine/renderer.dart';
import '../../models/batch_item.dart';
import '../../models/edit_params.dart';
import '../../models/template.dart';
import '../../session.dart';

/// Builds the render job for one photo at a given output size. The preview, the review
/// grid and the exporter all go through here, so they cannot drift apart.
typedef JobBuilder = RenderJob Function(BatchItem item, ui.Image source, Size outputSize, Rect crop);

/// The crop a photo will be exported with (normalized, on the rotated photo).
Rect exportCrop(BatchItem item, double? aspect) =>
    cropForShape(orientedSize(item.width, item.height, item.quarterTurns), aspect, item.crop);

/// The selected photo with its edit applied, live. Wheel or pinch zooms, drag pans.
class PreviewView extends StatefulWidget {
  final Session session;
  final Renderer? renderer; // null in widget tests: shows a placeholder
  final int longEdge; // 2048 on Windows, 1280 on Android

  const PreviewView({super.key, required this.session, required this.renderer, this.longEdge = 2048});

  @override
  State<PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<PreviewView> {
  ui.Image? _image;
  String? _path, _error;
  final _zoom = TransformationController();

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    _onSession();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    _image?.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _onSession() async {
    final path = widget.session.selected?.path;
    if (path == _path) return;
    _path = path;
    _zoom.value = Matrix4.identity();
    if (widget.renderer == null) return;
    if (path == null) return _show(null, null);
    try {
      final image = await decodeImage(path, maxLongEdge: widget.longEdge);
      if (!mounted || _path != path) return image.dispose(); // user moved on meanwhile
      _show(image, null);
    } on DecodeFailure catch (e) {
      if (mounted && _path == path) _show(null, e.reason);
    }
  }

  void _show(ui.Image? image, String? error) => setState(() {
    _image?.dispose();
    _image = image;
    _error = error;
  });

  @override
  Widget build(BuildContext context) {
    final session = widget.session, renderer = widget.renderer;
    if (session.selected == null) {
      return const Center(child: Text('Drop photos here or click Add photos'));
    }
    if (_error != null) return Center(child: Text("Can't open this photo. $_error"));
    final image = _image;
    if (renderer == null || image == null) {
      return Center(child: Text(_path?.split(RegExp(r'[\\/]')).last ?? ''));
    }
    return GestureDetector(
      onLongPressStart: (_) => session.showBefore.value = true,
      onLongPressEnd: (_) => session.showBefore.value = false,
      child: InteractiveViewer(
        transformationController: _zoom,
        maxScale: 8,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: _PreviewPainter(session, renderer, image),
          ),
        ),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final Session session;
  final Renderer renderer;
  final ui.Image image;

  _PreviewPainter(this.session, this.renderer, this.image)
    : super(repaint: Listenable.merge([session, session.liveEdit, session.showBefore]));

  @override
  void paint(Canvas canvas, Size size) {
    final item = session.selected;
    if (item == null || size.isEmpty) return;
    final oriented = orientedSize(item.width, item.height, item.quarterTurns);
    final crop = exportCrop(item, null);
    final aspect = (crop.width * oriented.width) / (crop.height * oriented.height);
    final fitted = size.width / size.height > aspect
        ? Size(size.height * aspect, size.height)
        : Size(size.width, size.width / aspect);
    canvas.translate((size.width - fitted.width) / 2, (size.height - fitted.height) / 2);
    renderer.paintJob(
      canvas,
      RenderJob(
        source: image,
        edit: session.showBefore.value ? EditParams.neutral : item.edit,
        quarterTurns: item.quarterTurns,
        straighten: item.straighten,
        crop: crop,
        outputSize: fitted,
        template: null,
        assets: const {},
        creditText: null,
        credit: const CreditStyle(),
      ),
    );
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.image != image;
}
