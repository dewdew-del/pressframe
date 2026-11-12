import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/geometry.dart';
import '../../engine/renderer.dart';
import '../../models/template.dart';
import '../../session.dart';
import '../theme.dart';
import 'preview_view.dart';

const _minSide = 0.05; // smallest crop, as a fraction of the photo

/// [rect] shifted by [delta], kept fully inside [bounds]. All normalized.
Rect moveCrop(Rect rect, Offset delta, Rect bounds) {
  double limit(double d, double low, double high) => d.clamp(low, math.max(low, high)).toDouble();
  return rect.shift(
    Offset(
      limit(delta.dx, bounds.left - rect.left, bounds.right - rect.right),
      limit(delta.dy, bounds.top - rect.top, bounds.bottom - rect.bottom),
    ),
  );
}

/// [rect] with one [corner] dragged to [pointer]; the opposite corner stays put.
/// With [aspect] (pixel width / height) the shape is locked. Stays inside [bounds].
Rect resizeCrop(
  Rect rect,
  Alignment corner,
  Offset pointer,
  Rect bounds,
  Size photo,
  double? aspect,
) {
  final sx = corner.x, sy = corner.y; // +1 = right/bottom, -1 = left/top
  final anchor = Offset(sx > 0 ? rect.left : rect.right, sy > 0 ? rect.top : rect.bottom);
  final maxW = sx > 0 ? bounds.right - anchor.dx : anchor.dx - bounds.left;
  final maxH = sy > 0 ? bounds.bottom - anchor.dy : anchor.dy - bounds.top;
  var w = ((pointer.dx - anchor.dx) * sx).clamp(_minSide, math.max(_minSide, maxW)).toDouble();
  var h = ((pointer.dy - anchor.dy) * sy).clamp(_minSide, math.max(_minSide, maxH)).toDouble();
  if (aspect != null) {
    h = w * photo.width / aspect / photo.height;
    final k = math.min(1.0, math.min(maxW / w, maxH / h));
    w *= k;
    h *= k;
  }
  return Rect.fromLTWH(sx > 0 ? anchor.dx : anchor.dx - w, sy > 0 ? anchor.dy : anchor.dy - h, w, h);
}

/// Shows the whole rotated photo with a crop rectangle to drag (inside) or resize (corners).
/// When [aspect] is set (the output shape has one) the rectangle keeps that shape.
class CropView extends StatefulWidget {
  final Session session;
  final Renderer? renderer; // null in widget tests
  final double? aspect;
  final int longEdge;

  const CropView({
    super.key,
    required this.session,
    required this.renderer,
    this.aspect,
    this.longEdge = 2048,
  });

  @override
  State<CropView> createState() => _CropViewState();
}

class _CropViewState extends State<CropView> {
  Alignment? _corner; // corner being resized; null while moving
  Rect? _startRect;
  Offset? _startPointer; // normalized

  static const _corners = [
    Alignment.topLeft,
    Alignment.topRight,
    Alignment.bottomLeft,
    Alignment.bottomRight,
  ];

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return PhotoLoader(
      session: session,
      enabled: widget.renderer != null,
      longEdge: widget.longEdge,
      builder: (context, image) => LayoutBuilder(
        builder: (context, constraints) => ListenableBuilder(
          listenable: Listenable.merge([session, session.liveEdit]),
          builder: (context, _) {
            final item = session.selected;
            if (item == null) return const SizedBox.expand();
            final oriented = orientedSize(item.width, item.height, item.quarterTurns);
            final box = constraints.biggest.shortestSide > 96
                ? constraints.biggest - const Offset(48, 48) as Size
                : constraints.biggest;
            final fitted = fitSize(box, oriented.width / oriented.height);
            final photo = Alignment.center.inscribe(fitted, Offset.zero & constraints.biggest);
            final bounds = insetForStraighten(oriented, item.straighten);
            final rect = exportCrop(item, widget.aspect);

            Offset normalized(Offset local) => Offset(
              (local.dx - photo.left) / photo.width,
              (local.dy - photo.top) / photo.height,
            );
            Offset pixels(Offset n) =>
                Offset(photo.left + n.dx * photo.width, photo.top + n.dy * photo.height);

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) {
                final p = d.localPosition;
                _corner = null;
                for (final c in _corners) {
                  if ((pixels(c.withinRect(rect)) - p).distance < 28) _corner = c;
                }
                final inside = rect.contains(normalized(p));
                _startRect = _corner != null || inside ? rect : null;
                _startPointer = normalized(p);
              },
              onPanUpdate: (d) {
                final start = _startRect;
                if (start == null) return;
                final p = normalized(d.localPosition);
                final next = _corner == null
                    ? moveCrop(start, p - _startPointer!, bounds)
                    : resizeCrop(start, _corner!, p, bounds, oriented, widget.aspect);
                session.updateLive((i) => i.copyWith(crop: () => next), commit: false);
              },
              onPanEnd: (_) {
                if (_startRect != null) session.updateLive((i) => i, commit: true);
                _startRect = null;
              },
              child: CustomPaint(
                size: Size.infinite,
                painter: _CropPainter(
                  session: session,
                  renderer: widget.renderer,
                  image: image,
                  photo: photo,
                  rect: Rect.fromPoints(pixels(rect.topLeft), pixels(rect.bottomRight)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final Session session;
  final Renderer? renderer;
  final ui.Image? image;
  final Rect photo, rect; // widget pixels

  _CropPainter({
    required this.session,
    required this.renderer,
    required this.image,
    required this.photo,
    required this.rect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final item = session.selected;
    if (item != null && renderer != null && image != null) {
      canvas.save();
      canvas.translate(photo.left, photo.top);
      renderer!.paintJob(
        canvas,
        RenderJob(
          source: image!,
          edit: item.edit,
          quarterTurns: item.quarterTurns,
          straighten: item.straighten,
          crop: const Rect.fromLTWH(0, 0, 1, 1),
          outputSize: photo.size,
          template: null,
          assets: const {},
          creditText: null,
          credit: const CreditStyle(),
        ),
      );
      canvas.restore();
    } else {
      canvas.drawRect(photo, Paint()..color = const Color(0xFF3A3A3A));
    }
    // Dim what will be cut away.
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(photo), Path()..addRect(rect)),
      Paint()..color = const Color(0xA0000000),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white;
    canvas.drawRect(rect, line);
    final thirds = Paint()..color = const Color(0x66FFFFFF);
    for (final t in [1 / 3, 2 / 3]) {
      canvas.drawLine(rect.topLeft + Offset(rect.width * t, 0), rect.bottomLeft + Offset(rect.width * t, 0), thirds);
      canvas.drawLine(rect.topLeft + Offset(0, rect.height * t), rect.topRight + Offset(0, rect.height * t), thirds);
    }
    for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      canvas.drawCircle(c, 7, Paint()..color = accentColor);
      canvas.drawCircle(c, 7, line);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => true;
}
