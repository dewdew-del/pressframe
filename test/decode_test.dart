import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pressframe/engine/decode.dart';

Uint8List jpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  for (final p in im) {
    p.setRgb((p.x * 7) % 256, (p.y * 5) % 256, (p.x + p.y) % 256);
  }
  return img.encodeJpg(im);
}

Uint8List junk(int n) => Uint8List(n)..fillRange(0, n, 0x11);

Uint8List cat(List<List<int>> parts) => Uint8List.fromList([for (final p in parts) ...p]);

/// Little-endian TIFF header whose IFD0 holds only the orientation tag.
Uint8List tiff(int orientation) => Uint8List.fromList([
  0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // II, 42, IFD0 at 8
  0x01, 0x00, // one entry
  0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, orientation, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, // no next IFD
]);

void main() {
  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('pf_decode'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  test('isRawPath', () {
    expect(isRawPath('a.CR3'), true);
    expect(isRawPath('b.arw'), true);
    expect(isRawPath(r'C:\x\d.Cr2'), true);
    expect(isRawPath('c.jpg'), false);
  });

  test('extractEmbeddedJpeg returns the largest JPEG', () {
    final big = jpeg(64, 48);
    final raw = cat([junk(100), jpeg(16, 8), junk(50), big, junk(70)]);
    final r = extractEmbeddedJpeg(raw)!;
    expect((r.width, r.height), (64, 48));
    expect(r.bytes.length, big.length, reason: 'slice ends at the JPEG end marker');
    expect(img.decodeJpg(r.bytes), isNotNull);
  });

  test('extractEmbeddedJpeg rejects lossless JPEG (the CR2 sensor data)', () {
    final fake = cat([
      [0xFF, 0xD8, 0xFF, 0xC3, 0x00, 0x0B, 0x08, 0x00, 0x30, 0x00, 0x40, 0x01, 0x01, 0x11, 0x00],
      [0xFF, 0xD9],
    ]);
    expect(extractEmbeddedJpeg(fake), isNull);
  });

  test('extractEmbeddedJpeg returns null for empty and random bytes', () {
    expect(extractEmbeddedJpeg(Uint8List(0)), isNull);
    var seed = 12345;
    final random = Uint8List(3000);
    for (var i = 0; i < random.length; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      random[i] = seed >> 16;
    }
    expect(extractEmbeddedJpeg(random), isNull);
  });

  test('extractEmbeddedJpeg ignores a JPEG that is cut off', () {
    final big = jpeg(64, 48);
    expect(extractEmbeddedJpeg(cat([junk(10), big.sublist(0, big.length ~/ 2)])), isNull);
  });

  test('rawOrientation reads TIFF containers and the CR3 CMT1 box', () {
    expect(rawOrientation(cat([tiff(6), junk(20)])), 6);
    final cr3 = cat([
      [0, 0, 0, 24], 'ftypcrx '.codeUnits, junk(12),
      [0, 0, 0, 34], 'CMT1'.codeUnits, tiff(8),
    ]);
    expect(rawOrientation(cr3), 8);
    expect(rawOrientation(junk(500)), isNull);
    expect(rawOrientation(Uint8List(0)), isNull);
  });

  testWidgets('decodeImage scales a JPEG down to maxLongEdge', (tester) async {
    await tester.runAsync(() async {
      final path = write('ok.jpg', jpeg(400, 200));
      final image = await decodeImage(path, maxLongEdge: 100);
      expect((image.width, image.height), (100, 50));
      image.dispose();
      final p = await probe(path);
      expect((p.width, p.height, p.isRaw, p.smallPreview), (400, 200, false, false));
    });
  });

  testWidgets('decodeImage never upscales', (tester) async {
    await tester.runAsync(() async {
      final image = await decodeImage(write('small.jpg', jpeg(40, 20)), maxLongEdge: 100);
      expect((image.width, image.height), (40, 20));
      image.dispose();
    });
  });

  testWidgets('decodeImage throws DecodeFailure on a half-written JPEG', (tester) async {
    await tester.runAsync(() async {
      final whole = jpeg(200, 200);
      final path = write('half.jpg', whole.sublist(0, whole.length ~/ 2));
      await expectLater(decodeImage(path, maxLongEdge: 100), throwsA(isA<DecodeFailure>()));
      await expectLater(probe(path), throwsA(isA<DecodeFailure>()));
    });
  });

  testWidgets('decodeImage throws DecodeFailure on a missing file and on non-image bytes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await expectLater(
        decodeImage('${tmp.path}/nope.jpg', maxLongEdge: 100),
        throwsA(isA<DecodeFailure>()),
      );
      await expectLater(
        decodeImage(write('junk.jpg', junk(500)), maxLongEdge: 100),
        throwsA(isA<DecodeFailure>()),
      );
      await expectLater(
        decodeImage(write('empty.cr3', junk(500)), maxLongEdge: 100),
        throwsA(isA<DecodeFailure>()),
      );
    });
  });

  testWidgets('RAW with orientation 6 in its container decodes upright', (tester) async {
    await tester.runAsync(() async {
      final path = write('fake.cr2', cat([tiff(6), junk(40), jpeg(64, 48), junk(10)]));
      final image = await decodeImage(path, maxLongEdge: 2048);
      expect((image.width, image.height), (48, 64));
      image.dispose();
      final p = await probe(path);
      expect((p.width, p.height, p.isRaw, p.smallPreview), (48, 64, true, true));
    });
  });

  // Review Focus 1: real camera files, supplied by Dewdew in test/samples/ (git-ignored).
  testWidgets('real RAW samples have an embedded JPEG and decode upright', (tester) async {
    final dir = Directory('test/samples');
    final files = dir.existsSync()
        ? (dir.listSync().whereType<File>().where((f) => isRawPath(f.path)).toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
        : <File>[];
    if (files.isEmpty) {
      markTestSkipped('No RAW files in test/samples/ - real-camera check not run');
      return;
    }
    await tester.runAsync(() async {
      for (final f in files) {
        final raw = f.readAsBytesSync();
        final e = extractEmbeddedJpeg(raw);
        final o = rawOrientation(raw);
        // ignore: avoid_print
        print('${f.uri.pathSegments.last}: embedded ${e?.width}x${e?.height}, orientation $o');
        expect(e, isNotNull, reason: f.path);
        final image = await decodeImage(f.path, maxLongEdge: 1024);
        if (o == 6 || o == 8) {
          expect(image.height, greaterThan(image.width), reason: f.path);
        }
        image.dispose();
      }
    });
  });
}
