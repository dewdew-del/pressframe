import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../export/exporter.dart';
import '../../session.dart';
import 'slider_group.dart';

/// Export settings, progress and the list of failures.
/// Shown in a dialog on the laptop and as a full page on the phone.
class ExportSheet extends StatefulWidget {
  final Session session;
  final Exporter? exporter; // null in widget tests
  final List<RenderSpec> Function() specs;

  /// Android: exports go through this folder into the gallery, so there is no folder picker.
  final String? fixedOutDir;

  const ExportSheet({
    super.key,
    required this.session,
    required this.exporter,
    required this.specs,
    this.fixedOutDir,
  });

  @override
  State<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<ExportSheet> {
  final _name = TextEditingController(text: 'Event');
  final _longEdge = TextEditingController(text: '2048');
  double _quality = 90;
  bool _fullSize = false;
  String? _outDir;
  ExportProgress? _progress;
  StreamSubscription<ExportProgress>? _running;

  @override
  void initState() {
    super.initState();
    _outDir = widget.fixedOutDir;
  }

  @override
  void dispose() {
    widget.exporter?.cancel(); // closing the dialog stops the export cleanly
    _running?.cancel();
    _name.dispose();
    _longEdge.dispose();
    super.dispose();
  }

  int? get _edge => int.tryParse(_longEdge.text);
  bool get _edgeOk => _fullSize || (_edge != null && _edge! >= 100 && _edge! <= 20000);

  void _start() {
    final settings = ExportSettings(
      eventName: _name.text,
      outDir: _outDir!,
      quality: _quality.round(),
      longEdge: _fullSize ? null : _edge,
    );
    setState(() {
      _progress = const ExportProgress(done: 0, total: 0);
      _running = widget.exporter!.run(widget.specs(), settings).listen(
        (p) => setState(() => _progress = p),
        onDone: () => setState(() => _running = null),
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
        widget.exporter != null && !busy && count > 0 && _outDir != null && _edgeOk;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              count == 0
                  ? 'There are no photos to export.'
                  : '$count photo${count == 1 ? '' : 's'} will be exported',
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
                        '$small RAW photo${small == 1 ? ' has' : 's have'} only a small preview '
                        'inside and will export small. Shoot RAW+JPEG to avoid this.',
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Event name',
                helperText: 'Files are named EventName_001.jpg',
              ),
            ),
            const SizedBox(height: 12),
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
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('long-edge'),
                    controller: _longEdge,
                    enabled: !busy && !_fullSize,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Long edge (px)',
                      errorText: _edgeOk ? null : 'Enter 100 to 20000',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const Text('Full size'),
                Switch(
                  value: _fullSize,
                  onChanged: busy ? null : (v) => setState(() => _fullSize = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.fixedOutDir != null)
              const Text('Photos are saved to the gallery album "PressFrame".')
            else
              Row(
                children: [
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final dir = await FilePicker.getDirectoryPath(
                              dialogTitle: 'Choose the export folder',
                            );
                            if (dir != null && mounted) setState(() => _outDir = dir);
                          },
                    child: const Text('Choose folder'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_outDir ?? 'No folder chosen', overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            if (p != null && p.total > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: p.done / p.total),
              const SizedBox(height: 8),
              Text(
                p.finished
                    ? '${p.cancelled ? 'Cancelled' : 'Finished'}: '
                          '${p.done - p.failures.length} of ${p.total} exported'
                    : 'Exporting ${p.done} of ${p.total}…',
              ),
            ],
            if (p != null && p.failures.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${p.failures.length} problem${p.failures.length == 1 ? '' : 's'}:',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final f in p.failures)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${f.path.split(RegExp(r'[\\/]')).last}: ${f.reason}'),
                ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? widget.exporter?.cancel : () => Navigator.of(context).maybePop(),
                  child: Text(busy ? 'Cancel' : 'Close'),
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
