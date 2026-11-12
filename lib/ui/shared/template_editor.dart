import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../engine/geometry.dart';
import '../../engine/renderer.dart';
import '../../export/exporter.dart';
import '../../models/template.dart';
import '../../session.dart';
import '../../storage/template_library.dart';
import '../theme.dart';
import 'preview_view.dart';
import 'slider_group.dart';

const _snap = 0.02; // snapping distance and edge margin, as a fraction of the photo

/// Where a logo's center lands on one axis: clamped to the photo, and pulled to the near
/// edge (with a small margin), the center or the far edge when within 2%.
/// [half] is half the logo's size on this axis, as a fraction of the photo.
double snapAxis(double v, double half) {
  final clamped = v.clamp(0.0, 1.0).toDouble();
  for (final target in [half + _snap, 0.5, 1 - half - _snap]) {
    if ((clamped - target).abs() <= _snap) return target;
  }
  return clamped;
}

/// '#RRGGBB' or 'RRGGBB' to an opaque ARGB int; null if it is not a color.
int? parseHex(String text) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(text.trim());
  return m == null ? null : 0xFF000000 | int.parse(m.group(1)!, radix: 16);
}

String toHex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Makes or edits a built template (gradient band + logos) with a live preview on the
/// selected photo. Pops with the saved [BuiltTemplate], or null on cancel.
class TemplateEditor extends StatefulWidget {
  final Session session;
  final TemplateLibrary library;
  final Renderer? renderer;
  final BuiltTemplate initial;
  final int longEdge;

  const TemplateEditor({
    super.key,
    required this.session,
    required this.library,
    required this.renderer,
    required this.initial,
    this.longEdge = 2048,
  });

