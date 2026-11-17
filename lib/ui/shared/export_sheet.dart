import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../../export/exporter.dart';
import '../../export/filename.dart';
import '../../session.dart';
import 'slider_group.dart';

bool exportSucceeded(ExportProgress p) => p.finished && !p.cancelled && p.failures.isEmpty;

/// The line under the progress bar. [gallery] = photos go to the phone's gallery album.
String exportResultText(ExportProgress p, {required bool gallery}) {
  if (!p.finished) return 'Exporting ${p.done} of ${p.total}…';
  if (exportSucceeded(p)) {
    return 'Export successful! ${p.total} photo${p.total == 1 ? '' : 's'} saved'
        '${gallery ? ' to the gallery album "PressFrame"' : ''}.';
  }
  return '${p.cancelled ? 'Cancelled' : 'Finished'}: ${p.done - p.failures.length} of ${p.total} exported';
}

String _name(String path) => path.split(RegExp(r'[\/]')).last;

/// What the user may have forgotten: photos with no template, and photos that will get
/// a credit line with no text. Empty when all is fine.
List<String> exportWarnings(List<RenderSpec> specs) {
  final noTemplate = [for (final s in specs) if (s.template == null) _name(s.item.path)];
  final noCredit = [
    for (final s in specs)
      if (s.credit.enabled && (s.creditText ?? '').trim().isEmpty) _name(s.item.path),
  ];
  String list(List<String> n) => n.length <= 3 ? n.join(', ') : '${n.take(3).join(', ')} and ${n.length - 3} more';
  return [
    if (noTemplate.isNotEmpty)
      '${noTemplate.length} photo${noTemplate.length == 1 ? ' has' : 's have'} no template: ${list(noTemplate)}',
    if (noCredit.isNotEmpty)
      'Credit is on but has no text for ${noCredit.length} photo${noCredit.length == 1 ? '' : 's'}: ${list(noCredit)}',
  ];
}

/// Where the photos go: [dir] itself, or a folder inside it named after the event.
String exportFolder(String dir, String eventName, {required bool newFolder}) =>
    newFolder ? '$dir${Platform.pathSeparator}${sanitizeEventName(eventName)}' : dir;

/// Export settings, progress and the list of failures.
/// Shown in a dialog on the laptop and as a full page on the phone.
class ExportSheet extends StatefulWidget {
  final Session session;
  final Exporter? exporter; // null in widget tests
  final List<RenderSpec> Function() specs;

  /// Android: exports go through this folder into the gallery, so there is no folder picker.
  final String? fixedOutDir;

  /// Phone: the sheet is a page two steps away from Edit; this jumps straight back.
  final VoidCallback? onBackToEdit;

  const ExportSheet({
    super.key,
    required this.session,
    required this.exporter,
    required this.specs,
    this.fixedOutDir,
    this.onBackToEdit,
  });

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  final _name = TextEditingController(text: 'Event');
  double _quality = 90;
  bool _newFolder = true; // laptop: export into a folder named after the event
  String? _outDir;
  ExportProgress? _progress;
  StreamSubscription<ExportProgress>? _running;

  @override
  void initState() {
    super.initState();
    _outDir = widget.fixedOutDir;
    if (_outDir == null) _useDownloads();
  }

  // Laptop: Downloads is where exports go until another folder is chosen.
  Future<void> _useDownloads() async {
    try {
      final dir = await getDownloadsDirectory();
      if (dir != null && mounted && _outDir == null) setState(() => _outDir = dir.path);
    } on Object {
      // No Downloads folder known: the user picks one with "Change…".
    }
  }

  /// The folder the files are written to (the exporter creates it when missing).
  String? get _target => _outDir == null || widget.fixedOutDir != null
      ? _outDir
      : exportFolder(_outDir!, _name.text, newFolder: _newFolder);

  // Phone: the screen must not sleep mid-export. Other platforms ignore the call.
  void _keepAwake(bool on) {
    if (widget.fixedOutDir == null || !Platform.isAndroid) return;
    const MethodChannel('pressframe/settings').invokeMethod<void>('keepAwake', on).ignore();
  }

