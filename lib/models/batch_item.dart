import 'dart:ui' show Rect;

import 'edit_params.dart';
import 'template.dart';

enum Flag { none, pick, reject }

/// One photo in the batch plus everything the user chose for it. Immutable.
class BatchItem {
  final String path;
  final bool isRaw;
  final int width, height; // decoded, upright, before quarterTurns
  final Flag flag;
  final EditParams edit;
  final int quarterTurns;
  final double straighten; // -15..15 degrees
  final Rect? crop; // normalized, on the rotated photo; null = auto
  final String? templateOverride;
  final OutputShape? shapeOverride;
  final String? creditOverride;

  const BatchItem({
    required this.path,
    required this.isRaw,
    required this.width,
    required this.height,
    this.flag = Flag.none,
    this.edit = EditParams.neutral,
    this.quarterTurns = 0,
    this.straighten = 0,
    this.crop,
    this.templateOverride,
    this.shapeOverride,
    this.creditOverride,
  });

  /// Nullable fields take a function so they can be set back to null:
  /// `copyWith(crop: () => null)`.
  BatchItem copyWith({
    Flag? flag,
    EditParams? edit,
    int? quarterTurns,
    double? straighten,
    Rect? Function()? crop,
    String? Function()? templateOverride,
    OutputShape? Function()? shapeOverride,
    String? Function()? creditOverride,
  }) => BatchItem(
    path: path,
    isRaw: isRaw,
    width: width,
    height: height,
    flag: flag ?? this.flag,
    edit: edit ?? this.edit,
    quarterTurns: quarterTurns ?? this.quarterTurns,
    straighten: straighten ?? this.straighten,
    crop: crop != null ? crop() : this.crop,
    templateOverride: templateOverride != null ? templateOverride() : this.templateOverride,
    shapeOverride: shapeOverride != null ? shapeOverride() : this.shapeOverride,
    creditOverride: creditOverride != null ? creditOverride() : this.creditOverride,
  );

  Map<String, dynamic> toJson() => {
    'path': path,
    'isRaw': isRaw,
    'width': width,
    'height': height,
    'flag': flag.name,
    'edit': edit.toJson(),
    'quarterTurns': quarterTurns,
    'straighten': straighten,
    'crop': crop == null ? null : [crop!.left, crop!.top, crop!.width, crop!.height],
    'templateOverride': templateOverride,
    'shapeOverride': shapeOverride?.name,
    'creditOverride': creditOverride,
  };

  factory BatchItem.fromJson(Map<String, dynamic> j) {
    final c = j['crop'];
    return BatchItem(
      path: j['path'] as String,
      isRaw: j['isRaw'] == true,
      width: j['width'] as int,
      height: j['height'] as int,
      flag: enumByName(Flag.values, j['flag'], Flag.none),
      edit: EditParams.fromJson(j['edit'] as Map<String, dynamic>? ?? const {}),
      quarterTurns: (j['quarterTurns'] as int? ?? 0) % 4,
      straighten: ((j['straighten'] as num?)?.toDouble() ?? 0).clamp(-15, 15),
      crop: c is List && c.length == 4
          ? Rect.fromLTWH(
              (c[0] as num).toDouble(),
              (c[1] as num).toDouble(),
              (c[2] as num).toDouble(),
              (c[3] as num).toDouble(),
            )
          : null,
      templateOverride: j['templateOverride'] as String?,
      shapeOverride: OutputShape.values.asNameMap()[j['shapeOverride']],
      creditOverride: j['creditOverride'] as String?,
    );
  }
}
