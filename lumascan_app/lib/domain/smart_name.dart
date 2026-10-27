/// Auto file naming (improvement.md #7): a name for a scan suggested from
/// the text on its first page, like "Invoice INV-2041 2026-10-26" or
/// "Rental Agreement", instead of "27-Oct-2026_14-30_SCAN".
///
/// Pure text work, so it runs anywhere; reading the page is the caller's
/// job (see `SmartNamer`).
library;

/// Kinds of document recognised by a word on the page, most specific first.
/// The first match names the document.
final _kinds = <(RegExp, String)>[
  (_k(r'tax\s+invoice'), 'Tax Invoice'),
  (_k(r'invoice'), 'Invoice'),
  (_k(r'receipt'), 'Receipt'),
  (_k(r'(bank\s+)?statement(\s+of\s+account)?'), 'Statement'),
  (_k(r'(electricity|water|gas|phone|mobile)\s+bill'), 'Bill'),
  (_k(r'bill'), 'Bill'),
  (_k(r'quotation|estimate'), 'Quotation'),
  (_k(r'purchase\s+order'), 'Purchase Order'),
  (_k(r'delivery\s+(note|challan)|challan'), 'Challan'),
  (_k(r'(rental|rent|lease)\s+agreement'), 'Rental Agreement'),
  (_k(r'agreement|contract'), 'Agreement'),
  (_k(r'salary\s+slip|pay\s*slip'), 'Payslip'),
  (_k(r'mark\s*sheet|report\s+card|grade\s+card'), 'Marksheet'),
  (_k(r'certificate'), 'Certificate'),
  (_k(r'prescription|rx\b'), 'Prescription'),
  (_k(r'question\s+paper'), 'Question Paper'),
  (_k(r'application\s+form'), 'Application Form'),
  (_k(r'boarding\s+pass'), 'Boarding Pass'),
  (_k(r'ticket'), 'Ticket'),
  (_k(r'resume|curriculum\s+vitae'), 'Resume'),
];

RegExp _k(String pattern) => RegExp('\\b(?:$pattern)\\b', caseSensitive: false);

/// "Invoice No: INV-2041", "Bill #  88/2026", "Receipt no. 4471".
final _number = RegExp(
  r'\b(?:invoice|inv|bill|receipt|order|ref(?:erence)?|challan|policy|account|a/c)\s*'
  r'(?:no\.?|number|num|#)\s*[:.\-]?\s*([A-Z0-9][A-Z0-9/\-]{1,20})',
  caseSensitive: false,
);

const _monthNames = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// A suggested name for a document whose first page reads [text], or null
/// when the text gives nothing better than the default name.
///
/// The name is the kind of document (Invoice, Receipt, Certificate…) with
/// its number and date when the page has them; otherwise the page's title
/// line. It is safe as a file name and at most [maxLength] characters.
String? suggestDocumentName(String text, {int maxLength = 60}) {
  final cleaned = text.replaceAll('\r', '');
  if (cleaned.trim().isEmpty) return null;

  final kind = _kindOf(cleaned);
  final number = kind == null ? null : _numberOf(cleaned);
  final date = findDocumentDate(cleaned);
  final dateText = date == null ? null : _isoDate(date);

  final String? base;
  if (kind != null) {
    base = kind;
  } else {
    base = _titleLine(cleaned);
  }
  if (base == null) return null;

  final parts = [base, ?number, ?dateText];
  return _fit(parts.join(' '), maxLength);
}

String? _kindOf(String text) {
  // Only the top of the page names the document; a word in the small print
  // ("receipt of goods") must not.
  final top = text.split('\n').take(12).join('\n');
  for (final (pattern, name) in _kinds) {
    if (pattern.hasMatch(top)) return name;
  }
  return null;
}

String? _numberOf(String text) {
  for (final m in _number.allMatches(text)) {
    final value = m.group(1)!.replaceAll(RegExp(r'[/\-]+$'), '');
    // A number needs a digit; "Invoice No: Date" is a label, not a number.
    if (RegExp(r'\d').hasMatch(value)) return value.replaceAll('/', '-');
  }
  return null;
}

/// The first plausible date on the page: 26/10/2026, 26-10-26, 2026-10-26,
/// 26 Oct 2026, Oct 26, 2026. Day first, as dates are written in India.
DateTime? findDocumentDate(String text) {
  final patterns = <(RegExp, DateTime? Function(Match))>[
    (RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b'), (m) => _date(m[1], m[2], m[3])),
    (RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})\b'), (m) => _date(m[3], m[2], m[1])),
    (
      RegExp(r'\b(\d{1,2})(?:st|nd|rd|th)?[\s\-]+([A-Za-z]{3,9})\.?,?[\s\-]+(\d{4})\b'),
      (m) => _date(m[3], _month(m[2]!), m[1]),
    ),
    (
      RegExp(r'\b([A-Za-z]{3,9})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b'),
      (m) => _date(m[3], _month(m[1]!), m[2]),
    ),
  ];
  DateTime? best;
  int? bestAt;
  for (final (pattern, read) in patterns) {
    for (final m in pattern.allMatches(text)) {
      final d = read(m);
      if (d == null) continue;
      if (bestAt == null || m.start < bestAt) {
        best = d;
        bestAt = m.start;
      }
      break;
    }
  }
  return best;
}

String? _month(String name) {
  final n = _monthNames[name.toLowerCase().substring(0, 3)];
  return n?.toString();
}

DateTime? _date(String? y, String? m, String? d) {
  if (y == null || m == null || d == null) return null;
  var year = int.tryParse(y);
  final month = int.tryParse(m);
  final day = int.tryParse(d);
  if (year == null || month == null || day == null) return null;
  if (year < 100) year += 2000;
  if (year < 1950 || year > 2100 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  // DateTime rolls 31 February into March; that is not a date.
  if (date.month != month) return null;
  return date;
}

String _isoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The first line that reads like a title: mostly letters, two to twelve
/// words, not a date, a phone number, an address line or a web address.
String? _titleLine(String text) {
  for (final raw in text.split('\n').take(8)) {
    final line = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (line.length < 4 || line.length > 90) continue;
    final letters = RegExp(r'[A-Za-zऀ-෿]').allMatches(line).length;
    if (letters < line.length * 0.6) continue;
    final words = line.split(' ');
    if (words.length < 2 || words.length > 12) continue;
    if (RegExp(r'@|www\.|https?:|\.com\b', caseSensitive: false).hasMatch(line)) continue;
    if (RegExp(r'^(page|date|to|from|dear|ph|tel|mob)\b', caseSensitive: false).hasMatch(line)) continue;
    return _titleCase(line);
  }
  return null;
}

/// "RENTAL AGREEMENT" becomes "Rental Agreement"; mixed case is kept.
String _titleCase(String line) {
  if (line != line.toUpperCase()) return line;
  return line
      .split(' ')
      .map((w) => w.length <= 1 || w.contains(RegExp(r'\d')) ? w : '${w[0]}${w.substring(1).toLowerCase()}')
      .join(' ');
}

String _fit(String name, int maxLength) {
  var safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  safe = safe.replaceAll(RegExp(r'^[.\s]+'), '');
  if (safe.length > maxLength) {
    safe = safe.substring(0, maxLength);
    final cut = safe.lastIndexOf(' ');
    if (cut > maxLength ~/ 2) safe = safe.substring(0, cut);
    safe = safe.trim();
  }
  return safe;
}
