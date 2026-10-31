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

## How Auto mask hides what it finds

Updated 2026-10-31 (Varun: "replace the character by cross X; if OCR does not recognise the number, put a black box").

- **Crossed out with Xs.** When OCR read the characters, the mask is filled with the colour of the paper around it (the median of a ring of pixels just outside the box) and gets one X per hidden character, in near-black on light paper or near-white on dark paper. A number printed in groups gets one mask per group, so the Xs sit on the digits and not on the spaces. The last four characters stay readable, as on UIDAI's masked Aadhaar.
- **Black box.** When a label such as "DOB" or "Passport No" is followed by something with digits that OCR could not read cleanly (`0l/?1/l9B0`), that part is covered with a solid black box instead. A box drawn by hand is black too.

`MaskAnnotation.crosses` holds the number of Xs; 0 is a solid box. The Xs are burned into the pixels the same way as a black box (`burnMasks`), and the editor draws them on white so they can still be moved.

Auto mask is Pro and Gold (`PlanFeature.autoMask`). It runs from **Auto mask ID numbers** under the Mask tool in Markup, and from **Mask IDs** under More in Batch Review for every selected page at once (one undo step).

## Which numbers Auto mask finds

`IdNumberFinder` works on the text ML Kit reports, line by line, with each word's own box, so a mask lands exactly on the characters. It finds numbers in three passes.

**1. Shapes that are IDs on their own**

| Kind | Shape | Example | Left visible |
| --- | --- | --- | --- |
| Aadhaar | 12 digits, three groups of four, never starting with 0 or 1 | `2345 6789 0120` | last 4 |
| Aadhaar VID | 16 digits, four groups of four | `9123 4567 8901 2349` | last 4 |
| Credit or debit card | 13 to 19 digits starting 2 to 6, passing the Luhn check, as one run or in groups (4-4-4-4, Amex 4-6-5, Diners 4-6-4) | `4111 1111 1111 1111` | last 4 |
| US Social Security | `123-45-6789` or `123 45 6789`, never 000, 666 or 9xx first | `123-45-6789` | last 4 |
| PAN | five letters, four digits, a letter | `ABCDE1234F` | last 4 |
| Voter ID (EPIC) | three letters, seven digits | `ABC1234567` | last 4 |
| Passport (India) | a letter and seven digits | `M1234567` | last 4 |
| UK National Insurance | two letters, six digits, a letter | `AB123456C` | last 4 |
| Driving licence (India) | two letters, two digits, then eleven digits | `MH12 20110012345` | last 4 |
| Passport machine-readable lines | the `P<IND...<<<` lines at the foot of any passport | | nothing |

**2. Labels, for any country.** A label marks what follows it on the line, or the line below when the label ends its line:

- Date of birth: `DOB`, `D.O.B`, `Date of Birth`, `Birth date`, `Born`, `YOB`, `Year of Birth`, and the German, French and Spanish words. Dates like `01/01/1990`, `1990-01-31`, `31.01.1990`, `12 Jan 1990` and a year alone are hidden whole.
- ID numbers: `Passport No`, `Document No`, `ID No`, `Identity`, `National ID`, `Social Security`, `SSN`, `SIN`, `NIN`, `TIN`, `Tax ID`, `NIC`, `CNIC`, `Licence No`, `DL No`, `Card No`, `Account No`, `Aadhaar`, `UID`, `VID`, `EPIC`, `Personal No`, and the German, French and Spanish words. The words with digits after the label are taken as the number, and all but its last four characters are hidden.

**3. Unreadable after a label.** Anything number-like after a label that is not a clean number gets a black box (above).

Guards against masking something harmless:

- A number printed in groups is taken as an Aadhaar or VID on its shape alone, since the grouping is distinctive.
- A single run of 12 or 16 digits must pass the Verhoeff check digit UIDAI uses, and a card number the Luhn check, so phone numbers, invoice numbers and totals are left alone.
- A date is only hidden after a birth label, so issue and expiry dates stay.
- When a number was already found by its shape, its label does not mask anything else on the line (so a card's expiry date after "Card No" stays).
- Letters that OCR often reads for digits (`O` for `0`, `B` for `8`, `I` for `1`) are fixed before matching, and the PAN check fixes digits read where letters must be, in those places only.
- When the engine gives no word boxes, they are estimated from the line's box and the position of each character.

The user is told how many numbers were masked, of what kind, and how many got a black box, and asked to check the page before sharing: OCR can misread, and a number printed in an unusual way may be missed. Masking by hand is always there as the fallback.
