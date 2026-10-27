/// The text read from a saved document, kept so the Library can search
/// inside documents and not only their names (improvement.md #8, Pro).
class DocumentText {
  DocumentText(this.text, this.readAt);

  /// Every page's text, pages separated by blank lines. Empty when the
  /// document has no readable text (a photo, or a page OCR could not read).
  final String text;

  /// When it was read. A document changed after this is read again.
  final DateTime readAt;

  /// [text] folded for search, worked out once.
  late final String searchable = normalizeForSearch(text);

  /// At most this many characters are kept per document, so the index
  /// stays small enough to load at start.
  static const maxLength = 60000;

  Map<String, Object?> toJson() => {'text': text, 'at': readAt.millisecondsSinceEpoch};

  static DocumentText? fromJson(Object? json) {
    if (json is! Map) return null;
    final text = json['text'];
    final at = json['at'];
    if (text is! String || at is! int) return null;
    return DocumentText(text, DateTime.fromMillisecondsSinceEpoch(at));
  }
}

/// Folds case and runs of white space, so "Invoice\n No" finds "invoice no".
String normalizeForSearch(String text) => text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// A line of context around the first place [text] contains [needle], like
/// "…paid the rent of ₹12,000 for March…", or null when it does not.
String? searchSnippet(String text, String needle, {int radius = 36}) {
  final hay = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final n = needle.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  if (n.isEmpty) return null;
  final at = hay.toLowerCase().indexOf(n);
  if (at < 0) return null;
  var start = (at - radius).clamp(0, hay.length);
  var end = (at + n.length + radius).clamp(0, hay.length);
  // Start and end on word boundaries when one is near.
  if (start > 0) {
    final space = hay.indexOf(' ', start);
    if (space >= 0 && space < at) start = space + 1;
  }
  if (end < hay.length) {
    final space = hay.lastIndexOf(' ', end);
    if (space > at + n.length) end = space;
  }
  return '${start > 0 ? '…' : ''}${hay.substring(start, end)}${end < hay.length ? '…' : ''}';
}
