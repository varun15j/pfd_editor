# ID card mode

Phase 2 item 1 in [improvement.md](improvement.md). Free on every plan. The design is
[design/UI_UX_screen/ID-card-scan](../design/UI_UX_screen/ID-card-scan/ID_CARD_UI_UX_EPIC_STORYBOARD.md)
(wireframe states ID-01 to ID-08).

## The flow

| Step | Screen | Code |
| --- | --- | --- |
| ID-01 | Tools > ID Card, + > ID copy, or the ID mode next to Docs in the camera's mode strip (it closes the camera and opens the type picker; pages already taken stay on Home). Never opens the plain document camera. | `openIdCardStudio` |
| ID-02 to ID-04 | Type picker: A4 paper example, description, Make it now, then Single Side / ID Card / Passport. Changing type only moves the green border and the example. | `IdCardTypeScreen` |
| ID-05 | Camera: 3 × 3 grid, green corners around a card-shaped guide, "Front page" / "Back page", "1 of 2". Close, shutter, Import only. While the back is taken the front stays in view at the top left; tap it to retake the front. | `IdCardCaptureScreen` |
| ID-06 | Review: black header with the editable title and Help, the white page with every side where it prints and page number 01, A4 / Letter and Actual size / Large, then Add Watermark, Edit, Filter and the green ✓. | `IdCardReviewScreen` |
| ID-07 | Add Watermark dialog: placeholder "Enter the content for the watermark", green underline, Cancel and OK. Up to 60 characters; an empty one is refused with "Add a purpose or remove the watermark." | `AddWatermarkDialog` |
| ID-08 | Saved grid, two to a row: 01 the copy, 02 front, 03 back, then "Tap to add new pages". Add, Collage, Share, Edit PDF, More. | `IdCardSavedScreen` |

Make it now starts a new document; whatever was on screen is kept on Home. Each side is an ordinary page of
that document, so it is saved as it is taken and nothing is lost if the app closes.

### Edit on the review page

Tapping a side selects it and opens Edit: Crop or resize (the normal crop screen), Rotate, Hide a number
(Markup opened on the Mask tool), Retake, and Swap front and back. Filter opens the normal filter screen for
the selected side. A side whose page is gone shows "Take the back page" and the ✓ explains what is missing.

### Saved grid actions

- **Add**: camera or photos, added after the last page.
- **Collage**: pick 2 to 4 pages, Make lays them out on one A4 page (one column for two, a 2 × 2 grid for
  three or four) and adds it as the last page.
- **Share**: the ID copy page alone (one page, ready to print) or all pages, then the usual send sheet.
- **Edit PDF**: saves the PDF and opens it in the PDF editor.
- **More**: Save as PDF, Word or JPG; Open all pages (the normal page screen); Rename; Done.
- Tapping 01 opens the review again; ✓ there makes the copy again in its place. Tapping another page opens
  its page menu (crop, filter, markup, and so on).

### Keeping the copy up to date

The ID copy setup (type, which pages are the sides and which is the copy page, watermark, paper and size)
is kept with the document, in `ScanDocInfo.idCopy`, so it is saved with the draft and with documents set
aside on Home. Opening a finished ID copy from Home opens the saved grid.

A side replaced in place stays that side wherever it is retaken (the ID screens, the page menu, the batch
camera), and an undo of the retake follows back (`IdCopyDraft.followPages`). When a side of a finished copy
changes in any way (retaken, cropped, filtered, masked, rotated, swapped), the copy page is made again from
the sides as they are now, in its place. That follows from the change, so it is not an undo step of its own.

## Layout

`idCopySlots` in `lib/domain/id_copy.dart` puts each side at its printed size: ISO/IEC 7810 ID-1
(85.6 × 53.98 mm) for cards, an open ID-3 passport (125 × 176 mm) for passports. Large is 1.5×. Sides are
centred, 15 mm apart, and shrink only if they would leave the 15 mm margin. One side and Passport have one
slot.

`composePage` in `lib/imaging/id_copy_composer.dart` draws the page with `dart:ui` at 200 dpi (A4 is
1654 × 2339 px), fits each picture inside its slot keeping its shape, and prints the watermark with
`paintWatermark`. The review screen draws its preview watermark with the same function, so the preview
matches the page.

The Library PDF uses `PdfPageSize.fitImage` at 200 dpi (`ExportOptions.fitImageDpi`), with no margin, so
the copy prints at real size. It is filed as `ScanType.idCard` under the document's name; saving again
replaces that file and keeps the Library entry.

## Privacy

- Every step runs on the phone. There is no OCR, face matching or check of the card in this flow; the
  screens say LumaScan copies the card and does not verify it.
- Each side goes on the copy rendered with `RenderService.renderMasked`, so masks are burned into the
  pixels before the page is composed. A number hidden on a side is not in the copy.
- Auto mask stays Pro and Gold, as decided for [id-masking.md](id-masking.md); drawing a mask is free.
- The sample cards on the type picker are made-up shapes marked SAMPLE; no real card artwork is used.

## Not built yet

- Live edge, glare and blur hints on the camera (the photo is cropped to the card found in it, or to the
  guide when none is found).
