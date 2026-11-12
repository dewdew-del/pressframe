enum OutputShape {
  original(null),
  r1x1(1),
  r4x5(4 / 5),
  r3x2(3 / 2),
  r16x9(16 / 9),
  r2x3(2 / 3),
  r9x16(9 / 16);

  /// width / height, null = keep the photo's own shape.
  final double? aspect;
  const OutputShape(this.aspect);
}

enum BandEdge { top, bottom, both }

enum Corner { topLeft, topRight, bottomLeft, bottomRight }

/// Reads an enum by name; an unknown or missing name gives [fallback].
T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.asNameMap()[name] ?? fallback;

double _d(Object? x, double fallback) => x is num ? x.toDouble() : fallback;

class GradientBand {
  final BandEdge edge;
  final double heightFraction; // of photo height
  final int startColor, endColor; // ARGB
  final double opacity;

  const GradientBand({
    this.edge = BandEdge.bottom,
    this.heightFraction = 0.25,
    this.startColor = 0xFF0B3D91,
    this.endColor = 0xFFD62828,
    this.opacity = 1,
  });

  Map<String, dynamic> toJson() => {
    'edge': edge.name,
    'heightFraction': heightFraction,
    'startColor': startColor,
    'endColor': endColor,
    'opacity': opacity,
  };

  factory GradientBand.fromJson(Map<String, dynamic> j) => GradientBand(
    edge: enumByName(BandEdge.values, j['edge'], BandEdge.bottom),
    heightFraction: _d(j['heightFraction'], 0.25).clamp(0, 1),
    startColor: j['startColor'] is int ? j['startColor'] as int : 0xFF000000,
    endColor: j['endColor'] is int ? j['endColor'] as int : 0xFF000000,
    opacity: _d(j['opacity'], 1).clamp(0, 1),
  );
}

class LogoLayer {
  final String file; // file name inside the app's assets folder
  final double cx, cy; // center, normalized 0..1
  final double widthFraction; // of output width
  final double opacity;

  const LogoLayer({
    required this.file,
    this.cx = 0.5,
    this.cy = 0.5,
    this.widthFraction = 0.12,
    this.opacity = 1,
  });

  LogoLayer copyWith({double? cx, double? cy, double? widthFraction, double? opacity}) => LogoLayer(
    file: file,
    cx: cx ?? this.cx,
    cy: cy ?? this.cy,
    widthFraction: widthFraction ?? this.widthFraction,
    opacity: opacity ?? this.opacity,
  );

  Map<String, dynamic> toJson() => {
    'file': file,
    'cx': cx,
    'cy': cy,
    'widthFraction': widthFraction,
    'opacity': opacity,
  };

  factory LogoLayer.fromJson(Map<String, dynamic> j) => LogoLayer(
    file: _string(j, 'file'),
    cx: _d(j['cx'], 0.5).clamp(0, 1),
    cy: _d(j['cy'], 0.5).clamp(0, 1),
    widthFraction: _d(j['widthFraction'], 0.12).clamp(0, 1),
    opacity: _d(j['opacity'], 1).clamp(0, 1),
  );
}

String _string(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v is! String || v.isEmpty) throw FormatException('Missing "$key"');
  return v;
}

sealed class Template {
  final String name;
  const Template({required this.name});

  Map<String, dynamic> toJson();

  factory Template.fromJson(Map<String, dynamic> j) => switch (j['type']) {
    'built' => BuiltTemplate.fromJson(j),
    'frame' => FrameTemplate.fromJson(j),
    final other => throw FormatException('Unknown template type: $other'),
  };
}

class BuiltTemplate extends Template {
  final GradientBand? band;
  final List<LogoLayer> logos;

  const BuiltTemplate({required super.name, this.band, this.logos = const []});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'built',
    'name': name,
    'band': band?.toJson(),
    'logos': [for (final l in logos) l.toJson()],
  };

  factory BuiltTemplate.fromJson(Map<String, dynamic> j) => BuiltTemplate(
    name: _string(j, 'name'),
    band: j['band'] is Map<String, dynamic>
        ? GradientBand.fromJson(j['band'] as Map<String, dynamic>)
        : null,
    logos: [
      for (final l in (j['logos'] as List? ?? const []))
        LogoLayer.fromJson(l as Map<String, dynamic>),
    ],
  );
}

class FrameTemplate extends Template {
  final String file; // PNG name inside the app's assets folder
  final double aspect; // width / height of the PNG

  const FrameTemplate({required super.name, required this.file, required this.aspect});

  @override
  Map<String, dynamic> toJson() => {'type': 'frame', 'name': name, 'file': file, 'aspect': aspect};

  factory FrameTemplate.fromJson(Map<String, dynamic> j) =>
      FrameTemplate(name: _string(j, 'name'), file: _string(j, 'file'), aspect: _d(j['aspect'], 1));
}

class CreditStyle {
  final bool enabled;
  final Corner corner;
  final double sizeFraction; // of output short edge
  final bool white;

  const CreditStyle({
    this.enabled = false,
    this.corner = Corner.bottomRight,
    this.sizeFraction = 0.025,
    this.white = true,
  });

  CreditStyle copyWith({bool? enabled, Corner? corner, double? sizeFraction, bool? white}) =>
      CreditStyle(
        enabled: enabled ?? this.enabled,
        corner: corner ?? this.corner,
        sizeFraction: sizeFraction ?? this.sizeFraction,
        white: white ?? this.white,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'corner': corner.name,
    'sizeFraction': sizeFraction,
    'white': white,
  };

  factory CreditStyle.fromJson(Map<String, dynamic> j) => CreditStyle(
    enabled: j['enabled'] == true,
    corner: enumByName(Corner.values, j['corner'], Corner.bottomRight),
    sizeFraction: _d(j['sizeFraction'], 0.025).clamp(0.005, 0.2),
    white: j['white'] != false,
  );
}
