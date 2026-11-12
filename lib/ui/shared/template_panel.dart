import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../engine/renderer.dart';
import '../../models/template.dart';
import '../../session.dart';
import '../../storage/app_store.dart';
import '../../storage/template_library.dart';
import 'slider_group.dart';

const shapeNames = {
  OutputShape.original: 'Original',
  OutputShape.r1x1: '1:1',
  OutputShape.r4x5: '4:5',
  OutputShape.r3x2: '3:2',
  OutputShape.r16x9: '16:9',
  OutputShape.r2x3: '2:3',
  OutputShape.r9x16: '9:16',
};
const landscapeShapes = [
  OutputShape.original,
  OutputShape.r1x1,
  OutputShape.r4x5,
  OutputShape.r3x2,
  OutputShape.r16x9,
];
const portraitShapes = [
  OutputShape.original,
  OutputShape.r1x1,
  OutputShape.r4x5,
  OutputShape.r2x3,
  OutputShape.r9x16,
];

/// The templates that can be used with [shape]: every built one, and frames that fit.
List<Template> templatesFor(List<Template> all, OutputShape shape) => [
  for (final t in all)
    if (t is! FrameTemplate || frameFits(t, shape)) t,
];

/// Batch branding: template and output shape for landscape and for portrait photos,
/// template management, and the optional photo credit.
class TemplatePanel extends StatefulWidget {
  final Session session;
  final TemplateLibrary? library; // null in widget tests
  final Renderer? renderer;
  final int longEdge;

  /// Opens the editor (dialog on the laptop, page on the phone) and returns what was saved.
  final Future<BuiltTemplate?> Function(BuildContext context, BuiltTemplate initial)? openEditor;

  const TemplatePanel({
    super.key,
    required this.session,
    required this.library,
    this.renderer,
    this.openEditor,
    this.longEdge = 2048,
  });

  @override
  State<TemplatePanel> createState() => _TemplatePanelState();
}

class _TemplatePanelState extends State<TemplatePanel> {
  late final _credit = TextEditingController(text: widget.session.creditText);

  Session get session => widget.session;
  List<Template> get _all => widget.library?.templates ?? const [];

  @override
  void dispose() {
    _credit.dispose();
    super.dispose();
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _edit(BuiltTemplate initial, {String? replaces}) async {
    final saved = await widget.openEditor?.call(context, initial);
    final library = widget.library;
    if (saved == null || library == null) return;
    if (replaces != null && replaces != saved.name) {
      await library.delete(replaces);
      if (session.landscapeTemplate == replaces) session.landscapeTemplate = saved.name;
      if (session.portraitTemplate == replaces) session.portraitTemplate = saved.name;
    }
    await library.save(saved);
    // A first template is put to use straight away.
    session.landscapeTemplate ??= saved.name;
    session.portraitTemplate ??= saved.name;
  }

  Future<void> _importFrame() async {
    final library = widget.library!;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png'],
      dialogTitle: 'Choose a frame (transparent PNG)',
    );
    final path = file?.path;
    if (path == null) return;
    try {
      final asset = await library.importAsset(path);
      final image = library.assets[asset]!;
      final aspect = image.width / image.height;
      final fits = OutputShape.values.where((s) => s.aspect != null && (s.aspect! - aspect).abs() <= 0.01);
      if (fits.isEmpty) {
        _say(
          'This frame is ${image.width}×${image.height}, which matches no output shape. '
          'Make it 1:1, 4:5, 3:2, 16:9, 2:3 or 9:16.',
        );
        return;
      }
      final base = path.split(RegExp(r'[\\/]')).last.replaceAll(RegExp(r'\.png$', caseSensitive: false), '');
      final name = uniqueName(base.isEmpty ? 'Frame' : base, _all.map((t) => t.name));
      await library.save(FrameTemplate(name: name, file: asset, aspect: aspect));
      if (mounted) _say('Frame "$name" added. Choose the ${shapeNames[fits.first]} shape to use it.');
    } on FormatException {
      if (mounted) _say('That file is not a PNG image. Nothing was added.');
    }
  }

