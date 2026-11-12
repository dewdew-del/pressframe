import 'package:flutter/foundation.dart';

import 'models/batch_item.dart';
import 'models/edit_params.dart';
import 'models/template.dart';

enum FlagFilter { all, picks, hideRejects }

/// All app state for the current batch of photos.
///
/// Two kinds of listeners: [addListener] hears every committed change; [liveEdit] hears
/// slider movement while dragging, so only the preview repaints during a drag.
class Session extends ChangeNotifier {
  final List<BatchItem> _items = [];
  int _selected = 0;
  // Undo history per photo, keyed by path. Each entry is the photo before a change.
  final Map<String, List<BatchItem>> _undo = {}, _redo = {};
  BatchItem? _dragStart; // the photo as it was before the current slider drag
  EditParams? _clipboard;

  final ValueNotifier<int> _live = ValueNotifier(0);
  Listenable get liveEdit => _live;

  /// True while the user holds the "before" key or presses the photo.
  final ValueNotifier<bool> showBefore = ValueNotifier(false);

  List<BatchItem> get items => List.unmodifiable(_items);
  int get selectedIndex => _selected;
  BatchItem? get selected => _items.isEmpty ? null : _items[_selected];

  FlagFilter _filter = FlagFilter.hideRejects;
  FlagFilter get filter => _filter;
  set filter(FlagFilter f) => _set(() => _filter = f);

  String? _landscapeTemplate, _portraitTemplate; // Template.name
  String? get landscapeTemplate => _landscapeTemplate;
  set landscapeTemplate(String? v) => _set(() => _landscapeTemplate = v);
  String? get portraitTemplate => _portraitTemplate;
  set portraitTemplate(String? v) => _set(() => _portraitTemplate = v);

  OutputShape _landscapeShape = OutputShape.original, _portraitShape = OutputShape.original;
  OutputShape get landscapeShape => _landscapeShape;
  set landscapeShape(OutputShape v) => _set(() => _landscapeShape = v);
  OutputShape get portraitShape => _portraitShape;
  set portraitShape(OutputShape v) => _set(() => _portraitShape = v);

  String _creditText = '';
  String get creditText => _creditText;
  set creditText(String v) => _set(() => _creditText = v);
  CreditStyle _credit = const CreditStyle();
  CreditStyle get credit => _credit;
  set credit(CreditStyle v) => _set(() => _credit = v);

  void _set(void Function() change) {
    change();
    notifyListeners();
  }

  bool _visible(BatchItem i) => switch (_filter) {
    FlagFilter.all => true,
    FlagFilter.picks => i.flag == Flag.pick,
    FlagFilter.hideRejects => i.flag != Flag.reject,
  };

  List<int> get visibleIndexes => [
    for (var i = 0; i < _items.length; i++)
      if (_visible(_items[i])) i,
  ];

  /// Photos that will be exported: everything not rejected, whatever the filter shows.
  List<BatchItem> get exportable => [
    for (final i in _items)
      if (i.flag != Flag.reject) i,
  ];

  void addItems(List<BatchItem> items) {
    if (items.isEmpty) return;
    _items.addAll(items);
    notifyListeners();
  }

  void select(int index) {
    if (index < 0 || index >= _items.length || index == _selected) return;
    _endDrag();
    _selected = index;
    notifyListeners();
  }

  /// Moves to the next (+1) or previous (-1) visible photo.
  void selectNext(int direction) {
    final visible = visibleIndexes;
    if (visible.isEmpty) return;
    final candidates = direction > 0
        ? visible.where((i) => i > _selected)
        : visible.reversed.where((i) => i < _selected);
    if (candidates.isNotEmpty) select(candidates.first);
  }

  void _push(BatchItem before) {
    (_undo[before.path] ??= []).add(before);
    _redo.remove(before.path);
  }

  // A drag that never got its final "commit" still becomes one undo step.
  void _endDrag() {
    final start = _dragStart;
    if (start == null) return;
    _dragStart = null;
    final now = _items[_selected];
    if (start.edit != now.edit || start.crop != now.crop || start.straighten != now.straighten) {
      _push(start);
    }
  }

  /// commit=false while a slider is being dragged, true when it is released.
  void setEdit(EditParams e, {required bool commit}) =>
      updateLive((i) => i.copyWith(edit: e), commit: commit);

  /// A change that arrives many times during one drag (slider, crop handle). The whole
  /// drag becomes a single undo step when it ends with commit=true.
  void updateLive(BatchItem Function(BatchItem) change, {required bool commit}) {
    final current = selected;
    if (current == null) return;
    _dragStart ??= current;
    _items[_selected] = change(current);
    if (commit) {
      _endDrag();
      notifyListeners();
    } else {
      _live.value++;
    }
  }

  /// Any other change to the selected photo (crop, rotate, overrides): one undo step.
  void updateSelected(BatchItem Function(BatchItem) change) {
    final current = selected;
    if (current == null) return;
    _endDrag();
    _push(current);
    _items[_selected] = change(current);
    notifyListeners();
  }

  bool get canUndo => selected != null && (_undo[selected!.path]?.isNotEmpty ?? false);
  bool get canRedo => selected != null && (_redo[selected!.path]?.isNotEmpty ?? false);

  void undo() => _step(_undo, _redo);
  void redo() => _step(_redo, _undo);

  void _step(Map<String, List<BatchItem>> from, Map<String, List<BatchItem>> to) {
    final current = selected;
    if (current == null) return;
    _endDrag();
    final stack = from[current.path];
    if (stack == null || stack.isEmpty) return;
    (to[current.path] ??= []).add(current);
    // Flags are not part of undo: undoing a slider must not un-reject a photo.
    _items[_selected] = stack.removeLast().copyWith(flag: current.flag);
    notifyListeners();
  }

  void resetEdit() => updateSelected((i) => i.copyWith(edit: EditParams.neutral));

  void setFlag(Flag f) {
    final current = selected;
    if (current == null) return;
    _endDrag();
    _items[_selected] = current.copyWith(flag: f);
    if (!_visible(_items[_selected])) {
      // The photo just left the filmstrip: move to the next visible one, else the previous.
      final visible = visibleIndexes;
      if (visible.isNotEmpty) {
        _selected = visible.firstWhere((i) => i > _selected, orElse: () => visible.last);
      }
    }
    notifyListeners();
  }

  void copyEdit() => _clipboard = selected?.edit;

  void pasteEdit() {
    final clip = _clipboard;
    if (clip == null || selected == null) return;
    updateSelected((i) => i.copyWith(edit: clip));
  }

  /// Copies the selected photo's sliders (not its crop) to every non-rejected photo.
  void applyEditToAll() {
    final current = selected;
    if (current == null) return;
    _endDrag();
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (i == _selected || item.flag == Flag.reject || item.edit == current.edit) continue;
      _push(item);
      _items[i] = item.copyWith(edit: current.edit);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _live.dispose();
    showBefore.dispose();
    super.dispose();
  }
}
