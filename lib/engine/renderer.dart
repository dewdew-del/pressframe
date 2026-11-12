import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../models/edit_params.dart';
import '../models/template.dart';

/// Everything needed to draw one photo. The preview and the exporter build the same job at
/// different sizes, which is what keeps them identical.
class RenderJob {
  /// Must come from the image codec or from pixels (decodeImage does this), never from
  /// Picture.toImage: on Impeller (Android) the shader samples drawn images upside down.
  final ui.Image source;
  final EditParams edit;
  final int quarterTurns;
  final double straighten; // degrees, clockwise
  final Rect crop; // normalized on the rotated photo, from cropForShape
  final Size outputSize; // pixels
  final Template? template;
  final Map<String, ui.Image> assets; // keyed by LogoLayer.file / FrameTemplate.file
  final String? creditText;
  final CreditStyle credit;

  const RenderJob({
    required this.source,
    required this.edit,
    required this.quarterTurns,
    required this.straighten,
    required this.crop,
    required this.outputSize,
    required this.template,
    required this.assets,
    required this.creditText,
    required this.credit,
  });
}

class Renderer {
  Renderer._(ui.FragmentProgram program) : _shader = program.fragmentShader();

  final ui.FragmentShader _shader;

  /// Loads the shader once for the whole app.
  static Future<Renderer> load() async =>
      Renderer._(await ui.FragmentProgram.fromAsset('shaders/adjust.frag'));

  /// Maps an output pixel to a source texture coordinate (0..1):
  /// output -> crop on the rotated photo -> undo straighten -> undo quarter turns.
  static Matrix4 sourceMatrix(RenderJob job) {
    final w = job.source.width.toDouble(), h = job.source.height.toDouble();
    final turns = job.quarterTurns % 4;
    final ow = turns.isOdd ? h : w, oh = turns.isOdd ? w : h; // rotated photo size
    final undoTurns = switch (turns) {
      1 => Matrix4(0, -1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, h, 0, 1), // x = Qy, y = h - Qx
      2 => Matrix4(-1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, w, h, 0, 1),
      3 => Matrix4(0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0, w, 0, 0, 1), // x = w - Qy, y = Qx
      _ => Matrix4.identity(),
    };
    return Matrix4.diagonal3Values(1 / w, 1 / h, 1)
      ..multiply(undoTurns)
      ..translateByDouble(ow / 2, oh / 2, 0, 1)
      ..rotateZ(-job.straighten * math.pi / 180)
      ..translateByDouble(-ow / 2, -oh / 2, 0, 1)
      ..scaleByDouble(ow, oh, 1, 1)
      ..translateByDouble(job.crop.left, job.crop.top, 0, 1)
      ..scaleByDouble(
        job.crop.width / job.outputSize.width,
        job.crop.height / job.outputSize.height,
        1,
        1,
      );
  }

  /// Draws the job into (0,0)-(outputSize) of [canvas].
  void paintJob(Canvas canvas, RenderJob job) {
    final m = sourceMatrix(job).storage;
    final e = job.edit;
    // Sharpen reaches 1/2048 of the output's long edge, measured in source coordinates,
    // so it looks the same whatever the source and output sizes are.
    final step = math.max(job.outputSize.width, job.outputSize.height) / 2048.0;
    double reach(double a, double b) => step * math.sqrt(a * a + b * b);
    final values = [
      m[0], m[4], m[12], reach(m[0], m[4]),
      m[1], m[5], m[13], reach(m[1], m[5]),
      e.exposure, e.contrast, e.highlights, e.shadows,
      e.temperature, e.tint, e.saturation, e.vibrance,
      e.sharpen, 0.0, 0.0, 0.0,
    ];
    for (var i = 0; i < values.length; i++) {
      _shader.setFloat(i, values[i]);
    }
    _shader.setImageSampler(0, job.source, filterQuality: ui.FilterQuality.low);
    canvas.drawRect(Offset.zero & job.outputSize, Paint()..shader = _shader);
    _paintOverlay(canvas, job);
  }

  /// Branding on top of the photo: gradient band(s) then logos, or the frame PNG; then the
  /// photo credit. Everything is sized from the output, so it looks the same at any size.
  void _paintOverlay(Canvas canvas, RenderJob job) {
    final size = job.outputSize;
    final full = Offset.zero & size;
    canvas.save();
    canvas.clipRect(full);
    Paint image(double opacity) => Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, opacity);

    switch (job.template) {
      case BuiltTemplate t:
        final band = t.band;
        if (band != null && band.heightFraction > 0 && band.opacity > 0) {
          if (band.edge != BandEdge.bottom) _paintBand(canvas, size, band, top: true);
          if (band.edge != BandEdge.top) _paintBand(canvas, size, band, top: false);
        }
        for (final logo in t.logos) {
          final picture = job.assets[logo.file];
          if (picture == null) continue; // missing file: the template is drawn without it
          final w = logo.widthFraction * size.width;
          canvas.drawImageRect(
            picture,
            Rect.fromLTWH(0, 0, picture.width.toDouble(), picture.height.toDouble()),
            Rect.fromCenter(
              center: Offset(logo.cx * size.width, logo.cy * size.height),
              width: w,
              height: w * picture.height / picture.width,
            ),
            image(logo.opacity),
          );
        }
      case FrameTemplate t:
        final picture = job.assets[t.file];
        if (picture != null) {
          canvas.drawImageRect(
            picture,
            Rect.fromLTWH(0, 0, picture.width.toDouble(), picture.height.toDouble()),
            full,
            image(1),
          );
        }
      case null:
    }

    final text = job.creditText?.trim() ?? '';
    if (job.credit.enabled && text.isNotEmpty) {
      final short = size.shortestSide;
      final inset = 0.02 * short, fontSize = job.credit.sizeFraction * short;
      final white = job.credit.white;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: white ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: white ? const Color(0xCC000000) : const Color(0xCCFFFFFF),
                blurRadius: fontSize * 0.2,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, size.width - 2 * inset));
      final corner = job.credit.corner;
      final right = corner == Corner.topRight || corner == Corner.bottomRight;
      final bottom = corner == Corner.bottomLeft || corner == Corner.bottomRight;
      painter.paint(
        canvas,
        Offset(
          right ? size.width - inset - painter.width : inset,
          bottom ? size.height - inset - painter.height : inset,
        ),
      );
      painter.dispose();
    }
    canvas.restore();
  }

  /// Colors run along the band; it is solid at the photo's edge and fades to nothing
  /// toward the middle of the photo.
  void _paintBand(Canvas canvas, Size size, GradientBand band, {required bool top}) {
    final h = band.heightFraction * size.height;
    final r = top
        ? Rect.fromLTWH(0, 0, size.width, h)
        : Rect.fromLTWH(0, size.height - h, size.width, h);
    canvas.saveLayer(r, Paint());
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(r.centerLeft, r.centerRight, [
          Color(band.startColor),
          Color(band.endColor),
        ]),
    );
    canvas.drawRect(
      r,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          top ? r.topCenter : r.bottomCenter,
          top ? r.bottomCenter : r.topCenter,
          [Color.fromRGBO(0, 0, 0, band.opacity), const Color(0x00000000)],
        ),
    );
    canvas.restore();
  }

  Future<ui.Image> render(RenderJob job) async {
    final recorder = ui.PictureRecorder();
    paintJob(Canvas(recorder), job);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(job.outputSize.width.round(), job.outputSize.height.round());
    } finally {
      picture.dispose();
    }
  }

  /// Straight RGBA bytes of the rendered job (alpha is always 255).
  Future<Uint8List> renderRgba(RenderJob job) async {
    final image = await render(job);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
