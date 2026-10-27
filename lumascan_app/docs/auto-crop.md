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

## Edge outlines, colour preview and speed (October 2026)

**Test pages.** `sample_photos/edge/` holds 19 photos made by `tool/make_edge_samples.py` from real page content (the KV question papers, the odds book and the book photos) laid on wood, concrete, a bedsheet, carpet, cloth and a black desk, with shadows, fingers, tilt and noise. Seven are colour pages, seven black and white (two as greyscale photos), five open books (spreads with a curved gutter, one page in view). Because they are made, the page corners are known exactly (`corners.json`). In a debug build, **Add edge test pages** (Settings > Developer, or the debug panel) imports them. The six odds book photos (real colour pages) now also have hand-marked corners.

**Edge outlines.** The detector has a fourth candidate mask, taken from open-source OpenCV document scanners (a grey closing, edges, closed outer contours; no code copied, only the method): the brightness is closed with a min/max filter wider than a text line so the print disappears, Sobel edges of the brightness and the smoothed colour are traced with Canny-style hysteresis, and whatever the frame border cannot reach without crossing an edge is inside an outline. It finds a page split by a shadow or lying on a surface of its own shade.

**Colour in the camera preview.** Preview frames were read as brightness only, so a coloured page as bright as the table could not be told from it. Android NV21 frames now keep their colour plane (camera_android_camerax sends one plane: brightness, then V and U at half size), iOS BGRA frames keep theirs, and `analyzeFrame` finds the outline in a 200 px colour copy. Auto capture, the page signature and QR still read the brightness.

**Speed.** The corner nudging rescored the whole mask for every trial move; it now uses running sums along each row, so a trial costs one subtraction per row. Erosion and dilation run as a row pass and a column pass. Results are unchanged by both, and a preview frame takes about 19 ms instead of 62 ms on the cloud test machine (not measured on a phone).

**Result** (overlap with the true page, 2026-10-26):

Before is the detector on 25 October 2026 with grey preview frames; after is this change with colour preview frames.

| Set | Photo (640 px) | Preview (200 px) |
| --- | --- | --- |
| Edge test pages, colour | 0.97 → 0.97 | 0.83 → 0.95 |
| Edge test pages, black and white | 0.75 → 0.80 | 0.74 → 0.78 |
| Edge test pages, books | 0.92 → 0.92 | 0.84 → 0.93 |
| 20 book photos | 0.83 → 0.83 | 0.79 → 0.82 |
| 6 odds book photos | 0.83 → 0.83 | 0.91 → 0.83 |

The odds book photos lose in the colour preview: 03 (0.82 → 0.69) and 05 (0.97 → 0.67) have a laptop screen and coloured cables beside the book, and in colour the outline takes in part of them. Their scores at photo size, which also uses colour, were already 0.67 and 0.71.

Pages that got better: a page with a shadow across it (b02) 0.71 → 0.97; a white page on a white bedsheet (b03) 0.89 → 0.97; a colour page on a beige table in the preview (c02) no page → 0.85.

Still weak, kept as targets: a narrow slip such as a receipt (b05; rejected as a strip of a page), a colour page on wood in a greyscale photo (b07, 0.66), and in the preview one page of an open book with a thumb over it (k03, 0.72) and the book photos where the lap under the book is as light as the page (16, 17).

Tried and dropped: rejecting outlines whose corners are far from square, as some open-source scanners do. Real book photos lose their outline altogether (05 and 09 went to nothing), because a page running off the frame has a cut corner.

**Colour book photos.** Varun scanned 22 pages of a colour textbook with this build on the OnePlus; they are in `sample_photos/colour_book/` with hand-marked corners. Scored at photo size the mean overlap is 0.84 (0.82 before this change; 17, a spread of colour photos, found nothing before), 0.79 in a colour preview frame, with 13 and 14 of 22 pages at 0.9 or better. They showed that an edge outline could close round a hand over a blurred page (16 fell to 0.03), so edge outlines must now have corners near square (between 53 and 127 degrees); the other masks are not held to this, since a page running off the frame has a cut corner. Still weak: page turns (03, 16 in the preview), the scroll border inside 04, and pages split by a big photo or a coloured panel (17, 18, 22).

