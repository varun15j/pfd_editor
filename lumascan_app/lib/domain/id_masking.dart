import 'package:flutter/foundation.dart';

import 'ocr.dart';

/// The kinds of private number Auto mask looks for. Each keeps its last
/// [visible] characters readable, the way UIDAI's masked Aadhaar shows only
/// the last four digits; a date of birth and a passport's machine-readable
/// lines are hidden whole.
enum IdKind {
  aadhaar('Aadhaar number'),
  vid('Aadhaar VID'),
  pan('PAN'),
  voterId('Voter ID'),
  passport('Passport number'),
  passportMrz('Passport machine-readable lines', visible: 0),
  drivingLicence('Driving licence number'),
  ssn('Social Security number'),
  card('Card number'),
  nationalId('ID number'),
  dateOfBirth('Date of birth', visible: 0);

  const IdKind(this.label, {this.visible = 4});

  final String label;

  /// Characters left readable at the end.
  final int visible;
}

/// One box of a mask, as fractions of the page (0 to 1). [chars] is how many
/// characters it hides: each is drawn over with an X. 0 means the text could
/// not be read, and the box is filled solid black instead.
@immutable
class IdPiece {
  const IdPiece({required this.left, required this.top, required this.right, required this.bottom, this.chars = 0});

  final double left;
  final double top;
  final double right;
  final double bottom;
  final int chars;

  @override
  String toString() => 'IdPiece(${left.toStringAsFixed(3)}..${right.toStringAsFixed(3)}, x$chars)';
}

/// A private number found on a page, and the boxes that hide it. A number
/// printed in groups ("2345 6789 0120") gets one box per hidden group, so
/// the Xs sit on the digits and not on the spaces between them.
@immutable
class IdMatch {
  const IdMatch({required this.kind, required this.text, required this.pieces});

  final IdKind kind;

  /// The number as read, with OCR look-alikes fixed (O to 0 and so on).
  /// Empty when a label such as "DOB" was found but what follows it could
  /// not be read.
  final String text;
  final List<IdPiece> pieces;

  /// The text could not be read, so the pieces are solid boxes.
  bool get unreadable => pieces.every((p) => p.chars == 0);

  double get left => pieces.map((p) => p.left).reduce((a, b) => a < b ? a : b);
  double get top => pieces.map((p) => p.top).reduce((a, b) => a < b ? a : b);
  double get right => pieces.map((p) => p.right).reduce((a, b) => a > b ? a : b);
  double get bottom => pieces.map((p) => p.bottom).reduce((a, b) => a > b ? a : b);

  @override
  String toString() => 'IdMatch(${kind.name}, $text, $pieces)';
}

