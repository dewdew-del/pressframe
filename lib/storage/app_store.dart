import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../engine/decode.dart';
import '../models/preset.dart';

/// The text of a `.pfpreset` file.
String encodePreset(Preset p) =>
    jsonEncode({'pressframe': 'preset', 'version': 1, ...p.toJson()});

/// [name], or "name (2)", "name (3)", ... if it is already in [taken].
String uniqueName(String name, Iterable<String> taken) {
  final used = taken.toSet();
  var candidate = name;
  for (var n = 2; used.contains(candidate); n++) {
    candidate = '$name ($n)';
  }
  return candidate;
}

/// Everything PressFrame keeps on disk: thumbnail cache, presets; templates and kits are
/// added by later tasks.
class AppStore {
  final Directory support; // user data that must survive: presets, templates, assets
  final Directory cache; // safe to delete at any time

  AppStore._(this.support, this.cache);

  /// Tests pass their own folders; the app uses the platform's.
  static Future<AppStore> open({String? supportDir, String? cacheDir}) async {
    final support = Directory(supportDir ?? (await getApplicationSupportDirectory()).path);
    final cache = Directory(cacheDir ?? (await getApplicationCacheDirectory()).path);
    await support.create(recursive: true);
    await Directory('${cache.path}/thumbs').create(recursive: true);
    return AppStore._(support, cache);
  }

  Future<void> _thumbQueue = Future.value();

  /// A 256 px copy of the photo, cached on disk. The cache key includes the file's size and
  /// modified time, so an edited or replaced file gets a fresh thumbnail.
  ///
  /// [wanted] is asked just before the work starts: a filmstrip tile that has scrolled away
  /// answers false and costs nothing.
  Future<ui.Image?> thumbnailIf(String path, bool Function() wanted) {
    // One at a time: decoding a dozen 24 MP photos at once would stall the UI thread's GPU
    // uploads and spike memory on the phone.
    final result = _thumbQueue.then((_) async => wanted() ? await thumbnail(path) : null);
    _thumbQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<ui.Image> thumbnail(String path) async {
    final FileStat stat;
    try {
      stat = await File(path).stat();
    } on FileSystemException {
      throw DecodeFailure(path, 'Cannot read the file');
    }
    final key = _hash('$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}');
    final cached = File('${cache.path}/thumbs/$key.png');
    if (cached.existsSync()) {
      try {
        return await decodeImage(cached.path, maxLongEdge: 256);
      } on DecodeFailure {
        // damaged cache entry: fall through and rebuild it
      }
    }
    final image = await decodeImage(path, maxLongEdge: 256);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png != null) await cached.writeAsBytes(png.buffer.asUint8List(), flush: true);
    } on FileSystemException {
      // a full or read-only cache folder only costs speed
    }
    return image;
  }

  // ---- JSON files ----

  /// Reads a JSON list file. A damaged file is renamed to `<name>.bad` so the next save
  /// cannot silently destroy what the user might still rescue by hand.
  Future<List<dynamic>> _readList(String name) async {
    final file = File('${support.path}/$name');
    if (!file.existsSync()) return [];
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is List) return data;
    } on FormatException {
      // fall through
    } on FileSystemException {
      return [];
    }
    try {
      file.renameSync('${file.path}.bad');
    } on FileSystemException {
      // nothing more we can do
    }
    return [];
  }

  /// Writes through a temporary file so a crash never leaves half a file.
  Future<void> _writeList(String name, List<dynamic> data) async {
    final tmp = File('${support.path}/$name.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename('${support.path}/$name');
  }

  // ---- Presets ----

  Future<List<Preset>> loadPresets() async {
    final out = <Preset>[];
    for (final e in await _readList('presets.json')) {
      try {
        out.add(Preset.fromJson(e as Map<String, dynamic>));
      } on Object {
        // one bad entry does not hide the others
      }
    }
    return out;
  }

  /// Adds the preset, or replaces the saved one with the same name.
  Future<void> savePreset(Preset p) async {
    final all = await loadPresets();
    final i = all.indexWhere((e) => e.name == p.name);
    i < 0 ? all.add(p) : all[i] = p;
    await _writeList('presets.json', [for (final e in all) e.toJson()]);
  }

  Future<void> deletePreset(String name) async {
    final all = await loadPresets();
    await _writeList('presets.json', [
      for (final e in all)
        if (e.name != name) e.toJson(),
    ]);
  }

  Future<void> exportPreset(Preset p, String filePath) =>
      File(filePath).writeAsString(encodePreset(p), flush: true);

  /// Reads a `.pfpreset` file and saves it. A name that already exists is kept and the
  /// new one becomes "Name (2)". Throws [FormatException] for anything that is not a
  /// preset; nothing is changed in that case.
  Future<Preset> importPreset(String filePath) async {
    final Object? data;
    try {
      final file = File(filePath);
      if (await file.length() > 1024 * 1024) throw const FormatException('File is too large');
      data = jsonDecode(await file.readAsString());
    } on FileSystemException catch (e) {
      throw FormatException('Cannot read the file (${e.message})');
    }
    if (data is! Map<String, dynamic> || data['pressframe'] != 'preset') {
      throw const FormatException('Not a PressFrame preset');
    }
    final parsed = Preset.fromJson(data);
    final existing = await loadPresets();
    final preset = Preset(
      name: uniqueName(parsed.name, existing.map((e) => e.name)),
      params: parsed.params,
    );
    await savePreset(preset);
    return preset;
  }

  /// FNV-1a, enough to turn a path into a file name.
  static String _hash(String s) {
    var h = 0xcbf29ce484222325;
    for (final byte in utf8.encode(s)) {
      h = (h ^ byte) * 0x100000001b3;
    }
    return h.toRadixString(16).replaceFirst('-', 'n');
  }
}
