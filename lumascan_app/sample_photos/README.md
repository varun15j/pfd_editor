# Sample photos

The original phone photos behind the scans in `sample_scan_img/`. Same file names, same pages: `sample_photos/01_….jpg` is the raw photo and `sample_scan_img/01_….jpg` is the cleaned scan of it. All are 1500 x 2000 px.

`test/page_detection_test.dart` uses both folders: it finds the page edges in each photo with `detectPageQuad` (`lib/imaging/page_detector.dart`), straightens the page with `warpPerspective`, and checks that the result looks most like its own scan out of the five.

| File | What makes it hard |
|---|---|
| 01_revision1_palindrome_lengths.jpg | Fingers over the left edge, grey concrete background |
| 02_revision2_multiplication.jpg | Page fills almost the whole frame, torn top edge, finger at the top right |
| 03_revision3_conversions_shapes.jpg | Torn page lying on other loose sheets at the top left and bottom left, thumb at the bottom |
| 04_revision4_lengths.jpg | Fingers at the top, left and bottom, page runs off the bottom of the frame |
| 05_revision_grocery_table.jpg | Notebook page with the facing page visible on the right, shadow at the bottom |

Bundled into the app as assets (listed in `pubspec.yaml`, about 2 MB). In a debug build, open Settings > Developer (or the debug panel, by swiping in from the left edge) and tap **Add sample pages**: the five photos go through the normal photo import with auto-crop and the draft opens, ready for Batch Review (enhance, rotate, crop, OCR, delete, markup, duplicate, reorder). `test/sample_pages_test.dart` checks they are bundled and that a page is found in each.

To try them through the system photo picker instead (emulator or USB phone):

```bash
adb push sample_photos/. /sdcard/Pictures/LumaScanPhotos/
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures/LumaScanPhotos
```

## Book pages (`book/`)

Twenty phone photos of a printed black-and-white children's science book, held open on a lap, taken with LumaScan on the CPH2661 (OnePlus) on 6 October 2026. They were picked from 134 photos in the app for sharp, readable text; blurred shots and page turns were left out. Each was resized from 2160 x 3840 to 1080 x 1920 (about 300 KB each, 6 MB in all).

They are harder than the math pages: two-page spreads with a curved gutter, the facing page and the page stack in view, fingers on the page (08, 13, 14, 15), and a busy background (cables, a lamp, cloth). In a debug build, tap **Add book pages** under Settings > Developer or in the debug panel.

Page detection on 6 October 2026 (`detectPageQuad`, 640 px): about 5 of 20 are outlined well (03, 08, 12, 18, 20). 02 gets no outline, and most others cut across both pages or keep only a strip of one. Two-page spreads need their own handling: pick one page at the gutter, or keep the spread.
