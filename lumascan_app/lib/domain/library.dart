import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// How a saved document was made. The scan modes follow EP-03; [pdf] is a
/// PDF opened and saved in the editor. Ids are stored, so never rename them.
enum ScanType {
  document('document', 'Document'),
  book('book', 'Book'),
  idCard('id_card', 'ID card'),
  businessCard('business_card', 'Business card'),
  pdf('pdf', 'PDF');

  const ScanType(this.id, this.label);

  final String id;
  final String label;

  static ScanType fromId(String? id) => values.firstWhere((t) => t.id == id, orElse: () => ScanType.document);
}

/// One saved PDF in the on-device library (US-02.1).
///
/// Paths are absolute in memory but stored relative to the app's private
/// root, because that root can move between launches (iOS changes it on
/// every app update).
@immutable
class SavedDocument {
  const SavedDocument({
    required this.id,
    required this.name,
    required this.pdfPath,
    required this.pageCount,
    required this.type,
    required this.createdAt,
    required this.modifiedAt,
    this.thumbnailPath,
    this.folderId,
    this.tags = const [],
    this.sizeBytes = 0,
  });

  final String id;

  /// Display name, without the .pdf extension.
  final String name;
  final String pdfPath;
  final int pageCount;

  /// Small JPEG of the first page, or null when none could be made.
  final String? thumbnailPath;
  final ScanType type;
  final DateTime createdAt;
  final DateTime modifiedAt;

  /// Null means the library root.
  final String? folderId;
  final List<String> tags;
  final int sizeBytes;

  SavedDocument copyWith({
    String? name,
    String? pdfPath,
    int? pageCount,
    String? thumbnailPath,
    ScanType? type,
    DateTime? modifiedAt,
    String? Function()? folderId,
    List<String>? tags,
    int? sizeBytes,
  }) => SavedDocument(
    id: id,
    name: name ?? this.name,
    pdfPath: pdfPath ?? this.pdfPath,
    pageCount: pageCount ?? this.pageCount,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    type: type ?? this.type,
    createdAt: createdAt,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    folderId: folderId == null ? this.folderId : folderId(),
    tags: tags ?? this.tags,
    sizeBytes: sizeBytes ?? this.sizeBytes,
  );

  Map<String, Object?> toJson(String root) => {
    'id': id,
    'name': name,
    'pdf': path.relative(pdfPath, from: root),
    'pageCount': pageCount,
    if (thumbnailPath != null) 'thumbnail': path.relative(thumbnailPath!, from: root),
    'type': type.id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'modifiedAt': modifiedAt.toUtc().toIso8601String(),
    if (folderId != null) 'folderId': folderId,
    if (tags.isNotEmpty) 'tags': tags,
    'sizeBytes': sizeBytes,
  };

  static SavedDocument fromJson(Map<String, Object?> json, String root) => SavedDocument(
    id: json['id']! as String,
    name: json['name']! as String,
    pdfPath: path.join(root, json['pdf']! as String),
    pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
    thumbnailPath: json['thumbnail'] == null ? null : path.join(root, json['thumbnail']! as String),
    type: ScanType.fromId(json['type'] as String?),
    createdAt: DateTime.parse(json['createdAt']! as String).toLocal(),
    modifiedAt: DateTime.parse(json['modifiedAt']! as String).toLocal(),
    folderId: json['folderId'] as String?,
    tags: [for (final t in (json['tags'] as List?) ?? const []) t as String],
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
  );
}

@immutable
class LibraryFolder {
  const LibraryFolder({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  static LibraryFolder fromJson(Map<String, Object?> json) =>
      LibraryFolder(id: json['id']! as String, name: json['name']! as String);
}

/// Everything the library index file holds.
@immutable
class LibraryIndex {
  const LibraryIndex({this.documents = const [], this.folders = const []});

  static const version = 1;

  /// Newest first by [SavedDocument.modifiedAt].
  final List<SavedDocument> documents;
  final List<LibraryFolder> folders;

  SavedDocument? byId(String id) {
    for (final d in documents) {
      if (d.id == id) return d;
    }
    return null;
  }

  LibraryIndex copyWith({List<SavedDocument>? documents, List<LibraryFolder>? folders}) {
    final docs = [...(documents ?? this.documents)]..sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return LibraryIndex(documents: List.unmodifiable(docs), folders: List.unmodifiable(folders ?? this.folders));
  }

  Map<String, Object?> toJson(String root) => {
    'version': version,
    'documents': [for (final d in documents) d.toJson(root)],
    'folders': [for (final f in folders) f.toJson()],
  };

  static LibraryIndex fromJson(Map<String, Object?> json, String root) => const LibraryIndex().copyWith(
    documents: [
      for (final d in (json['documents'] as List?) ?? const []) SavedDocument.fromJson((d as Map).cast(), root),
    ],
    folders: [for (final f in (json['folders'] as List?) ?? const []) LibraryFolder.fromJson((f as Map).cast())],
  );
}
