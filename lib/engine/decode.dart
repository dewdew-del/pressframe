import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

bool isRawPath(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.cr3') || p.endsWith('.cr2') || p.endsWith('.arw');
}

class DecodeFailure implements Exception {
  final String path, reason;
  const DecodeFailure(this.path, this.reason);
  @override
  String toString() => '$path: $reason';
}

class EmbeddedJpeg {
  final Uint8List bytes;
  final int width, height;
  const EmbeddedJpeg(this.bytes, this.width, this.height);
}

typedef _Jpeg = ({int width, int height, int orientation, int end});

/// Walks the JPEG that starts at [start] (its SOI marker).
/// Returns null when it is not a JPEG a normal decoder can open (lossless SOF3 = CR2 sensor
/// data, no SOF, garbage). `end` is the offset just past the EOI marker, or -1 when the
/// stream is cut off before its end.
_Jpeg? _parseJpeg(Uint8List b, int start) {
  final n = b.length;
  var p = start + 2;
  var w = 0, h = 0, orientation = 1;
  _Jpeg? cutOff() => w > 0 ? (width: w, height: h, orientation: orientation, end: -1) : null;

  while (true) {
    if (p + 2 > n) return cutOff();
    if (b[p] != 0xFF) return null;
    final m = b[p + 1];
    if (m == 0xFF) {
      p++; // fill byte
      continue;
    }
    if (m == 0xD9) {
      return w > 0 ? (width: w, height: h, orientation: orientation, end: p + 2) : null;
    }
    if (m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
      p += 2; // markers without a length
      continue;
    }
    if (m == 0x00 || m == 0xD8) return null;
    if (p + 4 > n) return cutOff();
    final len = (b[p + 2] << 8) | b[p + 3];
    if (len < 2) return null;

    final isSof = m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC;
    if (isSof) {
      // Baseline, extended and progressive only. C3 and up are lossless/arithmetic.
      if (m > 0xC2) return null;
      if (p + 9 > n) return null;
      h = (b[p + 5] << 8) | b[p + 6];
      w = (b[p + 7] << 8) | b[p + 8];
      if (w == 0 || h == 0) return null;
    } else if (m == 0xE1 &&
        p + 10 <= n &&
        b[p + 4] == 0x45 && // "Exif"
        b[p + 5] == 0x78 &&
        b[p + 6] == 0x69 &&
        b[p + 7] == 0x66) {
      orientation = _tiffOrientation(b, p + 10) ?? 1;
    }
    p += 2 + len;

    if (m == 0xDA) {
      if (w == 0) return null; // image data before any size: not a real JPEG
      // Skip the compressed data up to the next real marker.
      while (true) {
        p = b.indexOf(0xFF, p);
        if (p < 0 || p + 1 >= n) return cutOff();
        final next = b[p + 1];
        if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
          p += 2;
        } else if (next == 0xFF) {
          p++;
        } else {
          break;
        }
      }
    }
  }
}

/// EXIF orientation (1..8) from IFD0 of the TIFF block that starts at [t].
int? _tiffOrientation(Uint8List b, int t) {
  final n = b.length;
  if (t < 0 || t + 8 > n) return null;
  final little = b[t] == 0x49 && b[t + 1] == 0x49;
  if (!little && !(b[t] == 0x4D && b[t + 1] == 0x4D)) return null;
  int u16(int o) => little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
  int u32(int o) => little ? u16(o) | (u16(o + 2) << 16) : (u16(o) << 16) | u16(o + 2);
  if (u16(t + 2) != 42) return null;
  final ifd = t + u32(t + 4);
  if (ifd + 2 > n) return null;
  final count = u16(ifd);
  for (var i = 0; i < count; i++) {
    final e = ifd + 2 + 12 * i;
    if (e + 12 > n) return null;
    if (u16(e) == 0x0112) {
      final v = u16(e + 8);
      return v >= 1 && v <= 8 ? v : null;
    }
  }
  return null;
}

_Jpeg? _largestJpeg(Uint8List raw, void Function(int start) onFound) {
  _Jpeg? best;
  final last = raw.length - 3;
  var i = 0;
  while (i < last) {
    if (raw[i] == 0xFF && raw[i + 1] == 0xD8 && raw[i + 2] == 0xFF) {
      final j = _parseJpeg(raw, i);
      // A cut-off stream would decode as a half-gray photo, so it is not a candidate.
      if (j != null && j.end > 0) {
        if (best == null || j.width * j.height > best.width * best.height) {
          best = j;
          onFound(i);
        }
        i = j.end; // thumbnails nested inside this JPEG are smaller anyway
        continue;
      }
    }
    i++;
  }
  return best;
}

/// The largest ordinary JPEG stored inside a RAW file, or null. Pure Dart.
EmbeddedJpeg? extractEmbeddedJpeg(Uint8List raw) => _embedded(raw)?.jpeg;

({EmbeddedJpeg jpeg, int orientation})? _embedded(Uint8List raw) {
  var start = 0;
  final best = _largestJpeg(raw, (s) => start = s);
  if (best == null) return null;
  return (
    jpeg: EmbeddedJpeg(Uint8List.sublistView(raw, start, best.end), best.width, best.height),
    orientation: best.orientation,
  );
}

