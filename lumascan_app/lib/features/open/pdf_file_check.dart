import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Why a document could not be opened, with the words the user sees.
/// Every failure while opening a document ends as one of these, so the user
/// always gets a plain message and never a raw exception.
class DocumentOpenException implements Exception {
  const DocumentOpenException(this.kind, {this.detail});

  final OpenFailure kind;

  /// Extra words for the message, such as the format the file really is.
  final String? detail;

  String get title => kind.title;
  String get message => kind.message(detail);

  @override
  String toString() => 'DocumentOpenException(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// The kinds of failure, each with its title and message.
enum OpenFailure {
  missing('File not found'),
  empty('Empty file'),
  unreadable('Could not read the file'),
  noSpace('Not enough space'),
  wrongFormat('Not a PDF'),
  truncated('Incomplete PDF'),
  corrupted('Damaged PDF'),
  damagedPage('Damaged page'),
  noPages('No pages'),
  unsupportedSecurity('Protection not supported');

  const OpenFailure(this.title);

  final String title;

  String message(String? detail) => switch (this) {
    missing => 'This file is no longer on this device. It may have been moved or deleted.',
    empty => 'This file is empty (0 bytes), so there is nothing to open.',
    unreadable => 'The app could not read this file. Check that it is still there and try again.',
    noSpace => 'There is not enough free space on this device to open this file. Free up some space and try again.',
    wrongFormat =>
      detail == null
          ? 'This file is not a PDF, so it cannot be opened here.'
          : 'This file is $detail, not a PDF, so it cannot be opened here.',
    truncated =>
      'This PDF is incomplete. The download or copy may not have finished. Get the file again and try once more.',
    corrupted => 'This PDF is damaged and cannot be opened. Try getting a new copy of the file.',
    damagedPage => 'A page in this PDF is damaged, so the document cannot be opened.',
    noPages => 'This PDF has no pages to show.',
    unsupportedSecurity => 'This PDF uses a kind of protection that this app does not support.',
  };
}

/// What the quick check found in the first and last bytes of a file.
class PdfFileFacts {
  const PdfFileFacts({required this.size, required this.endsWithEof});

  final int size;

  /// `%%EOF` was found near the end. A PDF without it was very likely cut
  /// short, though PDFium can sometimes still read it.
  final bool endsWithEof;
}

/// How many bytes are read from each end of the file. The PDF spec allows
/// junk before `%PDF-` and after `%%EOF`; real files keep it well under this.
const pdfProbeBytes = 1024;
const pdfTailBytes = 2048;

/// Checks a file before PDFium sees it. Reads at most 3 KB, whatever the
/// file's size, using async file calls, so it never blocks the UI.
/// Throws [DocumentOpenException] for a missing, empty or non-PDF file.
Future<PdfFileFacts> checkPdfFile(String path) async {
  final file = File(path);
  final int size;
  try {
    if (!await file.exists()) throw const DocumentOpenException(OpenFailure.missing);
    size = await file.length();
  } on DocumentOpenException {
    rethrow;
  } on FileSystemException {
    throw const DocumentOpenException(OpenFailure.unreadable);
  }
  if (size == 0) throw const DocumentOpenException(OpenFailure.empty);

  final Uint8List head;
  final Uint8List tail;
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    head = await raf.read(pdfProbeBytes);
    if (size > pdfProbeBytes) {
      final from = size > pdfTailBytes ? size - pdfTailBytes : 0;
      await raf.setPosition(from);
      tail = await raf.read(pdfTailBytes);
    } else {
      tail = head;
    }
  } on FileSystemException {
    throw const DocumentOpenException(OpenFailure.unreadable);
  } finally {
    await raf?.close();
  }

  return inspectPdfBytes(head: head, tail: tail, size: size);
}

/// The byte checks of [checkPdfFile], on bytes already read. Kept apart so
/// tests can feed it bytes without files.
PdfFileFacts inspectPdfBytes({required Uint8List head, required Uint8List tail, required int size}) {
  if (!_contains(head, _pdfMagic)) {
    throw DocumentOpenException(OpenFailure.wrongFormat, detail: describeFormat(head));
  }
  return PdfFileFacts(size: size, endsWithEof: _contains(tail, _eofMarker));
}

final _pdfMagic = ascii.encode('%PDF-');
final _eofMarker = ascii.encode('%%EOF');

/// Names a common format from its first bytes, as words for a sentence
/// ("a JPEG image"), or null when it is not one we know.
String? describeFormat(Uint8List head) {
  bool startsWith(List<int> sig, [int at = 0]) {
    if (head.length < at + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (head[at + i] != sig[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'a JPEG image';
  if (startsWith(const [0x89, 0x50, 0x4E, 0x47])) return 'a PNG image';
  if (startsWith(ascii.encode('GIF8'))) return 'a GIF image';
  if (startsWith(ascii.encode('RIFF')) && startsWith(ascii.encode('WEBP'), 8)) return 'a WebP image';
  if (startsWith(ascii.encode('ftyp'), 4)) return 'a photo or video (HEIC, MP4 or similar)';
  if (startsWith(const [0x49, 0x49, 0x2A, 0x00]) || startsWith(const [0x4D, 0x4D, 0x00, 0x2A])) {
    return 'a TIFF image';
  }
  if (startsWith(const [0x50, 0x4B, 0x03, 0x04])) {
    final text = latin1.decode(head, allowInvalid: true);
    if (text.contains('word/')) return 'a Word document';
    if (text.contains('xl/')) return 'an Excel sheet';
    if (text.contains('ppt/')) return 'a PowerPoint file';
    return 'a ZIP archive or Office file';
  }
  if (startsWith(const [0xD0, 0xCF, 0x11, 0xE0])) return 'an old Office file (.doc, .xls or .ppt)';
  if (startsWith(ascii.encode('{\\rtf'))) return 'an RTF document';
  if (startsWith(ascii.encode('%!PS'))) return 'a PostScript file';
  final text = latin1.decode(head.length > 256 ? head.sublist(0, 256) : head).trimLeft().toLowerCase();
  if (text.startsWith('<!doctype html') || text.startsWith('<html')) {
    return 'a web page (often a download that failed)';
  }
  return null;
}

bool _contains(Uint8List data, List<int> needle) {
  outer:
  for (var i = 0; i <= data.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (data[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// PDFium's FPDF_ERR_* codes, as pdfrx reports them in PdfException.
const pdfiumErrFile = 2;
const pdfiumErrFormat = 3;
const pdfiumErrSecurity = 5;
const pdfiumErrPage = 6;

/// Turns a PDFium load error into the message the user sees. [facts] tells
/// a cut-short file apart from one damaged in some other way.
DocumentOpenException pdfiumFailure(int? errorCode, {PdfFileFacts? facts}) => switch (errorCode) {
  pdfiumErrFile => const DocumentOpenException(OpenFailure.unreadable),
  pdfiumErrSecurity => const DocumentOpenException(OpenFailure.unsupportedSecurity),
  pdfiumErrPage => const DocumentOpenException(OpenFailure.damagedPage),
  _ when facts != null && !facts.endsWithEof => const DocumentOpenException(OpenFailure.truncated),
  _ => const DocumentOpenException(OpenFailure.corrupted),
};

/// A page size PDFium gave back is usable. A damaged page can come back as
/// zero, negative or not a number, which would break layout and rendering.
bool isUsablePageSize(double width, double height) => width.isFinite && height.isFinite && width > 0 && height > 0;
