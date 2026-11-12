import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/ui/desktop_shell.dart';
import 'package:pressframe/ui/theme.dart';

Future<Session> pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session()
    ..addItems([const BatchItem(path: 'a.jpg', isRaw: false, width: 6000, height: 4000)]);
  // No renderer: the preview shows a placeholder, which is the stub for widget tests.
  await tester.pumpWidget(
    MaterialApp(theme: pressFrameTheme, home: DesktopShell(session: session)),
  );
  return session;
}

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('shows every slider with a label', (tester) async {
    await pumpShell(tester);
    for (final label in [
      'Exposure', 'Contrast', 'Highlights', 'Shadows', //
      'Temperature', 'Tint', 'Saturation', 'Vibrance', 'Sharpen',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
      expect(find.byKey(ValueKey('slider-$label')), findsOneWidget, reason: label);
    }
    expect(find.text('Auto fix'), findsOneWidget);
  });

  testWidgets('dragging Exposure edits the photo and Ctrl+Z undoes it', (tester) async {
    final session = await pumpShell(tester);
    await tester.drag(find.byKey(const ValueKey('slider-Exposure')), const Offset(60, 0));
    await tester.pump();
    expect(session.selected!.edit.exposure, greaterThan(0));
    expect(session.canUndo, true);

    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(session.selected!.edit.exposure, 0);
    await ctrl(tester, LogicalKeyboardKey.keyY);
    expect(session.selected!.edit.exposure, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 500)); // let the double-tap timer run out
  });

  testWidgets('double-tapping a slider resets it', (tester) async {
    final session = await pumpShell(tester);
    final slider = find.byKey(const ValueKey('slider-Exposure'));
    await tester.drag(slider, const Offset(60, 0));
    await tester.pump();
    expect(session.selected!.edit.exposure, greaterThan(0));

    await tester.tap(slider);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(slider);
    await tester.pumpAndSettle();
    expect(session.selected!.edit.exposure, 0);
  });

  testWidgets('Ctrl+C then Ctrl+V on an unchanged photo keeps it unchanged', (tester) async {
    final session = await pumpShell(tester);
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await ctrl(tester, LogicalKeyboardKey.keyV);
    expect(session.selected!.edit.exposure, 0);
  });

  testWidgets('the Help dialog lists the keyboard shortcuts', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('Keyboard shortcuts (F1)'));
    await tester.pumpAndSettle();
    for (final key in ['Ctrl+Z', 'Ctrl+Y', 'Ctrl+C', 'Ctrl+V', 'Backslash (hold)', 'P', 'X', 'U', 'Left / Right']) {
      expect(find.text(key), findsOneWidget, reason: key);
    }
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
  });

  testWidgets('holding backslash shows the before view', (tester) async {
    final session = await pumpShell(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backslash);
    expect(session.showBefore.value, true);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backslash);
    expect(session.showBefore.value, false);
  });
}
