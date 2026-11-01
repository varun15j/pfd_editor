import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'models.dart';
import 'ocr_languages.dart';
import 'plan.dart';
import 'scan_document.dart';

/// How a new scan is named, and the PDF offered for it in the save sheet.
/// Either can still be renamed, and nothing is renamed when this changes.
enum FileNamePattern {
  scan('Date, time and SCAN'),
  dateTime('Date and time'),
  date('Date only'),
  compact('Compact');

  const FileNamePattern(this.label);
  final String label;

  String format(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    final date = '${t.year}-${two(t.month)}-${two(t.day)}';
    return switch (this) {
      FileNamePattern.scan => scanDocumentName(t),
      FileNamePattern.dateTime => 'Scan $date ${two(t.hour)}.${two(t.minute)}',
      FileNamePattern.date => 'Scan $date',
      FileNamePattern.compact => 'Scan_${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}',
    };
  }

  /// Shown under the option, for 3 October 2026 at 14:30.
  String get example => format(DateTime(2026, 10, 3, 14, 30));
}

/// Photo size the camera takes (More capture settings).
enum CaptureResolution {
  standard('Standard', 'About 2 MP. Smallest files, quickest shots'),
  high('High', 'About 8 MP. Sharp small print; recommended'),
  maximum('Maximum', 'Full sensor. Largest files, slower between shots');

  const CaptureResolution(this.label, this.hint);
  final String label;
  final String hint;
}

/// How long a page must stay still before auto capture takes it.
enum AutoCaptureSteadiness {
  quick('Quick', 3),
  normal('Normal', 5),
  careful('Careful', 8);

  const AutoCaptureSteadiness(this.label, this.frames);
  final String label;

  /// Steady preview frames in a row needed before the photo is taken.
  final int frames;
}

/// How long the app may be away from the screen before the app lock asks
/// again. Every cold start asks.
enum AppLockDelay {
  immediately('Immediately', Duration.zero),
  oneMinute('After 1 minute', Duration(minutes: 1)),
  fiveMinutes('After 5 minutes', Duration(minutes: 5));

  const AppLockDelay(this.label, this.duration);
  final String label;
  final Duration duration;
}

