import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../app/cloud_config.dart';
import '../../domain/cloud_storage.dart';
import 'cloud_http.dart';

/// OneDrive through Microsoft Graph, read-only. Split from sign-in so it can
/// be tested with a fake HTTP client.
class OneDriveApi {
  OneDriveApi(this._http);

  final CloudHttp _http;

  static const _base = 'https://graph.microsoft.com/v1.0';

  /// The signed-in user's name and email.
  Future<CloudAccount> me() async {
    final json = await _http.getJson(Uri.parse('$_base/me?\$select=displayName,mail,userPrincipalName'));
    final email = (json['mail'] as String?) ?? (json['userPrincipalName'] as String?);
    return CloudAccount(name: (json['displayName'] as String?) ?? email ?? 'OneDrive', email: email);
  }

  /// Everything in [folderId] (or the top of the drive), following every
  /// page of results.
  Future<List<CloudEntry>> list(String? folderId) async {
    final path = folderId == null ? 'root' : 'items/${Uri.encodeComponent(folderId)}';
    final entries = <CloudEntry>[];
    Uri? next = Uri.parse(
      '$_base/me/drive/$path/children?\$top=200&\$select=id,name,size,lastModifiedDateTime,folder,file',
    );
    while (next != null) {
      final json = await _http.getJson(next);
      for (final item in (json['value'] as List?) ?? const []) {
        entries.add(_entry((item as Map).cast<String, dynamic>()));
      }
      final link = json['@odata.nextLink'] as String?;
      next = link == null ? null : Uri.parse(link);
    }
    return sortCloudEntries(entries);
  }

  Future<File> download(CloudEntry entry, Directory directory) => _http.download(
    Uri.parse('$_base/me/drive/items/${Uri.encodeComponent(entry.id)}/content'),
    downloadTarget(directory, entry.kind == CloudEntryKind.word ? '.docx' : '.pdf'),
  );

  static CloudEntry _entry(Map<String, dynamic> item) {
    final name = item['name'] as String? ?? '';
    return CloudEntry(
      id: item['id'] as String,
      name: name,
      kind: item['folder'] != null ? CloudEntryKind.folder : CloudEntry.kindForName(name),
      sizeBytes: (item['size'] as num?)?.toInt(),
      modifiedAt: DateTime.tryParse('${item['lastModifiedDateTime'] ?? ''}'),
    );
  }
}

/// OneDrive with a Microsoft account, signed in through the system browser
/// (AppAuth, PKCE, no client secret). The refresh token is kept in the
/// phone's secure storage (Keychain on iOS, Keystore-backed on Android).
class OneDriveProvider extends CloudStorageProvider {
  OneDriveProvider({http.Client? client, FlutterSecureStorage? storage, FlutterAppAuth? appAuth})
    : _storage = storage ?? const FlutterSecureStorage(),
      _appAuth = appAuth ?? const FlutterAppAuth() {
    _api = OneDriveApi(CloudHttp(client ?? http.Client(), _accessToken, onRejected: (_) async => _token = null));
  }

  final FlutterSecureStorage _storage;
  final FlutterAppAuth _appAuth;
  late final OneDriveApi _api;

  String? _token;
  DateTime? _tokenExpiry;

  static const _refreshKey = 'cloud.oneDrive.refreshToken';
  static const _accountKey = 'cloud.oneDrive.account';

  static const _service = AuthorizationServiceConfiguration(
    authorizationEndpoint: 'https://login.microsoftonline.com/${CloudConfig.microsoftTenant}/oauth2/v2.0/authorize',
    tokenEndpoint: 'https://login.microsoftonline.com/${CloudConfig.microsoftTenant}/oauth2/v2.0/token',
  );

  @override
  CloudProviderId get id => CloudProviderId.oneDrive;

  @override
  CloudAvailability get availability {
    if (!Platform.isAndroid && !Platform.isIOS) return CloudAvailability.unsupportedPlatform;
    return CloudConfig.microsoftClientId.isEmpty ? CloudAvailability.notConfigured : CloudAvailability.ready;
  }

  @override
  Future<CloudAccount?> restore() async {
    final saved = await _storage.read(key: _accountKey);
    if (saved == null || await _storage.read(key: _refreshKey) == null) return null;
    final json = (jsonDecode(saved) as Map).cast<String, dynamic>();
    return CloudAccount(name: json['name'] as String? ?? '', email: json['email'] as String?);
  }

  @override
  Future<CloudAccount> connect() async {
    final AuthorizationTokenResponse result;
    try {
      result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          CloudConfig.microsoftClientId,
          CloudConfig.microsoftRedirectUri,
          serviceConfiguration: _service,
          scopes: CloudConfig.microsoftScopes,
          promptValues: const ['select_account'],
        ),
      );
    } on FlutterAppAuthUserCancelledException {
      throw const CloudCancelled();
    }
    await _keep(result);
    final account = await _api.me();
    await _storage.write(key: _accountKey, value: jsonEncode({'name': account.name, 'email': account.email}));
    return account;
  }

  @override
  Future<void> disconnect() async {
    _token = null;
    _tokenExpiry = null;
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _accountKey);
  }

  Future<void> _keep(TokenResponse response) async {
    _token = response.accessToken;
    _tokenExpiry = response.accessTokenExpirationDateTime;
    // Microsoft hands out a new refresh token with each refresh.
    final refresh = response.refreshToken;
    if (refresh != null) await _storage.write(key: _refreshKey, value: refresh);
  }

  /// The cached token while it has a minute left, otherwise a refreshed one.
  Future<String> _accessToken() async {
    final token = _token;
    final expiry = _tokenExpiry;
    if (token != null && (expiry == null || expiry.isAfter(DateTime.now().add(const Duration(minutes: 1))))) {
      return token;
    }
    final refresh = await _storage.read(key: _refreshKey);
    if (refresh == null) throw const CloudSignInExpired();
    try {
      await _keep(
        await _appAuth.token(
          TokenRequest(
            CloudConfig.microsoftClientId,
            CloudConfig.microsoftRedirectUri,
            refreshToken: refresh,
            serviceConfiguration: _service,
            scopes: CloudConfig.microsoftScopes,
          ),
        ),
      );
    } on PlatformException {
      // A revoked or expired refresh token: the user has to connect again.
      await disconnect();
      throw const CloudSignInExpired();
    }
    final fresh = _token;
    if (fresh == null) throw const CloudSignInExpired();
    return fresh;
  }

  @override
  Future<List<CloudEntry>> list(String? folderId) => _api.list(folderId);

  @override
  Future<File> download(CloudEntry entry, Directory directory) => _api.download(entry, directory);
}
