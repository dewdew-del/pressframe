import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/auto_fix.dart';
import '../engine/decode.dart';
import '../engine/renderer.dart';
import '../export/exporter.dart';
import '../models/batch_item.dart';
import '../models/template.dart';
import '../session.dart';
import '../storage/app_store.dart';
import '../storage/template_library.dart';
import 'shared/crop_view.dart';
import 'shared/export_sheet.dart';
import 'shared/filmstrip.dart';
import 'shared/preset_panel.dart';
import 'shared/preview_view.dart';
import 'shared/slider_group.dart';
import 'shared/template_editor.dart';
import 'shared/template_panel.dart';
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
  final AppStore? store; // null in widget tests
  final TemplateLibrary? library; // null in widget tests
  const DesktopShell({super.key, required this.session, this.renderer, this.store, this.library});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  Session get session => widget.session;
  bool _cropping = false; // the photo area shows the crop tool instead of the preview
  bool _dropping = false; // files are being dragged over the window

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

  List<RenderSpec> _specs() => [
    for (final item in session.exportable)
      session.specFor(item, widget.library?.templates ?? const []),
  ];

  Future<BuiltTemplate?> _openEditor(BuildContext context, BuiltTemplate initial) =>
      showDialog<BuiltTemplate>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(32),
          clipBehavior: Clip.antiAlias,
          child: TemplateEditor(
            session: session,
            library: widget.library!,
            renderer: widget.renderer,
            initial: initial,
          ),
        ),
      );

  void _export() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      child: SizedBox(
        width: 520,
        child: ExportSheet(
          session: session,
          specs: _specs,
          exporter: widget.renderer == null
              ? null
              : Exporter(
                  widget.renderer!,
                  maxDecodeEdge: Platform.isAndroid ? 4096 : 8192,
                  loadAssets: (_) async => widget.library?.assets ?? const {},
                ),
        ),
      ),
    ),
  );

  static const _extensions = ['jpg', 'jpeg', 'png', 'cr3', 'cr2', 'arw'];

  Future<void> _addPhotos() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _extensions);
    await _import([for (final f in picked) ?f.path]);
  }

  Future<void> _addFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder of photos');
    if (dir != null) await _import([dir]);
  }

  Future<void> _import(List<String> paths) async {
    if (paths.isEmpty) return;
    final skipped = await session.import(paths);
    if (skipped.isEmpty || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${skipped.length} file${skipped.length == 1 ? '' : 's'} could not be opened'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [for (final p in skipped) Text(p.split(RegExp(r'[\\/]')).last)],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => setState(() => _dropping = true),
    onDragExited: (_) => setState(() => _dropping = false),
    onDragDone: (d) {
      setState(() => _dropping = false);
      _import([for (final f in d.files) f.path]);
    },
    child: Focus(
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
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _dropping ? accentColor : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: _cropping
                          ? CropView(session: session, renderer: widget.renderer)
                          : PreviewView(
                              session: session,
                              renderer: widget.renderer,
                              library: widget.library,
                            ),
                    ),
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
        PopupMenuButton<VoidCallback>(
          tooltip: 'Import photos',
          onSelected: (run) => run(),
          itemBuilder: (context) => [
            PopupMenuItem(value: _addPhotos, child: const Text('Add photos')),
            PopupMenuItem(value: _addFolder, child: const Text('Add folder')),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Text('Import ▾', style: TextStyle(color: accentColor, fontWeight: FontWeight.w500)),
          ),
        ),
        TextButton(onPressed: () {}, child: const Text('Edit')),
        const TextButton(onPressed: null, child: Text('Review')),
        ListenableBuilder(
          listenable: session,
          builder: (context, _) => TextButton(
            onPressed: session.exportable.isEmpty ? null : _export,
            child: const Text('Export'),
          ),
        ),
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
          _section('Presets', [PresetPanel(session: session, store: widget.store)]),
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
          _section('Crop', [_cropTools()], open: false),
          _section('Template', [
            TemplatePanel(
              session: session,
              library: widget.library,
              renderer: widget.renderer,
              openEditor: _openEditor,
            ),
          ], open: false),
        ],
      ),
    ),
  );

  Widget _cropTools() => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final item = session.selected;
      final on = item != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: on ? () => _rotate(3) : null,
                  icon: const Icon(Icons.rotate_left),
                  label: const Text('Rotate left'),
                ),
                OutlinedButton.icon(
                  onPressed: on ? () => _rotate(1) : null,
                  icon: const Icon(Icons.rotate_right),
                  label: const Text('Rotate right'),
                ),
                FilterChip(
                  label: const Text('Adjust crop'),
                  selected: _cropping,
                  onSelected: on ? (v) => setState(() => _cropping = v) : null,
                ),
                TextButton(
                  onPressed: on
                      ? () => session.updateSelected(
                          (i) => i.copyWith(crop: () => null, straighten: 0),
                        )
                      : null,
                  child: const Text('Reset crop'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          LabeledSlider(
            label: 'Straighten',
            min: -15,
            max: 15,
            value: item?.straighten ?? 0,
            enabled: on,
            format: (v) => '${v.toStringAsFixed(1)}°',
            onChanged: (v) => session.updateLive((i) => i.copyWith(straighten: v), commit: false),
            onChangeEnd: (v) => session.updateLive((i) => i.copyWith(straighten: v), commit: true),
          ),
        ],
      );
    },
  );

  // A turned photo has a different shape, so an old crop no longer fits: start over.
  void _rotate(int turns) => session.updateSelected(
    (i) => i.copyWith(quarterTurns: (i.quarterTurns + turns) % 4, crop: () => null),
  );

  Widget _section(String title, List<Widget> children, {bool open = true}) => ExpansionTile(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    initiallyExpanded: open,
    maintainState: true,
    children: children,
  );

  static const _filterNames = {
    FlagFilter.all: 'All',
    FlagFilter.picks: 'Picks',
    FlagFilter.hideRejects: 'Hide rejects',
  };

  Widget _bottomBar() => Container(
    color: panelColor,
    height: 72,
    child: Row(
      children: [
        Expanded(
          child: Filmstrip(session: session, thumbnails: widget.store?.thumbnailIf),
        ),
        ListenableBuilder(
          listenable: session,
          builder: (context, _) => Row(
            children: [
              if (session.items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('${session.selectedIndex + 1} / ${session.items.length}'),
                ),
              PopupMenuButton<FlagFilter>(
                tooltip: 'Filter photos',
                initialValue: session.filter,
                onSelected: (f) => session.filter = f,
                itemBuilder: (context) => [
                  for (final e in _filterNames.entries)
                    PopupMenuItem(value: e.key, child: Text(e.value)),
                ],
                icon: const Icon(Icons.filter_list),
              ),
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
              OutlinedButton(
                onPressed: session.exportable.length < 2 ? null : session.applyEditToAll,
                child: const Text('Apply to all'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: session.exportable.isEmpty ? null : _export,
                child: const Text('Export all'),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ],
    ),
  );
}
