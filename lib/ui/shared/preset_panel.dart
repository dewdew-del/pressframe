import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/preset.dart';
import '../../session.dart';
import '../../storage/app_store.dart';
import '../theme.dart';

/// Built-in and saved presets. Tapping one sets the sliders as a single undo step.
class PresetPanel extends StatefulWidget {
  final Session session;
  final AppStore? store; // null in widget tests: built-ins only
  const PresetPanel({super.key, required this.session, required this.store});

  @override
  State<PresetPanel> createState() => _PresetPanelState();
}

class _PresetPanelState extends State<PresetPanel> {
  List<Preset> _saved = const [];
  bool _options = false; // the Save current / ⋮ row is showing

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final saved = await widget.store?.loadPresets() ?? const <Preset>[];
    if (mounted) setState(() => _saved = saved);
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void _apply(Preset p) => widget.session.updateSelected((i) => i.copyWith(edit: p.params));

  Future<void> _saveCurrent() async {
    final item = widget.session.selected;
    if (item == null) return;
    final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name == null || name.trim().isEmpty) return;
    await widget.store?.savePreset(Preset(name: name.trim(), params: item.edit));
    await _reload();
  }

  Future<void> _export(Preset p) async {
    final saved = await FilePicker.saveFile(
      fileName: '${p.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '')}.pfpreset',
      bytes: utf8.encode(encodePreset(p)),
      dialogTitle: 'Save preset',
    );
    if (saved != null && mounted) _say('Preset saved.');
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(dialogTitle: 'Choose a .pfpreset file');
    final path = file?.path;
    if (path == null) return;
    try {
      final p = await widget.store!.importPreset(path);
      await _reload();
      if (mounted) _say('Added preset "${p.name}".');
    } on FormatException {
      if (mounted) _say('That file is not a PressFrame preset. Nothing was changed.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final on = widget.session.selected != null;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in builtInPresets)
                  ActionChip(label: Text(p.name), onPressed: on ? () => _apply(p) : null),
                for (final p in _saved)
                  ActionChip(label: Text(p.name), onPressed: on ? () => _apply(p) : null),
              ],
            ),
            // Save, import, export and delete stay out of the way until asked for.
            Semantics(
              button: true,
              expanded: _options,
              child: InkWell(
                key: const ValueKey('preset-options'),
                onTap: () => setState(() => _options = !_options),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      const Text('Preset options', style: TextStyle(fontSize: 13, color: hintColor)),
                      Icon(_options ? Icons.expand_less : Icons.expand_more, size: 18, color: hintColor),
                    ],
                  ),
                ),
              ),
            ),
            if (_options) Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: on && widget.store != null ? _saveCurrent : null,
                  child: const Text('Save current'),
                ),
                PopupMenuButton<VoidCallback>(
                  tooltip: 'More preset actions',
                  onSelected: (run) => run(),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      enabled: widget.store != null,
                      value: _import,
                      child: const Text('Import preset'),
                    ),
                    for (final p in _saved) ...[
                      PopupMenuItem(value: () => _export(p), child: Text('Export "${p.name}"')),
                      PopupMenuItem(
                        value: () async {
                          await widget.store?.deletePreset(p.name);
                          await _reload();
                        },
                        child: Text('Delete "${p.name}"'),
                      ),
                    ],
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Save preset'),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: 40,
      decoration: const InputDecoration(labelText: 'Preset name'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _name.text), child: const Text('Save')),
    ],
  );
}
