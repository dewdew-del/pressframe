import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

import '../engine/decode.dart';

/// Everything PressFrame keeps on disk: the thumbnail cache now; presets, templates and
/// kits are added by later tasks.
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

  /// FNV-1a, enough to turn a path into a file name.
  static String _hash(String s) {
    var h = 0xcbf29ce484222325;
    for (final byte in utf8.encode(s)) {
      h = (h ^ byte) * 0x100000001b3;
    }
    return h.toRadixString(16).replaceFirst('-', 'n');
  }
}
