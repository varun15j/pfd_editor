# luma_docx

Opens and reads Word (.docx) files in Flutter, in pure Dart: no WebView, no
native code and no network. Part of the premium Word library for Pro and Gold
(see `doc/feature-support.md` for what it reads, feature by feature).

```dart
import 'package:luma_docx/luma_docx.dart';

final doc = WordReader.read(bytes);          // parse (run it in an isolate for big files)
final docx = WordWriter.write(doc);          // save it back to .docx
WordDocumentView(
  document: doc,
  options: const WordViewOptions(layout: WordLayout.pages), // or WordLayout.reflow
  onLinkTap: (link) {},
  onNoteTap: (note) {},
  onCommentTap: (comment) {},
);
```

- `lib/src/model.dart`: the document model (sections, paragraphs, tables, runs,
  pictures, shapes, charts, equations, notes, comments, tracked changes).
- `lib/src/reader/`: the .docx reader (styles, theme, numbering, fields, math, charts).
- `lib/src/render/`: Flutter widgets (pages view and fit-to-screen view).
- `lib/src/writer/word_writer.dart`: `WordWriter.write(doc)` saves a `WordDocument`
  back to .docx with all of its formatting (round-trip tested on the feature file).
- `lib/src/writer/docx_writer.dart`: simple picture and text pages, for OCR to Word
  (a copy; the app's existing Word export in `lib/export/word` is separate and unchanged).

Tests: `flutter test`. Screenshots of every page for a visual check:
`PREVIEW_OUT=/some/dir flutter test --run-skipped -t preview`
(add `PREVIEW_LAYOUT=reflow` for the fit-to-screen view).

## Writer limits

`WordWriter` writes everything the reader keeps. Formatting goes on each paragraph
and run; styles keep their names and heading levels only. Not kept: a chart's
data workbook (the chart keeps its numbers), legacy form field settings (the
fields keep their shown text), SmartArt and embedded objects (they were
placeholders already), and exact positions of floating tables (kept: left,
center or right).
