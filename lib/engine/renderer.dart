import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Canvas, Offset, Paint, Rect, Size;

import 'package:flutter/widgets.dart' show Matrix4;

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
