import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/preferences.dart';
import '../../app/providers.dart';
import '../../data/page_store.dart';
import '../../data/cloud/google_drive_backup.dart';
import '../../domain/cloud_storage.dart';

/// How the phone is online right now, as far as sync cares.
enum NetworkKind {
  none,

  /// Wi-Fi, Ethernet or anything else that is not mobile data.
  unmetered,
  cellular,
}

/// The phone's connection, behind an interface so tests can switch it.
abstract class NetworkStatus {
  Future<NetworkKind> current();

  Stream<NetworkKind> get changes;
}

class ConnectivityNetworkStatus implements NetworkStatus {
  final _connectivity = Connectivity();

  static NetworkKind _kind(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) return NetworkKind.none;
    // Wi-Fi together with mobile data counts as Wi-Fi: Android routes there.
    final unmetered = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet || r == ConnectivityResult.vpn,
    );
    if (unmetered) return NetworkKind.unmetered;
    return results.contains(ConnectivityResult.mobile) ? NetworkKind.cellular : NetworkKind.unmetered;
  }

  @override
  Future<NetworkKind> current() async => _kind(await _connectivity.checkConnectivity());

  @override
  Stream<NetworkKind> get changes => _connectivity.onConnectivityChanged.map(_kind);
}

final networkStatusProvider = Provider<NetworkStatus>((ref) => ConnectivityNetworkStatus());

final driveBackupProvider = Provider<DriveBackup>((ref) => GoogleDriveBackup());

/// Keeps a copy of each export until it is in Drive. The app keeps no
/// exports (they wait in the Outbox only until saved or shared, and the
/// Outbox is cleared), so an upload waiting for Wi-Fi needs its own copy.
abstract class DriveSyncQueue {
  /// Copies [file] to where it waits, and returns that path.
  Future<String> keep(File file);

  /// Deletes the waiting copy at [path] once it is uploaded or dropped.
  Future<void> release(String path);
}

/// Waiting copies in `exports/Sync`, under the export's own name, so the
/// same name exported again replaces the same Drive file.
class PageStoreSyncQueue implements DriveSyncQueue {
  PageStoreSyncQueue(this._store);

  final PageStore _store;

  @override
  Future<String> keep(File file) async {
    final dir = await _store.syncQueueDir;
    final target = p.join(dir.path, p.basename(file.path));
    if (p.equals(target, file.path)) return target;
    await file.copy(target);
    return target;
  }

  @override
  Future<void> release(String path) async {
    final dir = await _store.syncQueueDir;
    if (!p.isWithin(dir.path, path)) return;
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}

final driveSyncQueueProvider = Provider<DriveSyncQueue>((ref) => PageStoreSyncQueue(ref.watch(pageStoreProvider)));

/// Why waiting files are not uploading right now.
enum SyncHold { none, off, offline, waitingForWifi }

class DriveSyncState {
  const DriveSyncState({this.account, this.pending = 0, this.uploading = false, this.hold = SyncHold.none, this.error});

  /// The Google account exports go to; null when sync is not connected.
  final CloudAccount? account;

  /// Exports waiting to upload.
  final int pending;
  final bool uploading;
  final SyncHold hold;

  /// The last upload's failure, cleared by the next success.
  final String? error;

  DriveSyncState copyWith({
    CloudAccount? Function()? account,
    int? pending,
    bool? uploading,
    SyncHold? hold,
    String? Function()? error,
  }) => DriveSyncState(
    account: account == null ? this.account : account(),
    pending: pending ?? this.pending,
    uploading: uploading ?? this.uploading,
    hold: hold ?? this.hold,
    error: error == null ? this.error : error(),
  );
}

/// Settings > Sync: uploads each export to the user's Google Drive, honouring
/// the Sync and "Sync using cellular data" switches. Exports wait in a queue
/// (kept between launches) while sync is held back, and go up when the
/// phone is back on a network sync may use.
final driveSyncProvider = AsyncNotifierProvider<DriveSyncController, DriveSyncState>(DriveSyncController.new);

class DriveSyncController extends AsyncNotifier<DriveSyncState> {
  bool _flushing = false;
  bool _again = false;

  DriveBackup get _backup => ref.read(driveBackupProvider);

