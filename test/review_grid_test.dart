import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/models/template.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/ui/shared/review_grid.dart';
import 'package:pressframe/ui/theme.dart';

BatchItem item(String name) => BatchItem(path: name, isRaw: false, width: 6000, height: 4000);

Session five() {
  final s = Session()..addItems([for (final n in ['a', 'b', 'c', 'd', 'e']) item(n)]);
  s.select(1);
  s.setFlag(Flag.reject); // b is rejected
  s.select(0);
  return s;
}

Future<void> pump(
  WidgetTester tester,
  Session session, {
  List<Template> templates = const [],
  VoidCallback? onOpenInEdit,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: pressFrameTheme,
      home: Scaffold(
        body: ReviewGrid(
          session: session,
          renderer: null, // stub: tiles are gray
          templates: templates,
          assets: const {},
          onOpenInEdit: onOpenInEdit ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows every photo that will be exported', (tester) async {
    await pump(tester, five());
    expect(find.byType(ReviewTile), findsNWidgets(4));
    expect(find.byKey(const ValueKey('review-b')), findsNothing);
  });

  testWidgets('Compare with original is a toggle that shows the edits again when off', (tester) async {
    await pump(tester, five());
    final chip = find.byKey(const ValueKey('compare-original'));
    expect(tester.widget<FilterChip>(chip).selected, false);
    await tester.tap(chip);
    await tester.pump();
    expect(tester.widget<FilterChip>(chip).selected, true);
    expect(find.byType(ReviewTile), findsNWidgets(4));
  });

  testWidgets('a credit override applies to the tapped photo only', (tester) async {
    final session = five();
    await pump(tester, session);
    await tester.tap(find.byKey(const ValueKey('review-d')));
    await tester.pumpAndSettle();
    expect(session.selected!.path, 'd');

    session.addCreditName('Photo by Ana');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('credit-override')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Photo by Ana').last);
    await tester.pumpAndSettle();
    expect(session.items.map((i) => i.creditOverride), [null, null, null, 'Photo by Ana', null]);

    await tester.tap(find.byKey(const ValueKey('credit-override')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Same as batch').last);
    await tester.pumpAndSettle();
    expect(session.items[3].creditOverride, isNull, reason: 'empty goes back to the batch credit');
  });

  testWidgets('template and shape can be overridden per photo', (tester) async {
    final session = five();
    await pump(tester, session, templates: const [BuiltTemplate(name: 'Band')]);
    await tester.tap(find.byKey(const ValueKey('review-c')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('template-override')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No template').last);
    await tester.pumpAndSettle();
    expect(session.items[2].templateOverride, '');

    await tester.tap(find.byKey(const ValueKey('shape-override')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1:1').last);
    await tester.pumpAndSettle();
    expect(session.items[2].shapeOverride, OutputShape.r1x1);
    expect(session.items[0].shapeOverride, isNull);
  });

  testWidgets('a template with a missing logo file is flagged', (tester) async {
    final session = five()..landscapeTemplate = 'Broken';
    await pump(
      tester,
      session,
      templates: const [
        BuiltTemplate(name: 'Broken', logos: [LogoLayer(file: 'gone.png')]),
        BuiltTemplate(name: 'Fine'),
      ],
    );
    expect(find.byTooltip('A template image is missing'), findsNWidgets(4));

    session.landscapeTemplate = 'Fine';
    await tester.pump();
    expect(find.byTooltip('A template image is missing'), findsNothing);
  });

  testWidgets('Open in Edit calls back with the photo selected', (tester) async {
    final session = five();
    var opened = 0;
    await pump(tester, session, onOpenInEdit: () => opened++);
    await tester.tap(find.byKey(const ValueKey('review-e')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open in Edit'));
    expect(opened, 1);
    expect(session.selected!.path, 'e');
  });

  testWidgets('nothing to review is said plainly', (tester) async {
    await pump(tester, Session());
    expect(find.text('No photos to review. Import photos first.'), findsOneWidget);
  });
}