/// EXIF orientation 1..8 stored in the RAW container, null if not found.
/// CR2 and ARW are TIFF files; CR3 keeps a TIFF block in its CMT1 box.
int? rawOrientation(Uint8List raw) {
  final tiff = _tiffOrientation(raw, 0);
  if (tiff != null) return tiff;
  if (raw.length < 12 || String.fromCharCodes(raw, 4, 8) != 'ftyp') return null;
  // shortcut: plain byte search for the box name in the first 1 MB instead of walking the
  // box tree, upgrade if a CR3 ever reports the wrong orientation.
  final limit = math.min(raw.length - 8, 1 << 20);
  for (var i = 8; i < limit; i++) {
    if (raw[i] == 0x43 && raw[i + 1] == 0x4D && raw[i + 2] == 0x54 && raw[i + 3] == 0x31) {
      final o = _tiffOrientation(raw, i + 4);
      if (o != null) return o;
    }
  }
  return null;
}

typedef _Source = ({Uint8List bytes, int width, int height, bool isRaw, int rotate});

/// Reads and checks a file without decoding pixels. width/height are upright.
/// `rotate` is the orientation this code must apply itself (RAW container); for plain JPEG
/// the image codec applies EXIF rotation, so it is 1.
Future<_Source> _load(String path) async {
  final Uint8List bytes;
  try {
    bytes = await File(path).readAsBytes();
  } on FileSystemException catch (e) {
    throw DecodeFailure(path, 'Cannot read the file (${e.osError?.message ?? e.message})');
  }
  bool swaps(int o) => o >= 5;

  if (isRawPath(path)) {
    final e = _embedded(bytes);
    if (e == null) throw DecodeFailure(path, 'No usable preview inside this RAW file');
    // If the embedded JPEG carries its own orientation the codec handles it.
    final own = e.orientation != 1;
    final o = own ? e.orientation : (rawOrientation(bytes) ?? 1);
    final sw = swaps(o);
    return (
      bytes: e.jpeg.bytes,
      width: sw ? e.jpeg.height : e.jpeg.width,
      height: sw ? e.jpeg.width : e.jpeg.height,
      isRaw: true,
      rotate: own ? 1 : o,
    );
  }

  if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    final j = _parseJpeg(bytes, 0);
    if (j == null || j.end < 0) throw DecodeFailure(path, 'The file is damaged or incomplete');
    final sw = swaps(j.orientation);
    return (
      bytes: bytes,
      width: sw ? j.height : j.width,
      height: sw ? j.width : j.height,
      isRaw: false,
      rotate: 1,
    );
  }

  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length > 33 && [for (var i = 0; i < 8; i++) bytes[i]].join() == png.join()) {
    final d = ByteData.sublistView(bytes);
    final w = d.getUint32(16), h = d.getUint32(20);
    var complete = false;
    for (var i = bytes.length - 8; i > 8 && !complete; i--) {
      complete =
          bytes[i] == 0x49 && bytes[i + 1] == 0x45 && bytes[i + 2] == 0x4E && bytes[i + 3] == 0x44;
    }
    if (w == 0 || h == 0 || !complete) {
      throw DecodeFailure(path, 'The file is damaged or incomplete');
    }
    return (bytes: bytes, width: w, height: h, isRaw: false, rotate: 1);
  }

  throw DecodeFailure(path, 'Not a JPEG, PNG or supported RAW file');
}

/// Size and kind of a photo, without decoding it.
/// smallPreview: a RAW whose embedded JPEG is under 2000 px on the long edge.
// shortcut: reads the whole file to check it is complete, upgrade to a header-only read if
// importing hundreds of photos from a slow drive feels sluggish.
Future<({int width, int height, bool isRaw, bool smallPreview})> probe(String path) async {
  final s = await _load(path);
  return (
    width: s.width,
    height: s.height,
    isRaw: s.isRaw,
    smallPreview: s.isRaw && math.max(s.width, s.height) < 2000,
  );
}

/// Decodes a photo upright with its long edge at most [maxLongEdge]. Never upscales.
Future<ui.Image> decodeImage(String path, {required int maxLongEdge}) async {
  final s = await _load(path);
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(s.bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        final scale = math.min(1.0, maxLongEdge / math.max(w, h));
        return ui.TargetImageSize(
          width: math.max(1, (w * scale).round()),
          height: math.max(1, (h * scale).round()),
        );
      },
    );
    final ui.Image image;
    try {
      image = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    return s.rotate == 1 ? image : await _rotated(image, s.rotate);
  } catch (e) {
    throw DecodeFailure(path, 'The file could not be decoded');
  }
}

/// Applies EXIF orientation 3, 6 or 8 and disposes [src].
// shortcut: mirrored orientations (2, 4, 5, 7) are shown unmirrored because cameras do not
// write them, upgrade if a scanner or edited file needs them.
Future<ui.Image> _rotated(ui.Image src, int orientation) async {
  final w = src.width.toDouble(), h = src.height.toDouble();
  final quarter = orientation == 6 || orientation == 5 || orientation == 8 || orientation == 7;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  switch (orientation) {
    case 3 || 4:
      canvas
        ..translate(w, h)
        ..rotate(math.pi);
    case 6 || 5:
      canvas
        ..translate(h, 0)
        ..rotate(math.pi / 2);
    case 8 || 7:
      canvas
        ..translate(0, w)
        ..rotate(-math.pi / 2);
  }
  canvas.drawImage(src, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(quarter ? src.height : src.width, quarter ? src.width : src.height);
  } finally {
    picture.dispose();
    src.dispose();
  }
}
