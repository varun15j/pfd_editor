import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../app/app_info.dart';
import '../../app/cloud_config.dart';
import '../../domain/cloud_storage.dart';
import 'cloud_http.dart';

/// Google Drive's upload API (v3) with the drive.file scope, which only sees
/// files and folders this app made. Split from sign-in so it can be tested
/// with a fake HTTP client.
class GoogleDriveUploadApi {
  GoogleDriveUploadApi(this._http);

  final CloudHttp _http;

  static const folderMime = 'application/vnd.google-apps.folder';
  static const _files = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  /// The id of the folder called [name] at the top of My Drive that this app
  /// made earlier, or of a new one.
  Future<String> ensureFolder(String name) async {
    final quoted = name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final found = await _http.getJson(
      Uri.parse(_files).replace(
        queryParameters: {
          'q': "name = '$quoted' and mimeType = '$folderMime' and 'root' in parents and trashed = false",
          'fields': 'files(id)',
          'pageSize': '1',
        },
      ),
    );
    final files = (found['files'] as List?) ?? const [];
    if (files.isNotEmpty) return (files.first as Map)['id'] as String;
    final made = await _http.sendJson(
      'POST',
      Uri.parse(_files).replace(queryParameters: {'fields': 'id'}),
      body: utf8.encode(
        jsonEncode({
          'name': name,
          'mimeType': folderMime,
          'parents': ['root'],
        }),
      ),
      contentType: 'application/json; charset=UTF-8',
    );
    return made['id'] as String;
  }

  /// Uploads [file] as [name] into [folderId] and returns the Drive file id.
  /// With [replaceId], that Drive file gets the new content and name instead,
  /// so exporting a scan again does not leave a second copy; if it was
  /// deleted meanwhile, a new file is made.
  Future<String> upload(File file, {required String name, required String folderId, String? replaceId}) async {
    final mime = mimeTypeFor(name);
    final bytes = await file.readAsBytes();
    if (replaceId != null) {
      try {
        final updated = await _http.sendJson(
          'PATCH',
          Uri.parse('$_upload/${Uri.encodeComponent(replaceId)}')
              .replace(queryParameters: {'uploadType': 'multipart', 'fields': 'id'}),
          body: _multipart({'name': name}, bytes, mime),
          contentType: 'multipart/related; boundary=$_boundary',
        );
        return updated['id'] as String;
      } on CloudHttpException catch (e) {
        if (e.statusCode != 404) rethrow;
      }
    }
    final made = await _http.sendJson(
      'POST',
      Uri.parse(_upload).replace(queryParameters: {'uploadType': 'multipart', 'fields': 'id'}),
      body: _multipart(
        {
          'name': name,
          'parents': [folderId],
        },
        bytes,
        mime,
      ),
      contentType: 'multipart/related; boundary=$_boundary',
    );
    return made['id'] as String;
  }

  static const _boundary = 'lumascan_upload_boundary';

  static List<int> _multipart(Map<String, Object> metadata, List<int> bytes, String mime) => [
    ...utf8.encode(
      '--$_boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'
      '${jsonEncode(metadata)}\r\n'
      '--$_boundary\r\nContent-Type: $mime\r\n\r\n',
    ),
    ...bytes,
    ...utf8.encode('\r\n--$_boundary--\r\n'),
  ];

