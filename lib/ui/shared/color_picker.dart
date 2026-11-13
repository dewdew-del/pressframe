import 'package:flutter/material.dart';

/// '#RRGGBB' or 'RRGGBB' to an opaque ARGB int; null if it is not a color.
int? parseHex(String text) {
  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(text.trim());
  return m == null ? null : 0xFF000000 | int.parse(m.group(1)!, radix: 16);
}

String toHex(int argb) =>
    '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

const readyColors = <int>[
  0xFF000000, 0xFFFFFFFF, 0xFF757575, 0xFF0B3D91, 0xFF1976D2, 0xFF00ACC1,
  0xFF2E7D32, 0xFFFBC02D, 0xFFF57C00, 0xFFD32F2F, 0xFF7B1FA2, 0xFF6D4C41, //
];

/// One row: a color swatch and its label. Tapping it opens the picker sheet.
class ColorField extends StatelessWidget {
  final String label;
  final int color; // ARGB
  final ValueChanged<int> onChanged;
  const ColorField({super.key, required this.label, required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: _Dot(color: color, size: 32),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false, // the mixer needs vertical drags
      builder: (_) => _PickerSheet(label: label, color: color, onChanged: onChanged),
    ),
  );
}

class _Dot extends StatelessWidget {
  final int color;
  final double size;
  final bool selected;
  const _Dot({required this.color, required this.size, this.selected = false});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Color(color),
      shape: BoxShape.circle,
      border: Border.all(color: selected ? Colors.white : Colors.white38, width: selected ? 3 : 1),
    ),
  );
}

class _PickerSheet extends StatefulWidget {
  final String label;
  final int color;
  final ValueChanged<int> onChanged;
  const _PickerSheet({required this.label, required this.color, required this.onChanged});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  // Kept as HSV because a gray or black color has no hue of its own to read back.
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.color));
  late final _hex = TextEditingController(text: toHex(widget.color));

  int get _argb => _hsv.toColor().toARGB32();

  void _set(HSVColor c, {bool fromText = false}) {
    setState(() => _hsv = c);
    if (!fromText) _hex.text = toHex(_argb);
    widget.onChanged(_argb);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 12, color: Color(0xFFA8A8A8));
    final hue = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Dot(color: _argb, size: 32),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.label, style: Theme.of(context).textTheme.titleMedium)),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Ready colors', style: small),
            Wrap(
              children: [
                for (final c in readyColors)
                  InkResponse(
                    key: ValueKey('swatch-${c.toRadixString(16).toUpperCase()}'),
                    onTap: () => _set(HSVColor.fromColor(Color(c))),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(child: _Dot(color: c, size: 36, selected: c == _argb)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Mix your own', style: small),
            const SizedBox(height: 6),
            // Left to right = more color, top to bottom = darker.
            _Pad(
              key: const ValueKey('mixer-square'),
              height: 150,
              thumb: Offset(_hsv.saturation, 1 - _hsv.value),
              onChanged: (p) => _set(_hsv.withSaturation(p.dx).withValue(1 - p.dy)),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.white, hue])),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _Pad(
              key: const ValueKey('mixer-hue'),
              height: 48,
              thumb: Offset(_hsv.hue / 360, 0.5),
              onChanged: (p) => _set(_hsv.withHue(p.dx * 360)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h % 360, 1, 1).toColor(),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Optional: for a publication that knows its exact brand color.
            SizedBox(
              width: 160,
              child: TextField(
                controller: _hex,
                decoration: const InputDecoration(isDense: true, labelText: 'Color code (optional)'),
                onChanged: (text) {
                  final c = parseHex(text);
                  if (c != null) _set(HSVColor.fromColor(Color(c)), fromText: true);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A colored area the user taps or drags on; reports the position as 0..1 fractions.
class _Pad extends StatelessWidget {
  final double height;
  final Offset thumb;
  final ValueChanged<Offset> onChanged;
  final Widget child;
  const _Pad({super.key, required this.height, required this.thumb, required this.onChanged, required this.child});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: LayoutBuilder(
      builder: (context, box) {
        void at(Offset p) => onChanged(
          Offset((p.dx / box.maxWidth).clamp(0.0, 1.0), (p.dy / height).clamp(0.0, 1.0)),
        );
        return GestureDetector(
          onPanDown: (d) => at(d.localPosition),
          onPanUpdate: (d) => at(d.localPosition),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child)),
              Positioned(
                left: thumb.dx * box.maxWidth - 9,
                top: thumb.dy * height - 9,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(blurRadius: 2)],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
