import 'dart:io';

/// An event name that is safe as a file name on Windows and Android.
String sanitizeEventName(String name) {
  var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), '');
  s = s.replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
  if (s.length > 80) s = s.substring(0, 80).trimRight(); // leave room in the 260-char path
  return s.isEmpty ? 'Event' : s;
}

/// 'Name_001.jpg'. [index] is 1-based; the number is as wide as [total] needs, at least 3.
String exportFileName(String eventName, int index, int total) {
  final width = total.toString().length < 3 ? 3 : total.toString().length;
  return '${eventName}_${index.toString().padLeft(width, '0')}.jpg';
}

/// A path in [dir] that does not exist yet: 'a.jpg', then 'a-2.jpg', 'a-3.jpg', ...
String uniquePath(String dir, String fileName, bool Function(String path) exists) {
  final dot = fileName.lastIndexOf('.');
  final stem = dot < 0 ? fileName : fileName.substring(0, dot);
  final ext = dot < 0 ? '' : fileName.substring(dot);
  var path = '$dir${Platform.pathSeparator}$fileName';
  for (var n = 2; exists(path); n++) {
    path = '$dir${Platform.pathSeparator}$stem-$n$ext';
  }
  return path;
}
