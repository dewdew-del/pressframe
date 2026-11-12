/// Slider values for one photo. Neutral is 0 for every field.
class EditParams {
  final double exposure; // -2..2 stops
  final double contrast, highlights, shadows; // -1..1
  final double temperature, tint, saturation, vibrance; // -1..1
  final double sharpen; // 0..1

  const EditParams({
    this.exposure = 0,
    this.contrast = 0,
    this.highlights = 0,
    this.shadows = 0,
    this.temperature = 0,
    this.tint = 0,
    this.saturation = 0,
    this.vibrance = 0,
    this.sharpen = 0,
  });

  static const neutral = EditParams();

  EditParams copyWith({
    double? exposure,
    double? contrast,
    double? highlights,
    double? shadows,
    double? temperature,
    double? tint,
    double? saturation,
    double? vibrance,
    double? sharpen,
  }) => EditParams(
    exposure: exposure ?? this.exposure,
    contrast: contrast ?? this.contrast,
    highlights: highlights ?? this.highlights,
    shadows: shadows ?? this.shadows,
    temperature: temperature ?? this.temperature,
    tint: tint ?? this.tint,
    saturation: saturation ?? this.saturation,
    vibrance: vibrance ?? this.vibrance,
    sharpen: sharpen ?? this.sharpen,
  );

  List<double> get _values => [
    exposure, contrast, highlights, shadows,
    temperature, tint, saturation, vibrance, sharpen,
  ];

  Map<String, dynamic> toJson() => {
    'exposure': exposure,
    'contrast': contrast,
    'highlights': highlights,
    'shadows': shadows,
    'temperature': temperature,
    'tint': tint,
    'saturation': saturation,
    'vibrance': vibrance,
    'sharpen': sharpen,
  };

  /// Missing or non-numeric keys become 0; values are clamped to their range,
  /// so a hand-edited or foreign preset file can never push a slider out of bounds.
  factory EditParams.fromJson(Map<String, dynamic> json) {
    double v(String key, double min, double max) {
      final x = json[key];
      return x is num && x.isFinite ? x.toDouble().clamp(min, max) : 0;
    }

    return EditParams(
      exposure: v('exposure', -2, 2),
      contrast: v('contrast', -1, 1),
      highlights: v('highlights', -1, 1),
      shadows: v('shadows', -1, 1),
      temperature: v('temperature', -1, 1),
      tint: v('tint', -1, 1),
      saturation: v('saturation', -1, 1),
      vibrance: v('vibrance', -1, 1),
      sharpen: v('sharpen', 0, 1),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! EditParams) return false;
    final a = _values, b = other._values;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_values);
}
