import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/decode.dart';
import '../../engine/geometry.dart';
import '../../engine/renderer.dart';
import '../../models/batch_item.dart';
import '../../models/edit_params.dart';
import '../../models/template.dart';
import '../../session.dart';

/// The crop a photo will be exported with (normalized, on the rotated photo).
Rect exportCrop(BatchItem item, double? aspect) => effectiveCrop(
  orientedSize(item.width, item.height, item.quarterTurns),
  aspect,
  item.crop,
  item.straighten,
);

/// The largest size with [aspect] (width / height) that fits inside [box].
Size fitSize(Size box, double aspect) => box.width / box.height > aspect
    ? Size(box.height * aspect, box.height)
    : Size(box.width, box.width / aspect);

/// Decodes the selected photo at preview size and hands it to [builder].
/// Shows the empty state, the file name while loading, or the reason a photo can't open.
class PhotoLoader extends StatefulWidget {
  final Session session;
  final bool enabled; // false in widget tests (no renderer): never touches the disk
  final int longEdge; // 2048 on Windows, 1280 on Android
  final Widget Function(BuildContext context, ui.Image? image) builder;

  const PhotoLoader({
    super.key,
    required this.session,
    required this.builder,
    this.enabled = true,
    this.longEdge = 2048,
  });

  @override
  State<PhotoLoader> createState() => _PhotoLoaderState();
}

class _PhotoLoaderState extends State<PhotoLoader> {
  ui.Image? _image;
  String? _path, _error;

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
    super.dispose();
  }

  Future<void> _onSession() async {
    final path = widget.session.selected?.path;
    if (path == _path) return;
    final first = _path == null && _image == null && _error == null;
    _path = path;
    if (!widget.enabled || path == null) {
      if (!first) _show(null, null);
      return;
    }
    try {
      final image = await decodeImage(path, maxLongEdge: widget.longEdge);
      if (!mounted || _path != path) return image.dispose(); // user moved on meanwhile
      _show(image, null);
    } on DecodeFailure catch (e) {
      if (mounted && _path == path) _show(null, e.reason);
    }
  }

  void _show(ui.Image? image, String? error) {
    if (!mounted) return;
    setState(() {
      _image?.dispose();
      _image = image;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      if (widget.session.selected == null) {
        return const Center(child: Text('Drop photos here or click Add photos'));
      }
      if (_error != null) return Center(child: Text("Can't open this photo. $_error"));
      if (widget.enabled && _image == null) {
        return Center(child: Text(_path?.split(RegExp(r'[\\/]')).last ?? ''));
      }
      return widget.builder(context, _image);
    },
  );
}

/// The selected photo with its edit applied, live. Wheel or pinch zooms, drag pans,
/// long-press shows the photo before editing.
class PreviewView extends StatefulWidget {
  final Session session;
  final Renderer? renderer; // null in widget tests: shows a placeholder
  final int longEdge;

  const PreviewView({super.key, required this.session, required this.renderer, this.longEdge = 2048});

  @override
  State<PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<PreviewView> {
  final _zoom = TransformationController();
  String? _path;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session, renderer = widget.renderer;
    return PhotoLoader(
      session: session,
      enabled: renderer != null,
      longEdge: widget.longEdge,
      builder: (context, image) {
        if (renderer == null || image == null) return const SizedBox.expand();
        if (_path != session.selected?.path) {
          _path = session.selected?.path;
          _zoom.value = Matrix4.identity(); // a new photo starts unzoomed
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
      },
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
    final fitted = fitSize(size, (crop.width * oriented.width) / (crop.height * oriented.height));
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
