import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/renderer.dart';
import '../models/batch_item.dart';
import '../models/template.dart';
import '../session.dart';
import '../storage/app_store.dart';
import '../storage/template_library.dart';
import 'shared/actions.dart';
import 'shared/crop_view.dart';
import 'shared/export_sheet.dart';
import 'shared/filmstrip.dart';
import 'shared/preset_panel.dart';
import 'shared/preview_view.dart';
import 'shared/review_grid.dart';
import 'shared/slider_group.dart';
import 'shared/template_editor.dart';
import 'shared/template_panel.dart';
import 'theme.dart';

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
  late final actions = AppActions(
    session: widget.session,
    renderer: widget.renderer,
    store: widget.store,
    library: widget.library,
  );
  Session get session => widget.session;
  bool _cropping = false; // the photo area shows the crop tool instead of the preview
  bool _dropping = false; // files are being dragged over the window
  bool _review = false; // the middle of the window shows the review grid
  int _kitImports = 0; // bumps so the preset list reloads after a kit import

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // Leave typing alone: letters in a text field are text, not shortcuts.
    if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f1 && event is KeyDownEvent) {
      _help();
      return KeyEventResult.handled;
    }
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
        child: ExportSheet(session: session, specs: actions.specs, exporter: actions.exporter()),
      ),
    ),
  );

  static const _shortcuts = {
    'Left / Right': 'Previous / next photo',
    'P': 'Pick the photo',
    'X': 'Reject the photo (it will not be exported)',
    'U': 'Clear the flag',
    'Backslash (hold)': 'Show the photo before editing',
    'Ctrl+Z': 'Undo',
    'Ctrl+Y': 'Redo',
    'Ctrl+C': 'Copy the edit',
    'Ctrl+V': 'Paste the edit',
    'Double-click a slider': 'Reset it',
    'Mouse wheel on the photo': 'Zoom (drag to move around)',
    'Tab': 'Move between controls',
    'F1': 'This list',
  };

  void _help() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Keyboard shortcuts'),
      content: SizedBox(
        width: 460,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in _shortcuts.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 200,
                      child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(child: Text(e.value)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );

  Future<void> _importKit() async {
    if (await actions.importKit(context) && mounted) setState(() => _kitImports++);
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => setState(() => _dropping = true),
    onDragExited: (_) => setState(() => _dropping = false),
    onDragDone: (d) {
      setState(() => _dropping = false);
      actions.importPaths(context, [for (final f in d.files) f.path]);
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
              child: _review
                  ? _reviewGrid()
                  : Row(
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

  Widget _menu(String label, String tooltip, Map<String, VoidCallback> entries, {bool enabled = true}) =>
      PopupMenuButton<VoidCallback>(
        tooltip: tooltip,
        enabled: enabled,
        onSelected: (run) => run(),
        itemBuilder: (context) => [
          for (final e in entries.entries) PopupMenuItem(value: e.value, child: Text(e.key)),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Text(
            '$label ▾',
            style: const TextStyle(color: accentColor, fontWeight: FontWeight.w500),
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
        _menu('Import', 'Import photos', {
          'Add photos': () => actions.addPhotos(context),
          'Add folder': () => actions.addFolder(context),
        }),
        _modeButton('Edit', !_review, () => setState(() => _review = false)),
        ListenableBuilder(
          listenable: session,
          builder: (context, _) => _modeButton(
            'Review',
            _review,
            session.exportable.isEmpty ? null : () => setState(() => _review = true),
          ),
        ),
        ListenableBuilder(
          listenable: session,
          builder: (context, _) => TextButton(
            onPressed: session.exportable.isEmpty ? null : _export,
            child: const Text('Export'),
          ),
        ),
        const Spacer(),
        _menu('Kit', 'Publication kit', {
          'Export kit': () => actions.exportKit(context),
          'Import kit': _importKit,
        }, enabled: widget.store != null),
        IconButton(
          tooltip: 'Keyboard shortcuts (F1)',
          onPressed: _help,
          icon: const Icon(Icons.help_outline),
        ),
      ],
    ),
  );

  // The current mode is underlined so it reads without relying on color alone.
  Widget _modeButton(String label, bool active, VoidCallback? onPressed) => TextButton(
    onPressed: onPressed,
    child: Text(
      label,
      style: TextStyle(
        decoration: active ? TextDecoration.underline : null,
        fontWeight: active ? FontWeight.w700 : null,
      ),
    ),
  );

  Widget _reviewGrid() => ListenableBuilder(
    listenable: Listenable.merge([widget.library]),
    builder: (context, _) => ReviewGrid(
      session: session,
      renderer: widget.renderer,
      templates: actions.templates,
      assets: actions.assets,
      thumbnails: actions.thumbnails,
      onOpenInEdit: () => setState(() => _review = false),
    ),
  );

  Widget _panel() => Material(
    color: panelColor,
    child: SingleChildScrollView(
      child: Column(
        children: [
          _section('Presets', [
            PresetPanel(key: ValueKey(_kitImports), session: session, store: widget.store),
          ]),
          _section('Light', [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: OutlinedButton(
                  onPressed: actions.autoFixSelected,
                  child: const Text('Auto fix'),
                ),
              ),
            ),
            SliderGroup(session: session, sliders: lightSliders),
          ]),
          _section('Color', [SliderGroup(session: session, sliders: colorSliders)]),
          _section('Detail', [SliderGroup(session: session, sliders: detailSliders)]),
          _section('Crop', [
            CropTools(
              session: session,
              cropping: _cropping,
              onCropping: (v) => setState(() => _cropping = v),
            ),
          ], open: false),
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

  Widget _section(String title, List<Widget> children, {bool open = true}) => ExpansionTile(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
    initiallyExpanded: open,
    maintainState: true,
    children: children,
  );

  Widget _bottomBar() => Container(
    color: panelColor,
    height: 72,
    child: Row(
      children: [
        Expanded(
          child: Filmstrip(session: session, thumbnails: actions.thumbnails),
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
                  for (final e in filterNames.entries)
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
