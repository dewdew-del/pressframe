import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/ui/desktop_shell.dart';
import 'package:pressframe/ui/shared/review_grid.dart';
import 'package:pressframe/ui/theme.dart';

Future<Session> pumpShell(WidgetTester tester, {int photos = 1}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session()
    ..addItems([
      for (var i = 0; i < photos; i++)
        BatchItem(path: 'p$i.jpg', isRaw: false, width: 6000, height: 4000),
    ]);
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

const brightness = ValueKey('slider-Brightness');

void main() {
  testWidgets('every slider is always shown; there is no More controls row', (tester) async {
    await pumpShell(tester);
    for (final label in [
      'Brightness', 'Contrast', 'Shadows', 'Highlights', 'Whites', 'Blacks', //
      'Warmth', 'Saturation', 'Tint', 'Vibrance', 'Sharpen', 'Texture', 'Clarity',
    ]) {
      expect(find.byKey(ValueKey('slider-$label'), skipOffstage: false), findsOneWidget, reason: label);
    }
    expect(find.text('More controls', skipOffstage: false), findsNothing);
    expect(find.text('Auto fix'), findsNothing);
    expect(find.text('Exposure'), findsNothing);
    expect(find.text('Temperature'), findsNothing);
  });

  testWidgets('no step label is underlined', (tester) async {
    await pumpShell(tester);
    for (final step in ['1 Edit', '2 Review', '3 Export']) {
      expect(tester.widget<Text>(find.text(step)).style!.decoration, isNull, reason: step);
    }
    expect(tester.widget<Text>(find.text('1 Edit')).style!.fontWeight, FontWeight.w700);
  });

  testWidgets('values read as whole numbers, Brightness with two decimals', (tester) async {
    final session = await pumpShell(tester);
    session.setEdit(
      session.selected!.edit.copyWith(exposure: 0.5, contrast: 0.25, temperature: -0.4),
      commit: true,
    );
    await tester.pump();
    expect(find.text('+0.50'), findsOneWidget);
    expect(find.text('+25'), findsOneWidget);
    expect(find.text('-40'), findsOneWidget);
  });

  testWidgets('dragging Brightness edits the photo and Ctrl+Z undoes it', (tester) async {
    final session = await pumpShell(tester);
    await tester.drag(find.byKey(brightness), const Offset(60, 0));
    await tester.pump();
    expect(session.selected!.edit.exposure, greaterThan(0));
    expect(session.canUndo, true);

    await ctrl(tester, LogicalKeyboardKey.keyZ);
    expect(session.selected!.edit.exposure, 0);
    expect(find.text('Undone. Redo?'), findsNothing, reason: 'undo shows no toast');
    await ctrl(tester, LogicalKeyboardKey.keyY);
    expect(session.selected!.edit.exposure, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 500)); // let the double-tap timer run out
  });

  testWidgets('the undo and redo buttons on the photo, with no toast', (tester) async {
    final session = await pumpShell(tester);
    session.setEdit(session.selected!.edit.copyWith(contrast: 0.5), commit: true);
    await tester.pump();
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pumpAndSettle();
    expect(session.selected!.edit.contrast, 0);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byTooltip('Redo (Ctrl+Y)'));
    await tester.pump();
    expect(session.selected!.edit.contrast, 0.5);
  });

  testWidgets('double-tapping a slider resets it', (tester) async {
    final session = await pumpShell(tester);
    await tester.drag(find.byKey(brightness), const Offset(60, 0));
    await tester.pump();
    expect(session.selected!.edit.exposure, greaterThan(0));

    await tester.tap(find.byKey(brightness));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(brightness));
    await tester.pumpAndSettle();
    expect(session.selected!.edit.exposure, 0);
  });

  testWidgets('Ctrl+C then Ctrl+V on an unchanged photo keeps it unchanged', (tester) async {
    final session = await pumpShell(tester);
    await ctrl(tester, LogicalKeyboardKey.keyC);
    await ctrl(tester, LogicalKeyboardKey.keyV);
    expect(session.selected!.edit.exposure, 0);
  });

  testWidgets('the step bar and the main button walk Edit, Review, Export', (tester) async {
    await pumpShell(tester, photos: 2);
    for (final step in ['1 Edit', '2 Review', '3 Export']) {
      expect(find.text(step), findsOneWidget, reason: step);
    }
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Export all'), findsNothing);

    await tester.tap(find.text('Next: Review →'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewGrid), findsOneWidget);
    expect(find.text('Next: Review →'), findsNothing);

    await tester.tap(find.text('Export all'));
    await tester.pumpAndSettle();
    expect(find.text('Event name'), findsOneWidget, reason: 'the export sheet is open');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1 Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewGrid), findsNothing);
    expect(find.text('Next: Review →'), findsOneWidget);
  });

  testWidgets('the More menu holds kit, filter and apply to all', (tester) async {
    final session = await pumpShell(tester, photos: 2);
    session.setEdit(session.selected!.edit.copyWith(exposure: 0.5), commit: true);
    await tester.pump();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    for (final entry in ['Export kit', 'Import kit', 'Show: All', 'Show: Picks', 'Show: Hide rejects', 'Apply to all']) {
      expect(find.text(entry), findsOneWidget, reason: entry);
    }
    await tester.tap(find.text('Apply to all'));
    await tester.pumpAndSettle();
    expect(session.items[1].edit.exposure, 0.5);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show: All'));
    await tester.pumpAndSettle();
    expect(session.filter, FlagFilter.all);
  });

  testWidgets('Before / After on the photo, and holding backslash', (tester) async {
    final session = await pumpShell(tester);
    await tester.tap(find.text('Before / After'));
    expect(session.showBefore.value, true);
    await tester.tap(find.text('Before / After'));
    expect(session.showBefore.value, false);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.backslash);
    expect(session.showBefore.value, true);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backslash);
    expect(session.showBefore.value, false);
    expect(find.text('Scroll to zoom, drag to move.'), findsOneWidget);
  });

  testWidgets('Presets start minimized and open from their header', (tester) async {
    await pumpShell(tester);
    expect(find.text('Indoor gym'), findsNothing);
    await tester.tap(find.text('Presets'));
    await tester.pumpAndSettle();
    expect(find.text('Indoor gym'), findsOneWidget);
    await tester.tap(find.text('Presets'));
    await tester.pumpAndSettle();
    expect(find.text('Indoor gym'), findsNothing);
  });

  testWidgets('with no photos the first screen says how to start', (tester) async {
    await pumpShell(tester, photos: 0);
    expect(find.byKey(const ValueKey('app-logo')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add photos'), findsOneWidget);
    expect(find.text('or drop photos or a folder here'), findsOneWidget);
    for (final line in ['1 Edit one photo', '2 Review the batch', '3 Export all']) {
      expect(find.text(line), findsNothing, reason: line);
    }
    expect(find.text('Before / After'), findsNothing);
  });

  testWidgets('every icon button has a tooltip', (tester) async {
    await pumpShell(tester);
    for (final b in tester.widgetList<IconButton>(find.byType(IconButton))) {
      expect(b.tooltip, isNotNull);
    }
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
}
