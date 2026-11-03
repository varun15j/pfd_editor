import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'scan_document.dart';

/// The kinds of file a scan can be exported as and kept in the Saved
/// folder. Each scan has at most one saved file per kind: exporting again
/// replaces it. Ids are stored, so never rename them.
enum ExportFormat {
  pdf('pdf', 'PDF'),
  textPdf('text_pdf', 'Text PDF'),
  word('docx', 'Word');

  const ExportFormat(this.id, this.label);

  final String id;
  final String label;

  static ExportFormat? fromId(String? id) {
    for (final f in values) {
      if (f.id == id) return f;
    }
    return null;
  }
}

/// One file exported from a scan, as the export state database keeps it:
/// where it is, and a fingerprint of the pages and options it was made
/// from. A later export of the same scan with the same fingerprint reuses
/// the file instead of making it again.
@immutable
class SavedExport {
  const SavedExport({
    required this.docKey,
    required this.format,
    required this.path,
    required this.fingerprint,
    required this.name,
    required this.pageCount,
    required this.sizeBytes,
    required this.exportedAt,
    this.libraryId,
  });

  /// The scan it was made from; see [scanDocKey].
  final String docKey;
  final ExportFormat format;

  /// Absolute in memory; stored relative to the exports folder.
  final String path;

  /// See [exportFingerprint].
  final String fingerprint;

  /// The scan's name when it was exported, without extension.
  final String name;
  final int pageCount;
  final int sizeBytes;
  final DateTime exportedAt;

  /// The Library entry for a PDF; null for Word files.
  final String? libraryId;

  @override
  bool operator ==(Object other) =>
      other is SavedExport &&
      other.docKey == docKey &&
      other.format == format &&
      other.path == path &&
      other.fingerprint == fingerprint &&
      other.name == name &&
      other.pageCount == pageCount &&
      other.sizeBytes == sizeBytes &&
      other.exportedAt == exportedAt &&
      other.libraryId == libraryId;

  @override
  int get hashCode => Object.hash(docKey, format, path, fingerprint, name, pageCount, sizeBytes, exportedAt, libraryId);
}

/// A stable key for a scan document. Scans have no id of their own, but
/// their start time is saved with them and never changes, also when they
/// are renamed, set aside or opened again.
String scanDocKey(ScanDocInfo info) => 'scan-${info.createdAt.toUtc().microsecondsSinceEpoch}';

/// A short hash of everything that changes an exported file: every page
/// (its image, crop, filter, marks and text) in order, the file name, and
/// the export [options] (page size, quality, watermark and so on). Two
/// exports with the same fingerprint make the same file.
String exportFingerprint(List<ScanPage> pages, {required String fileName, Map<String, Object?> options = const {}}) {
  final source = jsonEncode({
    'name': fileName,
    'options': options,
    'pages': [for (final p in pages) p.toJson()],
  });
  return _fnv1a64(utf8.encode(source));
}

/// 64-bit FNV-1a, as 16 hex digits. Not for security: only to notice a
/// change. Done as two 32-bit halves so it gives the same answer on every
/// platform.
String _fnv1a64(List<int> bytes) {
  // Offset basis 0xcbf29ce484222325, prime 0x100000001b3 (= 2^40 + 0x1b3).
  var hi = 0xcbf29ce4;
  var lo = 0x84222325;
  for (final b in bytes) {
    lo ^= b;
    // (hi:lo) * prime = (hi:lo) * 0x1b3 + (lo << 40).
    final loMul = lo * 0x1b3;
    final newLo = loMul % 0x100000000;
    final carry = (loMul - newLo) ~/ 0x100000000;
    final newHi = (hi * 0x1b3 + carry + lo * 256) % 0x100000000;
    hi = newHi;
    lo = newLo;
  }
  return hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');
}
