import 'package:flutter/foundation.dart';

import 'models.dart';

/// What a saved mark is: a full signature or just initials. Initials are
/// placed smaller.
enum SignatureKind {
  signature('Signature', 0.35),
  initials('Initials', 0.15);

  const SignatureKind(this.label, this.placedWidth);

  final String label;

  /// Width of the placed box as a fraction of the page width.
  final double placedWidth;
}

/// A signature or initials drawn once and kept on the device, so it can be
/// placed again without drawing. Strokes are normalized to the mark's own
/// box, as in a placed signature.
@immutable
class SavedSignature {
  const SavedSignature({
    required this.id,
    required this.kind,
    required this.strokes,
    required this.aspectRatio,
    required this.createdAt,
  });

  final String id;
  final SignatureKind kind;
  final List<List<NormPoint>> strokes;

  /// Width over height of the mark's box.
  final double aspectRatio;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'strokes': [
      for (final s in strokes) [for (final p in s) p.toJson()],
    ],
    'aspectRatio': aspectRatio,
    'createdAt': createdAt.toIso8601String(),
  };

  static SavedSignature fromJson(Map<String, Object?> json) => SavedSignature(
    id: json['id']! as String,
    kind: SignatureKind.values.asNameMap()[json['kind']] ?? SignatureKind.signature,
    strokes: [
      for (final s in json['strokes']! as List) [for (final p in s as List) NormPoint.fromJson(p)],
    ],
    aspectRatio: (json['aspectRatio']! as num).toDouble(),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// The saved signatures and initials, newest first, and the name used by
/// the name stamp.
@immutable
class SignatureLibrary {
  const SignatureLibrary({this.signatures = const [], this.stampName = ''});

  /// Most marks kept; saving one more drops the oldest.
  static const maxSaved = 12;

  final List<SavedSignature> signatures;
  final String stampName;

  SignatureLibrary copyWith({List<SavedSignature>? signatures, String? stampName}) =>
      SignatureLibrary(signatures: signatures ?? this.signatures, stampName: stampName ?? this.stampName);

  /// [s] added at the front, keeping at most [maxSaved].
  SignatureLibrary withSaved(SavedSignature s) =>
      copyWith(signatures: [s, ...signatures].take(maxSaved).toList(growable: false));

  SignatureLibrary without(String id) => copyWith(
    signatures: [
      for (final s in signatures)
        if (s.id != id) s,
    ],
  );

  Map<String, Object?> toJson() => {
    'signatures': [for (final s in signatures) s.toJson()],
    if (stampName.isNotEmpty) 'stampName': stampName,
  };

  /// Reads a saved library, skipping marks that cannot be read.
  static SignatureLibrary fromJson(Map<String, Object?> json) {
    final out = <SavedSignature>[];
    for (final item in (json['signatures'] as List?) ?? const []) {
      try {
        out.add(SavedSignature.fromJson((item as Map).cast<String, Object?>()));
      } catch (_) {
        // Skip a damaged mark.
      }
    }
    return SignatureLibrary(signatures: out, stampName: (json['stampName'] as String?) ?? '');
  }
}

/// What a stamp writes on the page.
enum StampKind {
  date('Date'),
  name('Name'),
  nameAndDate('Name and date');

  const StampKind(this.label);

  final String label;

  bool get needsName => this != StampKind.date;

  /// The stamp's text for [name] on [day].
  String text({required String name, required DateTime day}) => switch (this) {
    StampKind.date => stampDate(day),
    StampKind.name => name.trim(),
    StampKind.nameAndDate => '${name.trim()}\n${stampDate(day)}',
  };
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// [day] as written on a date stamp, such as "27 Oct 2026". The month is a
/// word so the date reads the same in every country.
String stampDate(DateTime day) => '${day.day} ${_months[day.month - 1]} ${day.year}';
