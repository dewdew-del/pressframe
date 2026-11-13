import 'package:flutter/material.dart';

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

enum _Tab { light, color, crop, template }

const _tabNames = {
  _Tab.light: 'Light',
  _Tab.color: 'Color',
  _Tab.crop: 'Crop',
  _Tab.template: 'Template',
};

/// Phone layout: photo on top, filmstrip, one tool group, and four tool tabs at the bottom
/// for thumb reach. "Next" walks Edit, Review, Export; those two open as full pages.
class PhoneShell extends StatefulWidget {
  final Session session;
  final Renderer? renderer; // null in widget tests
  final AppStore? store; // null in widget tests
  final TemplateLibrary? library; // null in widget tests
  const PhoneShell({super.key, required this.session, this.renderer, this.store, this.library});

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  late final actions = AppActions(
    session: widget.session,
    renderer: widget.renderer,
    store: widget.store,
    library: widget.library,
  );
  Session get session => widget.session;
  _Tab _tab = _Tab.light;
  int _kitImports = 0; // bumps so the preset list reloads after a kit import

  Widget _nextPill(VoidCallback? onPressed) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        minimumSize: const Size(72, 48),
      ),
      child: const Text('Next →'),
    ),
  );

  Future<T?> _page<T>(String title, Widget body, {VoidCallback? onNext}) =>
      Navigator.of(context).push<T>(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(title),
              backgroundColor: panelColor,
              actions: [if (onNext != null) _nextPill(onNext)],
            ),
            body: SafeArea(child: body),
          ),
        ),
      );

  void _openReview() => _page<void>(
    'Review',
    ListenableBuilder(
      listenable: Listenable.merge([widget.library]),
      builder: (context, _) => ReviewGrid(
        session: session,
        renderer: widget.renderer,
        templates: actions.templates,
        assets: actions.assets,
        thumbnails: actions.thumbnails,
        longEdge: actions.previewEdge,
        // Closes the photo's sheet and the Review page in one go.
        onOpenInEdit: () => Navigator.of(context).popUntil((route) => route.isFirst),
      ),
    ),
    onNext: _openExport,
  );

  Future<void> _openExport() async {
    final staging = actions.android ? await actions.galleryStagingDir() : null;
    if (!mounted) return;
    final sheet = ExportSheet(
      session: session,
      specs: actions.specs,
      exporter: actions.exporter(),
      fixedOutDir: staging,
      onBackToEdit: () => Navigator.of(context).popUntil((route) => route.isFirst),
    );
    await _page<void>(
      'Export',
      actions.android
          ? GalleryGate(
              check: actions.hasGalleryAccess,
              openSettings: actions.openAppSettings,
              child: sheet,
            )
          : sheet,
    );
  }

  Future<BuiltTemplate?> _openEditor(BuildContext context, BuiltTemplate initial) => _page<BuiltTemplate>(
    'Template',
    TemplateEditor(
      session: session,
      library: widget.library!,
      renderer: widget.renderer,
      initial: initial,
      longEdge: actions.previewEdge,
    ),
  );

  Future<void> _importKit() async {
    if (await actions.importKit(context) && mounted) setState(() => _kitImports++);
  }

  /// Back from Edit: asks, then drops the batch and shows the Add photos screen again.
  Future<void> _startOver() async {
    final n = session.items.length;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel editing?'),
        content: Text(
          'Your edits to ${n == 1 ? 'this photo' : 'these $n photos'} will be lost. '
          'The original photos are not changed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep editing')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel editing')),
        ],
      ),
    );
    if (yes == true) session.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    // The phone's own back button asks too, instead of closing the app mid-edit.
    builder: (context, child) => PopScope(
      canPop: session.items.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _startOver();
      },
      child: child!,
    ),
    child: _scaffold(),
  );

  Widget _scaffold() => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) => Column(
          children: [
            _topBar(),
            if (session.items.isEmpty)
              Expanded(child: EmptyState(onAdd: () => actions.addPhotos(context)))
            else ...[
              Expanded(
                child: _tab == _Tab.crop
                    ? CropView(session: session, renderer: widget.renderer, longEdge: actions.previewEdge)
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: PreviewView(
                              session: session,
                              renderer: widget.renderer,
                              library: widget.library,
                              longEdge: actions.previewEdge,
                              onSwipeUp: () => session.setFlag(Flag.pick),
                              onSwipeDown: () => session.setFlag(Flag.reject),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: BeforeAfterButton(
                              session: session,
                              tooltip: 'Show the photo before editing (or hold the photo)',
                            ),
                          ),
                        ],
                      ),
              ),
              Container(
                color: panelColor,
                child: Filmstrip(session: session, thumbnails: actions.thumbnails),
              ),
              SizedBox(
                height: 232,
                child: Material(
                  color: panelColor,
                  child: SingleChildScrollView(
                    key: ValueKey(_tab),
                    padding: const EdgeInsets.only(top: 8),
                    child: _tools(),
                  ),
                ),
              ),
              const Divider(height: 1),
              _tabs(),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _topBar() {
    final item = session.selected;
    final has = item != null;
    return Container(
      color: panelColor,
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: has ? _startOver : null,
            icon: const Icon(Icons.arrow_back),
          ),
          Expanded(
            child: Center(
              child: Text(has ? '${session.selectedIndex + 1} / ${session.items.length}' : 'PressFrame'),
            ),
          ),
          PopupMenuButton<Flag>(
            tooltip: 'Flag this photo',
            enabled: has,
            initialValue: item?.flag,
            onSelected: session.setFlag,
            itemBuilder: (context) => const [
              PopupMenuItem(value: Flag.pick, child: Text('Pick')),
              PopupMenuItem(value: Flag.reject, child: Text('Reject')),
              PopupMenuItem(value: Flag.none, child: Text('Clear flag')),
            ],
            icon: Icon(
              switch (item?.flag) {
                Flag.pick => Icons.flag,
                Flag.reject => Icons.block,
                _ => Icons.outlined_flag,
              },
              color: switch (item?.flag) {
                Flag.pick => Colors.greenAccent,
                Flag.reject => Colors.redAccent,
                _ => null,
              },
            ),
          ),
          PopupMenuButton<VoidCallback>(
            tooltip: 'More',
            onSelected: (run) => run(),
            itemBuilder: (context) => [
              PopupMenuItem(value: () => actions.addPhotos(context), child: const Text('Add photos')),
              const PopupMenuDivider(),
              PopupMenuItem(
                enabled: session.canUndo,
                value: session.undo,
                child: const Text('Undo'),
              ),
              PopupMenuItem(enabled: session.canRedo, value: session.redo, child: const Text('Redo')),
              PopupMenuItem(enabled: has, value: session.resetEdit, child: const Text('Reset edit')),
              PopupMenuItem(enabled: has, value: session.copyEdit, child: const Text('Copy edit')),
              PopupMenuItem(enabled: has, value: session.pasteEdit, child: const Text('Paste edit')),
              PopupMenuItem(
                enabled: session.exportable.length > 1,
                value: session.applyEditToAll,
                child: const Text('Apply to all'),
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
                enabled: widget.store != null,
                value: () => actions.exportKit(context),
                child: const Text('Export kit'),
              ),
              PopupMenuItem(
                enabled: widget.store != null,
                value: _importKit,
                child: const Text('Import kit'),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          ),
          _nextPill(session.exportable.isEmpty ? null : _openReview),
        ],
      ),
    );
  }

  Widget _tools() => switch (_tab) {
    // Presets folded away, the everyday light sliders, then detail at the bottom.
    _Tab.light => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          title: const Text('Presets'),
          children: [PresetPanel(key: ValueKey(_kitImports), session: session, store: widget.store)],
        ),
        SliderGroup(session: session, name: 'Light', sliders: lightSliders, more: lightMore),
        const Divider(),
        SliderGroup(session: session, name: 'Detail', sliders: detailSliders, more: detailMore),
      ],
    ),
    _Tab.color => SliderGroup(session: session, name: 'Color', sliders: colorSliders, more: colorMore),
    _Tab.crop => CropTools(session: session),
    _Tab.template => TemplatePanel(
      session: session,
      library: widget.library,
      renderer: widget.renderer,
      openEditor: _openEditor,
      longEdge: actions.previewEdge,
    ),
  };

  Widget _tabs() => Container(
    color: panelColor,
    height: 56,
    child: Row(
      children: [
        for (final t in _Tab.values)
          Expanded(
            child: Semantics(
              selected: t == _tab,
              button: true,
              child: InkWell(
                key: ValueKey('tab-${_tabNames[t]}'),
                onTap: () => setState(() => _tab = t),
                child: Center(
                  child: Text(
                    _tabNames[t]!,
                    style: TextStyle(
                      fontSize: 14,
                      color: t == _tab ? accentColor : textColor,
                      fontWeight: t == _tab ? FontWeight.w700 : FontWeight.w400,
                      // Underline too, so the active tab does not depend on color alone.
                      decoration: t == _tab ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Shows [child] only when the gallery may be written to. Otherwise explains why the
/// permission is needed and offers Retry and Open settings.
class GalleryGate extends StatefulWidget {
  final Future<bool> Function() check;
  final VoidCallback openSettings;
  final Widget child;
  const GalleryGate({super.key, required this.check, required this.openSettings, required this.child});

  @override
  State<GalleryGate> createState() => _GalleryGateState();
}

class _GalleryGateState extends State<GalleryGate> {
  bool? _allowed; // null while asking

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _allowed = null);
    bool ok;
    try {
      ok = await widget.check();
    } on Object {
      ok = false;
    }
    if (mounted) setState(() => _allowed = ok);
  }

  @override
  Widget build(BuildContext context) => switch (_allowed) {
    true => widget.child,
    null => const Center(child: CircularProgressIndicator()),
    false => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.photo_library_outlined, size: 48),
          const SizedBox(height: 16),
          const Text(
            'PressFrame needs permission to save photos to your gallery. '
            'Exported photos go to the album "PressFrame". Nothing else is read or changed.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _check, child: const Text('Retry')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: widget.openSettings, child: const Text('Open settings')),
        ],
      ),
    ),
  };
}