  @override
  State<TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<TemplateEditor> {
  late final _name = TextEditingController(text: widget.initial.name);
  late GradientBand? _band = widget.initial.band;
  late GradientBand _lastBand = widget.initial.band ?? const GradientBand(); // kept while off
  late List<LogoLayer> _logos = [...widget.initial.logos];
  int _selected = -1; // logo being edited
  Offset _grab = Offset.zero; // pointer minus logo center, while dragging

  BuiltTemplate get _draft => BuiltTemplate(name: _name.text.trim(), band: _band, logos: _logos);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setBand(GradientBand b) => setState(() => _band = _lastBand = b);

  GradientBand _bandWith({BandEdge? edge, double? height, int? start, int? end, double? opacity}) {
    final b = _band ?? _lastBand;
    return GradientBand(
      edge: edge ?? b.edge,
      heightFraction: height ?? b.heightFraction,
      startColor: start ?? b.startColor,
      endColor: end ?? b.endColor,
      opacity: opacity ?? b.opacity,
    );
  }

  void _setLogo(int i, LogoLayer logo) => setState(() => _logos = [..._logos]..[i] = logo);

  Future<void> _addLogo() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png'],
      dialogTitle: 'Choose a logo (PNG)',
    );
    final path = file?.path;
    if (path == null) return;
    try {
      final name = await widget.library.importAsset(path);
      if (!mounted) return;
      setState(() {
        // New logos start in a bottom corner, the usual place for a publication mark.
        _logos = [..._logos, LogoLayer(file: name, cx: _logos.isEmpty ? 0.1 : 0.9, cy: 0.9)];
        _selected = _logos.length - 1;
      });
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That file is not a PNG image. Logos must be PNG.')),
        );
      }
    }
  }

  /// Half the logo's width and height as fractions of an output of [size].
  Offset _half(LogoLayer logo, Size size) {
    final image = widget.library.assets[logo.file];
    final ratio = image == null ? 1.0 : image.height / image.width;
    return Offset(logo.widthFraction / 2, logo.widthFraction * ratio * size.width / size.height / 2);
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 700;
      final preview = _preview();
      final controls = _controls();
      return wide
          ? Row(
              children: [
                Expanded(child: preview),
                const VerticalDivider(width: 1),
                SizedBox(width: 320, child: controls),
              ],
            )
          : Column(
              children: [
                Expanded(flex: 4, child: preview),
                const Divider(height: 1),
                Expanded(flex: 5, child: controls),
              ],
            );
    },
  );

  Widget _preview() => PhotoLoader(
    session: widget.session,
    enabled: widget.renderer != null,
    longEdge: widget.longEdge,
    builder: (context, image) => LayoutBuilder(
      builder: (context, constraints) {
        final item = widget.session.selected!;
        final base = widget.session.specFor(item, const []);
        final RenderSpec spec = (
          item: base.item,
          shape: base.shape,
          template: _draft,
          creditText: base.creditText,
          credit: base.credit,
        );
        final oriented = orientedSize(item.width, item.height, item.quarterTurns);
        final crop = specCrop(spec);
        final fitted = fitSize(
          constraints.biggest,
          (crop.width * oriented.width) / (crop.height * oriented.height),
        );
        final area = Alignment.center.inscribe(fitted, Offset.zero & constraints.biggest);
        Offset normalized(Offset p) =>
            Offset((p.dx - area.left) / area.width, (p.dy - area.top) / area.height);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) {
            final p = normalized(d.localPosition);
            var hit = -1;
            for (var i = 0; i < _logos.length; i++) {
              final half = _half(_logos[i], fitted);
              final l = _logos[i];
              if ((p.dx - l.cx).abs() <= half.dx && (p.dy - l.cy).abs() <= half.dy) hit = i;
            }
            setState(() => _selected = hit);
            if (hit >= 0) _grab = p - Offset(_logos[hit].cx, _logos[hit].cy);
          },
          onPanUpdate: (d) {
            if (_selected < 0) return;
            final logo = _logos[_selected];
            final p = normalized(d.localPosition) - _grab;
            final half = _half(logo, fitted);
            _setLogo(
              _selected,
              logo.copyWith(cx: snapAxis(p.dx, half.dx), cy: snapAxis(p.dy, half.dy)),
            );
          },
          child: CustomPaint(
            size: Size.infinite,
            painter: _DraftPainter(
              renderer: widget.renderer,
              image: image,
              spec: spec,
              assets: widget.library.assets,
              area: area,
              selected: _selected >= 0 && _selected < _logos.length
                  ? Rect.fromCenter(
                      center: Offset(
                        area.left + _logos[_selected].cx * area.width,
                        area.top + _logos[_selected].cy * area.height,
                      ),
                      width: _half(_logos[_selected], fitted).dx * 2 * area.width,
                      height: _half(_logos[_selected], fitted).dy * 2 * area.height,
                    )
                  : null,
            ),
          ),
        );
      },
    ),
  );

  Widget _controls() {
    final band = _band;
    final logo = _selected >= 0 && _selected < _logos.length ? _logos[_selected] : null;
    return Container(
      color: panelColor,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Template name'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SwitchListTile(
            title: const Text('Gradient band'),
            value: band != null,
            onChanged: (on) => setState(() => _band = on ? _lastBand : null),
          ),
          if (band != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<BandEdge>(
                segments: const [
                  ButtonSegment(value: BandEdge.top, label: Text('Top')),
                  ButtonSegment(value: BandEdge.bottom, label: Text('Bottom')),
                  ButtonSegment(value: BandEdge.both, label: Text('Both')),
                ],
                selected: {band.edge},
                onSelectionChanged: (s) => _setBand(_bandWith(edge: s.first)),
              ),
            ),
            const SizedBox(height: 8),
            _percent('Band height', band.heightFraction, 0.05, 0.6, 0.25, (v) => _setBand(_bandWith(height: v))),
            _percent('Band opacity', band.opacity, 0, 1, 1, (v) => _setBand(_bandWith(opacity: v))),
            ColorField(
              label: 'Start color',
              color: band.startColor,
              onChanged: (c) => _setBand(_bandWith(start: c)),
            ),
            ColorField(
              label: 'End color',
              color: band.endColor,
              onChanged: (c) => _setBand(_bandWith(end: c)),
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _addLogo,
                  icon: const Icon(Icons.add),
                  label: const Text('Add logo'),
                ),
                for (var i = 0; i < _logos.length; i++)
                  ChoiceChip(
                    label: Text('Logo ${i + 1}'),
                    selected: i == _selected,
                    onSelected: (_) => setState(() => _selected = i),
                  ),
              ],
            ),
          ),
          if (_logos.isNotEmpty && logo == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text('Drag a logo on the photo to move it. It snaps to corners, edges and the center.'),
            ),
          if (logo != null) ...[
            const SizedBox(height: 8),
            _percent('Logo size', logo.widthFraction, 0.03, 0.6, 0.12, (v) => _setLogo(_selected, logo.copyWith(widthFraction: v))),
            _percent('Logo opacity', logo.opacity, 0.1, 1, 1, (v) => _setLogo(_selected, logo.copyWith(opacity: v))),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    _logos = [..._logos]..removeAt(_selected);
                    _selected = -1;
                  }),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete logo'),
                ),
              ),
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _name.text.trim().isEmpty ? null : _save,
                  child: const Text('Save template'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _percent(String label, double value, double min, double max, double reset, ValueChanged<double> set) =>
      LabeledSlider(
        label: label,
        min: min,
        max: max,
        value: value,
        resetValue: reset,
        format: (v) => '${(v * 100).round()}%',
        onChanged: set,
        onChangeEnd: set,
      );
}

