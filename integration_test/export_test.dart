import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:pressframe/engine/renderer.dart';
import 'package:pressframe/export/exporter.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/models/template.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Renderer renderer;
  late Directory tmp, src;
  var run = 0;

  setUpAll(() async {
    renderer = await Renderer.load();
    tmp = Directory.systemTemp.createTempSync('pf_export');
    src = Directory('${tmp.path}/src')..createSync();
    final im = img.Image(width: 1200, height: 800);
    for (final p in im) {
      p.setRgb(p.x % 256, p.y % 256, (p.x + p.y) % 256);
    }
    final bytes = img.encodeJpg(im);
    for (var i = 0; i < 5; i++) {
      File('${src.path}/good$i.jpg').writeAsBytesSync(bytes);
    }
    File('${src.path}/bad.jpg').writeAsBytesSync(List.generate(5000, (i) => (i * 37) % 251));
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  RenderSpec spec(String name, [OutputShape shape = OutputShape.original]) => (
    item: BatchItem(path: '${src.path}/$name', isRaw: false, width: 1200, height: 800),
    shape: shape,
    template: null,
    creditText: null,
    credit: const CreditStyle(),
  );

  Directory newOut() => Directory('${tmp.path}/out${run++}');
  Exporter exporter() => Exporter(renderer, maxDecodeEdge: 8192);
  ExportSettings settings(Directory out) =>
      ExportSettings(eventName: 'Intrams', outDir: out.path, longEdge: 600);
  List<File> jpgs(Directory d) =>
      d.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList();
  Map<String, Uint8List> sourceBytes() => {
    for (final f in src.listSync().whereType<File>()) f.path: f.readAsBytesSync(),
  };

  testWidgets('exports good photos, records the bad one, never touches originals', (t) async {
    final before = sourceBytes();
    final out = newOut();
    final events = await exporter().run([
      spec('good0.jpg'),
      spec('bad.jpg'),
      spec('good1.jpg'),
      spec('good2.jpg'),
    ], settings(out)).toList();
    final last = events.last;
    expect(last.finished, true);
    expect(last.cancelled, false);
    expect(last.done, 4);
    expect(last.failures.length, 1);
    expect(last.failures.single.path, endsWith('bad.jpg'));

    final files = jpgs(out);
    expect(files.length, 3);
    for (final f in files) {
      final im = img.decodeJpg(f.readAsBytesSync())!;
      expect((im.width, im.height), (600, 400), reason: f.path);
    }
    expect(files.map((f) => f.uri.pathSegments.last).toSet(), {
      'Intrams_001.jpg',
      'Intrams_003.jpg',
      'Intrams_004.jpg',
    });

    final after = sourceBytes();
    expect(after.keys.toSet(), before.keys.toSet());
    for (final k in before.keys) {
      expect(after[k], before[k], reason: k);
    }
  });

  // Review Focus 2
  testWidgets('exporting twice into one folder overwrites nothing', (t) async {
    final out = newOut();
    final specs = [spec('good0.jpg'), spec('good1.jpg'), spec('good2.jpg')];
    await exporter().run(specs, settings(out)).drain<void>();
    final first = {for (final f in jpgs(out)) f.path: f.readAsBytesSync()};
    await exporter().run(specs, settings(out)).drain<void>();
    final files = jpgs(out);
    expect(files.length, 6);
    expect(files.where((f) => f.path.endsWith('-2.jpg')).length, 3);
    for (final e in first.entries) {
      expect(File(e.key).readAsBytesSync(), e.value);
    }
  });

  // Review Focus 5
  testWidgets('cancel leaves no half-written file', (t) async {
    final out = newOut();
    final ex = exporter();
    final events = <ExportProgress>[];
    await for (final e in ex.run([for (var i = 0; i < 5; i++) spec('good$i.jpg')], settings(out))) {
      events.add(e);
      if (e.done == 1) ex.cancel();
    }
    expect(events.last.cancelled, true);
    expect(events.last.finished, true);
    expect(out.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
    final files = jpgs(out);
    expect(files.length, inInclusiveRange(1, 4));
    for (final f in files) {
      expect(img.decodeJpg(f.readAsBytesSync()), isNotNull, reason: f.path);
    }
  });

  testWidgets('an output path that is a file ends the export with a failure', (t) async {
    final notAFolder = File('${tmp.path}/occupied')..writeAsStringSync('x');
    final events = await exporter()
        .run([spec('good0.jpg')], ExportSettings(eventName: 'E', outDir: notAFolder.path))
        .toList();
    expect(events.last.finished, true);
    expect(events.last.failures, isNotEmpty);
    expect(notAFolder.readAsStringSync(), 'x');
  });

  testWidgets('full size never exceeds the source and follows the shape', (t) async {
    final out = newOut();
    await exporter()
        .run([
          spec('good0.jpg'),
          spec('good0.jpg', OutputShape.r1x1),
        ], ExportSettings(eventName: 'F', outDir: out.path, longEdge: null))
        .drain<void>();
    final files = jpgs(out)..sort((a, b) => a.path.compareTo(b.path));
    final sizes = [
      for (final f in files) img.decodeJpg(f.readAsBytesSync())!,
    ].map((im) => (im.width, im.height)).toList();
    expect(sizes, [(1200, 800), (800, 800)]);
  });
}