  Widget _pair(
    String label,
    OutputShape shape,
    ValueChanged<OutputShape> setShape,
    List<OutputShape> shapes,
    String? template,
    ValueChanged<String?> setTemplate,
  ) {
    final usable = templatesFor(_all, shape);
    final value = usable.any((t) => t.name == template) ? template : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('template-$label-$value-${usable.length}'),
                  initialValue: value,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Template', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final t in usable)
                      DropdownMenuItem(value: t.name, child: Text(t.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: setTemplate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<OutputShape>(
                  key: ValueKey('shape-$label-$shape'),
                  initialValue: shape,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Shape', isDense: true),
                  items: [
                    for (final s in shapes) DropdownMenuItem(value: s, child: Text(shapeNames[s]!)),
                  ],
                  onChanged: (s) => setShape(s!),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([session, widget.library]),
    builder: (context, _) {
      final library = widget.library;
      final credit = session.credit;
      final canEdit = library != null && widget.openEditor != null && session.selected != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _pair(
            'Landscape photos',
            session.landscapeShape,
            (s) => session.landscapeShape = s,
            landscapeShapes,
            session.landscapeTemplate,
            (t) => session.landscapeTemplate = t,
          ),
          _pair(
            'Portrait photos',
            session.portraitShape,
            (s) => session.portraitShape = s,
            portraitShapes,
            session.portraitTemplate,
            (t) => session.portraitTemplate = t,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Tooltip(
                  message: canEdit ? 'Make a gradient band with logos' : 'Import a photo first',
                  child: OutlinedButton(
                    onPressed: canEdit
                        ? () => _edit(
                            BuiltTemplate(
                              name: uniqueName('Template', _all.map((t) => t.name)),
                              band: const GradientBand(),
                            ),
                          )
                        : null,
                    child: const Text('New template'),
                  ),
                ),
                OutlinedButton(
                  onPressed: library == null ? null : _importFrame,
                  child: const Text('Import frame PNG'),
                ),
              ],
            ),
          ),
          if (_all.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text('No templates yet. Photos export without branding.'),
            ),
          for (final t in _all)
            ListTile(
              dense: true,
              title: Text(t.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                (t is FrameTemplate ? 'Imported frame' : 'Built template') +
                    (library!.hasMissingAssets(t) ? ' · image file missing' : ''),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t is BuiltTemplate)
                    IconButton(
                      tooltip: 'Edit "${t.name}"',
                      onPressed: canEdit ? () => _edit(t, replaces: t.name) : null,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  IconButton(
                    tooltip: 'Delete "${t.name}"',
                    onPressed: () => library.delete(t.name),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          const Divider(),
          SwitchListTile(
            key: const ValueKey('credit-switch'),
            title: const Text('Photo credit'),
            value: credit.enabled,
            onChanged: (on) => session.credit = credit.copyWith(enabled: on),
          ),
          if (credit.enabled) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                key: const ValueKey('credit-text'),
                controller: _credit,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Credit text',
                  hintText: 'Photo by Juan Dela Cruz',
                ),
                onChanged: (v) => session.creditText = v,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Corner>(
                      key: ValueKey('corner-${credit.corner}'),
                      initialValue: credit.corner,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Corner', isDense: true),
                      items: const [
                        DropdownMenuItem(value: Corner.topLeft, child: Text('Top left')),
                        DropdownMenuItem(value: Corner.topRight, child: Text('Top right')),
                        DropdownMenuItem(value: Corner.bottomLeft, child: Text('Bottom left')),
                        DropdownMenuItem(value: Corner.bottomRight, child: Text('Bottom right')),
                      ],
                      onChanged: (c) => session.credit = credit.copyWith(corner: c),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('White')),
                      ButtonSegment(value: false, label: Text('Black')),
                    ],
                    selected: {credit.white},
                    onSelectionChanged: (s) => session.credit = credit.copyWith(white: s.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LabeledSlider(
              label: 'Credit size',
              min: 0.015,
              max: 0.06,
              value: credit.sizeFraction,
              resetValue: 0.025,
              format: (v) => '${(v * 100).toStringAsFixed(1)}%',
              onChanged: (v) => session.credit = credit.copyWith(sizeFraction: v),
              onChangeEnd: (v) => session.credit = credit.copyWith(sizeFraction: v),
            ),
          ],
          const SizedBox(height: 8),
        ],
      );
    },
  );
}
