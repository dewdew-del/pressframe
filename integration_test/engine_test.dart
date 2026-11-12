import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pressframe/engine/renderer.dart';
import 'package:pressframe/models/edit_params.dart';
import 'package:pressframe/models/template.dart';

const _w = 3000, _h = 2000;
const _red = Color(0xFFE00000), _green = Color(0xFF00C000);
const _blue = Color(0xFF0000E0), _yellow = Color(0xFFE0E000);

/// Smooth gradients, hard-edged blocks, and a different solid color in each corner.
Future<ui.Image> syntheticImage() {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  const full = Rect.fromLTWH(0, 0, 3000, 2000);
  c.drawRect(
    full,
    Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF203040), Color(0xFFD0A060), Color(0xFF60C0E0)],
      ).createShader(full),
  );
  c.drawRect(
    full,
    Paint()
      ..blendMode = BlendMode.plus
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x00000000), Color(0x40204020)],
      ).createShader(full),
  );
  for (var i = 0; i < 6; i++) {
    c.drawRect(
      Rect.fromLTWH(500.0 + i * 350, 700.0 + (i.isEven ? 0 : 250), 200, 300),
      Paint()..color = [_red, _green, _blue, _yellow, const Color(0xFFFFFFFF), const Color(0xFF000000)][i],
    );
  }
  c.drawRect(const Rect.fromLTWH(0, 0, 300, 300), Paint()..color = _red); // top left
  c.drawRect(const Rect.fromLTWH(2700, 0, 300, 300), Paint()..color = _green); // top right
  c.drawRect(const Rect.fromLTWH(0, 1700, 300, 300), Paint()..color = _blue); // bottom left
  c.drawRect(const Rect.fromLTWH(2700, 1700, 300, 300), Paint()..color = _yellow); // bottom right
  return rec.endRecording().toImage(_w, _h);
}

Future<ui.Image> scaled(ui.Image src, int w, int h) {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawImageRect(
    src,
    Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  return rec.endRecording().toImage(w, h);
}

Future<Uint8List> rgba(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();

/// Mean absolute difference of the RGB channels, 0..255.
double meanDiff(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var sum = 0;
  for (var i = 0; i < a.length; i += 4) {
    sum += (a[i] - b[i]).abs() + (a[i + 1] - b[i + 1]).abs() + (a[i + 2] - b[i + 2]).abs();
  }
  return sum / (a.length / 4 * 3);
}

double meanLuma(Uint8List p) {
  var sum = 0.0;
  for (var i = 0; i < p.length; i += 4) {
    sum += 0.2126 * p[i] + 0.7152 * p[i + 1] + 0.0722 * p[i + 2];
  }
  return sum / (p.length / 4);
}

Color pixel(Uint8List p, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return Color.fromARGB(255, p[i], p[i + 1], p[i + 2]);
}

void expectColor(Color actual, Color expected) {
  for (final (a, e) in [(actual.r, expected.r), (actual.g, expected.g), (actual.b, expected.b)]) {
    expect(a * 255, closeTo(e * 255, 6), reason: '$actual vs $expected');
  }
}

RenderJob job(
  ui.Image source,
  int w,
  int h, {
  EditParams edit = EditParams.neutral,
  int quarterTurns = 0,
  Rect crop = const Rect.fromLTWH(0, 0, 1, 1),
}) => RenderJob(
  source: source,
  edit: edit,
  quarterTurns: quarterTurns,
  straighten: 0,
  crop: crop,
  outputSize: Size(w.toDouble(), h.toDouble()),
  template: null,
  assets: const {},
  creditText: null,
  credit: const CreditStyle(),
);

const strong = EditParams(
  exposure: 0.7,
  contrast: 0.3,
  highlights: -0.4,
  shadows: 0.4,
  temperature: 0.3,
  tint: -0.2,
  saturation: 0.2,
  vibrance: 0.3,
  sharpen: 0.5,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Renderer renderer;
  late ui.Image source;
  setUpAll(() async {
    renderer = await Renderer.load();
    source = await syntheticImage();
  });

  testWidgets('neutral edit is identity', (tester) async {
    final out = await renderer.renderRgba(job(source, _w, _h));
    expect(meanDiff(out, await rgba(source)), lessThan(1.0));
  });

  testWidgets('preview equals export', (tester) async {
    final small = await scaled(source, 768, 512);
    final a = await renderer.renderRgba(job(small, 768, 512, edit: strong));
    final big = await renderer.render(job(source, _w, _h, edit: strong));
    final b = await rgba(await scaled(big, 768, 512));
    final diff = meanDiff(a, b);
    // ignore: avoid_print
    print('preview vs export mean difference: ${diff.toStringAsFixed(3)}');
    expect(diff, lessThan(2.0));
  });

  testWidgets('exposure brightens', (tester) async {
    final neutral = await renderer.renderRgba(job(source, 768, 512));
    final brighter = await renderer.renderRgba(
      job(source, 768, 512, edit: const EditParams(exposure: 1)),
    );
    expect(meanLuma(brighter), greaterThan(meanLuma(neutral) + 10));
  });

  testWidgets('output is the right way up', (tester) async {
    final out = await renderer.renderRgba(job(source, 600, 400));
    expectColor(pixel(out, 600, 5, 5), _red);
    expectColor(pixel(out, 600, 594, 5), _green);
    expectColor(pixel(out, 600, 5, 394), _blue);
    expectColor(pixel(out, 600, 594, 394), _yellow);
  });

  testWidgets('one quarter turn rotates clockwise', (tester) async {
    final out = await renderer.renderRgba(job(source, 400, 600, quarterTurns: 1));
    expectColor(pixel(out, 400, 5, 5), _blue); // bottom left moves to top left
    expectColor(pixel(out, 400, 394, 5), _red);
    expectColor(pixel(out, 400, 394, 594), _green);
    expectColor(pixel(out, 400, 5, 594), _yellow);
  });

  testWidgets('crop shows only the chosen part', (tester) async {
    final out = await renderer.renderRgba(
      job(source, 300, 200, crop: const Rect.fromLTWH(0.5, 0, 0.5, 0.5)),
    );
    expectColor(pixel(out, 300, 294, 5), _green); // top right quadrant keeps its corner
  });

  // The preview paints through the widget tree, which scales and offsets the canvas.
  testWidgets('paintJob follows the canvas transform', (tester) async {
    final small = await scaled(source, 768, 512);
    final j = job(small, 768, 512, edit: strong);

    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawColor(const Color(0xFF000000), BlendMode.src);
    c.translate(100, 50);
    c.scale(0.5);
    renderer.paintJob(c, j);
    final actual = await rgba(await rec.endRecording().toImage(600, 400));

    final rec2 = ui.PictureRecorder();
    final c2 = Canvas(rec2);
    c2.drawColor(const Color(0xFF000000), BlendMode.src);
    c2.drawImageRect(
      await renderer.render(j),
      const Rect.fromLTWH(0, 0, 768, 512),
      const Rect.fromLTWH(100, 50, 384, 256),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final expected = await rgba(await rec2.endRecording().toImage(600, 400));
    final diff = meanDiff(actual, expected);
    // ignore: avoid_print
    print('transformed paint mean difference: ${diff.toStringAsFixed(3)}');
    expect(diff, lessThan(4.0));
  });
}
