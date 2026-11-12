import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/models/edit_params.dart';
import 'package:pressframe/session.dart';

BatchItem item(String name, {int w = 6000, int h = 4000}) =>
    BatchItem(path: name, isRaw: false, width: w, height: h);

Session three() => Session()..addItems([item('a'), item('b'), item('c')]);

EditParams exp(double v) => EditParams(exposure: v);

void main() {
  test('a slider drag is one undo step', () {
    final s = three();
    s.setEdit(exp(0.5), commit: true);
    s.setEdit(exp(0.6), commit: false);
    s.setEdit(exp(0.7), commit: false);
    s.setEdit(exp(0.8), commit: false);
    s.setEdit(exp(0.9), commit: true);
    expect(s.selected!.edit, exp(0.9));
    s.undo();
    expect(s.selected!.edit, exp(0.5));
    s.undo();
    expect(s.selected!.edit, EditParams.neutral);
    expect(s.canUndo, false);
  });

  test('live edits notify only the live listener', () {
    final s = three();
    var full = 0, live = 0;
    s.addListener(() => full++);
    s.liveEdit.addListener(() => live++);
    s.setEdit(exp(0.1), commit: false);
    expect((full, live), (0, 1));
    s.setEdit(exp(0.2), commit: true);
    expect(full, 1);
  });

  test('undo is per photo', () {
    final s = three();
    s.setEdit(exp(0.5), commit: true);
    s.select(1);
    s.setEdit(exp(1.0), commit: true);
    s.select(0);
    s.undo();
    expect(s.items[0].edit, EditParams.neutral);
    expect(s.items[1].edit, exp(1.0));
  });

  test('redo restores, and a new commit clears redo', () {
    final s = three();
    s.setEdit(exp(0.5), commit: true);
    s.undo();
    expect(s.canRedo, true);
    s.redo();
    expect(s.selected!.edit, exp(0.5));
    s.undo();
    s.setEdit(exp(0.2), commit: true);
    expect(s.canRedo, false);
  });

  test('undo does not bring back an old flag', () {
    final s = three();
    s.setEdit(exp(0.5), commit: true);
    s.filter = FlagFilter.all;
    s.setFlag(Flag.pick);
    s.undo();
    expect(s.selected!.flag, Flag.pick);
    expect(s.selected!.edit, EditParams.neutral);
  });

  test('applyEditToAll copies the edit but not crop, and skips rejects', () {
    final s = three();
    s.filter = FlagFilter.all;
    s.select(2);
    s.setFlag(Flag.reject);
    s.select(1);
    s.updateSelected((i) => i.copyWith(crop: () => const Rect.fromLTWH(0, 0, 0.5, 0.5)));
    s.select(0);
    s.setEdit(exp(0.7), commit: true);
    s.applyEditToAll();
    expect(s.items[1].edit, exp(0.7));
    expect(s.items[1].crop, const Rect.fromLTWH(0, 0, 0.5, 0.5));
    expect(s.items[2].edit, EditParams.neutral);
    s.select(1);
    s.undo();
    expect(s.items[1].edit, EditParams.neutral, reason: 'apply to all can be undone per photo');
  });

  test('filters and exportable', () {
    final s = three();
    s.select(1);
    s.setFlag(Flag.reject);
    expect(s.visibleIndexes, [0, 2]);
    expect(s.exportable.map((i) => i.path), ['a', 'c']);
    s.filter = FlagFilter.all;
    expect(s.visibleIndexes, [0, 1, 2]);
    expect(s.exportable.map((i) => i.path), ['a', 'c']);
    s.select(0);
    s.setFlag(Flag.pick);
    s.filter = FlagFilter.picks;
    expect(s.visibleIndexes, [0]);
    expect(s.exportable.map((i) => i.path), ['a', 'c']);
  });

  test('rejecting the selected photo under hideRejects selects the next visible one', () {
    final s = three();
    s.select(1);
    s.setFlag(Flag.reject);
    expect(s.selectedIndex, 2);
    s.setFlag(Flag.reject);
    expect(s.selectedIndex, 0);
  });

  test('copy and paste edit', () {
    final s = three();
    s.pasteEdit(); // nothing copied: no-op
    expect(s.selected!.edit, EditParams.neutral);
    expect(s.canUndo, false);
    s.setEdit(exp(0.4), commit: true);
    s.copyEdit();
    s.select(1);
    s.pasteEdit();
    expect(s.items[1].edit, exp(0.4));
  });

  test('resetEdit clears sliders as one undo step', () {
    final s = three();
    s.setEdit(exp(0.4), commit: true);
    s.resetEdit();
    expect(s.selected!.edit, EditParams.neutral);
    s.undo();
    expect(s.selected!.edit, exp(0.4));
  });

  test('an empty session is safe', () {
    final s = Session();
    expect(s.selected, isNull);
    s.setEdit(exp(1), commit: true);
    s.undo();
    s.redo();
    s.setFlag(Flag.pick);
    s.applyEditToAll();
    s.selectNext(1);
    expect(s.items, isEmpty);
  });

  test('selectNext moves through visible photos only', () {
    final s = three();
    s.select(1);
    s.setFlag(Flag.reject); // now on 2
    s.selectNext(-1);
    expect(s.selectedIndex, 0);
    s.selectNext(-1);
    expect(s.selectedIndex, 0);
    s.selectNext(1);
    expect(s.selectedIndex, 2);
  });
}
