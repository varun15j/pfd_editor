import 'package:flutter/foundation.dart';

/// Name and start time of a scan document: the pages on screen or one of the
/// earlier ones on Home. Every scan is kept on the device as page images from
/// the first shot; exporting to PDF or JPG makes copies and changes nothing.
@immutable
class ScanDocInfo {
  const ScanDocInfo({required this.name, required this.createdAt});

  final String name;
  final DateTime createdAt;

  ScanDocInfo copyWith({String? name}) => ScanDocInfo(name: name ?? this.name, createdAt: createdAt);

  Map<String, Object?> toJson() => {'name': name, 'createdAt': createdAt.toUtc().toIso8601String()};

  /// Null when [json] has no name (a file from before documents had names).
  static ScanDocInfo? fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final created = json['createdAt'];
    if (name is! String || name.trim().isEmpty) return null;
    return ScanDocInfo(name: name, createdAt: created is String ? DateTime.parse(created).toLocal() : DateTime.now());
  }

  @override
  bool operator ==(Object other) => other is ScanDocInfo && other.name == name && other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(name, createdAt);
}

/// The date part of a scan name, such as `2026-10-11`.
String scanDatePrefix(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}

/// Name for a new scan made at [now]: `2026-10-11 Scan`, then
/// `2026-10-11 Scan 2`, `2026-10-11 Scan 3` and so on for later scans that
/// day. [taken] are the names already in use; case is ignored.
String newScanName(DateTime now, Iterable<String> taken) {
  final base = '${scanDatePrefix(now)} Scan';
  final used = {for (final t in taken) t.trim().toLowerCase()};
  if (!used.contains(base.toLowerCase())) return base;
  for (var n = 2; ; n++) {
    final name = '$base $n';
    if (!used.contains(name.toLowerCase())) return name;
  }
}
