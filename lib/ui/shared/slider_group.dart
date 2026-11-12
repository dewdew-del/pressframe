import 'package:flutter/material.dart';

import '../../models/edit_params.dart';
import '../../session.dart';

/// One slider of the editor: its label, range, and how it reads and writes [EditParams].
class SliderSpec {
  final String label;
  final double min, max;
  final double Function(EditParams) get;
  final EditParams Function(EditParams, double) set;
  const SliderSpec(this.label, this.min, this.max, this.get, this.set);
}

final lightSliders = [
  SliderSpec('Exposure', -2, 2, (e) => e.exposure, (e, v) => e.copyWith(exposure: v)),
  SliderSpec('Contrast', -1, 1, (e) => e.contrast, (e, v) => e.copyWith(contrast: v)),
  SliderSpec('Highlights', -1, 1, (e) => e.highlights, (e, v) => e.copyWith(highlights: v)),
  SliderSpec('Shadows', -1, 1, (e) => e.shadows, (e, v) => e.copyWith(shadows: v)),
];
final colorSliders = [
  SliderSpec('Temperature', -1, 1, (e) => e.temperature, (e, v) => e.copyWith(temperature: v)),
  SliderSpec('Tint', -1, 1, (e) => e.tint, (e, v) => e.copyWith(tint: v)),
  SliderSpec('Saturation', -1, 1, (e) => e.saturation, (e, v) => e.copyWith(saturation: v)),
  SliderSpec('Vibrance', -1, 1, (e) => e.vibrance, (e, v) => e.copyWith(vibrance: v)),
];
final detailSliders = [
  SliderSpec('Sharpen', 0, 1, (e) => e.sharpen, (e, v) => e.copyWith(sharpen: v)),
];

/// A group of edit sliders bound to the selected photo.
class SliderGroup extends StatelessWidget {
  final Session session;
  final List<SliderSpec> sliders;
  const SliderGroup({super.key, required this.session, required this.sliders});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) {
      final item = session.selected;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in sliders)
            LabeledSlider(
              label: s.label,
              min: s.min,
              max: s.max,
              value: item == null ? 0 : s.get(item.edit),
              enabled: item != null,
              // Read the edit fresh each time: the drag updates it without rebuilding us.
              onChanged: (v) => session.setEdit(s.set(session.selected!.edit, v), commit: false),
              onChangeEnd: (v) => session.setEdit(s.set(session.selected!.edit, v), commit: true),
            ),
        ],
      );
    },
  );
}

/// Slider with a text label and a numeric value. Double-click or double-tap resets it to 0.
class LabeledSlider extends StatefulWidget {
  final String label;
  final double min, max, value;
  final bool enabled;
  final ValueChanged<double> onChanged, onChangeEnd;
  final String Function(double)? format;
  final double resetValue; // what a double-tap goes back to

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
    final value = (_dragging ?? widget.value).clamp(widget.min, widget.max);
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
                child: Text(
                  _text(value),
                  style: const TextStyle(
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
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
        ],
      ),
    );
  }
}
