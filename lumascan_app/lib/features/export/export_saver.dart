import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Saves an export where the user picks: Documents, Downloads, an SD card,
/// Google Drive or any other storage the phone offers. The app keeps no
/// copy of its exports, so this and the share sheet are the only ways an
/// export leaves the Outbox. Behind an interface so tests need no plugin.
abstract class ExportSaver {
  /// Shows the system save screen for the file at [path], named [name]
  /// (the file's own name when null). Returns the saved file's name, or
  /// null when the user cancelled. Throws when it could not be saved.
  Future<String?> saveFile(String path, {required String mimeType, String? name});

  /// Whether [saveToFolder] works here (Android). Elsewhere several files go
  /// through the share sheet, which offers "Save to Files" and the gallery.
  bool get canSaveToFolder;

  /// Lets the user pick a folder and copies every file in [paths] into it.
  /// Returns the folder's name, or null when cancelled.
  Future<String?> saveToFolder(List<String> paths, {required String mimeType});
}

/// Android: the system "Save to" and folder screens, through
/// `ExportSaver.kt`, which copies the file as a stream. iOS and others: the
/// file picker's save screen.
class PlatformExportSaver implements ExportSaver {
  static const _channel = MethodChannel('lumascan/export_saver');

  @override
  Future<String?> saveFile(String path, {required String mimeType, String? name}) async {
    final fileName = name ?? p.basename(path);
    if (Platform.isAndroid) {
      return _channel.invokeMethod<String>('saveFile', {'path': path, 'name': fileName, 'mimeType': mimeType});
    }
    final ext = p.extension(fileName).replaceFirst('.', '');
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: await File(path).readAsBytes(),
      mimeType: mimeType,
      type: ext.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: ext.isEmpty ? null : [ext],
    );
    return saved == null ? null : (saved.pathSegments.isEmpty ? fileName : Uri.decodeComponent(saved.pathSegments.last));
  }

  @override
  bool get canSaveToFolder => Platform.isAndroid;

  @override
  Future<String?> saveToFolder(List<String> paths, {required String mimeType}) {
    if (!canSaveToFolder) throw UnsupportedError('Saving to a folder needs Android');
    return _channel.invokeMethod<String>('saveToFolder', {'paths': paths, 'mimeType': mimeType});
  }
}

final exportSaverProvider = Provider<ExportSaver>((ref) => PlatformExportSaver());

/// MIME types of the files the app exports.
abstract final class ExportMime {
  static const pdf = 'application/pdf';
  static const docx = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
  static const xlsx = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const jpg = 'image/jpeg';

  static String of(String path) => switch (p.extension(path).toLowerCase()) {
    '.pdf' => pdf,
    '.docx' => docx,
    '.xlsx' => xlsx,
    '.jpg' || '.jpeg' => jpg,
    _ => 'application/octet-stream',
  };
}
