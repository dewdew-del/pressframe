import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import '../engine/decode.dart';
import '../engine/geometry.dart';
import '../engine/renderer.dart';
import '../models/batch_item.dart';
import '../models/edit_params.dart';
import '../models/template.dart';
import 'filename.dart';
import 'plain_errors.dart';

class ExportSettings {
  final String eventName;
  final int quality; // 60..100
  final int? longEdge; // pixels; null = full size
  final String outDir;

  const ExportSettings({
    required this.eventName,
    required this.outDir,
    this.quality = 90,
    this.longEdge = 2048,
  });
}

class ExportProgress {
  final int done, total;
  final List<({String path, String reason})> failures;
  final bool finished, cancelled;

  const ExportProgress({
    required this.done,
    required this.total,
    this.failures = const [],
    this.finished = false,
    this.cancelled = false,
  });
}

/// One photo plus everything the batch decided for it.
typedef RenderSpec = ({
  BatchItem item,
  OutputShape shape,
  Template? template,
  String? creditText,
  CreditStyle credit,
});

/// The crop a spec is rendered with (normalized, on the rotated photo).
ui.Rect specCrop(RenderSpec spec) => effectiveCrop(
  orientedSize(spec.item.width, spec.item.height, spec.item.quarterTurns),
  spec.shape.aspect,
  spec.item.crop,
  spec.item.straighten,
);

/// The one place a spec becomes a render job: preview, review grid and export all call it.
/// [edit] replaces the photo's sliders (the "before" view passes neutral).
RenderJob jobFromSpec(
  RenderSpec spec,
  ui.Image source,
  ui.Size outputSize,
  Map<String, ui.Image> assets, {
  EditParams? edit,
}) => RenderJob(
  source: source,
  edit: edit ?? spec.item.edit,
  quarterTurns: spec.item.quarterTurns,
  straighten: spec.item.straighten,
  crop: specCrop(spec),
  outputSize: outputSize,
  template: spec.template,
  assets: assets,
  creditText: spec.creditText,
  credit: spec.credit,
);

/// The output problem that stops a whole export (folder gone, read-only, disk full).
class _OutputFailure implements Exception {
  final String reason;
  const _OutputFailure(this.reason);
}

class Exporter {
  final Renderer renderer;
  final int maxDecodeEdge; // 8192 on Windows, 4096 on Android

  /// The logo / frame images a template needs. They stay owned by the caller.
  final Future<Map<String, ui.Image>> Function(Template template)? loadAssets;

  /// Android: hands each finished file to the gallery; the file is then deleted.
  final Future<void> Function(String path)? publish;

  bool _cancelled = false;

  Exporter(this.renderer, {required this.maxDecodeEdge, this.loadAssets, this.publish});

  /// Stops after the photo being written. Nothing half-written is left behind.
  void cancel() => _cancelled = true;

  /// Exports one photo at a time so only one full-size image is ever in memory.
  Stream<ExportProgress> run(List<RenderSpec> items, ExportSettings s) async* {
    _cancelled = false;
    final failures = <({String path, String reason})>[];
    final name = sanitizeEventName(s.eventName);
    final total = items.length;
    ExportProgress progress(int done, {bool finished = false}) => ExportProgress(
      done: done,
      total: total,
      failures: List.unmodifiable(failures),
      finished: finished,
      cancelled: finished && _cancelled,
    );

    try {
      Directory(s.outDir).createSync(recursive: true);
    } on FileSystemException catch (e) {
      failures.add((path: s.outDir, reason: plainOutputProblem(e)));
      yield progress(0, finished: true);
      return;
    }

    yield progress(0);
    var done = 0;
    for (final spec in items) {
      if (_cancelled) break;
      try {
        await _exportOne(spec, s, name, done + 1, total);
      } on DecodeFailure catch (e) {
        failures.add((path: spec.item.path, reason: plainPhotoProblem(_base(spec.item.path), e.reason)));
      } on _OutputFailure catch (e) {
        // Every later photo would fail the same way: stop and keep what is finished.
        failures.add((path: s.outDir, reason: e.reason));
        yield progress(done, finished: true);
        return;
      } catch (e) {
        failures.add((path: spec.item.path, reason: plainPhotoProblem(_base(spec.item.path), '$e')));
      }
      done++;
      yield progress(done);
    }
    yield progress(done, finished: true);
  }

  Future<void> _exportOne(RenderSpec spec, ExportSettings s, String name, int index, int total) async {
    final item = spec.item;
    final crop = specCrop(spec);
    // Decode only as large as the output needs; the codec downscales far better than we can.
    final needed = s.longEdge == null
        ? maxDecodeEdge
        : (s.longEdge! / math.min(crop.width, crop.height)).ceil();
    final source = await decodeImage(item.path, maxLongEdge: math.min(maxDecodeEdge, needed));

    final Uint8List rgba;
    final int w, h;
    try {
      final decoded = orientedSize(source.width, source.height, item.quarterTurns);
      final cw = crop.width * decoded.width, ch = crop.height * decoded.height;
      // Never larger than the pixels we actually have.
      final scale = s.longEdge == null ? 1.0 : math.min(1.0, s.longEdge! / math.max(cw, ch));
      w = math.max(1, (cw * scale).round());
      h = math.max(1, (ch * scale).round());
      final assets = spec.template != null && loadAssets != null
          ? await loadAssets!(spec.template!)
          : const <String, ui.Image>{};
      rgba = await renderer.renderRgba(
        jobFromSpec(spec, source, ui.Size(w.toDouble(), h.toDouble()), assets),
      );
    } finally {
      source.dispose();
    }

    final quality = s.quality.clamp(60, 100);
    final pixels = TransferableTypedData.fromList([rgba]); // moved, not copied
    final jpeg = await Isolate.run(
      () => img.encodeJpg(
        img.Image.fromBytes(width: w, height: h, bytes: pixels.materialize(), numChannels: 4),
        quality: quality,
      ),
    );
    if (_cancelled) return;

    // Write under a temporary name and rename: a crash or cancel never leaves half a JPEG.
    final path = uniquePath(
      s.outDir,
      exportFileName(name, index, total),
      (p) => File(p).existsSync() || File('$p.part').existsSync(),
    );
    final part = File('$path.part');
    try {
      await part.writeAsBytes(jpeg, flush: true);
      await part.rename(path);
    } on FileSystemException catch (e) {
      throw _OutputFailure(plainOutputProblem(e));
    } finally {
      if (part.existsSync()) part.deleteSync();
    }
    if (publish != null) {
      try {
        await publish!(path);
      } finally {
        if (File(path).existsSync()) File(path).deleteSync();
      }
    }
  }

  static String _base(String path) => path.split(RegExp(r'[\/]')).last;
}
