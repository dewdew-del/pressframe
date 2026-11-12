import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/engine/auto_fix.dart';
import 'package:pressframe/models/edit_params.dart';

Uint8List solid(int r, int g, int b, {int pixels = 64}) {
  final out = Uint8List(pixels * 4);
  for (var i = 0; i < out.length; i += 4) {
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
    out[i + 3] = 255;
  }
  return out;
}

EditParams fix(int r, int g, int b, [EditParams current = EditParams.neutral]) =>
    autoFix(solid(r, g, b), 8, 8, current);

void main() {
  test('a dark photo is brightened', () => expect(fix(30, 30, 30).exposure, greaterThan(0.5)));

  test('a bright photo is darkened', () => expect(fix(230, 230, 230).exposure, lessThan(-0.3)));

  test('a neutral gray photo keeps its color', () {
    final e = fix(125, 125, 125);
    expect(e.temperature.abs(), lessThan(0.01));
    expect(e.tint.abs(), lessThan(0.01));
  });

  test('a blue-ish photo is warmed', () => expect(fix(90, 110, 160).temperature, greaterThan(0.2)));

  test('sliders auto fix does not own are kept', () {
    final e = fix(125, 125, 125, const EditParams(saturation: 0.4, sharpen: 0.3));
    expect(e.saturation, 0.4);
    expect(e.sharpen, 0.3);
  });

  test('a black or empty photo does not produce NaN', () {
    for (final e in [fix(0, 0, 0), autoFix(Uint8List(0), 0, 0, EditParams.neutral)]) {
      expect(e.toJson().values.every((v) => (v as double).isFinite), true);
    }
  });
}