  static String mimeTypeFor(String name) => switch (p.extension(name).toLowerCase()) {
    '.pdf' => 'application/pdf',
    '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}

/// Saves exported files to the user's own Google Drive, into a folder named
/// after the app. Behind an interface so screens and tests do not depend on
/// Google's SDK.
abstract class DriveBackup {
  CloudAvailability get availability;

  /// The account connected on an earlier visit, without any sign-in screen.
  Future<CloudAccount?> restore();

  /// Signs in and asks for access to the app's own Drive files. Throws
  /// [CloudCancelled] when the user backs out.
  Future<CloudAccount> connect();

  /// Signs out and stops backing up. Files already in Drive stay there.
  Future<void> disconnect();

  /// Uploads [file]. The same local file uploaded again replaces its earlier
  /// copy in Drive. A successful upload takes the file off [pending].
  Future<void> upload(File file);

  /// Local files waiting to upload, oldest first; kept between launches so
  /// an export made offline or on mobile data still reaches Drive.
  Future<List<String>> pending();

  /// Adds [path] to [pending] unless it is already there.
  Future<void> addPending(String path);

  /// Drops [path] from [pending] without uploading it.
  Future<void> removePending(String path);
}

/// What the backup remembers between launches: the account's name, the
/// Drive folder and which Drive file holds each local export.
class DriveBackupState {
  const DriveBackupState({required this.account, this.folderId, this.uploads = const {}, this.pending = const []});

  final CloudAccount account;
  final String? folderId;

  /// Drive file id by local file path.
  final Map<String, String> uploads;

  /// Local files waiting to upload, oldest first.
  final List<String> pending;

  DriveBackupState copyWith({String? folderId, Map<String, String>? uploads, List<String>? pending}) =>
      DriveBackupState(
        account: account,
        folderId: folderId ?? this.folderId,
        uploads: uploads ?? this.uploads,
        pending: pending ?? this.pending,
      );

  Map<String, Object?> toJson() => {
    'name': account.name,
    'email': account.email,
    'folderId': folderId,
    'uploads': uploads,
    'pending': pending,
  };

  static DriveBackupState fromJson(Map<String, dynamic> json) => DriveBackupState(
    account: CloudAccount(name: json['name'] as String? ?? '', email: json['email'] as String?),
    folderId: json['folderId'] as String?,
    uploads: ((json['uploads'] as Map?) ?? const {}).cast<String, String>(),
    pending: ((json['pending'] as List?) ?? const []).cast<String>(),
  );
}

/// [DriveBackup] through Google Sign-In with the drive.file scope.
class GoogleDriveBackup implements DriveBackup {
  GoogleDriveBackup({http.Client? client, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    _api = GoogleDriveUploadApi(CloudHttp(client ?? http.Client(), _accessToken, onRejected: _dropToken));
  }

  final FlutterSecureStorage _storage;
  late final GoogleDriveUploadApi _api;
  Future<void>? _init;

  /// Uploads run one at a time so two exports cannot both make the folder.
  Future<void> _queue = Future.value();

  static const _stateKey = 'cloud.googleDriveBackup.state';
  static const _scopes = CloudConfig.googleDriveBackupScopes;

  @override
  CloudAvailability get availability {
    if (Platform.isIOS) {
      return CloudConfig.googleIosClientId.isEmpty ? CloudAvailability.notConfigured : CloudAvailability.ready;
    }
    if (Platform.isAndroid) {
      return CloudConfig.googleServerClientId.isEmpty ? CloudAvailability.notConfigured : CloudAvailability.ready;
    }
    return CloudAvailability.unsupportedPlatform;
  }

  Future<void> _ensureInitialized() => _init ??= GoogleSignIn.instance.initialize(
    clientId: Platform.isIOS ? CloudConfig.googleIosClientId : null,
    serverClientId: CloudConfig.googleServerClientId.isEmpty ? null : CloudConfig.googleServerClientId,
  );

  Future<DriveBackupState?> _read() async {
    final saved = await _storage.read(key: _stateKey);
    if (saved == null) return null;
    return DriveBackupState.fromJson((jsonDecode(saved) as Map).cast<String, dynamic>());
  }

  Future<void> _write(DriveBackupState state) => _storage.write(key: _stateKey, value: jsonEncode(state.toJson()));

  @override
  Future<CloudAccount?> restore() async => (await _read())?.account;

  @override
  Future<CloudAccount> connect() async {
    await _ensureInitialized();
    try {
      final user = await GoogleSignIn.instance.authenticate(scopeHint: _scopes);
      await user.authorizationClient.authorizeScopes(_scopes);
      final account = CloudAccount(name: user.displayName ?? user.email, email: user.email);
      await _write(DriveBackupState(account: account));
      return account;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const CloudCancelled();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _storage.delete(key: _stateKey);
    await _ensureInitialized();
    try {
      await GoogleSignIn.instance.disconnect();
    } on Object {
      // Forgotten on this phone either way; access can also be removed at
      // myaccount.google.com.
    }
  }

  @override
  Future<void> upload(File file) => _serial(() => _upload(file));

  @override
  Future<List<String>> pending() async => (await _read())?.pending ?? const [];

  @override
  Future<void> addPending(String path) => _serial(() async {
    final state = await _read();
    if (state == null || state.pending.contains(path)) return;
    await _write(state.copyWith(pending: [...state.pending, path]));
  });

  @override
  Future<void> removePending(String path) => _serial(() async {
    final state = await _read();
    if (state == null || !state.pending.contains(path)) return;
    await _write(state.copyWith(pending: [...state.pending]..remove(path)));
  });

  /// Runs [task] after the ones before it, so state writes never interleave.
  Future<void> _serial(Future<void> Function() task) {
    final run = _queue.then((_) => task());
    _queue = run.catchError((Object _) {});
    return run;
  }

  Future<void> _upload(File file) async {
    var state = await _read();
    if (state == null) throw StateError('Google Drive backup is not connected');
    final folderId = state.folderId ?? await _api.ensureFolder(appName);
    String id;
    try {
      id = await _api.upload(
        file,
        name: p.basename(file.path),
        folderId: folderId,
        replaceId: state.uploads[file.path],
      );
    } on CloudHttpException catch (e) {
      // The folder was deleted in Drive: make it again, once.
      if (e.statusCode != 404 || state.folderId == null) rethrow;
      final fresh = await _api.ensureFolder(appName);
      state = state.copyWith(folderId: fresh, uploads: const {});
      id = await _api.upload(file, name: p.basename(file.path), folderId: fresh);
    }
    // Read again: a pending entry may have been added while uploading.
    final latest = await _read() ?? state;
    await _write(
      latest.copyWith(
        folderId: state.folderId ?? folderId,
        uploads: {...state.uploads, file.path: id},
        pending: [...latest.pending]..remove(file.path),
      ),
    );
  }

  /// A token without any prompt when Google still has one; otherwise the
  /// sign-in is treated as expired, because uploads run after an export and
  /// must not pop up a consent screen on their own.
  Future<String> _accessToken() async {
    await _ensureInitialized();
    final auth = await GoogleSignIn.instance.authorizationClient.authorizationForScopes(_scopes);
    if (auth == null) throw const CloudSignInExpired();
    return auth.accessToken;
  }

  Future<void> _dropToken(String token) =>
      GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(accessToken: token);
}
