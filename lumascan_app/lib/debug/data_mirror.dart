import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// A copy of the app's private data in a folder that outlives the app
/// (debug builds: `Documents/<app name> test`), kept up to date file by file,
/// so a test build that is uninstalled and installed again can load it back.
///
/// [sources] names each private folder that is copied: the copy of
/// `documents` is in `<sharedDir>/documents`, and so on. Pure Dart, and every
/// argument is a plain string, so it can run on an isolate.
typedef MirrorJob = ({String sharedDir, Map<String, String> sources});

/// What the last backup holds, from its `backup.json`.
typedef MirrorInfo = ({DateTime time, int files, int bytes, String version});

/// Top-level folders that are rebuilt on their own (page previews,
/// thumbnails, smaller copies for sending): not copied.
const mirrorSkipped = {'renders', 'thumbnails', 'share', 'flutter_assets'};

const mirrorManifest = 'backup.json';

/// Kept in the app's first private folder once it has loaded the backup or
/// made it. Without it, a fresh install that already has a backup waiting
/// would overwrite that backup with its own empty start.
const mirrorLink = '.test_backup_link';

File _link(MirrorJob job) => File(p.join(job.sources.values.first, mirrorLink));

/// Brings the copy in line with the private folders: new and changed files
/// are copied, files gone from the app are removed from the copy. Returns
/// what it holds, or null when it did nothing: the app has no data yet, or
/// a backup is there that this install has not loaded (so it is kept for
/// [restoreMirror]).
MirrorInfo? backUpMirror(MirrorJob job, {String version = ''}) {
  if (readMirror(job.sharedDir) != null && !_link(job).existsSync()) return null;
  final sources = {for (final e in job.sources.entries) e.key: _files(e.value)};
  if (sources.values.every((f) => f.isEmpty)) return null;
  var files = 0, bytes = 0;
  for (final MapEntry(key: name, value: own) in sources.entries) {
    final from = job.sources[name]!, to = p.join(job.sharedDir, name);
    for (final rel in own) {
      final src = File(p.join(from, rel)), dst = File(p.join(to, rel));
      final size = src.lengthSync();
      files++;
      bytes += size;
      if (dst.existsSync() && dst.lengthSync() == size && !dst.lastModifiedSync().isBefore(src.lastModifiedSync())) {
        continue;
      }
      _copy(src, dst);
    }
    // Files the app no longer has.
    final kept = own.toSet();
    for (final rel in _files(to)) {
      if (!kept.contains(rel)) File(p.join(to, rel)).deleteSync();
    }
  }
  final info = (time: DateTime.now(), files: files, bytes: bytes, version: version);
  final tmp = File(p.join(job.sharedDir, '$mirrorManifest.tmp'))
    ..writeAsStringSync(
      jsonEncode({'time': info.time.toIso8601String(), 'files': files, 'bytes': bytes, 'version': version}),
      flush: true,
    );
  tmp.renameSync(p.join(job.sharedDir, mirrorManifest));
  _link(job).createSync(recursive: true);
  return info;
}

/// What the copy in [sharedDir] holds, or null when there is none or it
/// cannot be read (no access to the folder yet).
MirrorInfo? readMirror(String sharedDir) {
  try {
    final json = jsonDecode(File(p.join(sharedDir, mirrorManifest)).readAsStringSync()) as Map<String, dynamic>;
    return (
      time: DateTime.parse(json['time'] as String),
      files: json['files'] as int,
      bytes: json['bytes'] as int,
      version: json['version'] as String? ?? '',
    );
  } on Object {
    return null;
  }
}

/// True when the app's private folders hold no data: a fresh install.
bool mirrorTargetEmpty(MirrorJob job) => job.sources.values.every((dir) => _files(dir).isEmpty);

/// Copies the backup into the private folders when they hold no data (a
/// fresh install), so nothing the app has is overwritten. With [replace]
/// (asked for in the app, run before the app starts) the app's own files
/// are removed first. Returns how many files were copied, or 0 when it did
/// nothing.
int restoreMirror(MirrorJob job, {bool replace = false}) {
  if (readMirror(job.sharedDir) == null) return 0;
  if (!replace && !mirrorTargetEmpty(job)) return 0;
  var n = 0;
  for (final MapEntry(key: name, value: to) in job.sources.entries) {
    final from = p.join(job.sharedDir, name);
    if (replace) {
      for (final rel in _files(to)) {
        File(p.join(to, rel)).deleteSync();
      }
    }
    for (final rel in _files(from)) {
      _copy(File(p.join(from, rel)), File(p.join(to, rel)));
      n++;
    }
  }
  _link(job).createSync(recursive: true);
  return n;
}

void _copy(File src, File dst) {
  dst.parent.createSync(recursive: true);
  src.copySync(dst.path);
  try {
    dst.setLastModifiedSync(src.lastModifiedSync());
  } on FileSystemException {
    // Shared storage on some phones (BlueStacks) does not let an app set a
    // file's time. The copy is then as new as the moment it was made, never
    // older than its source, so it still counts as current.
  }
}

/// Every file under [dir], as paths relative to it, without the skipped
/// top-level folders and SQLite's short-lived journal files.
List<String> _files(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) return const [];
  return [
    for (final e in root.listSync(recursive: true, followLinks: false))
      if (e is File)
        if (p.relative(e.path, from: dir) case final rel
            when !mirrorSkipped.contains(p.split(rel).first) &&
                !rel.endsWith('-journal') &&
                rel != mirrorLink &&
                // Flutter's own marker of when the app was installed.
                !p.basename(rel).startsWith('res_timestamp-'))
          rel,
  ];
}