/// Choices the user makes in Settings, kept on the device. Each field says in
/// its comment whether changing it touches files that already exist.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.defaultFilter = DocumentFilter.magicColor,
    this.autoCropOnImport = true,
    this.keepOriginals = true,
    this.fileNamePattern = FileNamePattern.scan,
    this.onboardingSeen = false,
    this.analytics,
    this.captureResolution = CaptureResolution.high,
    this.shutterSound = false,
    this.captureHaptics = true,
    this.autoCaptureSteadiness = AutoCaptureSteadiness.normal,
    this.debugPlan,
    this.ocrLanguage = 'en',
    this.appLock = false,
    this.appLockDelay = AppLockDelay.oneMinute,
  });

  /// Looks only. Does not touch any file.
  final ThemeMode themeMode;

  /// Filter given to pages scanned or imported from now on. Auto colour
  /// unless changed, so every scan is enhanced. Pages already in a document
  /// keep theirs.
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

  /// True once the intro has been shown (finished or skipped). Replaying it
  /// from Settings does not change this.
  final bool onboardingSeen;

  /// Whether the user agreed to share anonymous usage data. Null until they
  /// answer; null and false both mean nothing is shared. Scanning never
  /// depends on the answer.
  final bool? analytics;

  /// Size of the photos the camera takes from now on. Pages already taken
  /// keep theirs.
  final CaptureResolution captureResolution;

  /// Play a click when a photo is taken. Some phones always play their own
  /// shutter sound, whatever this says.
  final bool shutterSound;

  /// Vibrate briefly when a photo is taken.
  final bool captureHaptics;

  /// How long auto capture waits for the page to be still.
  final AutoCaptureSteadiness autoCaptureSteadiness;

  /// Debug builds only: the plan to behave as, to try Basic, Pro and Gold
  /// without buying. Null means the plan the user is really on. Release
  /// builds ignore it.
  final AppPlan? debugPlan;

  /// Language text recognition reads, as a code from [OcrLanguage.all].
  /// Applies to the next read; text already recognised is kept.
  final String ocrLanguage;

  /// Ask for fingerprint, face or the phone's PIN before the app shows
  /// anything. Does not touch any file; saved PDFs open as before in other
  /// apps.
  final bool appLock;

  /// How long the app may be in the background before the lock asks again.
  final AppLockDelay appLockDelay;

  AppSettings copyWith({
    ThemeMode? themeMode,
    DocumentFilter? defaultFilter,
    bool? autoCropOnImport,
    bool? keepOriginals,
    FileNamePattern? fileNamePattern,
    bool? onboardingSeen,
    Object? analytics = _keep,
    CaptureResolution? captureResolution,
    bool? shutterSound,
    bool? captureHaptics,
    AutoCaptureSteadiness? autoCaptureSteadiness,
    Object? debugPlan = _keep,
    String? ocrLanguage,
    bool? appLock,
    AppLockDelay? appLockDelay,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    defaultFilter: defaultFilter ?? this.defaultFilter,
    autoCropOnImport: autoCropOnImport ?? this.autoCropOnImport,
    keepOriginals: keepOriginals ?? this.keepOriginals,
    fileNamePattern: fileNamePattern ?? this.fileNamePattern,
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
    analytics: identical(analytics, _keep) ? this.analytics : analytics as bool?,
    captureResolution: captureResolution ?? this.captureResolution,
    shutterSound: shutterSound ?? this.shutterSound,
    captureHaptics: captureHaptics ?? this.captureHaptics,
    autoCaptureSteadiness: autoCaptureSteadiness ?? this.autoCaptureSteadiness,
    debugPlan: identical(debugPlan, _keep) ? this.debugPlan : debugPlan as AppPlan?,
    ocrLanguage: ocrLanguage ?? this.ocrLanguage,
    appLock: appLock ?? this.appLock,
    appLockDelay: appLockDelay ?? this.appLockDelay,
  );

  static const Object _keep = Object();

  /// Written with the choices. Files without it are from before 2, when
  /// Original was the default filter; before 3, Date and time was the
  /// default file name.
  static const version = 3;

  Map<String, Object?> toJson() => {
    'version': version,
    'themeMode': themeMode.name,
    'defaultFilter': defaultFilter.id,
    'autoCropOnImport': autoCropOnImport,
    'keepOriginals': keepOriginals,
    'fileNamePattern': fileNamePattern.name,
    'onboardingSeen': onboardingSeen,
    if (analytics != null) 'analytics': analytics,
    'captureResolution': captureResolution.name,
    'shutterSound': shutterSound,
    'captureHaptics': captureHaptics,
    'autoCaptureSteadiness': autoCaptureSteadiness.name,
    if (debugPlan != null) 'debugPlan': debugPlan!.name,
    'ocrLanguage': ocrLanguage,
    'appLock': appLock,
    'appLockDelay': appLockDelay.name,
  };

  /// Unknown or missing values fall back to the defaults, so a settings file
  /// from an older or newer version still opens.
  static AppSettings fromJson(Map<String, Object?> json) => AppSettings(
    themeMode: ThemeMode.values.asNameMap()[json['themeMode']] ?? ThemeMode.dark,
    defaultFilter: _filterFromJson(json),
    autoCropOnImport: json['autoCropOnImport'] as bool? ?? true,
    keepOriginals: json['keepOriginals'] as bool? ?? true,
    fileNamePattern: _patternFromJson(json),
    onboardingSeen: json['onboardingSeen'] as bool? ?? false,
    analytics: json['analytics'] as bool?,
    captureResolution: CaptureResolution.values.asNameMap()[json['captureResolution']] ?? CaptureResolution.high,
    shutterSound: json['shutterSound'] as bool? ?? false,
    captureHaptics: json['captureHaptics'] as bool? ?? true,
    autoCaptureSteadiness:
        AutoCaptureSteadiness.values.asNameMap()[json['autoCaptureSteadiness']] ?? AutoCaptureSteadiness.normal,
    debugPlan: AppPlan.values.asNameMap()[json['debugPlan']],
    ocrLanguage: OcrLanguage.byCode(json['ocrLanguage'] as String? ?? '')?.code ?? 'en',
    appLock: json['appLock'] as bool? ?? false,
    appLockDelay: AppLockDelay.values.asNameMap()[json['appLockDelay']] ?? AppLockDelay.oneMinute,
  );

  /// Files before 3 always held Date and time, the default then, chosen or
  /// not; scans are now named like "11-Oct-2026_16-47_SCAN", so those move
  /// to that once.
  static FileNamePattern _patternFromJson(Map<String, Object?> json) {
    final known = FileNamePattern.values.asNameMap()[json['fileNamePattern']];
    final old = ((json['version'] as num?) ?? 0) < 3;
    if (known == null || (old && known == FileNamePattern.dateTime)) return FileNamePattern.scan;
    return known;
  }

  /// Older files always held Original, the default then, chosen or not; scans
  /// are now enhanced by default, so those move to Auto colour once.
  static DocumentFilter _filterFromJson(Map<String, Object?> json) {
    final id = json['defaultFilter'] as String?;
    final old = (json['version'] as num?) == null;
    final known = DocumentFilter.values.where((f) => f.id == id).firstOrNull;
    if (known == null || (old && known == DocumentFilter.original)) return DocumentFilter.magicColor;
    return known;
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.defaultFilter == defaultFilter &&
      other.autoCropOnImport == autoCropOnImport &&
      other.keepOriginals == keepOriginals &&
      other.fileNamePattern == fileNamePattern &&
      other.onboardingSeen == onboardingSeen &&
      other.analytics == analytics &&
      other.captureResolution == captureResolution &&
      other.shutterSound == shutterSound &&
      other.captureHaptics == captureHaptics &&
      other.autoCaptureSteadiness == autoCaptureSteadiness &&
      other.debugPlan == debugPlan &&
      other.ocrLanguage == ocrLanguage &&
      other.appLock == appLock &&
      other.appLockDelay == appLockDelay;

  @override
  int get hashCode => Object.hash(
    themeMode,
    defaultFilter,
    autoCropOnImport,
    keepOriginals,
    fileNamePattern,
    onboardingSeen,
    analytics,
    captureResolution,
    shutterSound,
    captureHaptics,
    autoCaptureSteadiness,
    debugPlan,
    ocrLanguage,
    appLock,
    appLockDelay,
  );
}
