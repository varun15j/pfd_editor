# Aadhaar and ID card masking

Added 2026-10-26. Code: `lib/pdf_edit/annotations.dart` (`MaskAnnotation`), `lib/domain/id_masking.dart` (the finder), `lib/imaging/masking.dart` (burning in), the Mask tool in `lib/features/pdf_editor/annotation_layer.dart` and the Auto mask button in `lib/features/markup/`.

## What it does

A mask is a solid box over part of a page, for hiding an Aadhaar number, a PAN or anything else that should not be shared. There are two ways to add one:

- **By hand, on every plan.** In Markup (and in the PDF editor) choose **Mask** and drag over what to hide.
- **Auto mask, on Pro and Gold.** "Auto mask ID numbers" reads the page on the device and masks every ID number it finds, leaving the last four characters readable, the way UIDAI's own masked Aadhaar does.

A mask is an ordinary mark: it can be dragged, made larger or smaller from its menu in Move mode, erased with the eraser, and taken back with Undo. Like other marks it is removed when the page is cropped or rotated, because it would no longer line up.

## Masks are burned in, not drawn on top

A box drawn in a layer above a picture hides nothing: anyone can take the layer away and read what is underneath. So a mask is painted into the page's pixels (`burnMasks`), as the last step of the render pipeline, in every path that leaves the app:

| Path | Where |
| --- | --- |
| Scan PDF export | `lib/export/pdf_exporter.dart` |
| JPG export | `lib/export/jpg_exporter.dart` |
| Edited PDF (imported PDFs, and the save of a scan) | `lib/pdf_edit/pdf_flattener.dart` |
| PDF to Word pictures | `lib/export/word/word_service.dart` |
| Text PDF pages | `lib/export/ocr_pdf_builder.dart` |
| Library thumbnail | `lib/data/library_store.dart` |
| What OCR reads | `RenderService.renderMasked`, used by `ocrEngineProvider` |

In a PDF the same box is also drawn as a vector rectangle on top, so its edges stay sharp at any zoom, but what it hides is already gone from the picture. Mask edges are rounded outwards by a whole pixel, so a mask never leaves a sliver of a digit showing.

Because text read from a page earlier could hold a number a new mask hides, adding or moving a mask forgets that text (`ScanController.setAnnotations`); reading the page again skips what the masks cover.

On screen, previews and thumbnails draw masks as boxes instead of burning them in, so they can still be moved. Only files that leave the app have them burned in.

## Which numbers Auto mask finds

`IdNumberFinder` works on the text ML Kit reports, line by line, with each word's own box, so a mask lands exactly on the digits.

| Kind | Shape | Example |
| --- | --- | --- |
| Aadhaar | 12 digits, usually in three groups of four, never starting with 0 or 1 | `2345 6789 0120` |
| Aadhaar VID | 16 digits, four groups of four | `9123 4567 8901 2349` |
| PAN | five letters, four digits, a letter | `ABCDE1234F` |
| Voter ID (EPIC) | three letters, seven digits | `ABC1234567` |
| Passport | a letter and seven digits | `M1234567` |
| Driving licence | two letters, two digits, then eleven digits | `MH12 20110012345` |

Guards against masking something harmless:

- A number printed in groups is taken as an Aadhaar or VID on its shape alone, since the grouping is distinctive.
- A single run of 12 or 16 digits must also pass the Verhoeff check digit UIDAI uses, so phone numbers, invoice numbers and totals are left alone.
- Letters that OCR often reads for digits (`O` for `0`, `B` for `8`, `I` for `1`) are fixed before matching, and the PAN check fixes digits read where letters must be, in those places only.
- When the engine gives no word boxes, they are estimated from the line's box and the position of each character.

The user is told how many numbers were masked and of what kind, and asked to check the page before sharing: OCR can misread, and a number printed in an unusual way may be missed. Masking by hand is always there as the fallback.
