import 'package:flutter/material.dart';

import '../../models/edit_params.dart';
import '../../session.dart';
import '../theme.dart';

/// One slider of the editor: its label, range, and how it reads and writes [EditParams].
class SliderSpec {
  final String label;
  final double min, max;
  final double Function(EditParams) get;
  final EditParams Function(EditParams, double) set;

  /// Colors of the track from left to right (Warmth, Tint); null = plain track.
  final List<Color>? track;

  /// Brightness is in stops and reads with two decimals; the rest read as -100..100.
  final bool stops;

  const SliderSpec(this.label, this.min, this.max, this.get, this.set, {this.track, this.stops = false});

  String format(double v) {
    if (stops) return '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)}';
    final n = (v * 100).round();
    return '${n > 0 ? '+' : ''}$n';
  }
}

// Plain names first ("Brightness", "Warmth"); the exact ones sit under "More controls".
final lightSliders = [
  SliderSpec('Brightness', -2, 2, (e) => e.exposure, (e, v) => e.copyWith(exposure: v), stops: true),
  SliderSpec('Contrast', -1, 1, (e) => e.contrast, (e, v) => e.copyWith(contrast: v)),
  SliderSpec('Shadows', -1, 1, (e) => e.shadows, (e, v) => e.copyWith(shadows: v)),
];
final lightMore = [
  SliderSpec('Highlights', -1, 1, (e) => e.highlights, (e, v) => e.copyWith(highlights: v)),
  SliderSpec('Whites', -1, 1, (e) => e.whites, (e, v) => e.copyWith(whites: v)),
  SliderSpec('Blacks', -1, 1, (e) => e.blacks, (e, v) => e.copyWith(blacks: v)),
];
final colorSliders = [
  SliderSpec(
    'Warmth',
    -1,
    1,
    (e) => e.temperature,
    (e, v) => e.copyWith(temperature: v),
    track: const [Color(0xFF3F7FE0), Color(0xFFE8C84A)],
  ),
  SliderSpec('Saturation', -1, 1, (e) => e.saturation, (e, v) => e.copyWith(saturation: v)),
];
final colorMore = [
  SliderSpec(
    'Tint',
    -1,
    1,
    (e) => e.tint,
    (e, v) => e.copyWith(tint: v),
    track: const [Color(0xFF3DBE5B), Color(0xFFD64BC2)],
  ),
  SliderSpec('Vibrance', -1, 1, (e) => e.vibrance, (e, v) => e.copyWith(vibrance: v)),
];
final detailSliders = [
  SliderSpec('Sharpen', 0, 1, (e) => e.sharpen, (e, v) => e.copyWith(sharpen: v)),
];
final detailMore = [
  SliderSpec('Texture', -1, 1, (e) => e.texture, (e, v) => e.copyWith(texture: v)),
  SliderSpec('Clarity', -1, 1, (e) => e.clarity, (e, v) => e.copyWith(clarity: v)),
];

/// A group of edit sliders bound to the selected photo, with the less-used ones behind a
/// "More controls" row that starts closed.
class SliderGroup extends StatefulWidget {
  final Session session;
  final String name; // "Light", "Color", "Detail"
  final List<SliderSpec> sliders;
  final List<SliderSpec> more;

  const SliderGroup({
    super.key,
    required this.session,
    required this.name,
    required this.sliders,
    this.more = const [],
  });

  @override
  State<SliderGroup> createState() => _SliderGroupState();
}

class _SliderGroupState extends State<SliderGroup> {
  bool _open = false;

  Widget _slider(SliderSpec s) {
    final session = widget.session, item = session.selected;
    return LabeledSlider(
      label: s.label,
      min: s.min,
      max: s.max,
      value: item == null ? 0 : s.get(item.edit),
      enabled: item != null,
      format: s.format,
      track: s.track,
      // Read the edit fresh each time: the drag updates it without rebuilding us.
      onChanged: (v) => session.setEdit(s.set(session.selected!.edit, v), commit: false),
      onChangeEnd: (v) => session.setEdit(s.set(session.selected!.edit, v), commit: true),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.session,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in widget.sliders) _slider(s),
        if (widget.more.isNotEmpty)
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              key: ValueKey('more-${widget.name}'),
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Text('More controls', style: TextStyle(fontSize: 13, color: hintColor)),
                      Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: hintColor),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_open)
          for (final s in widget.more) _slider(s),
      ],
    ),
  );
}

/// Slider with its label on the left, a small value box on the right, and a thin track
/// with a triangle marker. Double-click or double-tap resets it.
class LabeledSlider extends StatefulWidget {
  final String label;
  final double min, max, value;
  final bool enabled;
  final ValueChanged<double> onChanged, onChangeEnd;
  final String Function(double)? format;
  final double resetValue; // what a double-tap goes back to
  final List<Color>? track;

  const LabeledSlider({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    this.enabled = true,
    this.format,
    this.resetValue = 0,
    this.track,
  });

  @override
  State<LabeledSlider> createState() => _LabeledSliderState();
}

class _LabeledSliderState extends State<LabeledSlider> {
  double? _dragging; // shown while the thumb is held, so the panel need not rebuild

  String _text(double v) {
    if (widget.format != null) return widget.format!(v);
    final s = v.toStringAsFixed(2);
    return v > 0 ? '+$s' : s;
  }

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max).toDouble();
    final reset = widget.resetValue.clamp(widget.min, widget.max).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.label, style: const TextStyle(fontSize: 13)),
              ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    border: Border.all(color: const Color(0xFF4A4A4A)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _text(value),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
            ],
          ),
          GestureDetector(
            onDoubleTap: widget.enabled
                ? () {
                    setState(() => _dragging = null);
                    widget.onChangeEnd(reset);
                  }
                : null,
            child: Semantics(
              label: widget.label,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const _TriangleThumb(),
                  trackShape: _ThinTrack(widget.track),
                ),
                child: Slider(
                  key: ValueKey('slider-${widget.label}'),
                  min: widget.min,
                  max: widget.max,
                  value: value,
                  semanticFormatterCallback: _text,
                  onChanged: widget.enabled
                      ? (v) {
                          setState(() => _dragging = v);
                          widget.onChanged(v);
                        }
                      : null,
                  onChangeEnd: (v) {
                    setState(() => _dragging = null);
                    widget.onChangeEnd(v);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small triangle under the track that points at the value.
class _TriangleThumb extends SliderComponentShape {
  const _TriangleThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(14, 14);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final enabled = enableAnimation.value > 0.5;
    final path = Path()
      ..moveTo(center.dx, center.dy + 2)
      ..lineTo(center.dx - 6, center.dy + 12)
      ..lineTo(center.dx + 6, center.dy + 12)
      ..close();
    context.canvas.drawPath(path, Paint()..color = enabled ? textColor : const Color(0xFF6A6A6A));
    // A short tick through the track so the exact position is easy to read.
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: 2, height: 8),
      Paint()..color = enabled ? textColor : const Color(0xFF6A6A6A),
    );
  }
}

/// A 2 px track, plain gray or a left-to-right color ramp.
class _ThinTrack extends SliderTrackShape with BaseSliderTrackShape {
  final List<Color>? colors;
  const _ThinTrack(this.colors);

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final paint = Paint();
    if (colors != null && isEnabled) {
      paint.shader = LinearGradient(colors: colors!).createShader(rect);
    } else {
      paint.color = const Color(0xFF6A6A6A);
    }
    context.canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(1)), paint);
  }
}
