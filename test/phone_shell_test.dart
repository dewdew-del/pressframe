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

Future<Session> pumpApp(WidgetTester tester, Size size, {int photos = 3}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = Session()..addItems([for (final n in ['a', 'b', 'c'].take(photos)) item(n)]);
  await tester.pumpWidget(PressFrameApp(session: session));
  return session;
}

const phone = Size(390, 844);
const tabs = ['Light', 'Color', 'Crop', 'Template'];

void main() {
  testWidgets('the layout follows the window width', (tester) async {
    await pumpApp(tester, const Size(1280, 800));
    expect(find.byType(DesktopShell), findsOneWidget);
    expect(find.byType(PhoneShell), findsNothing);

    await pumpApp(tester, phone);
    expect(find.byType(PhoneShell), findsOneWidget);
    expect(find.byType(DesktopShell), findsNothing);
  });

  testWidgets('exactly four bottom tabs, one tool group at a time', (tester) async {
    await pumpApp(tester, phone);
    for (final t in tabs) {
      expect(find.byKey(ValueKey('tab-$t')), findsOneWidget, reason: t);
    }
    expect(find.byKey(const ValueKey('tab-Presets')), findsNothing);
    expect(find.byKey(const ValueKey('tab-Detail')), findsNothing);
    expect(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('tab-')), findsNWidgets(4));

    // Light is shown first: sliders right away, presets folded until "Presets" is tapped.
    expect(find.text('Brightness'), findsOneWidget);
    expect(find.text('Indoor gym'), findsNothing);
    await tester.tap(find.text('Presets'));
    await tester.pumpAndSettle();
    expect(find.text('Indoor gym'), findsOneWidget);
    await tester.tap(find.text('Presets'));
    await tester.pumpAndSettle();
    expect(find.text('Sharpen'), findsOneWidget);
    expect(find.text('Auto fix'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab-Color')));
    await tester.pumpAndSettle();
    expect(find.text('Warmth'), findsOneWidget);
    expect(find.text('Brightness'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tab-Crop')));
    await tester.pumpAndSettle();
    expect(find.byType(CropView), findsOneWidget);
    expect(find.text('Rotate right'), findsOneWidget);
  });

  testWidgets('a visible Before / After button on the photo, hidden while cropping', (tester) async {
    final session = await pumpApp(tester, phone);
    final button = find.widgetWithText(FilledButton, 'Before / After');
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    expect(session.showBefore.value, true);
    await tester.tap(button);
    expect(session.showBefore.value, false);

    await tester.tap(find.byKey(const ValueKey('tab-Crop')));
    await tester.pumpAndSettle();
    expect(button, findsNothing);
  });

  testWidgets('tabs are at least 44 px tall with 14 px text', (tester) async {
    await pumpApp(tester, phone);
    for (final t in tabs) {
      final tab = find.byKey(ValueKey('tab-$t'));
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(44), reason: t);
      final text = tester.widget<Text>(find.descendant(of: tab, matching: find.text(t)));
      expect(text.style!.fontSize, 14, reason: t);
    }
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

  testWidgets('the menu has import, kit, filter and apply to all, not review or export', (tester) async {
    await pumpApp(tester, phone);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    for (final entry in ['Add photos', 'Export kit', 'Import kit', 'Show: All', 'Apply to all']) {
      expect(find.text(entry), findsOneWidget, reason: entry);
    }
    expect(find.text('Review'), findsNothing);
    expect(find.text('Export'), findsNothing);
  });

  testWidgets('Next goes from Edit to Review to Export', (tester) async {
    await pumpApp(tester, phone);
    await tester.tap(find.text('Next →'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-a')), findsOneWidget);

    await tester.tap(find.text('Next →'));
    await tester.pumpAndSettle();
    expect(find.text('Event name'), findsOneWidget, reason: 'the export page is open');
  });

  testWidgets('with no photos the first screen says how to start', (tester) async {
    await pumpApp(tester, phone, photos: 0);
    expect(find.widgetWithText(FilledButton, 'Add photos'), findsOneWidget);
    for (final line in ['1 Edit one photo', '2 Review the batch', '3 Export all']) {
      expect(find.text(line), findsNothing, reason: line);
    }
  });

  testWidgets('the Light tools survive a scroll and a tab switch', (tester) async {
    await pumpApp(tester, phone);
    await tester.drag(find.text('Contrast'), const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-Color')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-Light')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Presets'), findsOneWidget);
  });

  testWidgets('the Export page goes straight back to editing', (tester) async {
    await pumpApp(tester, phone);
    await tester.tap(find.text('Next →'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next →'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back to editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tab-Light')).hitTestable(), findsOneWidget);
    expect(find.text('Back to editing'), findsNothing);
  });

  testWidgets('Back asks first, then returns to the Add photos screen', (tester) async {
    final session = await pumpApp(tester, phone);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel editing?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(session.items.length, 3);

    // The phone's own back button asks the same question.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel editing'));
    await tester.pumpAndSettle();
    expect(session.items, isEmpty);
    expect(session.canUndo, false);
    expect(find.widgetWithText(FilledButton, 'Add photos'), findsOneWidget);
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
