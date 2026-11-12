import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pressframe/session.dart';
import 'package:pressframe/storage/app_store.dart';

void main() {
  late Directory tmp, folder;
  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('pf_import');
    folder = Directory('${tmp.path}/event')..createSync();
    final im = img.Image(width: 400, height: 200);
    final jpg = img.encodeJpg(im);
    File('${folder.path}/b.jpg').writeAsBytesSync(jpg);
    File('${folder.path}/a.JPG').writeAsBytesSync(jpg);
    File('${folder.path}/c.png').writeAsBytesSync(img.encodePng(im));
    File('${folder.path}/notes.txt').writeAsStringSync('hello');
    File('${folder.path}/corrupt.jpg').writeAsBytesSync(jpg.sublist(0, jpg.length ~/ 2));
    Directory('${folder.path}/sub').createSync();
    File('${folder.path}/sub/deep.jpg').writeAsBytesSync(jpg);
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  String name(String path) => path.split(RegExp(r'[\\/]')).last;

  test('isSupportedPath', () {
    expect(isSupportedPath('x.ARW'), true);
    expect(isSupportedPath('x.jpeg'), true);
    expect(isSupportedPath('x.png'), true);
    expect(isSupportedPath('x.txt'), false);
    expect(isSupportedPath('jpg'), false);
  });

  test('a folder is expanded one level, bad files are skipped and listed', () async {
    final r = await importPaths([folder.path]);
    expect(r.items.map((i) => name(i.path)), ['a.JPG', 'b.jpg', 'c.png']);
    expect(r.items.first.width, 400);
    expect(r.items.first.height, 200);
    expect(r.skipped.map(name), ['corrupt.jpg']);
  });

  test('the same path twice gives one item', () async {
    final p = '${folder.path}/b.jpg';
    final r = await importPaths([p, p]);
    expect(r.items.length, 1);
  });

  test('Session.import adds new photos only and returns what was skipped', () async {
    final s = Session();
    expect(await s.import([folder.path]), hasLength(1));
    expect(s.items.length, 3);
    expect(await s.import([folder.path, '${folder.path}/sub/deep.jpg']), hasLength(1));
    expect(s.items.length, 4);
  });

  testWidgets('thumbnails are 256 px and cached on disk', (tester) async {
    await tester.runAsync(() async {
      final store = await AppStore.open(
        supportDir: '${tmp.path}/support',
        cacheDir: '${tmp.path}/cache',
      );
      final thumbs = Directory('${tmp.path}/cache/thumbs');
      final a = await store.thumbnail('${folder.path}/b.jpg');
      expect((a.width, a.height), (256, 128));
      expect(thumbs.listSync().length, 1);
      final b = await store.thumbnail('${folder.path}/b.jpg');
      expect((b.width, b.height), (256, 128));
      expect(thumbs.listSync().length, 1);
      await store.thumbnail('${folder.path}/c.png');
      expect(thumbs.listSync().length, 2);

      // A damaged cache file is replaced, not trusted.
      thumbs.listSync().whereType<File>().forEach((f) => f.writeAsStringSync('junk'));
      final c = await store.thumbnail('${folder.path}/b.jpg');
      expect(c.width, 256);
    });
  });
}
