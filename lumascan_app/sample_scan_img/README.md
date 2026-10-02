# Sample scan images

Phone photos of handwritten notebook pages, for trying the scanning flow by hand: **Import from photos**, manual corner crop, and the document filters (Magic Color, Grayscale, B&W). They are not bundled into the app (nothing in `pubspec.yaml` lists them as assets).

| File | Size (px) | What makes it a useful test |
|---|---|---|
| 01_revision1_palindrome_lengths.jpg | 1529 x 2000 | Fingers over the left edge, pink margin and ruled lines, blue and black ink |
| 02_revision2_multiplication.jpg | 1567 x 2000 | Page slightly rotated, crossed-out corrections, faint show-through from the back |
| 03_revision3_conversions_shapes.jpg | 1768 x 2000 | Torn page on a dark background, other pages in frame, hand-drawn circles and triangles |
| 04_revision4_lengths.jpg | 1765 x 2000 | Mostly empty page, thumb at the bottom, skewed ruled lines |
| 05_revision_grocery_table.jpg | 1236 x 2000 | Narrow page, tabular layout, rupee (₹) signs |

To copy them to an Android emulator or a USB-connected phone so they show up in the photo picker:

```bash
adb push sample_scan_img/. /sdcard/Pictures/LumaScanSamples/
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures/LumaScanSamples
```
