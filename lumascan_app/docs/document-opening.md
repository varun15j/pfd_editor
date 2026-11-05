# Opening documents: progress, cancel, large and damaged files

Opening a PDF (Library, Home, Tools, Create sheet, ID card) goes through one
path: `openPdfInEditor` / `pickAndEditPdf` in
`lib/features/pdf_editor/open_pdf.dart`, which runs the work under
`runOpenWithProgress` (`lib/features/open/open_progress.dart`). File checks
and user messages live in `lib/features/open/pdf_file_check.dart`.

## What the user sees

1. Tap a document. Taps are blocked at once so a double tap can't open it twice.
   For a file picked with the system picker, the dialog starts as soon as the
   picker reports it is copying the file (Android copies a picked file into
   the app's cache before handing it over, which takes seconds for a big
   file); the name shows once the copy is done.
2. The **Opening document** dialog shows straight away, with the
   file name, the current step and a progress bar:
   - "Copying the file": bytes copied, for files picked from the phone or a
     cloud provider (`3.1 of 40 MB`).
   - "Checking the file": the quick byte check below.
   - "Opening the document": PDFium reads the file structure.
   - "Reading pages": page sizes measured (`120 of 480 pages`, 25%).
3. The user can stop at any time with the **X**, the **Cancel** button or the
   phone's **back** button. The app goes back to where it was; a document
   that finishes opening after that is closed again, never shown.
4. After **10 s** the dialog changes to **Taking too long**: "This document is
   taking too long to open. It may be very large or damaged. You can wait or
   cancel." with the progress still showing, and **Wait** / **Cancel**.
   Wait keeps going and asks again 20 s later. Time spent typing a password
   does not count.
5. If it fails, a dialog (not a snackbar, so it isn't missed) gives the
   reason in plain words. See the table.

## Large files: reading and buffering

- **One copy only.** The picker's cached copy is moved into `pdf_sources`
  (a rename, instant, no second copy on disk). Only when that can't be done
  is the file streamed over chunk by chunk (`XFile.openRead`), never read
  into memory whole, with byte progress, and the picker's copy deleted.
  "Disk full" (ENOSPC) gets its own message.
- **Cleaned up.** The app's copy is deleted when the editor closes (edits
  are saved as new files), when opening fails and when it is cancelled.
  Copies left by a crash are cleared on the next pick if over a day old.
  Library documents are never deleted by this.
- **Check only the ends.** The byte check reads at most 3 KB (first 1 KB and
  last 2 KB) with async file calls, whatever the file size.
- **PDFium reads on demand.** pdfrx opens the file by path; PDFium reads the
  parts it needs from disk, so a 300 MB file is not loaded into RAM.
- **Off the UI thread.** Every PDFium call runs on pdfrx's background worker
  isolate. The UI isolate only awaits, so the dialog keeps animating and the
  buttons keep working.
- **Pages measured in slices.** The document opens with
  `useProgressiveLoading: true` (only the first page measured), then
  `loadPagesProgressively` measures the rest in 250 ms slices, reporting
  progress after each and stopping when the user cancels. Before, every page
  was measured in one call before anything showed.
- **Render only what is on screen.** The editor draws the visible page at
  screen size (up to 300 dpi) and thumbnails at 72 dpi; pages are not
  decoded ahead.
- **Merge picker.** Counting pages for Merge also uses progressive loading,
  so it no longer measures every page of every file.

## Checks and messages

