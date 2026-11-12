import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/main.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/session.dart';
import 'package:pressframe/ui/desktop_shell.dart';
import 'package:pressframe/ui/phone_shell.dart';
import 'package:pressframe/ui/shared/crop_view.dart';
import 'package:pressframe/ui/shared/filmstrip.dart';
import 'package:pressframe/ui/theme.dart';

BatchItem item(String name) => BatchItem(path: name, isRaw: false, width: 6000, height: 4000);

Future<Session> pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session()..addItems([item('a'), item('b'), item('c')]);
  await tester.pumpWidget(PressFrameApp(session: session));
  return session;
}

const phone = Size(390, 844);
const tabs = ['Presets', 'Light', 'Color', 'Detail', 'Crop', 'Template'];

void main() {
  testWidgets('the layout follows the window width', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(PhoneShell), findsNothing);

    await pumpApp(tester, phone);
    expect(find.byType(PhoneShell), findsOneWidget);
    expect(find.byType(DesktopShell), findsNothing);
  });

  testWidgets('bottom tabs show one tool group at a time', (tester) async {
    await pumpApp(tester, phone);
    for (final t in tabs) {
      expect(find.byKey(ValueKey('tab-$t')), findsOneWidget, reason: t);
    }
    expect(find.text('Exposure'), findsOneWidget, reason: 'Light is the first tab shown');

    await tester.tap(find.byKey(const ValueKey('tab-Color')));
    await tester.pumpAndSettle();
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('Exposure'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab-Crop')));
    await tester.pumpAndSettle();
    expect(find.byType(CropView), findsOneWidget);
    expect(find.text('Rotate right'), findsOneWidget);
  });

  testWidgets('everything tappable is at least 48 by 48', (tester) async {
    await pumpApp(tester, phone);
    for (final tab in tabs) {
      await tester.tap(find.byKey(ValueKey('tab-$tab')));
      await tester.pumpAndSettle();
      final targets = [
        for (final t in tabs) find.byKey(ValueKey('tab-$t')),
        find.byType(IconButton),
        find.byType(TextButton),
        find.byType(OutlinedButton),
        find.byType(FilledButton),
        find.byType(PopupMenuButton<VoidCallback>),
        find.byType(FilmstripTile),
        find.byType(ActionChip),
        find.byType(Slider),
        find.byType(SwitchListTile), // the whole row is the target, not the small switch in it
      ];
      for (final finder in targets) {
        for (final element in finder.evaluate()) {
          final size = tester.getSize(find.byElementPredicate((e) => e == element));
          expect(
            size.width >= 48 && size.height >= 48,
            true,
            reason: '${element.widget.runtimeType} on the $tab tab is $size',
          );
        }
      }
    }
  });

  testWidgets('the top bar shows the position and flags the photo', (tester) async {
    final session = await pumpApp(tester, phone);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Flag this photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(session.items[0].flag, Flag.pick);

    await tester.tap(find.byTooltip('Flag this photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    expect(session.items[0].flag, Flag.reject);
    expect(session.selectedIndex, 1, reason: 'moves on to the next photo');
  });

  testWidgets('the menu opens Review as a full page', (tester) async {
    await pumpApp(tester, phone);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    for (final entry in ['Add photos', 'Review', 'Export', 'Export kit', 'Import kit', 'Apply to all']) {
      expect(find.text(entry), findsOneWidget, reason: entry);
    }
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-a')), findsOneWidget);
    expect(find.byType(PhoneShell, skipOffstage: true), findsNothing);
  });

  testWidgets('a denied gallery permission is explained, with a way forward', (tester) async {
    var allowed = false, checks = 0, opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: pressFrameTheme,
        home: Scaffold(
          body: GalleryGate(
            check: () async {
              checks++;
              return allowed;
            },
            openSettings: () => opened++,
            child: const Text('export form'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('export form'), findsNothing);
    expect(find.textContaining('needs permission'), findsOneWidget);

    await tester.tap(find.text('Open settings'));
    expect(opened, 1);

    allowed = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(find.text('export form'), findsOneWidget);
  });
}