**Background, page type and page size (Varun's three steps, 2026-10-26).** Each was built and measured on all the sets above; only the first is kept.

- *Background colour.* The surface colour is now the most common hue along the frame border, not the median of the whole border, since pens, a laptop, a hand or the book itself can cover much of it, and brightness counts for less than colour in the distance from it (light falls off across a desk). Kept: a colour page on a beige table in the preview (c02) 0.84 → 0.97, book photos in the preview 0.817 → 0.823, colour book unchanged; one open book with a thumb over it (k03) drops 0.92 → 0.79 at photo size.
- *Page size.* The outline's true ratio, with the camera's tilt undone (Zhang and He's whiteboard method, focal length about 0.65 of the frame diagonal), was compared with real paper: 1.41 for A3, A4, B4 and B5, 1.29 for Letter and magazines, about 1.37 for textbooks, 1.5 to 1.65 for book pages. Outlines outside 1.16 to 1.8 were rated down. Dropped: it changed one photo of the 69 (book 20, 0.87 → 0.79). Most wrong outlines run off the frame, where the ratio cannot be judged, and whole outlines were already page-shaped.
- *Page type from straight lines.* A Hough transform of the edge map gave the strongest near-level and near-upright lines; every pair of each, with the frame border as a fallback side, was tried as a page and scored by how much of each side lies on an edge and how paper-like its shape is. Dropped: it helped the made book pages (k03 0.79 → 0.94) and a shadowed page, but on the colour book the desk edge and the book's bottom edge are both strong lines, and it took the desk (colour book 0.845 → 0.82 at photo size, page 16 0.87 → 0.47). Also tried: rating an outline down where the desk lies just inside its edge; it lost book photo 10 altogether.

The colour book pages that still fail (04, 06, 17, 18, 22, page turns 03 and 16) lie on a wooden desk the same tone as the book's edge, beside the facing page; hand-made rules have run out of room there.

**Tests:** `test/colour_book_detection_test.dart` (the 22 colour book photos), `test/edge_samples_test.dart` (each edge test page at photo size, as a colour preview frame and as a grey one, the odds book photos, and a loose time limit for a preview frame), `test/camera_colour_frame_test.dart` (NV21 and BGRA frames come out in colour, and the c02 page is outlined from a colour frame where the grey frame found none).

## Corner model in the camera preview (October 2026)

The hand-made detector had stopped improving on colour pages (see above), so the camera preview now asks a small open-source neural network first: DocAligner's LCNet heatmap model (DocsaidLab, Apache-2.0, 4.8 MB, `assets/models/`). It reads a 256 x 256 colour copy of the frame and gives one heatmap per corner. Its outline is used only when every corner's peak is at least 0.8 (`minCornerConfidence`); otherwise the hand-made detector decides, as before. It runs with ONNX Runtime (`onnxruntime_v2`, FFI, two threads) in one long-lived isolate that loads the model once (`FrameWorker`). Pro and Gold only, like the rest of smart scanning; if the model cannot load, the preview falls back to the hand-made detector. Imported photos and the capture crop still use the hand-made detector.

**What it is good at.** A whole page in view, whatever its colour, print or surface: on the made test pages it scores 0.98 to 0.99 where it is sure, including the narrow slip (b05, no page before) and the colour page in a greyscale photo (b07, 0.66 before).

**What it cannot do.** It finds nothing when a corner is out of the frame. It was never sure on any of the 22 colour book photos, where the open book fills the frame, so those keep the hand-made detector's result.

**Result** (overlap with the true page, hand-made detector alone → with the model first, scored with `onnxruntime` in Python on the same photos, 2026-10-27):

| Set | Photo (640 px) | Preview (200 px) |
| --- | --- | --- |
| Edge test pages, colour | 0.97 → 0.97 | 0.97 → 0.97 |
| Edge test pages, black and white | 0.79 → 0.99 | 0.78 → 0.98 |
| Edge test pages, books | 0.89 → 0.93 | 0.92 → 0.95 |
| 20 book photos | 0.83 → 0.83 | 0.82 → 0.84 (17: 0.69 → 0.93) |
| 6 odds book photos | 0.84 → 0.84 | 0.83 → 0.83 |
| 22 colour book photos | 0.85 → 0.85 | 0.79 → 0.79 |

The made test pages are cleaner than real photos and close to what such models are trained on, so the gain there is likely larger than on real pages. The model takes about 30 ms per frame on the cloud test machine (onnxruntime, CPU); on the phone it is not yet measured. The FastViT-T8 variant was also tried and was sure of fewer pages.

**Tests:** `test/corner_model_test.dart` (heatmaps to corners, the model input, and that the preview uses the model only when it is sure and only with smart scanning). The model itself does not run in `flutter test` (no native library there).
