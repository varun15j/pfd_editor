import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../domain/cloud_storage.dart';

/// A request the service turned down, with the reason it gave.
class CloudHttpException implements Exception {
  const CloudHttpException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message.isEmpty ? 'The service answered $statusCode.' : message;
}

/// Authorized GET requests to a cloud API. When the service rejects the
/// token, [onRejected] gets a chance to drop it and the request is tried once
/// more with a fresh one; a second rejection means the sign-in is gone.
class CloudHttp {
  CloudHttp(this._client, this._token, {this.onRejected});

  final http.Client _client;
  final Future<String> Function() _token;
  final Future<void> Function(String token)? onRejected;

  Future<http.StreamedResponse> _send(Uri uri) async {
    for (var attempt = 0; ; attempt++) {
      final token = await _token();
      final request = http.Request('GET', uri)..headers['Authorization'] = 'Bearer $token';
      final response = await _client.send(request);
      if (response.statusCode == 401) {
        await response.stream.drain<void>();
        final retry = onRejected;
        if (attempt == 0 && retry != null) {
          await retry(token);
          continue;
        }
        throw const CloudSignInExpired();
      }
      if (response.statusCode >= 400) {
        throw CloudHttpException(response.statusCode, _errorMessage(await response.stream.bytesToString()));
      }
      return response;
    }
  }

  Future<Map<String, dynamic>> getJson(Uri uri) async {
    final response = await _send(uri);
    return (jsonDecode(await response.stream.bytesToString()) as Map).cast<String, dynamic>();
  }

  /// Streams the response body into [file].
  Future<File> download(Uri uri, File file) async {
    final response = await _send(uri);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    try {
      await response.stream.pipe(sink);
    } catch (_) {
      if (file.existsSync()) file.deleteSync();
      rethrow;
    }
    return file;
  }

  /// Both Google and Microsoft answer errors as {"error": {"message": ...}}.
  static String _errorMessage(String body) {
    try {
      final error = (jsonDecode(body) as Map)['error'];
      if (error is Map && error['message'] is String) return error['message'] as String;
      if (error is String) return error;
    } on Object {
      // Not JSON; fall through.
    }
    return '';
  }
}

/// A name for a downloaded copy that cannot clash or escape [directory].
File downloadTarget(Directory directory, String extension) =>
    File(p.join(directory.path, '${DateTime.now().microsecondsSinceEpoch}$extension'));
