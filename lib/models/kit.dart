import 'preset.dart';
import 'template.dart';

/// What a publication shares: presets, templates and the credit style (not the credit text).
class Kit {
  final String name;
  final List<Preset> presets;
  final List<Template> templates;
  final CreditStyle credit;

  const Kit({
    required this.name,
    this.presets = const [],
    this.templates = const [],
    this.credit = const CreditStyle(),
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'presets': [for (final p in presets) p.toJson()],
    'templates': [for (final t in templates) t.toJson()],
    'credit': credit.toJson(),
  };

  factory Kit.fromJson(Map<String, dynamic> j) => Kit(
    name: j['name'] is String ? j['name'] as String : 'Kit',
    presets: [
      for (final p in (j['presets'] as List? ?? const []))
        Preset.fromJson(p as Map<String, dynamic>),
    ],
    templates: [
      for (final t in (j['templates'] as List? ?? const []))
        Template.fromJson(t as Map<String, dynamic>),
    ],
    credit: j['credit'] is Map<String, dynamic>
        ? CreditStyle.fromJson(j['credit'] as Map<String, dynamic>)
        : const CreditStyle(),
  );
}
