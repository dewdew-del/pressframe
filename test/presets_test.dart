import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/models/edit_params.dart';
import 'package:pressframe/models/preset.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/storage/app_store.dart';
import 'package:pressframe/ui/shared/preset_panel.dart';
import 'package:pressframe/ui/theme.dart';

void main() {
  late Directory tmp;
  var n = 0;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('pf_presets'));
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<AppStore> newStore() {
    n++;
    return AppStore.open(supportDir: '${tmp.path}/s$n', cacheDir: '${tmp.path}/c$n');
  }

  const gym = Preset(name: 'My gym', params: EditParams(exposure: 0.4, sharpen: 0.2));

  test('three built-in presets', () {
    expect(builtInPresets.map((p) => p.name), ['Indoor gym', 'Outdoor sun', 'Stage lights']);
  });

  test('save then load returns the preset', () async {
    final store = await newStore();
    expect(await store.loadPresets(), isEmpty);
    await store.savePreset(gym);
    final loaded = await store.loadPresets();
    expect(loaded.single.name, 'My gym');
    expect(loaded.single.params, gym.params);
  });

  test('saving the same name twice keeps one, with the new values', () async {
    final store = await newStore();
    await store.savePreset(gym);
    await store.savePreset(const Preset(name: 'My gym', params: EditParams(exposure: 1)));
    final loaded = await store.loadPresets();
    expect(loaded.length, 1);
    expect(loaded.single.params.exposure, 1);
  });

  test('delete removes only that preset', () async {
    final store = await newStore();
    await store.savePreset(gym);
    await store.savePreset(const Preset(name: 'Other', params: EditParams.neutral));
    await store.deletePreset('My gym');
    expect((await store.loadPresets()).map((p) => p.name), ['Other']);
  });

  test('export then import round-trips into another store', () async {
    final a = await newStore(), b = await newStore();
    final file = '${tmp.path}/gym.pfpreset';
    await a.exportPreset(gym, file);
    final imported = await b.importPreset(file);
    expect(imported.name, 'My gym');
    expect(imported.params, gym.params);
    expect((await b.loadPresets()).single.params, gym.params);
  });

  test('importing a name that exists keeps both', () async {
    final store = await newStore();
    final file = '${tmp.path}/dup.pfpreset';
    await store.savePreset(const Preset(name: 'My gym', params: EditParams(exposure: -1)));
    await store.exportPreset(gym, file);
    expect((await store.importPreset(file)).name, 'My gym (2)');
    final loaded = await store.loadPresets();
    expect(loaded.map((p) => p.name), ['My gym', 'My gym (2)']);
    expect(loaded.first.params.exposure, -1);
  });

  test('bad preset files are rejected and change nothing', () async {
    final store = await newStore();
    await store.savePreset(gym);
    final wrong = File('${tmp.path}/wrong.pfpreset')..writeAsStringSync('{"foo":1}');
    final notJson = File('${tmp.path}/notjson.pfpreset')..writeAsStringSync('hello <<<');
    final list = File('${tmp.path}/list.pfpreset')..writeAsStringSync('[1,2]');
    final huge = File('${tmp.path}/huge.pfpreset')..writeAsBytesSync(List.filled(1024 * 1024 + 1, 32));
    final binary = File('${tmp.path}/bin.pfpreset')..writeAsBytesSync([0xFF, 0xFE, 0x00, 0x80]);
    for (final f in [wrong, notJson, list, huge, binary, File('${tmp.path}/missing.pfpreset')]) {
      await expectLater(store.importPreset(f.path), throwsFormatException, reason: f.path);
    }
    expect((await store.loadPresets()).map((p) => p.name), ['My gym']);
  });

  test('a damaged presets file is set aside, not silently overwritten', () async {
    final store = await newStore();
    File('${store.support.path}/presets.json').writeAsStringSync('{{{ not json');
    expect(await store.loadPresets(), isEmpty);
    await store.savePreset(gym);
    expect((await store.loadPresets()).single.name, 'My gym');
    expect(File('${store.support.path}/presets.json.bad').existsSync(), true);
  });

  testWidgets('tapping a preset applies it as one undo step', (tester) async {
    final session = Session()
      ..addItems([const BatchItem(path: 'a.jpg', isRaw: false, width: 6000, height: 4000)])
      ..updateSelected((i) => i.copyWith(straighten: 3));
    await tester.pumpWidget(
      MaterialApp(
        theme: pressFrameTheme,
        home: Scaffold(body: PresetPanel(session: session, store: null)),
      ),
    );
    await tester.tap(find.text('Indoor gym'));
    expect(session.selected!.edit, builtInPresets.first.params);
    expect(session.selected!.straighten, 3, reason: 'crop and straighten are not part of a preset');
    session.undo();
    expect(session.selected!.edit, EditParams.neutral);
    expect(find.text('Save current'), findsOneWidget);
    expect(find.text('Import preset'), findsNothing);
    await tester.tap(find.byTooltip('More preset actions'));
    await tester.pumpAndSettle();
    expect(find.text('Import preset'), findsOneWidget);
  });
}
