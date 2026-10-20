# Auto crop: finding the page, and cropping every photo

Covers US-03.12 and requirement CAP-12 (see `epics-user-stories.md` and `requirements.md`). Added 2026-10-07.

## Problem

On the 20 book photos in `sample_photos/book` (cream paper, an open book held on the lap, light blue jeans and a beige chair behind it) the detector found the right page in only 2 of 20 photos at 85% overlap or better, and none at all in 4. It looked only for bright, nearly colourless paper, so cream pages lost to the bright jeans; it kept the largest region wherever it was; and it trimmed the facing page only when one side of the book ran off the frame. On the camera the outline then flickered out, and a photo with no page found was kept uncropped.

## Finding the page (`lib/imaging/page_detector.dart`)

1. **Two masks.** White paper as before (bright, cool, nearly colourless, above an Otsu cut), and a new **colour-seeded mask**: the paper colour is taken from the brighter half of the middle 30% of the frame (where the page is held; print does not count), and every pixel close to it in brightness and colour (red-green, yellow-blue) is kept, the cut set by Otsu between 14 and 60. Shade on curved paper changes brightness more than colour, so brightness counts less, and less again when darker. This finds cream, yellowed and coloured paper.
2. **Regions.** Each mask is eroded once, then one region is kept: the largest, or the one nearest the middle (a region holding the middle keeps its full size; others are weighed down by distance). Paper mask: both; colour mask: the middle one.
3. **Corners** as before: largest quadrilateral on the convex hull, nudged off background.
4. **Rating.** Each outline is rated by the contrast across its four edges (median of 24 samples, 3 px inside against 3 px outside, brightness plus colour), times closeness to the middle, times a full score only if it holds the middle of the frame (half otherwise), and lower when under 15% of the frame. An edge along the frame border counts as a fair edge (30). An outline with no edge of at least 6 is not a page (a plain wall).
5. **One page.** The best outline goes through `focusOnePage` (below).

`focusOnePage` (`page_focus.dart`) now also:
- trims when **both** sides of the outline run off the frame (a book held close), keeping the clearly larger part, the one held in the middle;
- finds a seam with **no dark gutter line**: a shaded page meeting a brighter one in a rise of at least 22 grey levels within 8% of the width, up to the brightest paper. The seam goes at the top of the rise.

**Result** on the 20 book photos, scored against corners marked by hand (`test/book_detection_test.dart`): mean overlap 0.54 → 0.83 at photo size, 0.57 → 0.83 at preview size; photos at 85% or better 2 → 10 and 2 → 8. Before/after image: `screenshots/book_crop_before_after.jpg` in the project files. Detection takes about twice as long (21 ms against 11 ms per preview frame on the cloud test machine; not measured on a phone).

Tried and dropped: moving each corner to the strongest edge contrast nearby. It fixed one photo and broke four, by moving corners off the frame edge that the one-page trim relies on.

## Every photo cropped (camera)

- Auto crop stays on by default (camera settings sheet).
- The outline seen on the preview stays drawn for 0.7 s after the detector loses the page for a frame, so it does not flicker.
- When the detector finds no page in the saved photo, the photo is cropped to the outline that was on the preview when it was taken. Preview frames and photos come from the same camera preset; if a phone streams the preview at a different shape than the photo, this fallback crop will be off, and the user adjusts it.
- Every crop can be adjusted later in the crop screen.

## Crop all selected pages (Batch Review)

Crop now opens a choice for the selected pages (Select all covers the whole document):
- **Auto crop**: finds the page in each photo, with progress and Cancel. Pages with no page found keep their crop. One undo step; the message says how many were cropped and on how many no page was found.
- **Full photo**: removes the crop from every selected page. One undo step.
- **Adjust each page**: the guided crop queue, as before.

## Tests

- `test/book_detection_test.dart`: overlap with the hand-marked pages, at photo and preview size (mean at least 0.8, at least 8 photos at 0.85). It fails on the old detector (0.54).
- `test/sample_pages_test.dart`: book page 05 is outlined as its page, not the strip beside it (it used to give the strip, then nothing).
- `test/batch_crop_queue_test.dart`: Auto crop on three pages (one with no page found) and its undo; Full photo; the queue through Adjust each page.
- `test/capture_modes_test.dart`: a photo with no page found is cropped to the preview outline; the outline stays drawn when the page is lost for a frame.
