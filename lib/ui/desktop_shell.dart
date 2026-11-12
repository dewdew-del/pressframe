import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/auto_fix.dart';
import '../engine/decode.dart';
import '../engine/renderer.dart';
import '../models/batch_item.dart';
import '../session.dart';
import 'shared/preview_view.dart';
import 'shared/slider_group.dart';
import 'theme.dart';

/// Reads a small copy of the selected photo and moves the sliders to a sensible start.
Future<void> runAutoFix(Session session) async {
  final item = session.selected;
  if (item == null) return;
  final ui.Image small;
  try {
    small = await decodeImage(item.path, maxLongEdge: 256);
  } on DecodeFailure {
    return; // the preview already shows why this photo cannot be opened
  }
  final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
  final (w, h) = (small.width, small.height);
  small.dispose();
  if (data == null || session.selected?.path != item.path) return;
  session.setEdit(
    autoFix(data.buffer.asUint8List(), w, h, session.selected!.edit),
    commit: true,
  );
}

/// Laptop layout: top bar, photo with a 320 px tool panel on the right, bottom bar.
class DesktopShell extends StatefulWidget {
  final Session session;
  final Renderer? renderer; // null in widget tests
  const DesktopShell({super.key, required this.session, this.renderer});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  Session get session => widget.session;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Leave typing alone: letters in a text field are text, not shortcuts.
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backslash) {
      session.showBefore.value = event is! KeyUpEvent;
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final action = switch ((ctrl, key)) {
      (true, LogicalKeyboardKey.keyZ) => session.undo,
      (true, LogicalKeyboardKey.keyY) => session.redo,
      (true, LogicalKeyboardKey.keyC) => session.copyEdit,
      (true, LogicalKeyboardKey.keyV) => session.pasteEdit,
      (false, LogicalKeyboardKey.arrowLeft) => () => session.selectNext(-1),
      (false, LogicalKeyboardKey.arrowRight) => () => session.selectNext(1),
      (false, LogicalKeyboardKey.keyP) => () => session.setFlag(Flag.pick),
      (false, LogicalKeyboardKey.keyX) => () => session.setFlag(Flag.reject),
      (false, LogicalKeyboardKey.keyU) => () => session.setFlag(Flag.none),
      _ => null,
    };
    if (action == null) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  // Temporary import for Task 4; Task 7 replaces it with folders, drag and drop and a
  // skipped-files list.
  Future<void> _import() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'cr3', 'cr2', 'arw'],
    );
    final items = <BatchItem>[];
    for (final path in picked.map((f) => f.path).nonNulls) {
      try {
        final p = await probe(path);
        items.add(BatchItem(path: path, isRaw: p.isRaw, width: p.width, height: p.height));
      } on DecodeFailure {
        // listed to the user from Task 7 on
      }
    }
    session.addItems(items);
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _onKey,
    child: Scaffold(
      body: Column(
        children: [
          _topBar(),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: PreviewView(session: session, renderer: widget.renderer),
                ),
                const VerticalDivider(width: 1),
                SizedBox(width: 320, child: _panel()),
              ],
            ),
          ),
          const Divider(height: 1),
          _bottomBar(),
        ],
      ),
    ),
  );

  Widget _topBar() => Container(
    color: panelColor,
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        const Text('PressFrame', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        const SizedBox(width: 24),
        TextButton(onPressed: _import, child: const Text('Import')),
        TextButton(onPressed: () {}, child: const Text('Edit')),
        const TextButton(onPressed: null, child: Text('Review')),
        const TextButton(onPressed: null, child: Text('Export')),
        const Spacer(),
        const TextButton(onPressed: null, child: Text('Kit ▾')),
      ],
    ),
  );

  Widget _panel() => Container(
    color: panelColor,
    child: SingleChildScrollView(
      child: Column(
        children: [
          _section('Presets', const [_Later('Presets arrive in a later step.')], open: false),
          _section('Light', [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: OutlinedButton(
                  onPressed: () => runAutoFix(session),
                  child: const Text('Auto fix'),
                ),
              ),
            ),
            SliderGroup(session: session, sliders: lightSliders),
          ]),
          _section('Color', [SliderGroup(session: session, sliders: colorSliders)]),
          _section('Detail', [SliderGroup(session: session, sliders: detailSliders)]),
          _section('Crop', const [_Later('Crop arrives in the next step.')], open: false),
          _section('Template', const [_Later('Templates arrive in a later step.')], open: false),
        ],
      ),
    ),
  );

  Widget _section(String title, List<Widget> children, {bool open = true}) => ExpansionTile(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    initiallyExpanded: open,
    maintainState: true,
    children: children,
  );

  Widget _bottomBar() => Container(
    color: panelColor,
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: ListenableBuilder(
      listenable: session,
      builder: (context, _) => Row(
        children: [
          IconButton(
            tooltip: 'Undo (Ctrl+Z)',
            onPressed: session.canUndo ? session.undo : null,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Redo (Ctrl+Y)',
            onPressed: session.canRedo ? session.redo : null,
            icon: const Icon(Icons.redo),
          ),
          TextButton(
            onPressed: session.selected == null ? null : session.resetEdit,
            child: const Text('Reset'),
          ),
          const Spacer(),
          if (session.items.isNotEmpty)
            Text('${session.selectedIndex + 1} / ${session.items.length}'),
          const SizedBox(width: 12),
        ],
      ),
    ),
  );
}

class _Later extends StatelessWidget {
  final String text;
  const _Later(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Align(alignment: Alignment.centerLeft, child: Text(text)),
  );
}