class _DraftPainter extends CustomPainter {
  final Renderer? renderer;
  final ui.Image? image;
  final RenderSpec spec;
  final Map<String, ui.Image> assets;
  final Rect area;
  final Rect? selected;

  _DraftPainter({
    required this.renderer,
    required this.image,
    required this.spec,
    required this.assets,
    required this.area,
    required this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (renderer != null && image != null) {
      canvas.save();
      canvas.translate(area.left, area.top);
      renderer!.paintJob(canvas, jobFromSpec(spec, image!, area.size, assets));
      canvas.restore();
    } else {
      canvas.drawRect(area, Paint()..color = const Color(0xFF3A3A3A));
    }
    if (selected != null) {
      canvas.drawRect(
        selected!,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = accentColor,
      );
    }
  }

  @override
  bool shouldRepaint(_DraftPainter old) => true;
}

/// A color picker made of hue, saturation and brightness sliders plus a hex field.
class ColorField extends StatefulWidget {
  final String label;
  final int color; // ARGB
  final ValueChanged<int> onChanged;
  const ColorField({super.key, required this.label, required this.color, required this.onChanged});

  @override
  State<ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<ColorField> {
  late final _hex = TextEditingController(text: toHex(widget.color));
  // Kept here because a gray or black color has no hue of its own to read back.
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.color));

  @override
  void didUpdateWidget(ColorField old) {
    super.didUpdateWidget(old);
    if (widget.color != _hsv.toColor().toARGB32()) _hsv = HSVColor.fromColor(Color(widget.color));
    if (parseHex(_hex.text) != widget.color) _hex.text = toHex(widget.color);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor c) {
    setState(() => _hsv = c);
    widget.onChanged(c.toColor().toARGB32());
  }

  Widget _slider(String name, double value, double max, HSVColor Function(double) apply) => Row(
    children: [
      SizedBox(width: 84, child: Text(name, style: const TextStyle(fontSize: 12))),
      Expanded(
        child: Semantics(
          label: '${widget.label} $name',
          child: Slider(value: value.clamp(0, max), max: max, onChanged: (v) => _set(apply(v))),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(widget.color),
                border: Border.all(color: Colors.white38),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.label)),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _hex,
                decoration: const InputDecoration(isDense: true, labelText: 'Hex'),
                onChanged: (text) {
                  final c = parseHex(text);
                  if (c != null) widget.onChanged(c);
                },
              ),
            ),
          ],
        ),
        _slider('Hue', _hsv.hue, 360, _hsv.withHue),
        _slider('Saturation', _hsv.saturation, 1, _hsv.withSaturation),
        _slider('Brightness', _hsv.value, 1, _hsv.withValue),
      ],
    ),
  );
}
