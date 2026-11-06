import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lumascan/debug/data_mirror.dart';
import 'package:path/path.dart' as p;

import 'support/temp_dir.dart';

void main() {
  late Directory tmp;
  late MirrorJob job;
  late String docs, dbs, shared;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumascan_mirror');
    docs = p.join(tmp.path, 'app_flutter');
    dbs = p.join(tmp.path, 'databases');
    shared = p.join(tmp.path, 'Documents', 'LumaScan test');
    job = (sharedDir: shared, sources: {'documents': docs, 'databases': dbs});
  });
  tearDown(() => deleteTemp(tmp));

  void write(String dir, String rel, String text) => File(p.join(dir, rel))
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
  String? read(String dir, String rel) {
    final f = File(p.join(dir, rel));
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  test('the data is copied, page previews are not, and an uninstall then a fresh install gets it back', () {
    write(docs, 'library/index.json', '{"docs":1}');
    write(docs, 'exports/Saved/Scan.pdf', 'pdf');
    write(docs, 'pages/a.jpg', 'photo');
    write(docs, 'renders/a_preview.jpg', 'preview');
    write(dbs, 'export_state.db', 'db');
    final info = backUpMirror(job, version: '1.44.0+76')!;
    expect(info.files, 4);
    expect(read(shared, 'documents/exports/Saved/Scan.pdf'), 'pdf');
    expect(read(shared, 'databases/export_state.db'), 'db');
    expect(read(shared, 'documents/renders/a_preview.jpg'), isNull);
    expect(readMirror(shared)!.version, '1.44.0+76');

    // Uninstalled: the private folders are gone.
    Directory(docs).deleteSync(recursive: true);
    Directory(dbs).deleteSync(recursive: true);
    expect(restoreMirror(job), 4);
    expect(read(docs, 'library/index.json'), '{"docs":1}');
    expect(read(docs, 'exports/Saved/Scan.pdf'), 'pdf');
    expect(read(dbs, 'export_state.db'), 'db');
  });

  test('changes and deletions reach the backup; unchanged files are not copied again', () {
    write(docs, 'a.txt', 'one');
    write(docs, 'b.txt', 'two');
    backUpMirror(job);
    final kept = File(p.join(shared, 'documents', 'a.txt'));
    final copiedAt = kept.lastModifiedSync();
    File(p.join(docs, 'b.txt')).deleteSync();
    write(docs, 'c.txt', 'three');
    backUpMirror(job);
    expect(read(shared, 'documents/b.txt'), isNull);
    expect(read(shared, 'documents/c.txt'), 'three');
    expect(kept.lastModifiedSync(), copiedAt);
  });

  test('a fresh install never wipes a backup it has not loaded', () {
    write(docs, 'library/index.json', 'real');
    backUpMirror(job);
    // Reinstalled without access at first: the app starts empty, then
    // writes its first settings.
    Directory(docs).deleteSync(recursive: true);
    expect(backUpMirror(job), isNull, reason: 'nothing to back up');
    write(docs, 'settings.json', 'new');
    expect(backUpMirror(job), isNull, reason: 'the backup waits to be loaded');
    expect(read(shared, 'documents/library/index.json'), 'real');
    // Not empty, so a plain restore leaves the app alone...
    expect(restoreMirror(job), 0);
    expect(read(docs, 'settings.json'), 'new');
    // ...and a load asked for in the app replaces it.
    expect(restoreMirror(job, replace: true), 1);
    expect(read(docs, 'library/index.json'), 'real');
    expect(read(docs, 'settings.json'), isNull);
    // Loaded, so backups go on.
    write(docs, 'more.json', 'x');
    expect(backUpMirror(job), isNotNull);
    expect(read(shared, 'documents/more.json'), 'x');
  });

  test('with no backup there is nothing to load, and the app data is untouched', () {
    write(docs, 'a.txt', 'one');
    expect(readMirror(shared), isNull);
    expect(restoreMirror(job, replace: true), 0);
    expect(read(docs, 'a.txt'), 'one');
  });
}