/// Finds private numbers in the text read from a page and works out the
/// boxes that hide all but their last four characters.
///
/// Three passes, line by line:
///
/// 1. **Shapes that are IDs on their own**: Aadhaar and VID in groups or
///    passing the Verhoeff check, card numbers passing the Luhn check, US
///    Social Security numbers, PAN, Indian voter ID, passport and driving
///    licence numbers, UK National Insurance numbers, and the
///    machine-readable lines at the foot of a passport.
/// 2. **Labels**: words such as "DOB", "Passport No", "ID Number", "SSN" or
///    "Card No" mark what follows them on the line (or the line below, when
///    the label ends its line) as private, in any country's format.
/// 3. **Unreadable after a label**: when a label is followed by something
///    with digits in it that is not a clean number, that part of the line is
///    hidden with a solid box instead, so a misread number is still covered.
///
/// When the engine gives no word boxes, they are estimated from the line's
/// box and the position of each letter.
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
      for (var i = 0; i < lines.length; i++) {
        out.addAll(findInLine(lines[i], next: i + 1 < lines.length ? lines[i + 1] : null));
      }
    }
    return out;
  }

  /// The matches in one line. [next] is the line below in the same block,
  /// read for the value when a label ends this line. Public for tests.
  List<IdMatch> findInLine(OcrLine line, {OcrLine? next}) {
    final words = line.words.isNotEmpty ? line.words : estimateWords(line);
    final mrz = _mrz(line, words);
    if (mrz != null) return [mrz];
    final out = <IdMatch>[];
    final used = <int>{};
    var i = 0;
    while (i < words.length) {
      final hit = _matchAt(words, i);
      if (hit == null) {
        i++;
        continue;
      }
      out.add(hit.$1);
      for (var k = i; k < i + hit.$2; k++) {
        used.add(k);
      }
      i += hit.$2;
    }
    out.addAll(_byLabel(words, used, next));
    return out;
  }

  // ---- Pass 1: shapes that are IDs on their own ----

  /// The ID starting at word [i], and how many words it takes.
  (IdMatch, int)? _matchAt(List<OcrBox> words, int i) {
    // Grouped digits first, longest first.
    final groups = <String>[];
    for (var k = i; k < words.length && k < i + 5; k++) {
      final d = digitsOf(words[k].text);
      if (d == null) break;
      groups.add(d);
    }
    for (var n = groups.length; n >= 2; n--) {
      final parts = groups.sublist(0, n);
      final kind = _groupedKind(parts);
      if (kind != null) return (_grouped(kind, parts, words.sublist(i, i + n)), n);
    }

    final word = words[i];
    final raw = word.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final digits = digitsOf(word.text);
    if (digits != null) {
      // One long run of digits could be any number, so it must also pass a
      // check digit.
      if (digits.length == 16 && _aadhaarLike(digits) && verhoeffValid(digits)) {
        return (_partOf(IdKind.vid, digits, word), 1);
      }
      if (digits.length == 12 && _aadhaarLike(digits) && verhoeffValid(digits)) {
        return (_partOf(IdKind.aadhaar, digits, word), 1);
      }
      if (_cardLike(digits)) return (_partOf(IdKind.card, digits, word), 1);
      if (RegExp(r'^\d{3}-\d{2}-\d{4}$').hasMatch(word.text.trim()) && _ssnValid(digits)) {
        return (_partOf(IdKind.ssn, digits, word), 1);
      }
    }
    final upper = raw.toUpperCase();
    final pan = _panFixed(upper);
    if (RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan)) return (_partOf(IdKind.pan, pan, word), 1);
    if (RegExp(r'^[A-Z]{3}[0-9]{7}$').hasMatch(upper)) return (_partOf(IdKind.voterId, upper, word), 1);
    if (RegExp(r'^[A-Z][0-9]{7}$').hasMatch(upper)) return (_partOf(IdKind.passport, upper, word), 1);
    // UK National Insurance number, such as QQ123456C.
    if (RegExp(r'^[A-CEGHJ-PR-TW-Z]{2}[0-9]{6}[A-D]$').hasMatch(upper)) {
      return (_partOf(IdKind.nationalId, upper, word), 1);
    }
    // Driving licence: state code, RTO code, year and a serial, often split
    // as "MH12 20110012345" or written as one word.
    if (RegExp(r'^[A-Z]{2}[0-9]{2}$').hasMatch(upper) && i + 1 < words.length) {
      final next = digitsOf(words[i + 1].text);
      if (next != null && next.length == 11) {
        return (_split(IdKind.drivingLicence, upper, next, word, words[i + 1]), 2);
      }
    }
    if (RegExp(r'^[A-Z]{2}[0-9]{13}$').hasMatch(upper)) return (_partOf(IdKind.drivingLicence, upper, word), 1);
    return null;
  }

  /// What a run of digit groups is, by the length of each group.
  static IdKind? _groupedKind(List<String> parts) {
    final all = parts.join();
    final shape = parts.map((p) => p.length).join('-');
    switch (shape) {
      case '4-4-4-4':
        // A card number passes the Luhn check; a VID the Verhoeff check.
        if (_cardLike(all) && !verhoeffValid(all)) return IdKind.card;
        return _aadhaarLike(all) ? IdKind.vid : (_cardLike(all) ? IdKind.card : null);
      case '4-4-4':
        return _aadhaarLike(all) ? IdKind.aadhaar : null;
      case '4-6-5': // American Express
      case '4-6-4': // Diners Club
      case '4-4-4-4-3':
        return _cardLike(all) ? IdKind.card : null;
      case '3-2-4':
        return _ssnValid(all) ? IdKind.ssn : null;
    }
    return null;
  }

  /// Aadhaar and VID numbers never start with 0 or 1. Grouped numbers need
  /// nothing more: a misread digit would fail the check digit, and the
  /// grouped format is strong enough on its own.
  static bool _aadhaarLike(String digits) => !digits.startsWith('0') && !digits.startsWith('1');

  /// A payment card number: 13 to 19 digits, a known first digit, and a
  /// valid Luhn check digit.
  static bool _cardLike(String digits) =>
      digits.length >= 13 && digits.length <= 19 && RegExp(r'^[2-6]').hasMatch(digits) && luhnValid(digits);

  /// US Social Security numbers never start with 000, 666 or 9, and never
  /// have 00 or 0000 in the other groups.
  static bool _ssnValid(String digits) {
    if (digits.length != 9) return false;
    final area = digits.substring(0, 3), group = digits.substring(3, 5), serial = digits.substring(5);
    return area != '000' && area != '666' && !area.startsWith('9') && group != '00' && serial != '0000';
  }

  /// The passport's machine-readable lines ("P<INDKUMAR<<A..."), hidden
  /// whole: they repeat the number, name and date of birth.
  IdMatch? _mrz(OcrLine line, List<OcrBox> words) {
    final t = line.text.replaceAll(' ', '').toUpperCase();
    if (t.length < 28 || '<'.allMatches(t).length < 3 || !RegExp(r'^[A-Z0-9<«]+$').hasMatch(t)) return null;
    return IdMatch(
      kind: IdKind.passportMrz,
      text: t,
      pieces: [
        _piece(line.left, line.right, [line], t.length),
      ],
    );
  }

  // ---- Pass 2 and 3: labels ----

  static final _dobLabel = RegExp(
    r'(\bd\.?\s?o\.?\s?b\b|date\s+of\s+birth|birth\s*date|\bborn\b|\by\.?o\.?b\b|year\s+of\s+birth|'
    r'geburtsdatum|date\s+de\s+naissance|fecha\s+de\s+nacimiento|जन्म)',
    caseSensitive: false,
  );

  static final _idLabel = RegExp(
    r'(passport\s*(no|number|#)?|document\s*(no|number|#)|\bid\s*(no|number|#)|identity\s*(card)?\s*(no|number)?|'
    r'national\s*(id|insurance)|social\s+security|\bssn\b|\bsin\b|\bnin\b|\bnino\b|\btin\b|tax\s*(id|no|number)|'
    r'\bnic\b|\bcnic\b|licen[cs]e\s*(no|number|#)|\bdl\s*no|card\s*(no|number|#)|account\s*(no|number|#)|'
    r'\ba/?c\s*no|aadhaa?r|\buid\b|\bvid\b|permanent\s+account|\bepic\b|personal\s*(no|number)|'
    r'personalausweis|ausweis|numéro|n[º°o]\.?\s*(de\s+)?(documento|pasaporte|passeport))',
    caseSensitive: false,
  );

  /// Values marked private by a label on the line, such as "DOB: 01/01/1990"
  /// or "Passport No. X1234567". Words already matched in pass 1 are left.
  List<IdMatch> _byLabel(List<OcrBox> words, Set<int> used, OcrLine? next) {
    final out = <IdMatch>[];
    final text = words.map((w) => w.text).join(' ');
    for (final (label, kind) in [(_dobLabel, IdKind.dateOfBirth), (_idLabel, IdKind.nationalId)]) {
      // The last label on the line is the one next to the value, as in
      // "जन्म तिथि/DOB: 01/01/1990".
      final all = label.allMatches(text);
      if (all.isEmpty) continue;
      final m = all.last;
      // The first word after the label: count words up to the label's end.
      final after = _wordIndexAfter(words, m.end);
      // Pass 1 already hid the number after this label.
      if (used.any((k) => k >= after)) continue;
      var value = [for (var k = after; k < words.length; k++) k];
      var source = words;
      if (value.isEmpty && next != null) {
        // "Passport No." on its own line: the number is on the line below.
        source = next.words.isNotEmpty ? next.words : estimateWords(next);
        value = [for (var k = 0; k < source.length; k++) k];
      }
      final hit = kind == IdKind.dateOfBirth ? _date(source, value) : _labelledId(source, value);
      if (hit != null) out.add(hit);
    }
    return out;
  }

  /// The index of the first word after the character offset [end] of the
  /// words joined with spaces. A word the label ends inside ("DOB:01/01/1990")
  /// counts when the rest of it holds a digit.
  static int _wordIndexAfter(List<OcrBox> words, int end) {
    var pos = 0;
    for (var k = 0; k < words.length; k++) {
      final start = pos, stop = pos + words[k].text.length;
      if (start >= end) return k;
      if (stop > end) return RegExp(r'[0-9]').hasMatch(words[k].text.substring(end - start)) ? k : k + 1;
      pos = stop + 1;
    }
    return words.length;
  }

  static final _dateShapes = [
    RegExp(r'^\d{1,2}[/.\-]\d{1,2}[/.\-]\d{2,4}$'),
    RegExp(r'^\d{4}[/.\-]\d{1,2}[/.\-]\d{1,2}$'),
    RegExp(r'^\d{8}$'),
    RegExp(r'^(19|20)\d{2}$'), // year of birth alone
  ];

  static final _month = RegExp(
    r'^(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?$',
    caseSensitive: false,
  );

  /// A date of birth in [value] words of [words], hidden whole.
  IdMatch? _date(List<OcrBox> words, List<int> value) {
    if (value.isEmpty) return null;
    String clean(int k) {
      final t = words[k].text;
      // "DOB:01/01/1990" in one word: the date is after the colon.
      final colon = t.lastIndexOf(':');
      return (colon >= 0 ? t.substring(colon + 1) : t).replaceAll(RegExp(r'^[\-,]+|[,;.]+$'), '');
    }

    final first = value.first;
    final one = clean(first);
    if (_dateShapes.any((r) => r.hasMatch(_digitsFixed(one)))) {
      return IdMatch(
        kind: IdKind.dateOfBirth,
        text: one,
        pieces: [
          _piece(words[first].left, words[first].right, [words[first]], one.length),
        ],
      );
    }
    // "12 Jan 1990" or "Jan 12, 1990" as three words.
    if (value.length >= 3 && value[1] == first + 1 && value[2] == first + 2) {
      final a = clean(first), b = clean(first + 1), c = clean(first + 2);
      final dayMonthYear = RegExp(r'^\d{1,2}$').hasMatch(a) && _month.hasMatch(b) && RegExp(r'^\d{4}$').hasMatch(c);
      final monthDayYear = _month.hasMatch(a) && RegExp(r'^\d{1,2}$').hasMatch(b) && RegExp(r'^\d{4}$').hasMatch(c);
      if (dayMonthYear || monthDayYear) {
        final span = [words[first], words[first + 1], words[first + 2]];
        return IdMatch(
          kind: IdKind.dateOfBirth,
          text: '$a $b $c',
          pieces: [
            for (final w in span) _piece(w.left, w.right, [w], w.text.length),
          ],
        );
      }
    }
    return _unreadable(IdKind.dateOfBirth, words, value);
  }

  /// An ID number in [value] words of [words]: the words that hold digits,
  /// up to the first plain word. All but the last four characters hidden.
  IdMatch? _labelledId(List<OcrBox> words, List<int> value) {
    final run = <int>[];
    for (final k in value) {
      if (run.isNotEmpty && k != run.last + 1) break;
      final t = words[k].text.replaceAll(RegExp(r'^[:#.\-]+'), '');
      if (t.isEmpty) continue;
      final hasDigit = RegExp(r'[0-9]').hasMatch(t);
      final idLike = RegExp(r'^[A-Za-z0-9\-/]+$').hasMatch(t);
      if (!hasDigit && run.isEmpty && RegExp(r'^[A-Za-z]{1,3}$').hasMatch(t)) {
        // A short code before the number, such as "ABC 1234567": keep it in.
        run.add(k);
        continue;
      }
      if (!hasDigit || !idLike) break;
      run.add(k);
    }
    // Leading letters only, with no digits after them, are not a number.
    final withDigits = run.where((k) => RegExp(r'[0-9]').hasMatch(words[k].text)).toList();
    if (withDigits.isEmpty) return _unreadable(IdKind.nationalId, words, value);
    final pieces = run.map((k) => words[k]).toList();
    final text = pieces.map((w) => w.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')).join();
    if (text.length < 5) return _unreadable(IdKind.nationalId, words, value);
    return _spread(IdKind.nationalId, text, pieces);
  }

  /// A solid box over [value] when it holds something like a number that
  /// could not be read cleanly, such as "2O1/1?/19B9". Null when there is
  /// nothing number-like there at all.
  IdMatch? _unreadable(IdKind kind, List<OcrBox> words, List<int> value) {
    final run = <int>[];
    for (final k in value) {
      if (run.isNotEmpty && k != run.last + 1) break;
      final t = words[k].text;
      final digitish = RegExp(r'[0-9OoIl|SBZ/\-]').allMatches(t).length;
      if (!RegExp(r'[0-9]').hasMatch(t) && digitish < t.length) break;
      run.add(k);
    }
    if (run.isEmpty) return null;
    final span = [for (final k in run) words[k]];
    return IdMatch(kind: kind, text: '', pieces: [_piece(span.first.left, span.last.right, span, 0)]);
  }

  // ---- Boxes ----

  /// A number in groups: one box per hidden group, and a part of the group
  /// where the visible characters start.
  IdMatch _grouped(IdKind kind, List<String> parts, List<OcrBox> words) =>
      _spread(kind, parts.join(), words, chars: parts.map((p) => p.length).toList());

  /// Hides all but the last [IdKind.visible] characters of [text], spread
  /// over [words] in order. [chars] is how many characters each word holds,
  /// counted from its own text when not given.
  IdMatch _spread(IdKind kind, String text, List<OcrBox> words, {List<int>? chars}) {
    final counts = chars ?? [for (final w in words) w.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length];
    var hide = text.length - kind.visible;
    final pieces = <IdPiece>[];
    for (var k = 0; k < words.length && hide > 0; k++) {
      final w = words[k], n = counts[k];
      if (n == 0) continue;
      final take = hide < n ? hide : n;
      final cut = w.left + (w.right - w.left) * take / n;
      pieces.add(_piece(w.left, cut, [w], take));
      hide -= take;
    }
    return IdMatch(kind: kind, text: text, pieces: pieces);
  }

  /// The box over all but the last four characters of a one-word ID.
  IdMatch _partOf(IdKind kind, String text, OcrBox word) => _spread(kind, text, [word], chars: [text.length]);

  /// A driving licence split over two words, such as "MH12 20110012345".
  IdMatch _split(IdKind kind, String first, String second, OcrBox a, OcrBox b) =>
      _spread(kind, '$first$second', [a, b], chars: [first.length, second.length]);

  IdPiece _piece(double left, double right, List<OcrBox> boxes, int chars) {
    var top = boxes.first.top, bottom = boxes.first.bottom;
    for (final w in boxes) {
      if (w.top < top) top = w.top;
      if (w.bottom > bottom) bottom = w.bottom;
    }
    final grow = (bottom - top) * pad;
    return IdPiece(
      left: (left - grow).clamp(0.0, 1.0),
      top: (top - grow).clamp(0.0, 1.0),
      right: right.clamp(0.0, 1.0),
      bottom: (bottom + grow).clamp(0.0, 1.0),
      chars: chars,
    );
  }

  /// [s] with letters OCR often reads for digits turned into digits, for
  /// matching dates.
  static String _digitsFixed(String s) => s.split('').map((c) => _digitLookAlikes[c] ?? c).join();

  /// The Luhn check used by payment card numbers.
  static bool luhnValid(String digits) {
    var sum = 0;
    for (var i = 0; i < digits.length; i++) {
      var d = int.parse(digits[digits.length - 1 - i]);
      if (i.isOdd) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
    }
    return sum % 10 == 0;
  }

  /// The digits of [text] with OCR look-alikes fixed, or null when it is
  /// not a number. Dashes, dots and stray punctuation are ignored.
  static String? digitsOf(String text) {
    final s = text.replaceAll(RegExp(r'[\s\-.,:;]'), '');
    if (s.isEmpty) return null;
    // Plain digits, even a short group such as the "45" of an SSN.
    if (RegExp(r'^[0-9]+$').hasMatch(s)) return s;
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
      return [for (var k = 0; k < 5; k++) letter(s[k]), for (var k = 5; k < 9; k++) digit(s[k]), letter(s[9])].join();
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
