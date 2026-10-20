import 'package:flutter/foundation.dart';

/// What a profiled step was.
enum ProfileKind {
  /// The full photo decoded once into its working copies.
  workingCopy('working_copy', 'Working copies from photo'),

  /// A thumbnail (480 px or smaller) rendered with the page's edits.
  thumbnail('thumbnail', 'Thumbnail render'),

  /// A larger preview rendered with the page's edits or an effect.
  preview('preview', 'Preview render'),

  /// A picture appearing on screen, from asking to showing, wherever it came
  /// from (rendered now, read from disk, or already in memory).
  shown('shown', 'Picture shown on screen');

  const ProfileKind(this.id, this.label);

  final String id;
  final String label;

  static ProfileKind fromId(String id) => values.firstWhere((k) => k.id == id, orElse: () => shown);
}

/// Where a shown picture came from.
enum ProfileOrigin {
  rendered('rendered', 'Rendered'),
  disk('disk', 'From disk'),
  memory('memory', 'In memory');

  const ProfileOrigin(this.id, this.label);

  final String id;
  final String label;

  static ProfileOrigin? fromId(String? id) => values.where((o) => o.id == id).firstOrNull;
}

/// The steps a render is split into, in pipeline order.
const profileStages = ['read', 'decode', 'convert', 'resize', 'crop', 'filter', 'adjust', 'encode', 'write'];

/// One measured picture load or render.
@immutable
class ProfileSample {
  const ProfileSample({
    required this.at,
    required this.kind,
    required this.totalMs,
    this.screen,
    this.pageId,
    this.origin,
    this.filter,
    this.sourceBytes = 0,
    this.width = 0,
    this.height = 0,
    this.maxDimension = 0,
    this.waitMs = 0,
    this.stageMs = const {},
  });

  final DateTime at;
  final ProfileKind kind;

  /// The screen the picture was shown on, for [ProfileKind.shown].
  final String? screen;
  final String? pageId;
  final ProfileOrigin? origin;

  /// The filter applied, by id.
  final String? filter;

  /// Size of the file the picture was made from.
  final int sourceBytes;
  final int width;
  final int height;
  final int maxDimension;

  /// Time spent waiting for a free render slot.
  final double waitMs;

  /// From asking for the picture to having it.
  final double totalMs;

  /// Time per step, keyed by [profileStages].
  final Map<String, double> stageMs;

  double get sourceMb => sourceBytes / (1024 * 1024);

  static Map<String, double> stagesFromMicros(Map<String, int> micros) => {
    for (final e in micros.entries) e.key: e.value / 1000,
  };
}

/// Averages for one kind of step (and screen, for shown pictures).
@immutable
class ProfileSummaryRow {
  const ProfileSummaryRow({
    required this.kind,
    required this.screen,
    required this.count,
    required this.avgMs,
    required this.minMs,
    required this.maxMs,
    required this.avgWaitMs,
    required this.avgSourceMb,
    required this.avgStageMs,
  });

  final ProfileKind kind;
  final String? screen;
  final int count;
  final double avgMs;
  final double minMs;
  final double maxMs;
  final double avgWaitMs;
  final double avgSourceMb;
  final Map<String, double> avgStageMs;
}

/// Formats a duration for the debug labels: "85 ms" or "1.24 s".
String formatProfileMs(double ms) => ms < 1000 ? '${ms.round()} ms' : '${(ms / 1000).toStringAsFixed(2)} s';
