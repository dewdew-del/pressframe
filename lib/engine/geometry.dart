import 'dart:ui';

/// Photo size after [quarterTurns] 90-degree rotations.
Size orientedSize(int width, int height, int quarterTurns) => quarterTurns.isOdd
    ? Size(height.toDouble(), width.toDouble())
    : Size(width.toDouble(), height.toDouble());

/// The normalized crop to export. [aspect] null: the user crop, or the full photo.
/// Otherwise the largest rect of that pixel aspect (width / height) that fits inside the
/// user crop (or the full photo), centered on it.
Rect cropForShape(Size oriented, double? aspect, Rect? userCrop) {
  const full = Rect.fromLTWH(0, 0, 1, 1);
  var base = userCrop?.intersect(full) ?? full;
  if (base.width <= 0 || base.height <= 0) base = full;
  if (aspect == null) return base;

  final pw = base.width * oriented.width, ph = base.height * oriented.height;
  final double w, h; // pixels
  if (pw / ph > aspect) {
    h = ph;
    w = ph * aspect;
  } else {
    w = pw;
    h = pw / aspect;
  }
  return Rect.fromCenter(
    center: base.center,
    width: w / oriented.width,
    height: h / oriented.height,
  );
}
