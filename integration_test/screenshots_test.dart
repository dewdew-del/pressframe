// Takes the README screenshots from the real app. Not a test of behavior.
// Put a few JPEGs in build/demo-photos, then run:
//   flutter test integration_test/screenshots_test.dart -d windows
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pressframe/engine/renderer.dart';
import 'package:pressframe/main.dart';
import 'package:pressframe/models/template.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/storage/app_store.dart';
import 'package:pressframe/storage/template_library.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final photos = Directory('build/demo-photos');
  final shot = GlobalKey();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> save(WidgetTester tester, String name, double pixelRatio) async {
    await settle(tester);
    final boundary = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  }

  testWidgets('README screenshots', (tester) async {
    final temp = Directory.systemTemp.createTempSync('pressframe_shots');
    final store = await AppStore.open(supportDir: '${temp.path}/s', cacheDir: '${temp.path}/c');
    final library = TemplateLibrary(store, maxAssetEdge: 4096);
    await library.save(
      const BuiltTemplate(
        name: 'School paper',
        band: GradientBand(
          edge: BandEdge.bottom,
          heightFraction: 0.16,
          startColor: 0xFF0B3D91,
          endColor: 0xFF4DA3FF,
          opacity: 0.9,
        ),
      ),
    );
    final session = Session();
    final files = photos.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    await session.import([for (final f in files) f.absolute.path]);
    session.landscapeTemplate = 'School paper';
    session.portraitTemplate = 'School paper';
    session.setEdit(
      session.selected!.edit.copyWith(contrast: 0.12, temperature: 0.06, saturation: 0.1),
      commit: true,
    );
    session.applyEditToAll();

    await binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      RepaintBoundary(
        key: shot,
        child: PressFrameApp(
          session: session,
          renderer: await Renderer.load(),
          store: store,
          library: library,
        ),
      ),
    );
    await save(tester, 'laptop-edit', 1);

    await tester.tap(find.textContaining('Next: Review'));
    await save(tester, 'laptop-review', 1);

    await binding.setSurfaceSize(const Size(390, 844));
    await save(tester, 'phone-edit', 2);
    await tester.tap(find.byKey(const ValueKey('tab-Template')));
    await save(tester, 'phone-template', 2);
  }, skip: !photos.existsSync());
}
