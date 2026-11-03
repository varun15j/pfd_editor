/// Word (.docx) reading, rendering and writing for Flutter, in pure Dart.
///
/// * [WordReader.read] turns .docx bytes into a [WordDocument] with all
///   formatting resolved.
/// * [WordDocumentView] draws a [WordDocument] as pages or as reflowed text.
/// * [DocxWriter] writes picture and text pages (scans, OCR text).
library;

export 'src/model.dart';
export 'src/reader/word_reader.dart' show WordReader;
export 'src/render/context.dart' show WordLayout, WordViewOptions, WordLinkCallback, WordNoteCallback, WordCommentCallback;
export 'src/render/document_view.dart' show WordDocumentView, WordViewController;
export 'src/writer/docx_writer.dart';
