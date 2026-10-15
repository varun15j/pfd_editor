import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../app/cloud_config.dart';
import '../../domain/cloud_storage.dart';
import 'cloud_http.dart';

/// Google Drive's REST API (v3), read-only. Split from sign-in so it can be
/// tested with a fake HTTP client.
class GoogleDriveApi {
  GoogleDriveApi(this._http);

  final CloudHttp _http;

  static const folderMime = 'application/vnd.google-apps.folder';
  static const googleDocMime = 'application/vnd.google-apps.document';
  static const _base = 'https://www.googleapis.com/drive/v3/files';

  /// Everything in [folderId] (or the top of My Drive) that is not in the
  /// bin, following every page of results.
  Future<List<CloudEntry>> list(String? folderId) async {
    final parent = (folderId ?? 'root').replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final entries = <CloudEntry>[];
    String? pageToken;
    do {
      final json = await _http.getJson(
        Uri.parse(_base).replace(
          queryParameters: {
            'q': "'$parent' in parents and trashed = false",
            'fields': 'nextPageToken,files(id,name,mimeType,size,modifiedTime)',
            'pageSize': '200',
            'pageToken': ?pageToken,
          },
        ),
      );
      for (final f in (json['files'] as List?) ?? const []) {
        entries.add(_entry((f as Map).cast<String, dynamic>()));
      }
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null);
    return sortCloudEntries(entries);
  }

  /// The file's bytes, or for a Google Docs document a PDF export of it.
  Future<File> download(CloudEntry entry, Directory directory) {
    final id = Uri.encodeComponent(entry.id);
    if (entry.kind == CloudEntryKind.googleDoc) {
      return _http.download(
        Uri.parse('$_base/$id/export?mimeType=${Uri.encodeQueryComponent('application/pdf')}'),
        downloadTarget(directory, '.pdf'),
      );
    }
    final ext = entry.kind == CloudEntryKind.word ? '.docx' : '.pdf';
    return _http.download(Uri.parse('$_base/$id?alt=media'), downloadTarget(directory, ext));
  }

  static CloudEntry _entry(Map<String, dynamic> f) {
    final name = f['name'] as String? ?? '';
    final mime = f['mimeType'] as String? ?? '';
    final kind = switch (mime) {
      folderMime => CloudEntryKind.folder,
      googleDocMime => CloudEntryKind.googleDoc,
      'application/pdf' => CloudEntryKind.pdf,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => CloudEntryKind.word,
      _ => CloudEntry.kindForName(name),
    };
    return CloudEntry(
      id: f['id'] as String,
      name: name,
      kind: kind,
      sizeBytes: int.tryParse('${f['size'] ?? ''}'),
      modifiedAt: DateTime.tryParse('${f['modifiedTime'] ?? ''}'),
    );
  }
}

/// Google Drive through Google Sign-In, with the drive.readonly scope.
class GoogleDriveProvider extends CloudStorageProvider {
  GoogleDriveProvider({http.Client? client, FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    _api = GoogleDriveApi(CloudHttp(client ?? http.Client(), _accessToken, onRejected: _dropToken));
  }

  final FlutterSecureStorage _storage;
  late final GoogleDriveApi _api;
  Future<void>? _init;

  static const _accountKey = 'cloud.googleDrive.account';

  @override
  CloudProviderId get id => CloudProviderId.googleDrive;

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

  /// The account is remembered by name only; Google keeps the sign-in itself.
  @override
  Future<CloudAccount?> restore() async {
    final saved = await _storage.read(key: _accountKey);
    if (saved == null) return null;
    final json = (jsonDecode(saved) as Map).cast<String, dynamic>();
    return CloudAccount(name: json['name'] as String? ?? '', email: json['email'] as String?);
  }

  @override
  Future<CloudAccount> connect() async {
    await _ensureInitialized();
    try {
      final user = await GoogleSignIn.instance.authenticate(scopeHint: CloudConfig.googleDriveScopes);
      await user.authorizationClient.authorizeScopes(CloudConfig.googleDriveScopes);
      final account = CloudAccount(name: user.displayName ?? user.email, email: user.email);
      await _storage.write(key: _accountKey, value: jsonEncode({'name': account.name, 'email': account.email}));
      return account;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const CloudCancelled();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _storage.delete(key: _accountKey);
    await _ensureInitialized();
    try {
      await GoogleSignIn.instance.disconnect();
    } on Object {
      // Forgotten on this phone either way; access can also be removed at
      // myaccount.google.com.
    }
  }

  /// A token without any prompt when Google still has one, otherwise the
  /// consent screen again (the user is on the browse screen, so it is shown
  /// in answer to their tap).
  Future<String> _accessToken() async {
    await _ensureInitialized();
    final client = GoogleSignIn.instance.authorizationClient;
    try {
      final auth =
          await client.authorizationForScopes(CloudConfig.googleDriveScopes) ??
          await client.authorizeScopes(CloudConfig.googleDriveScopes);
      return auth.accessToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const CloudSignInExpired();
      rethrow;
    }
  }

  Future<void> _dropToken(String token) =>
      GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(accessToken: token);

  @override
  Future<List<CloudEntry>> list(String? folderId) => _api.list(folderId);

  @override
  Future<File> download(CloudEntry entry, Directory directory) => _api.download(entry, directory);
}
