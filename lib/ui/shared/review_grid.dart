import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../engine/decode.dart';
import '../../engine/geometry.dart';
import '../../engine/renderer.dart';
import '../../export/exporter.dart';
import '../../models/batch_item.dart';
import '../../models/template.dart';
import '../../session.dart';
import '../theme.dart';
import 'crop_view.dart';
import 'filmstrip.dart' show ThumbnailLoader;
import 'preview_view.dart';
import 'template_panel.dart' show shapeNames;

/// Every photo that will be exported, drawn with its edit, crop, template and credit.
/// Tap one to change its template, shape, credit or crop, or to open it in the editor.
class ReviewGrid extends StatelessWidget {
  final Session session;
  final Renderer? renderer; // null in widget tests: gray tiles
  final List<Template> templates;
  final Map<String, ui.Image> assets;
  final ThumbnailLoader? thumbnails;
  final VoidCallback onOpenInEdit;
  final int longEdge;

  const ReviewGrid({
    super.key,
    required this.session,
    required this.renderer,
    required this.templates,
    required this.assets,
    required this.onOpenInEdit,
    this.thumbnails,
    this.longEdge = 2048,
  });

  Widget _panel() => ReviewPanel(
    session: session,
    renderer: renderer,
    templates: templates,
    onOpenInEdit: onOpenInEdit,
    longEdge: longEdge,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      return ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final indexes = [
            for (var i = 0; i < session.items.length; i++)
              if (session.items[i].flag != Flag.reject) i,
          ];
          if (indexes.isEmpty) {
            return const Center(child: Text('No photos to review. Import photos first.'));
          }
          final grid = GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: indexes.length,
            itemBuilder: (context, i) {
              final index = indexes[i];
              final item = session.items[index];
              final spec = session.specFor(item, templates);
              final template = spec.template;
              return ReviewTile(
                key: ValueKey('review-${item.path}'),
                spec: spec,
                selected: index == session.selectedIndex,
                renderer: renderer,
                assets: assets,
                thumbnails: thumbnails,
                missingAsset: template != null && assetFiles(template).any((f) => !assets.containsKey(f)),
                onTap: () {
                  session.select(index);
                  if (!wide) {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => FractionallySizedBox(heightFactor: 0.85, child: _panel()),
                    );
                  }
                },
              );
            },
          );
          if (!wide) return grid;
          return Row(
            children: [
              Expanded(child: grid),
              const VerticalDivider(width: 1),
              SizedBox(width: 320, child: _panel()),
            ],
          );
        },
      );
    },
  );
}

class ReviewTile extends StatefulWidget {
  final RenderSpec spec;
  final bool selected, missingAsset;
  final Renderer? renderer;
  final Map<String, ui.Image> assets;
  final ThumbnailLoader? thumbnails;
  final VoidCallback onTap;

  const ReviewTile({
    super.key,
    required this.spec,
    required this.selected,
    required this.missingAsset,
    required this.renderer,
    required this.assets,
    required this.onTap,
    this.thumbnails,
  });

  @override
  State<ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<ReviewTile> {
  ui.Image? _source; // small copy of the photo; the edit is drawn live on top of it

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final load = widget.thumbnails;
    if (load == null) return;
    try {
      final image = await load(widget.spec.item.path, () => mounted);
      if (!mounted) return image?.dispose();
      setState(() => _source = image);
    } on DecodeFailure {
      // stays gray; export will list this photo as a failure
    }
  }

