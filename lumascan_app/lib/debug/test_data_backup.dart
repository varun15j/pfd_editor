import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../app/app_info.dart';
import 'data_mirror.dart';
import 'profile_location.dart';

/// Debug builds on Android: the app's data (Library, scans, saved files,
/// settings, the export database) is copied to `Documents/<app name> test`
/// on the phone, which outlives the app. A test build that is uninstalled
/// (by `flutter run`, `flutter test` or by hand) and installed again loads
/// it back on its first start. Release builds and iOS never do any of this.
///
/// Needs "All files access" (Android 11+) or the storage permission
/// (Android 8 to 10), which only debug builds ask for. Over adb:
/// `adb shell appops set --uid com.mobi.scanner MANAGE_EXTERNAL_STORAGE allow`
/// or `adb shell pm grant com.mobi.scanner android.permission.WRITE_EXTERNAL_STORAGE`.
class TestDataBackup {
  TestDataBackup._();

  static final instance = TestDataBackup._();

  static const folderName = '$appName test';
  static const sharedDir = '/storage/emulated/0/Documents/$folderName';

  /// How often the data is copied while the app is open; it is copied too
  /// whenever the app goes to the background.
  static const every = Duration(minutes: 3);

  static bool get supported => kDebugMode && !kIsWeb && Platform.isAndroid;

  /// The state the Settings tile shows.
  final state = ValueNotifier<TestBackupState>(const TestBackupState());

  bool _busy = false;
  Timer? _timer;

  Future<MirrorJob> _job() async => (
    sharedDir: sharedDir,
    sources: {'documents': (await getApplicationDocumentsDirectory()).path, 'databases': await getDatabasesPath()},
  );

  Future<File> get _pendingFlag async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'load_test_backup'));

  /// Before the app starts: a fresh install loads the backup, and a load
  /// asked for in the app (see [loadOnNextStart]) replaces what is there.
  Future<void> restoreAtStart() async {
    if (!supported) return;
    try {
      final flag = await _pendingFlag;
      final replace = flag.existsSync();
      final n = await _restoreOn(await _job(), replace);
      if (replace) flag.deleteSync();
      if (n > 0) debugPrint('Test data backup: loaded $n files from $sharedDir');
    } on Object catch (e) {
      debugPrint('Test data backup: not loaded ($e)');
    }
  }

  /// Copies the data now and then while the app runs.
  void start() {
    if (!supported) return;
    WidgetsBinding.instance.addObserver(_Lifecycle(backUp));
    _timer ??= Timer.periodic(every, (_) => backUp());
    unawaited(refresh().then((_) => backUp()));
  }

  /// Reads where things stand, for the tile.
  Future<void> refresh() async {
    if (!supported) return;
    final access = await ProfileLocation(sharedDir: sharedDir).canUseShared();
    final job = await _job();
    final linked = File(p.join(job.sources.values.first, mirrorLink)).existsSync();
    state.value = TestBackupState(
      access: access,
      backup: access ? readMirror(sharedDir) : null,
      waiting: access && !linked && readMirror(sharedDir) != null,
      busy: _busy,
    );
  }

  /// Asks for access to the shared folder, then backs up.
  Future<void> requestAccess() async {
    await ProfileLocation(sharedDir: sharedDir).requestShared();
    await refresh();
    await backUp();
  }

  /// Copies what changed since the last time. Does nothing without access,
  /// and never overwrites a backup this install has not loaded.
  Future<void> backUp() async {
    if (!supported || _busy) return;
    _busy = true;
    try {
      if (await ProfileLocation(sharedDir: sharedDir).canUseShared()) {
        final version = await PackageInfo.fromPlatform().then(
          (i) => '${i.version}+${i.buildNumber}',
          onError: (_) => '',
        );
        await _backUpOn(await _job(), version);
      }
    } on Object catch (e) {
      debugPrint('Test data backup: not copied ($e)');
    } finally {
      _busy = false;
      await refresh();
    }
  }

  /// Marks the backup to replace this install's data on the next start.
  Future<void> loadOnNextStart() async => (await _pendingFlag).create(recursive: true);

  /// Keeps this install's data and lets it overwrite the waiting backup.
  Future<void> replaceBackup() async {
    final job = await _job();
    File(p.join(job.sources.values.first, mirrorLink)).createSync(recursive: true);
    await backUp();
  }
}

/// What the tile shows.
@immutable
class TestBackupState {
  const TestBackupState({this.access = false, this.backup, this.waiting = false, this.busy = false});

  /// The shared folder can be written.
  final bool access;

  /// What the backup holds, when there is one.
  final MirrorInfo? backup;

  /// A backup is there that this install did not load: it is not
  /// overwritten until the tester loads it or chooses to replace it.
  final bool waiting;

  final bool busy;
}

class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this.onLeave);

  final Future<void> Function() onLeave;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) unawaited(onLeave());
  }
}

// Top-level, so the isolate gets only the plain job, never this object.
Future<int> _restoreOn(MirrorJob job, bool replace) => Isolate.run(() => restoreMirror(job, replace: replace));

Future<MirrorInfo?> _backUpOn(MirrorJob job, String version) => Isolate.run(() => backUpMirror(job, version: version));
