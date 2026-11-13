import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pressframe/models/template.dart';
import 'package:pressframe/storage/app_store.dart';
import 'package:pressframe/ui/shared/color_picker.dart';
import 'package:pressframe/ui/shared/template_editor.dart';

void main() {
  late Directory tmp;
  var n = 0;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('pf_templates'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<AppStore> newStore() {
    n++;
    return AppStore.open(supportDir: '${tmp.path}/s$n', cacheDir: '${tmp.path}/c$n');
  }

  const built = BuiltTemplate(
    name: 'Band',
    band: GradientBand(edge: BandEdge.both, heightFraction: 0.2, opacity: 0.8),
    logos: [LogoLayer(file: 'x.png', cx: 0.1, cy: 0.9)],
  );
  const frame = FrameTemplate(name: 'Frame', file: 'f.png', aspect: 0.8);

  test('templates survive save and load', () async {
    final store = await newStore();
    expect(await store.loadTemplates(), isEmpty);
    await store.saveTemplate(built);
    await store.saveTemplate(frame);
    final loaded = await store.loadTemplates();
    expect(jsonEncode([for (final t in loaded) t.toJson()]), jsonEncode([built.toJson(), frame.toJson()]));
    expect(loaded[0], isA<BuiltTemplate>());
    expect(loaded[1], isA<FrameTemplate>());
  });

  test('saving a template with the same name replaces it; delete removes it', () async {
    final store = await newStore();
    await store.saveTemplate(built);
    await store.saveTemplate(const BuiltTemplate(name: 'Band'));
    var loaded = await store.loadTemplates();
    expect(loaded.length, 1);
    expect((loaded.single as BuiltTemplate).band, isNull);
    await store.deleteTemplate('Band');
    loaded = await store.loadTemplates();
    expect(loaded, isEmpty);
  });

  test('importAsset copies a PNG under a name made from its content', () async {
    final store = await newStore();
    final png = img.encodePng(img.Image(width: 20, height: 10));
    final a = File('${tmp.path}/logo.png')..writeAsBytesSync(png);
    final b = File('${tmp.path}/same-logo-other-name.png')..writeAsBytesSync(png);
    final name = await store.importAsset(a.path);
    expect(name, endsWith('.png'));
    expect(await store.importAsset(b.path), name);
    expect(File('${store.support.path}/assets/$name').readAsBytesSync(), png);
    expect(Directory('${store.support.path}/assets').listSync().length, 1);
  });

  test('importAsset rejects anything that is not a whole PNG', () async {
    final store = await newStore();
    final jpgAsPng = File('${tmp.path}/fake.png')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 20, height: 10)));
    final png = img.encodePng(img.Image(width: 20, height: 10));
    final cut = File('${tmp.path}/cut.png')..writeAsBytesSync(png.sublist(0, png.length - 12));
    for (final f in [jpgAsPng, cut, File('${tmp.path}/missing.png')]) {
      await expectLater(store.importAsset(f.path), throwsFormatException, reason: f.path);
    }
    expect(Directory('${store.support.path}/assets').listSync(), isEmpty);
  });

  test('logos snap to the edges and the center, and stay inside the photo', () {
    // A logo 0.2 wide: its center snaps to 0.12 (edge + margin), 0.5 and 0.88.
    expect(snapAxis(0.13, 0.1), closeTo(0.12, 1e-9));
    expect(snapAxis(0.51, 0.1), 0.5);
    expect(snapAxis(0.87, 0.1), closeTo(0.88, 1e-9));
    expect(snapAxis(0.3, 0.1), 0.3);
    expect(snapAxis(-0.5, 0.1), 0.0);
    expect(snapAxis(1.7, 0.1), 1.0);
  });

  test('hex colors parse with or without the hash', () {
    expect(parseHex('#FF8000'), 0xFFFF8000);
    expect(parseHex('ff8000'), 0xFFFF8000);
    expect(parseHex('nope'), isNull);
    expect(parseHex('#FFF'), isNull);
    expect(toHex(0xFF0B3D91), '#0B3D91');
  });
}
