import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
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
    expect(find.textContaining('small preview'), findsOneWidget);
    expect(find.text('2 photos will be exported'), findsOneWidget);
  });

  testWidgets('no warning without small RAW files, and rejected ones do not count', (tester) async {
    final session = Session()..addItems([jpg, smallRaw]);
    session.select(1);
    session.setFlag(Flag.reject);
    await pump(tester, session);
    expect(find.textContaining('small preview'), findsNothing);
    expect(find.text('1 photo will be exported'), findsOneWidget);
  });

  testWidgets('Export stays off until a folder is chosen', (tester) async {
    await pump(tester, Session()..addItems([jpg]));
    expect(exportButton(tester).onPressed, isNull);
    expect(find.text('Choose folder'), findsOneWidget);
  });

  testWidgets('nothing to export is said plainly', (tester) async {
    await pump(tester, Session(), fixedOutDir: 'x');
    expect(find.text('There are no photos to export.'), findsOneWidget);
    expect(exportButton(tester).onPressed, isNull);
  });

  testWidgets('Full size turns the long edge field off', (tester) async {
    await pump(tester, Session()..addItems([jpg]));
    TextField field() => tester.widget<TextField>(find.byKey(const ValueKey('long-edge')));
    expect(find.byKey(const ValueKey('long-edge')), findsNothing); // folded away by default
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    expect(field().enabled, true);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(field().enabled, false);
  });
}
