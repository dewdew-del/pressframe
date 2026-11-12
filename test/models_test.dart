import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/models/batch_item.dart';
import 'package:pressframe/models/edit_params.dart';
import 'package:pressframe/models/kit.dart';
import 'package:pressframe/models/preset.dart';
import 'package:pressframe/models/template.dart';

void main() {
  const full = EditParams(
    exposure: 1.5,
    contrast: 0.1,
    highlights: -0.2,
    shadows: 0.3,
    temperature: -0.4,
    tint: 0.5,
    saturation: -0.6,
    vibrance: 0.7,
    sharpen: 0.8,
  );

  test('EditParams survives a JSON round trip', () {
    expect(EditParams.fromJson(full.toJson()), full);
  });

  test('EditParams.fromJson with missing keys is neutral', () {
    expect(EditParams.fromJson({}), EditParams.neutral);
  });

  test('EditParams.fromJson clamps values to their range', () {
    expect(EditParams.fromJson({'exposure': 99}).exposure, 2.0);
    expect(EditParams.fromJson({'sharpen': -1}).sharpen, 0.0);
  });

  test('EditParams.copyWith changes only the named field', () {
    expect(full.copyWith(exposure: 0), isNot(full));
    expect(full.copyWith(exposure: 0).copyWith(exposure: 1.5), full);
  });

  test('OutputShape aspect', () {
    expect(OutputShape.r4x5.aspect, 0.8);
    expect(OutputShape.original.aspect, isNull);
  });

  test('Kit survives a JSON round trip', () {
    final kit = Kit(
      name: 'The Scribe',
      presets: [const Preset(name: 'Gym', params: full)],
      templates: [
        BuiltTemplate(
          name: 'Band',
          band: const GradientBand(
            edge: BandEdge.bottom,
            heightFraction: 0.25,
            startColor: 0xFFFF0000,
            endColor: 0xFF0000FF,
            opacity: 0.9,
          ),
          logos: const [
            LogoLayer(file: 'a.png', cx: 0.1, cy: 0.9, widthFraction: 0.1, opacity: 1),
            LogoLayer(file: 'b.png', cx: 0.9, cy: 0.9, widthFraction: 0.12, opacity: 0.8),
          ],
        ),
        const FrameTemplate(name: 'Frame', file: 'f.png', aspect: 0.8),
      ],
      credit: const CreditStyle(enabled: true, corner: Corner.topLeft, white: false),
    );
    final json = jsonEncode(kit.toJson());
    final back = Kit.fromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), json);
    expect(back.templates[0], isA<BuiltTemplate>());
    expect(back.templates[1], isA<FrameTemplate>());
  });

  test('photo credit is off by default', () {
    expect(const CreditStyle().enabled, false);
  });

  test('BatchItem survives a JSON round trip and copyWith can clear crop', () {
    const item = BatchItem(
      path: r'C:\p\a.cr3',
      isRaw: true,
      width: 6000,
      height: 4000,
      flag: Flag.pick,
      edit: full,
      quarterTurns: 1,
      straighten: -3.5,
      crop: Rect.fromLTWH(0.1, 0.2, 0.5, 0.5),
      templateOverride: 'Band',
      shapeOverride: OutputShape.r1x1,
      creditOverride: 'Photo by X',
    );
    final json = jsonEncode(item.toJson());
    final back = BatchItem.fromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(jsonEncode(back.toJson()), json);
    expect(back.crop, item.crop);
    expect(item.copyWith(crop: () => null).crop, isNull);
    expect(item.copyWith(flag: Flag.reject).crop, item.crop);
  });
}
