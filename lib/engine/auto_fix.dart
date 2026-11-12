import 'dart:math' as math;
import 'dart:typed_data';

import '../models/edit_params.dart';

/// Suggests exposure, contrast, temperature and tint from the photo's pixels (RGBA, 8 bit).
/// Every other slider is copied from [current].
EditParams autoFix(Uint8List rgba, int width, int height, EditParams current) {
  final count = rgba.length ~/ 4;
  if (count == 0) return current;

  var sumR = 0, sumG = 0, sumB = 0;
  final histogram = List.filled(256, 0);
  for (var i = 0; i < count * 4; i += 4) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    sumR += r;
    sumG += g;
    sumB += b;
    histogram[(0.2126 * r + 0.7152 * g + 0.0722 * b).round()]++;
  }
  // Means in 0..1, kept above zero so a black frame cannot divide by zero.
  double mean(int sum) => math.max(sum / count / 255, 1e-4);
  final r = mean(sumR), g = mean(sumG), b = mean(sumB);
  final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;

  double percentile(double fraction) {
    final target = count * fraction;
    var seen = 0;
    for (var v = 0; v < 256; v++) {
      seen += histogram[v];
      if (seen >= target) return v / 255;
    }
    return 1;
  }

  final spread = percentile(0.99) - percentile(0.01);
  return current.copyWith(
    exposure: (math.log(0.45 / luma) / math.ln2).clamp(-1.5, 1.5),
    contrast: (0.9 - spread).clamp(0.0, 0.5),
    temperature: (2 * (b - r) / (b + r)).clamp(-0.5, 0.5),
    tint: (2 * (g - (r + b) / 2) / g).clamp(-0.5, 0.5),
  );
}