| Case | How it is caught | Title | Message |
|---|---|---|---|
| File deleted or moved | `exists()` before opening | File not found | This file is no longer on this device. It may have been moved or deleted. |
| 0-byte file | size check | Empty file | This file is empty (0 bytes), so there is nothing to open. |
| No permission / read error | `FileSystemException`, PDFium FPDF_ERR_FILE | Could not read the file | The app could not read this file. Check that it is still there and try again. |
| Disk full while copying | ENOSPC on write | Not enough space | There is not enough free space on this device to open this file. Free up some space and try again. |
| JPEG, PNG, GIF, WebP, HEIC, TIFF renamed to .pdf | no `%PDF-` in the first 1 KB, magic bytes | Not a PDF | This file is a JPEG image, not a PDF, so it cannot be opened here. |
| Word / Excel / PowerPoint / ZIP renamed | ZIP magic + `word/`, `xl/`, `ppt/` | Not a PDF | This file is a Word document, not a PDF, … |
| Old .doc/.xls, RTF, PostScript | magic bytes | Not a PDF | This file is an old Office file (.doc, .xls or .ppt), not a PDF, … |
| HTML error page saved as .pdf (failed download) | starts with `<!doctype html` / `<html` | Not a PDF | This file is a web page (often a download that failed), not a PDF, … |
| Unknown bytes | no `%PDF-` | Not a PDF | This file is not a PDF, so it cannot be opened here. |
| Cut-short download/copy | PDFium fails, no `%%EOF` in the last 2 KB, and the first 1 KB holds PDF objects (`1 0 obj`) | Incomplete PDF | This PDF is incomplete. The download or copy may not have finished. Get the file again and try once more. |
| Broken structure (xref, objects, garbage after the header) | PDFium FPDF_ERR_FORMAT | Damaged PDF | This PDF is damaged and cannot be opened. Try getting a new copy of the file. |
| Page PDFium can't read | FPDF_ERR_PAGE | Damaged page | A page in this PDF is damaged, so the document cannot be opened. |
| Page size 0, negative, NaN or infinite | `isUsablePageSize` after measuring | Damaged page | (same) |
| Zero pages | page count 0 | No pages | This PDF has no pages to show. |
| Unsupported protection (certificate, DRM) | FPDF_ERR_SECURITY | Protection not supported | This PDF uses a kind of protection that this app does not support. |
| Password protected | password dialog; wrong one asks again | – | Cancel the password: "The PDF stays locked without its password." (snackbar, as before) |
| Anything unexpected | catch-all | Damaged PDF | (same as damaged) |

Tolerated on purpose: junk before `%PDF-` (within 1 KB) and after `%%EOF`,
which the PDF spec allows, and files missing `%%EOF` that PDFium can still
repair. These open normally.

## Other edge cases

- **Double tap** on a document while one is opening: ignored.
- **Screen closed while opening** (context unmounted): the result is closed.
- **Cancel while PDFium is inside one call** (a badly damaged file it is
  trying to repair): the app returns at once; the half-opened document is
  disposed when that call ends. PDFium can't be interrupted in the middle of
  a native call, so the background worker stays busy until it returns, and
  a new open waits behind it (the new dialog shows and can be cancelled).
- **App sent to the background while opening**: opening carries on.
- **Very large page count** (thousands): progress shows pages measured.
- **Password**: the progress dialog hides while the password dialog is up
  and the 10 s count pauses.
- **Page with a zero MediaBox** (`[0 0 0 0]`): PDFium falls back to a
  default page size, so it opens normally. Only sizes PDFium itself reports
  as unusable are treated as a damaged page.

## Test files

`/mnt/project-files/open_test_files/` and `F:\AI_Projects\open_test_files`
(not in the repo because of their size; `make_big_files.py` there makes
03, 04 and 06):

| File | Expect |
|---|---|
| 01_valid_3_pages.pdf | opens |
| 02_large_3000_pages.pdf | opens, "Reading pages" progress |
| 03_large_40_photo_pages.pdf (261 MB from make_big_files.py) | copy progress, opens, may show "Taking too long" |
| 04_truncated_half.pdf | Incomplete PDF (or opens what PDFium can repair) |
| 05_broken_xref.pdf | opens (PDFium rebuilds the xref) or Damaged PDF |
| 06_header_then_garbage.pdf | Damaged PDF |
| 07_empty.pdf | Empty file |
| 08_jpeg_renamed.pdf | Not a PDF: a JPEG image |
| 09_word_renamed.pdf | Not a PDF: a Word document |
| 10_failed_download_html.pdf | Not a PDF: a web page |
| 11_zero_size_page.pdf | opens (PDFium uses a default page size) |
| 12_pages_tree_loop.pdf | Damaged PDF or No pages, no hang |
| 13_no_pages.pdf | No pages |
| 14_content_bomb.pdf | opens; first page render may be slow |
| 15_password_1234.pdf | asks for password `1234` |
| 16_junk_before_header.pdf | opens |

Unit tests: `test/pdf_file_check_test.dart` (checks and messages) and
`test/open_progress_test.dart` (dialog, X / Cancel / back, 10 s prompt,
Wait, late result disposed, double tap).
