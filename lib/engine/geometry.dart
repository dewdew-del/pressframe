import 'dart:math' as math;
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

/// The largest centered rect with the photo's own shape that shows no empty corner after
/// the photo is rotated by [degrees]. Normalized on the rotated photo.
Rect insetForStraighten(Size oriented, double degrees) {
  final a = degrees.abs() * math.pi / 180;
  final w = oriented.width, h = oriented.height;
  final scale = 1 / (math.cos(a) + math.max(w / h, h / w) * math.sin(a));
  return Rect.fromCenter(center: const Offset(0.5, 0.5), width: scale, height: scale);
}

/// The crop that is actually exported: the user's crop (or everything), kept inside the
/// straighten inset, then fitted to the output shape.
Rect effectiveCrop(Size oriented, double? aspect, Rect? userCrop, double straighten) {
  if (straighten == 0) return cropForShape(oriented, aspect, userCrop);
  final inset = insetForStraighten(oriented, straighten);
  var base = userCrop?.intersect(inset) ?? inset;
  if (base.width <= 0 || base.height <= 0) base = inset;
  return cropForShape(oriented, aspect, base);
}
