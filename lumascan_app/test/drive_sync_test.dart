import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumascan/app/preferences.dart';
import 'package:lumascan/data/cloud/cloud_http.dart';
import 'package:lumascan/data/cloud/google_drive_backup.dart';
import 'package:lumascan/domain/app_settings.dart';
import 'package:lumascan/domain/cloud_storage.dart';
import 'package:lumascan/features/cloud/drive_sync.dart';

import 'support/fake_sync.dart';
import 'support/memory_stores.dart';
import 'support/pump_app.dart';
import 'support/temp_dir.dart';

void main() {
  group('Google Drive upload API', () {
    late Directory tmp;
    late File pdf;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lumascan_upload');
      pdf = File('${tmp.path}/Lease.pdf')..writeAsStringSync('%PDF-1.7');
    });
    tearDown(() => deleteTemp(tmp));

    test('reuses the app folder it made earlier', () async {
      final requests = <http.Request>[];
      final api = GoogleDriveUploadApi(
        CloudHttp(
          MockClient((request) async {
            requests.add(request);
            return http.Response(
              jsonEncode({
                'files': [
                  {'id': 'folder1'},
                ],
              }),
              200,
            );
          }),
          () async => 't',
        ),
      );

      expect(await api.ensureFolder('LumaScan'), 'folder1');
      expect(requests.single.method, 'GET');
      expect(requests.single.url.queryParameters['q'], contains("name = 'LumaScan'"));
    });

    test('makes the folder when there is none', () async {
      final requests = <http.Request>[];
      final api = GoogleDriveUploadApi(
        CloudHttp(
          MockClient((request) async {
            requests.add(request);
            return http.Response(jsonEncode(request.method == 'GET' ? {'files': []} : {'id': 'new'}), 200);
          }),
          () async => 't',
        ),
      );

      expect(await api.ensureFolder('LumaScan'), 'new');
      expect(requests.last.method, 'POST');
      expect(jsonDecode(requests.last.body), {
        'name': 'LumaScan',
        'mimeType': GoogleDriveUploadApi.folderMime,
        'parents': ['root'],
      });
    });

    test('uploads a new file into the folder as multipart', () async {
      late http.Request sent;
      final api = GoogleDriveUploadApi(
        CloudHttp(
          MockClient((request) async {
            sent = request;
            return http.Response(jsonEncode({'id': 'f1'}), 200);
          }),
          () async => 't',
        ),
      );

      expect(await api.upload(pdf, name: 'Lease.pdf', folderId: 'folder1'), 'f1');
      expect(sent.method, 'POST');
      expect(sent.url.path, '/upload/drive/v3/files');
      expect(sent.url.queryParameters['uploadType'], 'multipart');
      expect(sent.headers['Authorization'], 'Bearer t');
      expect(sent.headers['Content-Type'], startsWith('multipart/related'));
      final body = utf8.decode(sent.bodyBytes);
      expect(body, contains('"parents":["folder1"]'));
      expect(body, contains('Content-Type: application/pdf'));
      expect(body, contains('%PDF-1.7'));
    });

    test('replaces the earlier copy, or makes a new one when it was deleted', () async {
      final methods = <String>[];
      var gone = false;
      final api = GoogleDriveUploadApi(
        CloudHttp(
          MockClient((request) async {
            methods.add('${request.method} ${request.url.path}');
            if (request.method == 'PATCH' && gone) return http.Response('{"error":{"message":"File not found"}}', 404);
            return http.Response(jsonEncode({'id': request.method == 'PATCH' ? 'f1' : 'f2'}), 200);
          }),
          () async => 't',
        ),
      );

      expect(await api.upload(pdf, name: 'Lease.pdf', folderId: 'd', replaceId: 'f1'), 'f1');
      gone = true;
      expect(await api.upload(pdf, name: 'Lease.pdf', folderId: 'd', replaceId: 'f1'), 'f2');
      expect(methods, [
        'PATCH /upload/drive/v3/files/f1',
        'PATCH /upload/drive/v3/files/f1',
        'POST /upload/drive/v3/files',
      ]);
    });
  });

  group('Sync', () {
    late Directory tmp;
    late File pdf;
    late FakeNetwork network;
    late FakeDriveBackup backup;
    late ProviderContainer container;

    Future<void> start({AppSettings settings = const AppSettings(), bool connected = true}) async {
      backup = FakeDriveBackup(saved: connected ? const CloudAccount(name: 'Varun') : null);
      container = ProviderContainer(
        overrides: [
          networkStatusProvider.overrideWithValue(network),
          driveBackupProvider.overrideWithValue(backup),
          appSettingsStoreProvider.overrideWithValue(MemoryAppSettingsStore(settings)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.notifier).loaded;
      await container.read(driveSyncProvider.future);
    }

    DriveSyncState state() => container.read(driveSyncProvider).value!;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('lumascan_sync');
      pdf = File('${tmp.path}/Lease.pdf')..writeAsStringSync('%PDF');
      network = FakeNetwork();
    });
    tearDown(() => deleteTemp(tmp));

    test('uploads an export straight away on Wi-Fi', () async {
      await start();
      await container.read(driveSyncProvider.notifier).enqueue(pdf);

      expect(backup.uploaded, [pdf.path]);
      expect(state().pending, 0);
      expect(state().uploading, isFalse);
    });

    test('does nothing when sync is not connected', () async {
      await start(connected: false);
      await container.read(driveSyncProvider.notifier).enqueue(pdf);

      expect(backup.uploaded, isEmpty);
      expect(backup.queue, isEmpty);
    });

    test('waits for Wi-Fi on mobile data, then uploads', () async {
      network.kind = NetworkKind.cellular;
      await start();
      await container.read(driveSyncProvider.notifier).enqueue(pdf);

      expect(backup.uploaded, isEmpty);
      expect(state().pending, 1);
      expect(state().hold, SyncHold.waitingForWifi);

      network.change(NetworkKind.unmetered);
      await pumpEventQueue();
      expect(backup.uploaded, [pdf.path]);
      expect(state().pending, 0);
    });

    test('uses mobile data when allowed', () async {
      network.kind = NetworkKind.cellular;
      await start(settings: const AppSettings(syncOnCellular: true));
      await container.read(driveSyncProvider.notifier).enqueue(pdf);

      expect(backup.uploaded, [pdf.path]);
    });

    test('holds everything while sync is off, and sends it once turned on', () async {
      await start(settings: const AppSettings(syncEnabled: false));
      await container.read(driveSyncProvider.notifier).enqueue(pdf);

      expect(backup.uploaded, isEmpty);
      expect(state().hold, SyncHold.off);

      container.read(appSettingsProvider.notifier).setSyncEnabled(true);
      await pumpEventQueue();
      expect(backup.uploaded, [pdf.path]);
    });

    test('keeps a failed upload queued and says why', () async {
      await start();
      backup.uploadError = const CloudSignInExpired();
      await container.read(driveSyncProvider.notifier).enqueue(pdf);

      expect(state().pending, 1);
      expect(state().error, contains('Connect Google Drive again'));

      backup.uploadError = null;
      await container.read(driveSyncProvider.notifier).flush();
      expect(backup.uploaded, [pdf.path]);
      expect(state().error, isNull);
    });

    test('drops a waiting export whose file was deleted', () async {
      network.kind = NetworkKind.none;
      await start();
      await container.read(driveSyncProvider.notifier).enqueue(pdf);
      pdf.deleteSync();

      network.change(NetworkKind.unmetered);
      await pumpEventQueue();
      expect(backup.uploaded, isEmpty);
      expect(backup.queue, isEmpty);
    });
  });

  test('sync settings are saved and default to on, Wi-Fi only', () {
    const defaults = AppSettings();
    expect(defaults.syncEnabled, isTrue);
    expect(defaults.syncOnCellular, isFalse);
    final back = AppSettings.fromJson(const AppSettings(syncEnabled: false, syncOnCellular: true).toJson());
    expect(back.syncEnabled, isFalse);
    expect(back.syncOnCellular, isTrue);
  });

  group('Settings > Sync', () {
    Future<(FakeDriveBackup, MemoryAppSettingsStore)> openSync(WidgetTester tester) async {
      final backup = FakeDriveBackup();
      final store = MemoryAppSettingsStore();
      await pumpApp(
        tester,
        settings: store,
        overrides: [
          driveBackupProvider.overrideWithValue(backup),
          networkStatusProvider.overrideWithValue(FakeNetwork()),
        ],
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      return (backup, store);
    }

    testWidgets('has the Sync and cellular data switches, Wi-Fi only by default', (tester) async {
      final (_, store) = await openSync(tester);

      expect(find.text('Sync using cellular data'), findsOneWidget);
      expect(find.textContaining('wait for Wi-Fi'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);

      await tester.tap(find.text('Sync using cellular data'));
      await tester.pumpAndSettle();
      expect(find.text('Uploads use Wi-Fi or mobile data.'), findsOneWidget);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Sync'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Exports stay on this phone and wait'), findsOneWidget);
      final cellular = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Sync using cellular data'));
      expect(cellular.onChanged, isNull, reason: 'cellular data only matters while sync is on');

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect((store.settings.syncEnabled, store.settings.syncOnCellular), (false, true));
    });

    testWidgets('connects and disconnects Google Drive', (tester) async {
      final (backup, _) = await openSync(tester);

      await tester.tap(find.text('Connect Google Drive'));
      await tester.pumpAndSettle();
      expect(find.text('Syncing to Varun (varun@example.com)'), findsWidgets);
      expect(find.text('Up to date.'), findsOneWidget);

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
      await tester.pumpAndSettle();
      expect(backup.saved, isNull);
      expect(find.text('Not connected'), findsOneWidget);
    });
  });
}
