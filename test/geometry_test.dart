import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/engine/geometry.dart';

void expectRect(Rect actual, Rect expected, [double eps = 1e-9]) {
  expect(actual.left, closeTo(expected.left, eps));
  expect(actual.top, closeTo(expected.top, eps));
  expect(actual.width, closeTo(expected.width, eps));
  expect(actual.height, closeTo(expected.height, eps));
}

void main() {
  const full = Rect.fromLTWH(0, 0, 1, 1);

  test('orientedSize swaps on odd quarter turns', () {
    expect(orientedSize(6000, 4000, 1), const Size(4000, 6000));
    expect(orientedSize(6000, 4000, 2), const Size(6000, 4000));
    expect(orientedSize(6000, 4000, 3), const Size(4000, 6000));
  });

  test('cropForShape with no aspect and no crop is the full photo', () {
    expect(cropForShape(const Size(6000, 4000), null, null), full);
  });

  test('cropForShape with no aspect keeps the user crop', () {
    const user = Rect.fromLTWH(0.1, 0.2, 0.3, 0.4);
    expect(cropForShape(const Size(6000, 4000), null, user), user);
  });

  test('square crop of a landscape photo is centered', () {
    expectRect(
      cropForShape(const Size(6000, 4000), 1.0, null),
      const Rect.fromLTWH(1 / 6, 0, 2 / 3, 1),
    );
  });

  test('4:5 crop of a portrait photo keeps full width', () {
    expectRect(
      cropForShape(const Size(4000, 6000), 0.8, null),
      const Rect.fromLTWH(0, (1 - 5000 / 6000) / 2, 1, 5000 / 6000),
    );
  });

  test('shape crop stays inside the user crop with the right pixel aspect', () {
    const user = Rect.fromLTWH(0.5, 0.5, 0.5, 0.5);
    final r = cropForShape(const Size(6000, 4000), 16 / 9, user);
    expect(r.left, greaterThanOrEqualTo(user.left - 1e-9));
    expect(r.top, greaterThanOrEqualTo(user.top - 1e-9));
    expect(r.right, lessThanOrEqualTo(user.right + 1e-9));
    expect(r.bottom, lessThanOrEqualTo(user.bottom + 1e-9));
    expect((r.width * 6000) / (r.height * 4000), closeTo(16 / 9, 1e-6));
  });

  test('a user crop hanging outside the photo is clamped', () {
    final r = cropForShape(const Size(6000, 4000), null, const Rect.fromLTWH(0.8, -0.2, 0.5, 0.5));
    expect(r.left >= 0 && r.top >= 0 && r.right <= 1 && r.bottom <= 1, true);
    expect(r.width > 0 && r.height > 0, true);
  });
}
