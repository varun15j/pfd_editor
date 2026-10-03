import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'models.dart';

/// How a new PDF is named in the save sheet. The name can still be edited
/// before saving, and a saved file is never renamed when this changes.
enum FileNamePattern {
  dateTime('Date and time'),
  date('Date only'),
  compact('Compact');

  const FileNamePattern(this.label);
  final String label;

  String format(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${t.year}-${two(t.month)}-${two(t.day)}';
    return switch (this) {
      FileNamePattern.dateTime => 'Scan $date ${two(t.hour)}.${two(t.minute)}',
      FileNamePattern.date => 'Scan $date',
      FileNamePattern.compact => 'Scan_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}',
    };
  }

  /// Shown under the option, for 3 October 2026 at 14:30.
  String get example => format(DateTime(2026, 10, 3, 14, 30));
}

/// Choices the user makes in Settings, kept on the device. Each field says in
/// its comment whether changing it touches files that already exist.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.defaultFilter = DocumentFilter.original,
    this.autoCropOnImport = true,
    this.keepOriginals = true,
    this.fileNamePattern = FileNamePattern.dateTime,
  });

  /// Looks only. Does not touch any file.
  final ThemeMode themeMode;

  /// Filter given to pages scanned or imported from now on. Pages already in
  /// a document keep theirs.
  final DocumentFilter defaultFilter;

  /// Whether imported photos start cropped to the page found in them. The
  /// choice can still be changed for each import, and imported pages can be
  /// re-cropped.
  final bool autoCropOnImport;

  /// When off, the page images of a document are deleted from this device as
  /// soon as it is saved as a PDF. Applies to the next save; saved PDFs are
  /// never touched either way.
  final bool keepOriginals;

  /// Name offered for the next PDF. Saved files keep their names.
  final FileNamePattern fileNamePattern;

  AppSettings copyWith({
    ThemeMode? themeMode,
    DocumentFilter? defaultFilter,
    bool? autoCropOnImport,
    bool? keepOriginals,
    FileNamePattern? fileNamePattern,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    defaultFilter: defaultFilter ?? this.defaultFilter,
    autoCropOnImport: autoCropOnImport ?? this.autoCropOnImport,
    keepOriginals: keepOriginals ?? this.keepOriginals,
    fileNamePattern: fileNamePattern ?? this.fileNamePattern,
  );

  Map<String, Object?> toJson() => {
    'themeMode': themeMode.name,
    'defaultFilter': defaultFilter.id,
    'autoCropOnImport': autoCropOnImport,
    'keepOriginals': keepOriginals,
    'fileNamePattern': fileNamePattern.name,
  };

  /// Unknown or missing values fall back to the defaults, so a settings file
  /// from an older or newer version still opens.
  static AppSettings fromJson(Map<String, Object?> json) => AppSettings(
    themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ?? ThemeMode.system,
    defaultFilter: DocumentFilter.fromId(json['defaultFilter'] as String? ?? DocumentFilter.original.id),
    autoCropOnImport: json['autoCropOnImport'] as bool? ?? true,
    keepOriginals: json['keepOriginals'] as bool? ?? true,
    fileNamePattern: FileNamePattern.values.asNameMap()[json['fileNamePattern']] ?? FileNamePattern.dateTime,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.defaultFilter == defaultFilter &&
      other.autoCropOnImport == autoCropOnImport &&
      other.keepOriginals == keepOriginals &&
      other.fileNamePattern == fileNamePattern;

  @override
  int get hashCode => Object.hash(themeMode, defaultFilter, autoCropOnImport, keepOriginals, fileNamePattern);
}