  @override
  Future<DriveSyncState> build() async {
    // Nothing to watch on a phone or build where sync cannot run.
    if (_backup.availability != CloudAvailability.ready) return const DriveSyncState();
    final sub = ref
        .read(networkStatusProvider)
        .changes
        .listen((_) => unawaited(flush()), onError: (Object _) {}, cancelOnError: false);
    ref.onDispose(sub.cancel);
    ref.listen(appSettingsProvider.select((s) => (s.syncEnabled, s.syncOnCellular)), (_, _) => unawaited(flush()));

    CloudAccount? account;
    var pending = 0;
    try {
      account = await _backup.restore();
      if (account != null) pending = (await _backup.pending()).length;
    } on Object {
      // A saved sign-in that cannot be read counts as not connected.
    }
    if (account != null && pending > 0) scheduleMicrotask(() => unawaited(flush()));
    return DriveSyncState(account: account, pending: pending);
  }

  /// Signs in. Returns null when the user backed out.
  Future<CloudAccount?> connect() async {
    final CloudAccount account;
    try {
      account = await _backup.connect();
    } on CloudCancelled {
      return null;
    }
    final current = await future;
    state = AsyncData(current.copyWith(account: () => account, pending: 0, error: () => null));
    return account;
  }

  /// Stops syncing and signs out. Files already in Drive stay there.
  Future<void> disconnect() async {
    await _backup.disconnect();
    final current = await future;
    state = AsyncData(const DriveSyncState().copyWith(hold: current.hold));
  }

  /// Queues [file] for Drive and uploads it now if sync may run. Does
  /// nothing when sync is not connected. Never throws: a failed upload stays
  /// queued and is shown on the Sync screen.
  Future<void> enqueue(File file) async {
    final current = await future;
    if (current.account == null) return;
    try {
      await _backup.addPending(await ref.read(driveSyncQueueProvider).keep(file));
      _set((s) => s.copyWith(pending: s.pending + 1));
    } on Object catch (e) {
      _set((s) => s.copyWith(error: () => '$e'));
      return;
    }
    await flush();
  }

  /// Why sync would wait right now, or [SyncHold.none].
  Future<SyncHold> _hold() async {
    final settings = ref.read(appSettingsProvider);
    if (!settings.syncEnabled) return SyncHold.off;
    final kind = await ref.read(networkStatusProvider).current();
    if (kind == NetworkKind.none) return SyncHold.offline;
    if (kind == NetworkKind.cellular && !settings.syncOnCellular) return SyncHold.waitingForWifi;
    return SyncHold.none;
  }

  /// Uploads every waiting export, oldest first, if sync may run now.
  Future<void> flush() async {
    if (_flushing) {
      _again = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _again = false;
        await _flushOnce();
      } while (_again && ref.mounted);
    } finally {
      _flushing = false;
    }
  }

  Future<void> _flushOnce() async {
    final current = await future;
    if (current.account == null) return;
    final hold = await _hold();
    _set((s) => s.copyWith(hold: hold));
    if (hold != SyncHold.none) return;
    final paths = await _backup.pending();
    if (paths.isEmpty) return;
    _set((s) => s.copyWith(uploading: true));
    try {
      for (final path in paths) {
        if (await _hold() != SyncHold.none) break;
        final file = File(path);
        if (!file.existsSync()) {
          // Deleted before it went up: nothing left to send.
          await _backup.removePending(path);
          continue;
        }
        await _backup.upload(file);
        await ref.read(driveSyncQueueProvider).release(path);
        _set((s) => s.copyWith(error: () => null));
      }
    } on CloudSignInExpired {
      _set(
        (s) => s.copyWith(error: () => 'Google sign-in has expired. Connect Google Drive again in Settings > Sync.'),
      );
    } on Object catch (e) {
      _set((s) => s.copyWith(error: () => 'Upload to Google Drive failed. It will be tried again. ($e)'));
    } finally {
      final left = await _backup.pending().catchError((Object _) => const <String>[]);
      _set((s) => s.copyWith(uploading: false, pending: left.length));
    }
  }

  void _set(DriveSyncState Function(DriveSyncState) update) {
    final current = state.value;
    if (current == null || !ref.mounted) return;
    state = AsyncData(update(current));
  }
}
