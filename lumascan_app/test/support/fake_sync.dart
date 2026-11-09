import 'dart:async';
import 'dart:io';

import 'package:lumascan/data/cloud/google_drive_backup.dart';
import 'package:lumascan/domain/cloud_storage.dart';
import 'package:lumascan/features/cloud/drive_sync.dart';

/// A connection the test switches by hand.
class FakeNetwork implements NetworkStatus {
  FakeNetwork([this.kind = NetworkKind.unmetered]);

  NetworkKind kind;
  final _changes = StreamController<NetworkKind>.broadcast();

  void change(NetworkKind to) {
    kind = to;
    _changes.add(to);
  }

  @override
  Future<NetworkKind> current() async => kind;

  @override
  Stream<NetworkKind> get changes => _changes.stream;
}

/// Google Drive backup held in memory.
class FakeDriveBackup implements DriveBackup {
  FakeDriveBackup({this.availability = CloudAvailability.ready, this.saved});

  @override
  CloudAvailability availability;
  CloudAccount? saved;
  final queue = <String>[];
  final uploaded = <String>[];
  Object? uploadError;

  @override
  Future<CloudAccount?> restore() async => saved;

  @override
  Future<CloudAccount> connect() async => saved = const CloudAccount(name: 'Varun', email: 'varun@example.com');

  @override
  Future<void> disconnect() async {
    saved = null;
    queue.clear();
  }

  @override
  Future<void> upload(File file) async {
    final error = uploadError;
    if (error != null) throw error;
    uploaded.add(file.path);
    queue.remove(file.path);
  }

  @override
  Future<List<String>> pending() async => [...queue];

  @override
  Future<void> addPending(String path) async {
    if (!queue.contains(path)) queue.add(path);
  }

  @override
  Future<void> removePending(String path) async => queue.remove(path);
}

/// Queues each export where it is, so tests see the paths they made.
class InPlaceSyncQueue implements DriveSyncQueue {
  final released = <String>[];

  @override
  Future<String> keep(File file) async => file.path;

  @override
  Future<void> release(String path) async => released.add(path);
}
