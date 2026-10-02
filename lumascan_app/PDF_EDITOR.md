# LumaScan PDF editor (first cut)

Open any PDF from the phone, page through it, add pen, highlighter, text and a drawn signature, reorder or delete pages, and save the result as a new PDF. The opened file is never changed.

## Screens

| Screen | File | What it does |
|---|---|---|
| Open | `lib/features/pdf_editor/open_pdf.dart` | System file picker (PDF only), copies the file into app storage, asks for a password if the PDF is locked, opens it with pdfrx |
| Editor | `lib/features/pdf_editor/pdf_editor_screen.dart` | One page at a time with Previous/Next. Tools: View (pinch zoom and pan), Move, Pen, Highlight, Text, Erase, Sign. Undo in the app bar. Asks before leaving with unsaved changes |
| Overlay | `lib/features/pdf_editor/annotation_layer.dart` | Draws the marks and turns touches into strokes, text boxes and drags |
| Signature pad | `lib/features/pdf_editor/signature_pad_screen.dart` | Full-screen pad (signature package). The signature lands centred on the page in Move mode so it can be dragged into place; tap it to resize or delete |
| Organize pages | `lib/features/pdf_editor/organize_pages_screen.dart` | Thumbnails, drag to reorder, Move up / Move down / Delete page menu (with Undo). Tap a page to jump to it |
| Save | `lib/features/pdf_editor/save_pdf_sheet.dart` | File name and quality, progress, then the share sheet |

Logic without UI lives in `lib/pdf_edit/`: annotation models, the Riverpod controller (page list, marks, undo, unsaved flag), the flattener that writes the new PDF, and the saver.

## How it follows the design docs

- **ADR-012 pdfrx** renders pages on screen and for saving.
- **ADR-013 annotations as an app-owned overlay, flattened at export.** Marks are stored in page-relative coordinates, so the same data draws the overlay and the PDF. Ink and signatures become vector strokes; text becomes real PDF text.
- **ADR-011 `pdf` package** writes the new file, using the existing atomic write in `PageStore` (`exports/` folder).
- **ADR-014 is still open** (no write engine for imported PDFs yet), so saving renders each original page to an image. The save sheet says this plainly: text from the original stops being selectable or searchable in the new file (LLD §11 forbids an undisclosed rasterizing fallback). Swapping in a write engine later only changes `PdfEditSaver`.

## Run it

```bash
cd lumascan_app
flutter pub get
flutter test                       # 43 tests, 17 of them for the editor
flutter run                        # phone or emulator
```

On the home screen tap **Edit a PDF**.

Packages added to `pubspec.yaml`: `pdfrx: ^2.6.5`, `signature: ^6.4.0`, `file_picker: ^13.1.0`. pdfrx bundles PDFium through Dart native assets on Android and through CocoaPods or Swift Package Manager on iOS, so the first build downloads it. No new permissions are needed: the file picker uses the system document picker on both platforms.

## Known gaps

- Saved pages are images (see ADR-014 above). Quality "High" renders at 2400 px on the long edge.
- Text marks use the built-in Helvetica font, so characters outside Western European languages (for example ₹ or Devanagari) are dropped from the saved PDF. Bundling a Noto font fixes this.
- The on-screen text font differs slightly from Helvetica, so long text can wrap a little differently in the saved file.
- Page rotation, duplicate page and merging several PDFs are not in this cut.
- Edits live in memory until saved, like the scan draft.
- Not yet run on a real device. The cloud build machine cannot download the Android SDK, so only `flutter analyze` and `flutter test` were run.
