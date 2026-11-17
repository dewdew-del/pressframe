import 'dart:io';

/// What a photo problem means for the user, and what to do about it.
String plainPhotoProblem(String fileName, String reason) {
  final r = reason.toLowerCase();
  if (r.contains('cannot read the file')) {
    return "$fileName can't be opened. Check that it was not moved or deleted, then add it again.";
  }
  if (r.contains('damaged') || r.contains('not a jpeg') || r.contains('decoded') || r.contains('no usable preview')) {
    return '$fileName is damaged or not supported. Export it from your camera as a JPEG and add it again.';
  }
  return '$fileName could not be exported. Add it again from the original file and retry.';
}

/// A write failure in the output folder, in plain words.
String plainOutputProblem(FileSystemException e) {
  final code = e.osError?.errorCode;
  final text = '${e.osError?.message ?? ''} ${e.message}'.toLowerCase();
  // 112 = Windows disk full, 28 = ENOSPC.
  if (code == 112 || code == 28 || text.contains('not enough space') || text.contains('no space')) {
    return 'The disk is full. Free some space and export again. Photos already saved are kept.';
  }
  // 80 / 183 = Windows file exists, 17 = EEXIST.
  if (code == 80 || code == 183 || code == 17 || text.contains('already exists')) {
    return 'A file with that name already exists. Choose another folder or event name.';
  }
  return "PressFrame can't save to this folder. Choose another folder with Change…";
}
