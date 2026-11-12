import 'edit_params.dart';

class Preset {
  final String name;
  final EditParams params;

  const Preset({required this.name, required this.params});

  Map<String, dynamic> toJson() => {'name': name, 'params': params.toJson()};

  factory Preset.fromJson(Map<String, dynamic> j) {
    final name = j['name'], params = j['params'];
    if (name is! String || name.isEmpty || params is! Map<String, dynamic>) {
      throw const FormatException('Not a preset');
    }
    return Preset(name: name, params: EditParams.fromJson(params));
  }
}

/// Starting points for common school-event light.
// shortcut: these values are first guesses, tune them by eye on real event photos.
const List<Preset> builtInPresets = [
  Preset(
    name: 'Indoor gym',
    params: EditParams(
      exposure: 0.5,
      shadows: 0.3,
      temperature: -0.15,
      tint: 0.05,
      vibrance: 0.2,
      sharpen: 0.3,
    ),
  ),
  Preset(
    name: 'Outdoor sun',
    params: EditParams(exposure: -0.2, highlights: -0.5, shadows: 0.3, contrast: 0.1, vibrance: 0.15),
  ),
  Preset(
    name: 'Stage lights',
    params: EditParams(
      exposure: 0.3,
      highlights: -0.6,
      shadows: 0.4,
      contrast: 0.15,
      saturation: -0.1,
      sharpen: 0.2,
    ),
  ),
];
