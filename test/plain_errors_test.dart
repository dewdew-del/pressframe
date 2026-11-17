import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pressframe/export/plain_errors.dart';

void main() {
  test('a damaged photo says what to do', () {
    expect(
      plainPhotoProblem('IMG_0412.CR3', 'The file is damaged or incomplete'),
      'IMG_0412.CR3 is damaged or not supported. Export it from your camera as a JPEG and add it again.',
    );
    expect(plainPhotoProblem('a.jpg', 'Cannot read the file (x)'), contains("can't be opened"));
  });

  test('full disk and existing file are explained', () {
    String of(int code) => plainOutputProblem(FileSystemException('x', 'p', OSError('m', code)));
    expect(of(112), startsWith('The disk is full'));
    expect(of(28), startsWith('The disk is full'));
    expect(of(183), startsWith('A file with that name already exists'));
    expect(of(5), contains('Choose another folder'));
  });
}
