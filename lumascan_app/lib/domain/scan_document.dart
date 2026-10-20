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

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Name for a scan made at [t], like `11-Oct-2026_16-47_SCAN`. Two scans in
/// the same minute share the name; either can be renamed.
String scanDocumentName(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}-${_months[t.month - 1]}-${t.year}_${two(t.hour)}-${two(t.minute)}_SCAN';
}
