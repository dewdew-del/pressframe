import 'dart:math' as math;
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

  group('insetForStraighten', () {
    const photo = Size(6000, 4000);

    test('no rotation keeps the full photo', () {
      expectRect(insetForStraighten(photo, 0), full);
    });

    test('at 10 degrees it is centered, same shape, and has no empty corners', () {
      for (final degrees in [10.0, -10.0]) {
        final r = insetForStraighten(photo, degrees);
        expect(r.center.dx, closeTo(0.5, 1e-9));
        expect(r.center.dy, closeTo(0.5, 1e-9));
        expect((r.width * 6000) / (r.height * 4000), closeTo(1.5, 1e-9));
        final a = -degrees * math.pi / 180;
        for (final corner in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
          // The corner in pixels around the center, rotated back onto the unrotated photo.
          final x = (corner.dx - 0.5) * 6000, y = (corner.dy - 0.5) * 4000;
          final sx = x * math.cos(a) - y * math.sin(a), sy = x * math.sin(a) + y * math.cos(a);
          expect(sx.abs(), lessThanOrEqualTo(3000 + 1e-6));
          expect(sy.abs(), lessThanOrEqualTo(2000 + 1e-6));
        }
      }
    });

    test('more rotation leaves less photo', () {
      double area(double d) {
        final r = insetForStraighten(photo, d);
        return r.width * r.height;
      }

      expect(area(15), lessThan(area(5)));
      expect(area(5), lessThan(1));
    });
  });

  group('effectiveCrop', () {
    const photo = Size(6000, 4000);

    test('a straightened photo with no crop uses the inset', () {
      expectRect(effectiveCrop(photo, null, null, 10), insetForStraighten(photo, 10));
    });

    test('a user crop is kept inside the inset', () {
      final inset = insetForStraighten(photo, 10);
      final r = effectiveCrop(photo, null, const Rect.fromLTWH(0, 0, 0.6, 0.6), 10);
      expect(r.left, closeTo(inset.left, 1e-9));
      expect(r.top, closeTo(inset.top, 1e-9));
      expect(r.right, closeTo(0.6, 1e-9));
    });

    test('without straighten it is cropForShape', () {
      expectRect(effectiveCrop(photo, 1.0, null, 0), cropForShape(photo, 1.0, null));
    });
  });
}
