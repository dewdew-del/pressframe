import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/ui/shared/color_picker.dart';

void main() {
  Future<List<int>> open(WidgetTester tester) async {
    final picked = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ColorField(label: 'Start color', color: 0xFF0B3D91, onChanged: picked.add),
        ),
      ),
    );
    return picked;
  }

  testWidgets('the row shows no text box; tapping it opens the picker', (tester) async {
    await open(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.text('Start color'));
    await tester.pumpAndSettle();
    expect(find.text('Ready colors'), findsOneWidget);
    expect(find.text('Mix your own'), findsOneWidget);
  });

  testWidgets('tapping a ready color picks it', (tester) async {
    final picked = await open(tester);
    await tester.tap(find.text('Start color'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('swatch-FFD32F2F')));
    await tester.pump();
    expect(picked.last, 0xFFD32F2F);
  });

  testWidgets('dragging on the mixer and the rainbow bar changes the color', (tester) async {
    final picked = await open(tester);
    await tester.tap(find.text('Start color'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('mixer-square'))));
    await tester.pump();
    final afterSquare = picked.last;
    final bar = tester.getRect(find.byKey(const ValueKey('mixer-hue')));
    await tester.tapAt(Offset(bar.left + bar.width / 3, bar.center.dy)); // green
    await tester.pump();
    expect(picked.last, isNot(afterSquare));
    final c = Color(picked.last);
    expect(c.g, greaterThan(c.r));
    expect(c.g, greaterThan(c.b));
  });
}