  @override
  void dispose() {
    _keepAwake(false);
    widget.exporter?.cancel(); // closing the dialog stops the export cleanly
    _running?.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final specs = widget.specs();
    final warnings = exportWarnings(specs);
    if (warnings.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Check before exporting'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in warnings)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(w)),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go back')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Export anyway')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final settings = ExportSettings(
      eventName: _name.text,
      outDir: _target!,
      quality: _quality.round(),
      longEdge: null, // always the photo's own size after the crop
    );
    _keepAwake(true);
    setState(() {
      _progress = const ExportProgress(done: 0, total: 0);
      _running = widget.exporter!.run(specs, settings).listen(
        (p) => setState(() => _progress = p),
        onDone: () {
          _keepAwake(false);
          setState(() => _running = null);
        },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.session.exportable.length;
    final small = widget.session.exportable.where((i) => i.smallPreview).length;
    final busy = _running != null;
    final p = _progress;
    final canExport =
        widget.exporter != null && !busy && count > 0 && _outDir != null;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              style: Theme.of(context).textTheme.titleMedium,
              count == 0
                  ? 'There are no photos to export.'
                  : 'Export $count photo${count == 1 ? '' : 's'}',
            ),
            if (small > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$small RAW photo${small == 1 ? '' : 's'} will export small',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !busy,
              onChanged: (_) => setState(() {}), // the folder name follows the event name
              decoration: const InputDecoration(labelText: 'Event name'),
            ),
            const SizedBox(height: 12),
            if (widget.fixedOutDir != null)
              const Text('Saves to your gallery')
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      // Just the folder's name: the full path is long and says little.
                      _outDir == null
                          ? 'No folder chosen'
                          : 'Saves to ${_outDir!.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final dir = await FilePicker.getDirectoryPath(
                              dialogTitle: 'Choose the export folder',
                            );
                            if (dir != null && mounted) setState(() => _outDir = dir);
                          },
                    child: const Text('Change…'),
                  ),
                ],
              ),
              CheckboxListTile(
                value: _newFolder,
                onChanged: busy ? null : (v) => setState(() => _newFolder = v!),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('New folder for this event'),
              ),
            ],
            // Quality has a good default, so it stays folded away.
            ExpansionTile(
              title: const Text('More options'),
              tilePadding: EdgeInsets.zero,
              children: [
            LabeledSlider(
              label: 'JPEG quality',
              min: 60,
              max: 100,
              value: _quality,
              enabled: !busy,
              resetValue: 90,
              format: (v) => v.round().toString(),
              onChanged: (v) => setState(() => _quality = v),
              onChangeEnd: (v) => setState(() => _quality = v),
            ),
              ],
            ),
            if (p != null && p.total > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: p.done / p.total),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (exportSucceeded(p)) ...[
                    const Icon(Icons.check_circle, color: Colors.greenAccent),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      exportResultText(p, gallery: widget.fixedOutDir != null),
                      style: exportSucceeded(p) ? const TextStyle(fontWeight: FontWeight.w600) : null,
                    ),
                  ),
                ],
              ),
            ],
            if (p != null && exportSucceeded(p) && !busy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: widget.fixedOutDir != null
                          ? () => Gal.open().ignore()
                          // explorer reports exit code 1 even when it opens fine
                          : () => Process.run('explorer.exe', [_target!]).ignore(),
                      child: Text(widget.fixedOutDir != null ? 'Open gallery' : 'Open folder'),
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() => _progress = null),
                      child: const Text('Export again'),
                    ),
                  ],
                ),
              ),
            if (p != null && p.failures.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${p.failures.length} problem${p.failures.length == 1 ? '' : 's'}:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final f in p.failures)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(f.reason),
                ),
            ],
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: busy
                      ? widget.exporter?.cancel
                      : widget.onBackToEdit ?? () => Navigator.of(context).maybePop(),
                  child: Text(busy ? 'Cancel' : (widget.onBackToEdit != null ? 'Back to editing' : 'Close')),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: canExport ? _start : null, child: const Text('Export')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
