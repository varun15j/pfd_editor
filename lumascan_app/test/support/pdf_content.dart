import 'dart:io';
import 'dart:typed_data';

/// The page content streams of [pdf], inflated.
String pdfContentText(Uint8List pdf) {
  final out = StringBuffer();
  final latin = String.fromCharCodes(pdf);
  var at = 0;
  while (true) {
    final start = latin.indexOf('stream\n', at);
    if (start < 0) break;
    final end = latin.indexOf('endstream', start);
    if (end < 0) break;
    final data = pdf.sublist(start + 'stream\n'.length, end);
    try {
      out.write(String.fromCharCodes(zlib.decode(data)));
    } on FormatException {
      // An image or a stream that is not deflated.
    }
    at = end;
  }
  return out.toString();
}
