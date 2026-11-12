import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/ui/desktop_shell.dart';
import 'package:pressframe/ui/shared/filmstrip.dart';
import 'package:pressframe/ui/theme.dart';

BatchItem item(String name, {bool raw = false, int w = 6000}) =>
    BatchItem(path: name, isRaw: raw, width: w, height: w * 2 ~/ 3);

Future<Session> pumpShell(WidgetTester tester, List<BatchItem> items) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session()..addItems(items);
  await tester.pumpWidget(
    MaterialApp(theme: pressFrameTheme, home: DesktopShell(session: session)),
  );
  return session;
}

void main() {
  testWidgets('rejected photos are hidden by default', (tester) async {
    final session = await pumpShell(tester, [item('a'), item('b'), item('c')]);
    expect(find.byType(FilmstripTile), findsNWidgets(3));
    session.select(1);
    session.setFlag(Flag.reject);
    await tester.pump();
    expect(find.byType(FilmstripTile), findsNWidgets(2));
  });

  testWidgets('X rejects and moves on, arrows move the selection', (tester) async {
    final session = await pumpShell(tester, [item('a'), item('b'), item('c')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(session.selectedIndex, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();
    expect(session.items[1].flag, Flag.reject);
    expect(session.selectedIndex, 2);
    expect(find.byType(FilmstripTile), findsNWidgets(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(session.selectedIndex, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(session.items[0].flag, Flag.pick);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyU);
    expect(session.items[0].flag, Flag.none);
  });

  testWidgets('tapping a tile selects it', (tester) async {
    final session = await pumpShell(tester, [item('a'), item('b'), item('c')]);
    await tester.tap(find.byKey(const ValueKey('tile-c')));
    expect(session.selectedIndex, 2);
  });

  testWidgets('tiles show RAW and small-preview badges', (tester) async {
    await pumpShell(tester, [item('a'), item('b.cr3', raw: true), item('c.arw', raw: true, w: 1616)]);
    expect(find.text('RAW'), findsNWidgets(2));
    expect(find.byTooltip('Small preview: this RAW will export small'), findsOneWidget);
  });

  testWidgets('the filter menu changes what is shown', (tester) async {
    final session = await pumpShell(tester, [item('a'), item('b'), item('c')]);
    session.select(1);
    session.setFlag(Flag.reject);
    await tester.pump();
    await tester.tap(find.byTooltip('Filter photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    expect(session.filter, FlagFilter.all);
    expect(find.byType(FilmstripTile), findsNWidgets(3));
  });

  testWidgets('Apply to all copies the edit', (tester) async {
    final session = await pumpShell(tester, [item('a'), item('b')]);
    session.setEdit(session.selected!.edit.copyWith(exposure: 0.5), commit: true);
    await tester.pump();
    await tester.tap(find.text('Apply to all'));
    expect(session.items[1].edit.exposure, 0.5);
  });

  testWidgets('an empty batch shows how to start', (tester) async {
    await pumpShell(tester, []);
    expect(find.text('Drop photos here or click Add photos'), findsOneWidget);
    expect(find.byType(FilmstripTile), findsNothing);
  });
}
