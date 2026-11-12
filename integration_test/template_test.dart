import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:pressframe/engine/renderer.dart';
import 'package:pressframe/export/exporter.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/models/edit_params.dart';
import 'package:pressframe/models/template.dart';

const gray = Color(0xFF808080);

/// An ordinary texture (not a drawn one) filled by [color] per pixel.
Future<ui.Image> pixels(int w, int h, Color Function(int x, int y) color) {
  final data = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = color(x, y), i = (y * w + x) * 4;
      data[i] = (c.r * c.a * 255).round();
      data[i + 1] = (c.g * c.a * 255).round();
      data[i + 2] = (c.b * c.a * 255).round();
      data[i + 3] = (c.a * 255).round();
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(data, w, h, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

({int r, int g, int b}) at(Uint8List p, int width, int x, int y) {
  final i = (y * width + x) * 4;
  return (r: p[i], g: p[i + 1], b: p[i + 2]);
}

int distance(({int r, int g, int b}) a, ({int r, int g, int b}) b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

const grayPx = (r: 128, g: 128, b: 128);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Renderer renderer;
  late ui.Image source; // 1000 x 800 mid gray
  setUpAll(() async {
    renderer = await Renderer.load();
    source = await pixels(1000, 800, (x, y) => gray);
  });

  Future<Uint8List> render({
    Template? template,
    Map<String, ui.Image> assets = const {},
    String? creditText,
    CreditStyle credit = const CreditStyle(),
    ui.Image? from,
    Size size = const Size(1000, 800),
    Rect crop = const Rect.fromLTWH(0, 0, 1, 1),
  }) => renderer.renderRgba(
    RenderJob(
      source: from ?? source,
      edit: EditParams.neutral,
      quarterTurns: 0,
      straighten: 0,
      crop: crop,
      outputSize: size,
      template: template,
      assets: assets,
      creditText: creditText,
      credit: credit,
    ),
  );

  testWidgets('gradient band: colors run along it and it fades toward the photo', (t) async {
    final out = await render(
      template: const BuiltTemplate(
        name: 'b',
        band: GradientBand(
          edge: BandEdge.bottom,
          heightFraction: 0.25,
          startColor: 0xFFFF0000,
          endColor: 0xFF0000FF,
          opacity: 1,
        ),
      ),
    );
    final left = at(out, 1000, 50, 795), right = at(out, 1000, 950, 795);
    expect(left.r > 200 && left.b < 60, true, reason: 'left end is red: $left');
    expect(right.b > 200 && right.r < 60, true, reason: 'right end is blue: $right');
    expect(distance(at(out, 1000, 500, 100), grayPx), lessThan(6), reason: 'photo untouched');
    expect(
      distance(at(out, 1000, 500, 610), grayPx),
      lessThan(distance(at(out, 1000, 500, 790), grayPx)),
      reason: 'the inner side of the band is fainter',
    );
  });

  testWidgets('band on both edges', (t) async {
    final out = await render(
      template: const BuiltTemplate(
        name: 'b',
        band: GradientBand(edge: BandEdge.both, heightFraction: 0.2, startColor: 0xFFFF0000, endColor: 0xFFFF0000),
      ),
    );
    expect(at(out, 1000, 500, 3).r, greaterThan(200));
    expect(at(out, 1000, 500, 796).r, greaterThan(200));
    expect(distance(at(out, 1000, 500, 400), grayPx), lessThan(6));
  });

  testWidgets('logo is placed by its center and width', (t) async {
    final logo = await pixels(100, 50, (x, y) => const Color(0xFF00FF00));
    final out = await render(
      template: const BuiltTemplate(
        name: 'l',
        logos: [LogoLayer(file: 'logo.png', cx: 0.9, cy: 0.1, widthFraction: 0.1, opacity: 1)],
      ),
      assets: {'logo.png': logo},
    );
    final on = at(out, 1000, 900, 80);
    expect(on.g > 240 && on.r < 20 && on.b < 20, true, reason: '$on');
    expect(distance(at(out, 1000, 500, 400), grayPx), lessThan(6));
    expect(distance(at(out, 1000, 900, 120), grayPx), lessThan(6), reason: 'below the logo');
    expect(distance(at(out, 1000, 840, 80), grayPx), lessThan(6), reason: 'left of the logo');
  });

  testWidgets('a template whose logo file is missing still renders', (t) async {
    final out = await render(
      template: const BuiltTemplate(name: 'l', logos: [LogoLayer(file: 'gone.png')]),
    );
    expect(distance(at(out, 1000, 500, 400), grayPx), lessThan(6));
  });

  testWidgets('photo credit is drawn only when enabled', (t) async {
    final plain = await render();
    final off = await render(creditText: 'Photo by Juan Dela Cruz');
    expect(off, plain, reason: 'credit is off by default');
    final blank = await render(creditText: '  ', credit: const CreditStyle(enabled: true));
    expect(blank, plain, reason: 'no text, nothing drawn');

    final on = await render(
      creditText: 'Photo by Juan Dela Cruz',
      credit: const CreditStyle(enabled: true, white: true, corner: Corner.bottomRight),
    );
    bool bright(int x0, int y0, int x1, int y1) {
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final p = at(on, 1000, x, y);
          if (p.r > 240 && p.g > 240 && p.b > 240) return true;
        }
      }
      return false;
    }

    expect(bright(700, 740, 1000, 800), true, reason: 'text in the bottom right corner');
    expect(bright(0, 0, 300, 60), false, reason: 'nothing in the top left corner');

    final black = await render(
      creditText: 'Photo by Juan Dela Cruz',
      credit: const CreditStyle(enabled: true, white: false, corner: Corner.topLeft),
    );
    var dark = false;
    for (var y = 0; y < 60 && !dark; y++) {
      for (var x = 0; x < 300 && !dark; x++) {
        final p = at(black, 1000, x, y);
        dark = p.r < 20 && p.g < 20 && p.b < 20;
      }
    }
    expect(dark, true, reason: 'black text in the top left corner');
  });

  testWidgets('imported frame is stretched over the whole output', (t) async {
    final frame = await pixels(
      400,
      400,
      (x, y) => x < 20 || y < 20 || x >= 380 || y >= 380 ? const Color(0xFFFF0000) : const Color(0x00000000),
    );
    final out = await render(
      template: const FrameTemplate(name: 'f', file: 'frame.png', aspect: 1),
      assets: {'frame.png': frame},
      size: const Size(400, 400),
      crop: const Rect.fromLTWH(0.1, 0, 0.8, 1),
    );
    final corner = at(out, 400, 3, 3);
    expect(corner.r > 240 && corner.g < 20, true, reason: '$corner');
    expect(distance(at(out, 400, 200, 200), grayPx), lessThan(6));
  });

  testWidgets('export follows the output shape and draws the template', (t) async {
    final tmp = Directory.systemTemp.createTempSync('pf_template');
    final photo = File('${tmp.path}/p.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 1500, height: 1000)..clear(img.ColorRgb8(128, 128, 128))));
    final logo = await pixels(100, 50, (x, y) => const Color(0xFF00FF00));
    const template = BuiltTemplate(
      name: 'l',
      logos: [LogoLayer(file: 'logo.png', cx: 0.5, cy: 0.5, widthFraction: 0.2)],
    );
    final exporter = Exporter(renderer, maxDecodeEdge: 8192, loadAssets: (t) async => {'logo.png': logo});
    final events = await exporter.run([
      (
        item: BatchItem(path: photo.path, isRaw: false, width: 1500, height: 1000),
        shape: OutputShape.r1x1,
        template: template,
        creditText: null,
        credit: const CreditStyle(),
      ),
    ], ExportSettings(eventName: 'T', outDir: '${tmp.path}/out', longEdge: 500)).toList();
    expect(events.last.failures, isEmpty);
    final out = img.decodeJpg(File('${tmp.path}/out/T_001.jpg').readAsBytesSync())!;
    expect((out.width, out.height), (500, 500));
    final center = out.getPixel(250, 250);
    expect(center.g > 200 && center.r < 80, true, reason: 'logo in the middle: $center');
    tmp.deleteSync(recursive: true);
  });
}
