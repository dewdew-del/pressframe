import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/ui/desktop_shell.dart';
import 'package:pressframe/ui/shared/crop_view.dart';
import 'package:pressframe/ui/theme.dart';

const start = Rect.fromLTWH(0.2, 0.2, 0.5, 0.5);

Future<Session> pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session()
    ..addItems([const BatchItem(path: 'a.jpg', isRaw: false, width: 6000, height: 4000)])
    ..updateSelected((i) => i.copyWith(crop: () => start));
  await tester.pumpWidget(
    MaterialApp(theme: pressFrameTheme, home: DesktopShell(session: session)),
  );
  // The crop tool lives in the pill at the top right of the photo.
  await tester.tap(find.byTooltip('Crop and rotate'));
  await tester.pumpAndSettle();
  return session;
}

void main() {
  testWidgets('Rotate right turns the photo and clears the crop', (tester) async {
    final session = await pumpShell(tester);
    await tester.tap(find.text('Rotate right'));
    await tester.pump();
    expect(session.selected!.quarterTurns, 1);
    expect(session.selected!.crop, isNull);
    await tester.tap(find.text('Rotate left'));
    await tester.tap(find.text('Rotate left'));
    await tester.pump();
    expect(session.selected!.quarterTurns, 3);
  });

  testWidgets('dragging the crop rect moves it, as one undo step', (tester) async {
    final session = await pumpShell(tester);
    expect(find.byType(CropView), findsOneWidget);

    await tester.drag(find.byType(CropView), const Offset(40, 0));
    await tester.pump();
    final moved = session.selected!.crop!;
    expect(moved.left, greaterThan(start.left));
    expect(moved.width, closeTo(start.width, 1e-9));
    expect(moved.top, closeTo(start.top, 1e-9));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(session.selected!.crop, start);
  });

  testWidgets('Reset crop clears crop and straighten', (tester) async {
    final session = await pumpShell(tester);
    session.updateSelected((i) => i.copyWith(straighten: 5));
    await tester.pump();
    await tester.tap(find.text('Reset crop'));
    await tester.pump();
    expect(session.selected!.crop, isNull);
    expect(session.selected!.straighten, 0);
  });

  test('moveCrop keeps the rect inside its bounds', () {
    const bounds = Rect.fromLTWH(0, 0, 1, 1);
    final r = moveCrop(start, const Offset(0.9, -0.9), bounds);
    expect(r.right, closeTo(1, 1e-9));
    expect(r.top, closeTo(0, 1e-9));
    expect(r.width, closeTo(start.width, 1e-9));
    expect(r.height, closeTo(start.height, 1e-9));
  });

  test('resizeCrop keeps the locked pixel aspect and stays in bounds', () {
    const bounds = Rect.fromLTWH(0, 0, 1, 1);
    const photo = Size(6000, 4000);
    // Drag the bottom-right corner far outside the photo with a square lock.
    final r = resizeCrop(start, Alignment.bottomRight, const Offset(2, 2), bounds, photo, 1.0);
    expect((r.width * 6000) / (r.height * 4000), closeTo(1.0, 1e-6));
    expect(r.topLeft, start.topLeft);
    expect(r.right <= 1 + 1e-9 && r.bottom <= 1 + 1e-9, true);
    // Free resize follows the pointer.
    final f = resizeCrop(start, Alignment.topLeft, const Offset(0.1, 0.3), bounds, photo, null);
    expect(f.left, closeTo(0.1, 1e-9));
    expect(f.top, closeTo(0.3, 1e-9));
    expect(f.bottomRight, start.bottomRight);
  });

  testWidgets('the grid tool shows and hides the grid', (tester) async {
    final session = await pumpShell(tester);
    await tester.tap(find.byTooltip('Crop and rotate')); // close the crop tool again
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show the grid'));
    await tester.pump();
    expect(session.showGrid.value, true);
    await tester.tap(find.byTooltip('Hide the grid'));
    await tester.pump();
    expect(session.showGrid.value, false);
  });
}
