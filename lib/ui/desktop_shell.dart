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

enum _Step { edit, review, export }

/// Laptop layout: top bar with the three steps, photo with a 320 px tool panel on the
/// right, and a bottom bar with the filmstrip and one main button.
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
  _Step _step = _Step.edit;
  bool _exporting = false; // the export sheet is open (step 3)
  bool _cropping = false; // the photo area shows the crop tool instead of the preview
  bool _dropping = false; // files are being dragged over the window
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
      (true, LogicalKeyboardKey.keyZ) => () => actions.undo(context),
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

  Future<void> _export() async {
    setState(() => _exporting = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 520,
          child: ExportSheet(session: session, specs: actions.specs, exporter: actions.exporter()),
        ),
      ),
    );
    if (mounted) setState(() => _exporting = false);
  }

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
              child: ListenableBuilder(
                listenable: session,
                builder: (context, _) => DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _dropping ? accentColor : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: session.items.isEmpty
                      ? EmptyState(onAdd: () => actions.addPhotos(context), canDrop: true)
                      : _step == _Step.review
                      ? _reviewGrid()
                      : Row(
                          children: [
                            Expanded(child: _photoArea()),
                            const VerticalDivider(width: 1),
                            SizedBox(width: 320, child: _panel()),
                          ],
                        ),
                ),
              ),
            ),
            const Divider(height: 1),
            _bottomBar(),
          ],
        ),
      ),
    ),
  );

  /// The photo with its floating controls: Before / After and undo, redo, reset.
  Widget _photoArea() => Stack(
    children: [
      Positioned.fill(
        child: _cropping
            ? CropView(session: session, renderer: widget.renderer)
            : PreviewView(session: session, renderer: widget.renderer, library: widget.library),
      ),
      Positioned(
        top: 8,
        right: 8,
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BeforeAfterButton(
                session: session,
                tooltip: 'Show the photo before editing (or hold \\)',
              ),
              const SizedBox(width: 8),
              Material(
                color: const Color(0xCC2A2A2A),
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Undo (Ctrl+Z)',
                      onPressed: session.canUndo ? () => actions.undo(context) : null,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: 'Redo (Ctrl+Y)',
                      onPressed: session.canRedo ? session.redo : null,
                      icon: const Icon(Icons.redo),
                    ),
                    IconButton(
                      tooltip: 'Reset this photo\'s sliders',
                      onPressed: session.selected == null ? null : session.resetEdit,
                      icon: const Icon(Icons.restart_alt),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      if (!_cropping)
        const Positioned(
          left: 12,
          bottom: 8,
          child: IgnorePointer(
            child: Text('Scroll to zoom, drag to move.', style: TextStyle(fontSize: 12, color: hintColor)),
          ),
        ),
    ],
  );

  Widget _topBar() => Container(
    color: panelColor,
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final any = session.exportable.isNotEmpty;
        final current = _exporting ? _Step.export : _step;
        return Row(
          children: [
            Image.asset('assets/logo.png', key: const ValueKey('app-logo'), width: 28, height: 28),
            const SizedBox(width: 8),
            const Text('PressFrame', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(width: 16),
            PopupMenuButton<VoidCallback>(
              tooltip: 'Import photos',
              onSelected: (run) => run(),
              itemBuilder: (context) => [
                PopupMenuItem(value: () => actions.addPhotos(context), child: const Text('Add photos')),
                PopupMenuItem(value: () => actions.addFolder(context), child: const Text('Add folder')),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                child: Text('Import ▾', style: TextStyle(color: accentColor, fontWeight: FontWeight.w500)),
              ),
            ),
            const Spacer(),
            _stepButton('1 Edit', current == _Step.edit, () => setState(() => _step = _Step.edit)),
            const Text('›', style: TextStyle(color: hintColor)),
            _stepButton(
              '2 Review',
              current == _Step.review,
              any ? () => setState(() => _step = _Step.review) : null,
            ),
            const Text('›', style: TextStyle(color: hintColor)),
            _stepButton('3 Export', current == _Step.export, any ? _export : null),
            const Spacer(),
            PopupMenuButton<VoidCallback>(
              tooltip: 'More',
              onSelected: (run) => run(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: widget.store != null,
                  value: () => actions.exportKit(context),
                  child: const Text('Export kit'),
                ),
                PopupMenuItem(
                  enabled: widget.store != null,
                  value: _importKit,
                  child: const Text('Import kit'),
                ),
                const PopupMenuDivider(),
                for (final e in filterNames.entries)
                  CheckedPopupMenuItem(
                    checked: session.filter == e.key,
                    value: () => session.filter = e.key,
                    child: Text('Show: ${e.value}'),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  enabled: session.exportable.length > 1,
                  value: session.applyEditToAll,
                  child: const Text('Apply to all'),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
            IconButton(
              tooltip: 'Keyboard shortcuts (F1)',
              onPressed: _help,
              icon: const Icon(Icons.help_outline),
            ),
          ],
        );
      },
    ),
  );

  // The current step is bold, so it reads without relying on color alone.
  Widget _stepButton(String label, bool active, VoidCallback? onPressed) => TextButton(
    onPressed: onPressed,
    child: Text(
      label,
      style: TextStyle(
        color: onPressed == null ? null : (active ? accentColor : textColor),
        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
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
      onOpenInEdit: () => setState(() => _step = _Step.edit),
    ),
  );

  Widget _panel() => Material(
    color: panelColor,
    child: SingleChildScrollView(
      child: Column(
        children: [
          _section('Presets', [
            PresetPanel(key: ValueKey(_kitImports), session: session, store: widget.store),
          ], open: false),
          _section('Light', [
            SliderGroup(session: session, name: 'Light', sliders: lightSliders, more: lightMore),
          ]),
          _section('Color', [
            SliderGroup(session: session, name: 'Color', sliders: colorSliders, more: colorMore),
          ]),
          _section('Detail', [
            SliderGroup(session: session, name: 'Detail', sliders: detailSliders, more: detailMore),
          ]),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('${session.selectedIndex + 1} / ${session.items.length}'),
                ),
              // One main button: it always says what the next step is.
              FilledButton(
                onPressed: session.exportable.isEmpty
                    ? null
                    : _step == _Step.edit
                    ? () => setState(() => _step = _Step.review)
                    : _export,
                child: Text(_step == _Step.edit ? 'Next: Review →' : 'Export all'),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ],
    ),
  );
}
