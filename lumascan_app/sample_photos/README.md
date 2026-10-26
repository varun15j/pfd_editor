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

Page detection on 6 October 2026 (`detectPageQuad`, 640 px): about 5 of 20 are outlined well (03, 08, 12, 18, 20). Most others cut across both pages. Thin strips of a page (05, 14, 16) were accepted as pages until the detector learned to reject shapes narrower than 0.28 of their length, so those photos now import uncropped; 13 is still a strip, just above the limit. Two-page spreads need their own handling: pick one page at the gutter, or keep the spread.

## Edge test pages (`edge/`)

Nineteen photos for testing page edge detection, made by `tool/make_edge_samples.py` from real page content: the KV question papers in `sample_docs/` (black and white, and printed on pink, yellow and blue paper), the odds book pages (colour) and the book photos above. Each is laid on a surface (dark or light wood, concrete, a white bedsheet, red carpet, blue cloth, a black desk, a beige table) with a shadow, tilt, light falloff and noise, at 1080 x 1440 (about 190 KB each, 3.5 MB in all). Some have fingers over the edges, a shadow across the page or are taken in greyscale; the open books have a curved gutter, a page stack below and a darker gutter.

| Group | Files | What they test |
|---|---|---|
| Colour pages | `c01`-`c07` | Colour print, coloured paper on a surface of the same hue or shade, strong perspective, a turned page |
| Black and white pages | `b01`-`b07` | Print on dark, grey and white surfaces, a shadow across the page, fingers, a narrow slip, greyscale photos |
| Books | `k01`-`k05` | Spreads with a curved gutter, one page in view with the facing page cut off, a thumb, a deep gutter shadow |

Since the pictures are made, the page corners are known exactly: `edge/corners.json` lists them (and, for an open book, the spread and each page). `test/edge_samples_test.dart` scores the detector on them. In a debug build, tap **Add edge test pages** under Settings > Developer or in the debug panel. To change them, edit the script and run `python3 tool/make_edge_samples.py` from `lumascan_app` (Python 3 with Pillow and numpy, and `pdftoppm`); the output is the same on every run.

## Colour book pages (`colour_book/`)

Twenty-two photos of a colour textbook (NCERT Class 6 Social Science) open on a wooden desk, taken with the LumaScan camera on the CPH2661 (OnePlus) on 26 October 2026 with the PR #65 build. They are the original photos before crop, turned upright and resized from 3840 x 2160 to 1080 x 1920 (6.4 MB in all). Most show a right-hand page with a strip of the facing page; 17 to 22 show more of the spread. Pens, a pencil case, a laptop and sometimes an arm are in view; 03 and 16 are pages being turned, blurred, with a hand on them; 12 has a hand shadow over the globe.

`test/colour_book_detection_test.dart` has their page corners marked by hand (the right page, and the spread) and scores `detectPageQuad` on them at photo and preview size. In a debug build, tap **Add colour book pages** under Settings > Developer or in the debug panel.

On the phone (camera auto crop, 26 October 2026): 6 fitted well, 6 also took in a strip of the facing page, 4 cut into the page (the pink scroll border of 04, the title band of 06, the spreads 18 and 20), and 6 were wrong (page turns, a hand shadow, the photo spread 17, the chapter opener 22).
