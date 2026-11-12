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
