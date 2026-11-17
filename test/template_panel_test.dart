import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/models/template.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/ui/shared/template_panel.dart';
import 'package:pressframe/ui/theme.dart';

Future<Session> pump(WidgetTester tester) async {
  final session = Session()
    ..addItems([const BatchItem(path: 'a.jpg', isRaw: false, width: 6000, height: 4000)]);
  await tester.pumpWidget(
    MaterialApp(
      theme: pressFrameTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 320, child: TemplatePanel(session: session, library: null)),
        ),
      ),
    ),
  );
  return session;
}

void main() {
  testWidgets('photo credit is off by default and the switch reveals its text field', (tester) async {
    final session = await pump(tester);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('credit-switch'))).value, false);
    expect(find.byKey(const ValueKey('credit-text')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('credit-switch')));
    await tester.pump();
    expect(session.credit.enabled, true);
    expect(find.byKey(const ValueKey('credit-text')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('credit-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a name…').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Photo by Ana');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(session.creditText, 'Photo by Ana');
    expect(session.creditNames, ['Photo by Ana']);

    await tester.tap(find.text('Black'));
    await tester.pump();
    expect(session.credit.white, false);
  });

  testWidgets('the shape picker sets the batch shape', (tester) async {
    final session = await pump(tester);
    await tester.tap(find.text('Original').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('16:9').last);
    await tester.pumpAndSettle();
    expect(session.landscapeShape, OutputShape.r16x9);
    expect(session.portraitShape, OutputShape.original);
  });

  test('frames are offered only for the shape they fit', () {
    const band = BuiltTemplate(name: 'Band');
    const frame = FrameTemplate(name: 'F', file: 'f.png', aspect: 0.8);
    expect(templatesFor(const [band, frame], OutputShape.r4x5), [band, frame]);
    expect(templatesFor(const [band, frame], OutputShape.r1x1), [band]);
    expect(templatesFor(const [band, frame], OutputShape.original), [band]);
  });

  testWidgets('with no templates the panel says so', (tester) async {
    await pump(tester);
    expect(find.text('No templates yet. Photos export without branding.'), findsOneWidget);
  });
}