  @override
  void dispose() {
    _source?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.spec.item.path.split(RegExp(r'[\\/]')).last;
    return Semantics(
      label: 'Photo $name',
      button: true,
      selected: widget.selected,
      child: InkWell(
        onTap: widget.onTap,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: widget.selected ? accentColor : Colors.transparent, width: 2),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The boundary keeps the drawn tile until its spec or source changes.
              RepaintBoundary(
                child: CustomPaint(
                  painter: _TilePainter(widget.spec, widget.renderer, _source, widget.assets),
                ),
              ),
              if (widget.missingAsset)
                const Positioned(
                  right: 4,
                  top: 4,
                  child: Tooltip(
                    message: 'A template image is missing',
                    child: Icon(Icons.warning_amber, color: Colors.amber, size: 20),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  final RenderSpec spec;
  final Renderer? renderer;
  final ui.Image? source;
  final Map<String, ui.Image> assets;

  _TilePainter(this.spec, this.renderer, this.source, this.assets);

  @override
  void paint(Canvas canvas, Size size) {
    final item = spec.item;
    final oriented = orientedSize(item.width, item.height, item.quarterTurns);
    final crop = specCrop(spec);
    final fitted = fitSize(size, (crop.width * oriented.width) / (crop.height * oriented.height));
    final area = Alignment.center.inscribe(fitted, Offset.zero & size);
    if (renderer == null || source == null) {
      canvas.drawRect(area, Paint()..color = const Color(0xFF3A3A3A));
      return;
    }
    canvas.translate(area.left, area.top);
    renderer!.paintJob(canvas, jobFromSpec(spec, source!, fitted, assets));
  }

  @override
  bool shouldRepaint(_TilePainter old) =>
      old.spec != spec || old.source != source || old.assets.length != assets.length;
}

/// Per-photo choices for the selected photo.
class ReviewPanel extends StatefulWidget {
  final Session session;
  final Renderer? renderer;
  final List<Template> templates;
  final VoidCallback onOpenInEdit;
  final int longEdge;

  const ReviewPanel({
    super.key,
    required this.session,
    required this.renderer,
    required this.templates,
    required this.onOpenInEdit,
    this.longEdge = 2048,
  });

  @override
  State<ReviewPanel> createState() => _ReviewPanelState();
}

class _ReviewPanelState extends State<ReviewPanel> {
  final _credit = TextEditingController();
  String? _path;

  @override
  void dispose() {
    _credit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final item = session.selected;
      if (item == null || item.flag == Flag.reject) {
        return const Center(child: Text('Tap a photo to adjust it.'));
      }
      if (_path != item.path) {
        _path = item.path;
        _credit.text = item.creditOverride ?? '';
      }
      final names = widget.templates.map((t) => t.name).toList();
      final template = item.templateOverride == null || item.templateOverride == '' || names.contains(item.templateOverride)
          ? item.templateOverride
          : null;
      return Container(
        color: panelColor,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              item.path.split(RegExp(r'[\\/]')).last,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: const ValueKey('template-override'),
              initialValue: template,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Template for this photo'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Same as batch')),
                const DropdownMenuItem(value: '', child: Text('No template')),
                for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => session.updateSelected((i) => i.copyWith(templateOverride: () => v)),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OutputShape?>(
              key: const ValueKey('shape-override'),
              initialValue: item.shapeOverride,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Shape for this photo'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Same as batch')),
                for (final s in OutputShape.values) DropdownMenuItem(value: s, child: Text(shapeNames[s]!)),
              ],
              onChanged: (v) => session.updateSelected(
                // A new shape needs a new crop, like a rotation does.
                (i) => i.copyWith(shapeOverride: () => v, crop: () => null),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('credit-override'),
              controller: _credit,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'Credit for this photo',
                helperText: session.credit.enabled
                    ? 'Empty uses the batch credit'
                    : 'Photo credit is off (turn it on in Template)',
              ),
              // Typing is one undo step, closed when the field loses focus or Enter is hit.
              onChanged: (v) => session.updateLive(
                (i) => i.copyWith(creditOverride: () => v.trim().isEmpty ? null : v),
                commit: false,
              ),
              onEditingComplete: () {
                session.updateLive((i) => i, commit: true);
                FocusScope.of(context).unfocus();
              },
            ),
            const SizedBox(height: 4),
            const Text('Crop position', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            SizedBox(
              height: 220,
              child: CropView(session: session, renderer: widget.renderer, longEdge: widget.longEdge),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: widget.onOpenInEdit, child: const Text('Open in Edit')),
          ],
        ),
      );
    },
  );
}
