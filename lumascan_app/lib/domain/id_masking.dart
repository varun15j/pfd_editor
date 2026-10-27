import 'package:flutter/foundation.dart';

import 'ocr.dart';

/// The kinds of ID number Auto mask looks for. Each keeps its last
/// [visible] characters readable, the way UIDAI's masked Aadhaar shows only
/// the last four digits.
enum IdKind {
  aadhaar('Aadhaar number'),
  vid('Aadhaar VID'),
  pan('PAN'),
  voterId('Voter ID'),
  passport('Passport number'),
  drivingLicence('Driving licence number');

  const IdKind(this.label);

  final String label;

  int get visible => 4;
}

/// Where an ID number was found and the part of it to hide, as fractions of
/// the page (0 to 1).
@immutable
class IdMatch {
  const IdMatch({
    required this.kind,
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final IdKind kind;

  /// The number as read, with OCR look-alikes fixed (O to 0 and so on).
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  String toString() => 'IdMatch(${kind.name}, $text)';
}

/// Finds ID numbers in the text read from a page and works out the box that
/// hides all but their last four characters.
///
/// It looks at each line on its own. Aadhaar numbers are printed in groups
/// ("2345 6789 0123"), so a line is read as words, and a run of words that
/// together make an ID is one match. When the engine gives no word boxes,
/// they are estimated from the line's box and the position of each letter.
class IdNumberFinder {
  const IdNumberFinder();

  /// Extra room around a mask, as a fraction of the text height, so the
  /// edges of the characters are covered too.
  static const pad = 0.12;

  List<IdMatch> find(OcrLayout layout) {
    final out = <IdMatch>[];
    for (final block in layout.blocks) {
      final lines = block.lines.isEmpty
          ? [OcrLine(text: block.text, left: block.left, top: block.top, right: block.right, bottom: block.bottom)]
          : block.lines;
      for (final line in lines) {
        out.addAll(findInLine(line));
      }
    }
    return out;
  }

  /// The matches in one line. Public for tests.
  List<IdMatch> findInLine(OcrLine line) {
    final words = line.words.isNotEmpty ? line.words : estimateWords(line);
    final out = <IdMatch>[];
    var i = 0;
    while (i < words.length) {
      final hit = _matchAt(words, i);
      if (hit == null) {
        i++;
        continue;
      }
      out.add(hit.$1);
      i += hit.$2;
    }
    return out;
  }

  /// The ID starting at word [i], and how many words it takes.
  (IdMatch, int)? _matchAt(List<OcrBox> words, int i) {
    // Grouped digits first: 4+4+4+4 (VID) before 4+4+4 (Aadhaar).
    for (final (kind, groups) in const [(IdKind.vid, 4), (IdKind.aadhaar, 3)]) {
      if (i + groups > words.length) continue;
      final parts = [for (var k = 0; k < groups; k++) digitsOf(words[i + k].text)];
      if (parts.every((p) => p != null && p.length == 4) && _plausible(kind, parts.join())) {
        // Hide every group but the last.
        return (_box(kind, parts.join(), words.sublist(i, i + groups - 1)), groups);
      }
    }
    final word = words[i];
    final raw = word.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final digits = digitsOf(word.text);
    // One long run of digits could be any number, so it must also pass the
    // check digit.
    if (digits != null && digits.length == 16 && _plausible(IdKind.vid, digits) && verhoeffValid(digits)) {
      return (_partOf(IdKind.vid, digits, word), 1);
    }
    if (digits != null && digits.length == 12 && _plausible(IdKind.aadhaar, digits) && verhoeffValid(digits)) {
      return (_partOf(IdKind.aadhaar, digits, word), 1);
    }
    final upper = raw.toUpperCase();
    final pan = _panFixed(upper);
    if (RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan)) return (_partOf(IdKind.pan, pan, word), 1);
    if (RegExp(r'^[A-Z]{3}[0-9]{7}$').hasMatch(upper)) return (_partOf(IdKind.voterId, upper, word), 1);
    if (RegExp(r'^[A-Z][0-9]{7}$').hasMatch(upper)) return (_partOf(IdKind.passport, upper, word), 1);
    // Driving licence: state code, RTO code, year and a serial, often split
    // as "MH12 20110012345" or written as one word.
    if (RegExp(r'^[A-Z]{2}[0-9]{2}$').hasMatch(upper) && i + 1 < words.length) {
      final next = digitsOf(words[i + 1].text);
      if (next != null && next.length == 11) {
        final all = '$upper$next';
        final hidden = all.length - IdKind.drivingLicence.visible;
        // All of the first word and the start of the second.
        final second = words[i + 1];
        final cut = second.left + (second.right - second.left) * (hidden - upper.length) / next.length;
        return (_rect(IdKind.drivingLicence, all, word.left, cut, [word, second]), 2);
      }
    }
    if (RegExp(r'^[A-Z]{2}[0-9]{13}$').hasMatch(upper)) return (_partOf(IdKind.drivingLicence, upper, word), 1);
    return null;
  }

  /// Aadhaar and VID numbers never start with 0 or 1. Grouped numbers need
  /// nothing more: a misread digit would fail the check digit, and the
  /// grouped format is strong enough on its own.
  static bool _plausible(IdKind kind, String digits) => !digits.startsWith('0') && !digits.startsWith('1');

  /// The box over [words], whole.
  IdMatch _box(IdKind kind, String text, List<OcrBox> words) =>
      _rect(kind, text, words.first.left, words.last.right, words);

  /// The box over all but the last four characters of a one-word ID.
  IdMatch _partOf(IdKind kind, String text, OcrBox word) {
    final hidden = text.length - kind.visible;
    final cut = word.left + (word.right - word.left) * hidden / text.length;
    return _rect(kind, text, word.left, cut, [word]);
  }

  IdMatch _rect(IdKind kind, String text, double left, double right, List<OcrBox> words) {
    var top = words.first.top, bottom = words.first.bottom;
    for (final w in words) {
      if (w.top < top) top = w.top;
      if (w.bottom > bottom) bottom = w.bottom;
    }
    final grow = (bottom - top) * pad;
    return IdMatch(
      kind: kind,
      text: text,
      left: (left - grow).clamp(0.0, 1.0),
      top: (top - grow).clamp(0.0, 1.0),
      right: right.clamp(0.0, 1.0),
      bottom: (bottom + grow).clamp(0.0, 1.0),
    );
  }

  /// The digits of [text] with OCR look-alikes fixed, or null when it is
  /// not a number. Dashes, dots and stray punctuation are ignored.
  static String? digitsOf(String text) {
    final s = text.replaceAll(RegExp(r'[\s\-.,:;]'), '');
    if (s.isEmpty) return null;
    final real = RegExp(r'[0-9]').allMatches(s).length;
    // Mostly digits: allow a misread letter or two, never a word.
    if (real < s.length - 2 || real < 3) return null;
    final fixed = s.split('').map((c) => _digitLookAlikes[c] ?? c).join();
    return RegExp(r'^[0-9]+$').hasMatch(fixed) ? fixed : null;
  }

  static const _digitLookAlikes = {
    'O': '0', 'o': '0', 'D': '0', 'Q': '0', //
    'I': '1', 'l': '1', 'i': '1', '|': '1', '!': '1',
    'Z': '2', 'z': '2', 'S': '5', 's': '5', 'B': '8', 'b': '6', 'g': '9', 'q': '9',
  };

  /// A PAN is five letters, four digits and a letter. This fixes digits read
  /// where letters must be and letters read where digits must be, in those
  /// places only, and leaves anything that is not PAN-shaped alone.
  static String _panFixed(String s) {
    if (s.length == 10 && RegExp(r'^[A-Z05189IS]{5}[0-9OISB]{4}[A-Z05189IS]$').hasMatch(s)) {
      String letter(String c) => const {'0': 'O', '1': 'I', '5': 'S', '8': 'B'}[c] ?? c;
      String digit(String c) => const {'O': '0', 'I': '1', 'S': '5'}[c] ?? c;
      return [
        for (var k = 0; k < 5; k++) letter(s[k]),
        for (var k = 5; k < 9; k++) digit(s[k]),
        letter(s[9]),
      ].join();
    }
    return s;
  }

  /// Word boxes made from a line's box, by the share of the line's letters
  /// before and in each word. Public for tests.
  static List<OcrBox> estimateWords(OcrLine line) {
    final text = line.text;
    if (text.isEmpty) return const [];
    final width = line.right - line.left;
    return [
      for (final m in RegExp(r'\S+').allMatches(text))
        OcrBox(
          text: m.group(0)!,
          left: line.left + width * m.start / text.length,
          top: line.top,
          right: line.left + width * m.end / text.length,
          bottom: line.bottom,
        ),
    ];
  }

  /// The Verhoeff check UIDAI uses for the last digit of an Aadhaar number.
  static bool verhoeffValid(String digits) {
    var c = 0;
    final reversed = digits.split('').reversed.toList();
    for (var i = 0; i < reversed.length; i++) {
      c = _d[c][_p[i % 8][int.parse(reversed[i])]];
    }
    return c == 0;
  }

  static const _d = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
    [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
    [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
    [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
    [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
    [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
    [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
    [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
    [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
  ];

  static const _p = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
    [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
    [5, 8, 0, 3, 7, 9, 6, 1, 2, 4],
    [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
    [9, 4, 5, 3, 1, 2, 7, 6, 8, 0],
    [4, 3, 6, 9, 5, 7, 0, 2, 1, 8],
    [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
    [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
  ];
}
