import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../engine/decode.dart';
import '../models/kit.dart';
import '../models/preset.dart';
import '../models/template.dart';

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
    await Directory('${support.path}/assets').create(recursive: true);
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

  // ---- Text size ----

  File get _scaleFile => File('${support.path}/text_scale');
  double loadTextScale() {
    try {
      return (double.tryParse(_scaleFile.readAsStringSync()) ?? 1).clamp(0.8, 1.3);
    } on FileSystemException {
      return 1;
    }
  }

  Future<void> saveTextScale(double v) => _scaleFile.writeAsString('$v');

  File get _lightFile => File('${support.path}/light_theme');
  bool loadLightTheme() => _lightFile.existsSync();
  Future<void> saveLightTheme(bool on) async {
    if (on) {
      await _lightFile.writeAsString('1');
    } else if (_lightFile.existsSync()) {
      await _lightFile.delete();
    }
  }

  // ---- First-run tips ----

  File get _tipsFlag => File('${support.path}/tips_seen');
  bool get tipsSeen => _tipsFlag.existsSync();
  Future<void> markTipsSeen() => _tipsFlag.writeAsString('1');

  // ---- Last session ----

  Future<Map<String, dynamic>?> loadSession() async {
    final l = await _readList('session.json');
    return l.isNotEmpty && l.first is Map<String, dynamic> ? l.first as Map<String, dynamic> : null;
  }

  /// True after "Save" on the logo: the empty screen must not wipe the saved session.
  bool holdSession = false;

  /// null clears it (nothing left to continue).
  Future<void> saveSession(Map<String, dynamic>? data) async {
    if (data == null && holdSession) return;
    if (data != null) holdSession = false;
    await _writeList('session.json', [if (data != null) data]);
  }

  Future<List<String>> loadCreditNames() async => [
    for (final n in await _readList('credit_names.json'))
      if (n is String) n,
  ];

  Future<void> saveCreditNames(List<String> names) => _writeList('credit_names.json', names);

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

  // ---- Templates and their images ----

  Future<List<Template>> loadTemplates() async {
    final out = <Template>[];
    for (final e in await _readList('templates.json')) {
      try {
        out.add(Template.fromJson(e as Map<String, dynamic>));
      } on Object {
        // one bad entry does not hide the others
      }
    }
    return out;
  }

  /// Adds the template, or replaces the saved one with the same name.
  Future<void> saveTemplate(Template t) async {
    final all = await loadTemplates();
    final i = all.indexWhere((e) => e.name == t.name);
    i < 0 ? all.add(t) : all[i] = t;
    await _writeList('templates.json', [for (final e in all) e.toJson()]);
  }

  Future<void> deleteTemplate(String name) async {
    final all = await loadTemplates();
    await _writeList('templates.json', [
      for (final e in all)
        if (e.name != name) e.toJson(),
    ]);
  }

  /// True for a plain file name that can only point inside the assets folder.
  static bool isSafeAssetName(String name) =>
      RegExp(r'^[A-Za-z0-9_-]{1,80}\.png$').hasMatch(name);

  File assetFile(String name) {
    if (!isSafeAssetName(name)) throw DecodeFailure(name, 'Not a valid asset name');
    return File('${support.path}/assets/$name');
  }

  /// Copies a PNG into the assets folder under a name made from its content, so the same
  /// picture is stored once. Throws [FormatException] if the file is not a whole PNG.
  Future<String> importAsset(String pngPath) async {
    final Uint8List bytes;
    try {
      bytes = await File(pngPath).readAsBytes();
    } on FileSystemException catch (e) {
      throw FormatException('Cannot read the file (${e.message})');
    }
    return storeAssetBytes(bytes);
  }

  /// Validates [bytes] as a PNG and stores them. Used by [importAsset] and kit import.
  Future<String> storeAssetBytes(Uint8List bytes) async {
    if (!isWholePng(bytes)) throw const FormatException('Not a PNG image');
    final name = '${_hashBytes(bytes)}.png';
    final file = assetFile(name);
    if (!file.existsSync()) {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    }
    return name;
  }

  /// PNG signature, a sane IHDR and an IEND chunk at the end.
  static bool isWholePng(Uint8List b) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (b.length < 45) return false;
    for (var i = 0; i < 8; i++) {
      if (b[i] != signature[i]) return false;
    }
    final data = ByteData.sublistView(b);
    if (String.fromCharCodes(b, 12, 16) != 'IHDR') return false;
    final w = data.getUint32(16), h = data.getUint32(20);
    if (w == 0 || h == 0 || w > 20000 || h > 20000) return false;
    return String.fromCharCodes(b, b.length - 8, b.length - 4) == 'IEND';
  }

  Future<ui.Image> asset(String file, {int maxLongEdge = 4096}) =>
      decodeImage(assetFile(file).path, maxLongEdge: maxLongEdge);

  // ---- Publication kit (.pfkit) ----

  /// The bytes of a `.pfkit` file: a zip with kit.json plus `assets/NAME.png` for every logo and
  /// frame the templates use. The credit text is never part of a kit; its style is.
  Future<Uint8List> encodeKit(String name, {CreditStyle credit = const CreditStyle()}) async {
    final kit = Kit(
      name: name,
      presets: await loadPresets(),
      templates: await loadTemplates(),
      credit: credit,
    );
    final archive = Archive()
      ..add(
        ArchiveFile.bytes(
          'kit.json',
          utf8.encode(jsonEncode({'pressframe': 'kit', 'version': 1, ...kit.toJson()})),
        ),
      );
    for (final file in {for (final t in kit.templates) ...assetFiles(t)}) {
      if (!isSafeAssetName(file)) continue;
      final f = assetFile(file);
      if (f.existsSync()) archive.add(ArchiveFile.bytes('assets/$file', await f.readAsBytes()));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  Future<void> exportKit(String name, String filePath, {CreditStyle credit = const CreditStyle()}) async =>
      File(filePath).writeAsBytes(await encodeKit(name, credit: credit), flush: true);

  /// Adds a kit's presets, templates and images to this install and returns what was added
  /// (with the names they ended up with). An incoming name that already exists becomes
  /// "Name (2)"; nothing of the user's is replaced.
  ///
  /// The whole file is checked in memory first. Anything unexpected throws
  /// [FormatException] before a single byte is written.
  Future<Kit> importKit(String filePath, {int maxUnpackedBytes = 200 * 1024 * 1024}) async {
    final Uint8List bytes;
    try {
      final file = File(filePath);
      if (await file.length() > maxUnpackedBytes) throw const FormatException('The kit is too large');
      bytes = await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw FormatException('Cannot read the file (${e.message})');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const FormatException('Not a PressFrame kit');
    }

    // Only two kinds of entry are allowed: kit.json and assets/<plain-name>.png.
    // The pattern has no room for "..", a leading slash, a backslash or a drive letter.
    final assetEntry = RegExp(r'^assets/([A-Za-z0-9_-]{1,80}\.png)$');
    Uint8List? kitJson;
    final pictures = <String, Uint8List>{};
    var declared = 0, actual = 0;
    for (final entry in archive.files) {
      if (!entry.isFile && (entry.name == 'assets/' || entry.name == 'assets')) continue;
      if (!entry.isFile || entry.isSymbolicLink) {
        throw FormatException('Unexpected entry in the kit: ${entry.name}');
      }
      // shortcut: trusts the zip's declared sizes to stop a zip bomb before unpacking it,
      // upgrade to a streaming size check if kits ever come from strangers.
      declared += entry.size;
      if (declared > maxUnpackedBytes) throw const FormatException('The kit is too large');
      final match = assetEntry.firstMatch(entry.name);
      if (entry.name != 'kit.json' && match == null) {
        throw FormatException('Unexpected file in the kit: ${entry.name}');
      }
      final Uint8List content;
      try {
        content = entry.content;
      } on Object {
        throw const FormatException('The kit is damaged');
      }
      actual += content.length;
      if (actual > maxUnpackedBytes) throw const FormatException('The kit is too large');
      if (match == null) {
        kitJson = content;
      } else {
        if (!isWholePng(content)) throw FormatException('${entry.name} is not a PNG image');
        pictures[match.group(1)!] = content;
      }
    }
    if (kitJson == null) throw const FormatException('Not a PressFrame kit (kit.json is missing)');

    final Kit kit;
    try {
      final data = jsonDecode(utf8.decode(kitJson));
      if (data is! Map<String, dynamic> || data['pressframe'] != 'kit') {
        throw const FormatException('Not a PressFrame kit');
      }
      kit = Kit.fromJson(data);
    } on FormatException {
      rethrow;
    } on Object {
      // wrong types inside otherwise valid JSON
      throw const FormatException('The kit is damaged');
    }
    for (final t in kit.templates) {
      if (!assetFiles(t).every(isSafeAssetName)) {
        throw FormatException('Template "${t.name}" points outside the kit');
      }
    }

    // Everything is valid: now write. Pictures are stored under a name made from their
    // content, so templates are pointed at wherever each picture really landed.
    final stored = <String, String>{};
    for (final e in pictures.entries) {
      stored[e.key] = await storeAssetBytes(e.value);
    }
    String at(String file) => stored[file] ?? file;

    final presets = await loadPresets();
    final addedPresets = <Preset>[];
    for (final p in kit.presets) {
      final added = Preset(
        name: uniqueName(p.name, [...presets, ...addedPresets].map((e) => e.name)),
        params: p.params,
      );
      addedPresets.add(added);
    }
    final templates = await loadTemplates();
    final addedTemplates = <Template>[];
    for (final t in kit.templates) {
      final name = uniqueName(t.name, [...templates, ...addedTemplates].map((e) => e.name));
      addedTemplates.add(switch (t) {
        BuiltTemplate() => BuiltTemplate(
          name: name,
          band: t.band,
          logos: [
            for (final l in t.logos)
              LogoLayer(
                file: at(l.file),
                cx: l.cx,
                cy: l.cy,
                widthFraction: l.widthFraction,
                opacity: l.opacity,
              ),
          ],
        ),
        FrameTemplate() => FrameTemplate(name: name, file: at(t.file), aspect: t.aspect),
      });
    }
    if (addedPresets.isNotEmpty) {
      await _writeList('presets.json', [for (final e in [...presets, ...addedPresets]) e.toJson()]);
    }
    if (addedTemplates.isNotEmpty) {
      await _writeList('templates.json', [for (final e in [...templates, ...addedTemplates]) e.toJson()]);
    }
    return Kit(name: kit.name, presets: addedPresets, templates: addedTemplates, credit: kit.credit);
  }

  /// FNV-1a, enough to turn a path or a file's content into a file name.
  static String _hash(String s) => _hashBytes(utf8.encode(s));

  static String _hashBytes(List<int> bytes) {
    var h = 0xcbf29ce484222325;
    for (final byte in bytes) {
      h = (h ^ byte) * 0x100000001b3;
    }
    return h.toRadixString(16).replaceFirst('-', 'n');
  }
}
