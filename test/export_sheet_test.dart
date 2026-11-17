import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/models/template.dart';
import 'package:pressframe/export/exporter.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/ui/shared/export_sheet.dart';
import 'package:pressframe/ui/theme.dart';

const jpg = BatchItem(path: 'a.jpg', isRaw: false, width: 6000, height: 4000);
const smallRaw = BatchItem(path: 'b.arw', isRaw: true, width: 1616, height: 1080);

Future<void> pump(WidgetTester tester, Session session, {String? fixedOutDir}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: pressFrameTheme,
        home: Scaffold(
          body: ExportSheet(
            session: session,
            exporter: null,
            specs: () => const [],
            fixedOutDir: fixedOutDir,
          ),
        ),
      ),
    );

FilledButton exportButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Export'));

void main() {
  test('a finished export says so plainly', () {
    const ok = ExportProgress(done: 3, total: 3, finished: true);
    expect(exportResultText(ok, gallery: true), 'Export successful! 3 photos saved to the gallery album "PressFrame".');
    expect(exportResultText(ok, gallery: false), 'Export successful! 3 photos saved.');
    expect(
      exportResultText(const ExportProgress(done: 1, total: 1, finished: true), gallery: false),
      'Export successful! 1 photo saved.',
    );
    const partly = ExportProgress(done: 3, total: 3, finished: true, failures: [(path: 'x', reason: 'bad')]);
    expect(exportResultText(partly, gallery: false), 'Finished: 2 of 3 exported');
    const stopped = ExportProgress(done: 1, total: 3, finished: true, cancelled: true);
    expect(exportResultText(stopped, gallery: false), 'Cancelled: 1 of 3 exported');
    expect(exportResultText(const ExportProgress(done: 1, total: 3), gallery: false), 'Exporting 1 of 3…');
  });

  test('smallPreview is a RAW under 2000 px', () {
    expect(smallRaw.smallPreview, true);
    expect(jpg.smallPreview, false);
    expect(const BatchItem(path: 'c.cr3', isRaw: true, width: 6000, height: 4000).smallPreview, false);
  });

  testWidgets('warns when a RAW with a small preview will be exported', (tester) async {
    await pump(tester, Session()..addItems([jpg, smallRaw]));
    expect(find.text('1 RAW photo will export small'), findsOneWidget);
    expect(find.text('Export 2 photos'), findsOneWidget);
  });

  testWidgets('no warning without small RAW files, and rejected ones do not count', (tester) async {
    final session = Session()..addItems([jpg, smallRaw]);
    session.select(1);
    session.setFlag(Flag.reject);
    await pump(tester, session);
    expect(find.textContaining('will export small'), findsNothing);
    expect(find.text('Export 1 photo'), findsOneWidget);
  });

  test('the new folder is named after the event, with unsafe characters removed', () {
    final sep = Platform.pathSeparator;
    expect(exportFolder('D', 'Intrams: Day 1/2?', newFolder: true), 'D${sep}Intrams Day 12');
    expect(exportFolder('D', '', newFolder: true), 'D${sep}Event');
    expect(exportFolder('D', 'Intrams', newFolder: false), 'D');
  });

  testWidgets('laptop: a folder can be changed and a new folder is offered', (tester) async {
    // No Downloads folder is known in a widget test, so Export stays off until one is chosen.
    await pump(tester, Session()..addItems([jpg]));
    await tester.pump();
    expect(exportButton(tester).onPressed, isNull);
    expect(find.text('No folder chosen'), findsOneWidget);
    expect(find.text('Change…'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, true);
    expect(find.text('New folder for this event'), findsOneWidget);
  });

  testWidgets('phone: the gallery is the only place, so no folder controls', (tester) async {
    await pump(tester, Session()..addItems([jpg]), fixedOutDir: 'x');
    expect(find.text('Change…'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
  });

  testWidgets('nothing to export is said plainly', (tester) async {
    await pump(tester, Session(), fixedOutDir: 'x');
    expect(find.text('There are no photos to export.'), findsOneWidget);
    expect(exportButton(tester).onPressed, isNull);
  });

  testWidgets('no size controls: photos export at their own size', (tester) async {
    await pump(tester, Session()..addItems([jpg]));
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    expect(find.text('JPEG quality'), findsOneWidget);
    expect(find.text('Long edge (px)'), findsNothing);
    expect(find.text('Full size'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  test('warns about photos without a template and about a credit with no text', () {
    const credit = CreditStyle(enabled: true);
    RenderSpec spec(String n, {Template? t, String text = ''}) => (
      item: BatchItem(path: 'x/$n.jpg', isRaw: false, width: 10, height: 10),
      shape: OutputShape.original,
      template: t,
      creditText: text,
      credit: credit,
    );
    const band = BuiltTemplate(name: 'Band');
    expect(exportWarnings([spec('a', t: band, text: 'Ana')]), isEmpty);
    final w = exportWarnings([spec('a.x'), spec('b', t: band, text: ' ')]);
    expect(w, hasLength(2));
    expect(w[0], contains('1 photo has no template: a.x.jpg'));
    expect(w[1], contains('no text for 2 photos'));
  });
}
