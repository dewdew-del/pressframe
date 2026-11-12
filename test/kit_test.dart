import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pressframe/models/edit_params.dart';
import 'package:pressframe/models/kit.dart';
import 'package:pressframe/models/preset.dart';
import 'package:pressframe/models/template.dart';
import 'package:pressframe/storage/app_store.dart';

void main() {
  late Directory tmp;
  var n = 0;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pf_kit'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<AppStore> newStore() {
    n++;
    return AppStore.open(supportDir: '${tmp.path}/store$n/support', cacheDir: '${tmp.path}/store$n/cache');
  }

  final logoPng = img.encodePng(img.Image(width: 20, height: 10)..clear(img.ColorRgb8(0, 255, 0)));
  final framePng = img.encodePng(img.Image(width: 40, height: 50, numChannels: 4));

  /// Store A with one preset, a built template using a logo, and a frame.
  Future<(AppStore, String logo, String frame)> filled() async {
    final a = await newStore();
    final logo = await a.storeAssetBytes(logoPng);
    final frame = await a.storeAssetBytes(framePng);
    await a.savePreset(const Preset(name: 'Gym', params: EditParams(exposure: 0.4)));
    await a.saveTemplate(
      BuiltTemplate(
        name: 'Band',
        band: const GradientBand(),
        logos: [LogoLayer(file: logo, cx: 0.1, cy: 0.9)],
      ),
    );
    await a.saveTemplate(FrameTemplate(name: 'Frame', file: frame, aspect: 0.8));
    return (a, logo, frame);
  }

  String json(List<dynamic> list) => jsonEncode([for (final e in list) e.toJson()]);

  /// Every file under [dir], by relative path.
  Map<String, Uint8List> snapshot(Directory dir) => {
    for (final f in dir.listSync(recursive: true).whereType<File>())
      f.path.substring(dir.path.length): f.readAsBytesSync(),
  };

  File zipFile(String name, Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((path, bytes) => archive.add(ArchiveFile.bytes(path, bytes)));
    return File('${tmp.path}/$name')..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
  }

  List<int> kitJson({List<Template> templates = const [], List<Preset> presets = const []}) => utf8.encode(
    jsonEncode({
      'pressframe': 'kit',
      'version': 1,
      ...Kit(name: 'K', presets: presets, templates: templates).toJson(),
    }),
  );

  test('a kit carries presets, templates, credit style and logo files to another install', () async {
    final (a, logo, frame) = await filled();
    final b = await newStore();
    final file = '${tmp.path}/staff.pfkit';
    await a.exportKit('The Scribe', file, credit: const CreditStyle(corner: Corner.topLeft, white: false));

    final kit = await b.importKit(file);
    expect(kit.name, 'The Scribe');
    expect(kit.credit.corner, Corner.topLeft);
    expect(kit.credit.white, false);
    expect(json(await b.loadPresets()), json(await a.loadPresets()));
    expect(json(await b.loadTemplates()), json(await a.loadTemplates()));
    expect(b.assetFile(logo).readAsBytesSync(), logoPng);
    expect(b.assetFile(frame).readAsBytesSync(), framePng);
  });

  test('importing twice keeps both copies and overwrites nothing', () async {
    final (a, _, _) = await filled();
    final b = await newStore();
    final file = '${tmp.path}/staff.pfkit';
    await a.exportKit('Kit', file);
    await b.importKit(file);
    await b.savePreset(const Preset(name: 'Gym', params: EditParams(exposure: -1))); // user edits it
    final second = await b.importKit(file);

    expect(second.presets.map((p) => p.name), ['Gym (2)']);
    expect(second.templates.map((t) => t.name), ['Band (2)', 'Frame (2)']);
    final presets = await b.loadPresets();
    expect(presets.map((p) => p.name), ['Gym', 'Gym (2)']);
    expect(presets.first.params.exposure, -1, reason: "the user's own preset is untouched");
    expect((await b.loadTemplates()).map((t) => t.name), ['Band', 'Frame', 'Band (2)', 'Frame (2)']);
    expect(Directory('${b.support.path}/assets').listSync().length, 2, reason: 'same pictures stored once');
  });

  test('a template whose logo is not in the kit is imported and left without it', () async {
    final a = await newStore(), b = await newStore();
    await a.saveTemplate(const BuiltTemplate(name: 'Band', logos: [LogoLayer(file: 'abc123.png')]));
    await a.exportKit('Kit', '${tmp.path}/k.pfkit');
    final kit = await b.importKit('${tmp.path}/k.pfkit');
    expect(kit.templates.single.name, 'Band');
    expect(b.assetFile('abc123.png').existsSync(), false);
  });

  group('rejected kits change nothing', () {
    late AppStore b;
    late Map<String, Uint8List> before;

    Future<void> expectRejected(File kit, {int? maxUnpackedBytes}) async {
      b = await newStore();
      await b.savePreset(const Preset(name: 'Mine', params: EditParams.neutral));
      before = snapshot(tmp);
      await expectLater(
        maxUnpackedBytes == null
            ? b.importKit(kit.path)
            : b.importKit(kit.path, maxUnpackedBytes: maxUnpackedBytes),
        throwsFormatException,
        reason: kit.path,
      );
      final after = snapshot(tmp);
      expect(after.keys.toSet(), before.keys.toSet(), reason: 'no file added or removed');
      for (final k in before.keys) {
        expect(after[k], before[k], reason: k);
      }
    }

    test('no kit.json', () => expectRejected(zipFile('a.pfkit', {'assets/a.png': logoPng})));

    test('kit.json that is not a kit', () async {
      await expectRejected(zipFile('a.pfkit', {'kit.json': utf8.encode('{"foo":1}')}));
      await expectRejected(zipFile('b.pfkit', {'kit.json': utf8.encode('not json')}));
      await expectRejected(zipFile('c.pfkit', {'kit.json': utf8.encode('{"pressframe":"kit","templates":[{"type":"alien"}]}')}));
    });

    test('a text file named like a PNG', () => expectRejected(
      zipFile('a.pfkit', {'kit.json': kitJson(), 'assets/x.png': utf8.encode('I am not a picture')}),
    ));

    test('an extra file that is not an asset', () => expectRejected(
      zipFile('a.pfkit', {'kit.json': kitJson(), 'readme.txt': utf8.encode('hi')}),
    ));

    // Review Focus 4
    for (final evil in ['../evil.png', 'assets/../../evil.png', r'C:\evil.png', '/evil.png', r'assets\..\..\evil.png', 'assets/sub/evil.png']) {
      test('zip entry "$evil"', () => expectRejected(zipFile('a.pfkit', {'kit.json': kitJson(), evil: logoPng})));
    }

    test('a template that points outside the assets folder', () => expectRejected(
      zipFile('a.pfkit', {
        'kit.json': kitJson(templates: const [FrameTemplate(name: 'F', file: '../../secret.png', aspect: 1)]),
      }),
    ));

    test('not a zip file', () async {
      await expectRejected(File('${tmp.path}/junk.pfkit')..writeAsBytesSync(List.generate(4000, (i) => i % 251)));
      await expectRejected(File('${tmp.path}/missing.pfkit'));
    });

    test('a kit that unpacks larger than the limit', () => expectRejected(
      zipFile('a.pfkit', {'kit.json': kitJson(), 'assets/a.png': logoPng}),
      maxUnpackedBytes: 50,
    ));
  });
}
