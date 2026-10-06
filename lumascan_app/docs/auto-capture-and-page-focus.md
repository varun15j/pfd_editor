# Auto capture page change and one-page focus

Covers US-03.9 and US-03.10, use cases UC-11 and UC-12, and requirements CAP-09 and CAP-10 (see `epics-user-stories.md` and `requirements.md`). Added to the continuous camera on 2026-10-06.

## Problem

1. **Duplicate pages.** Auto capture re-armed after a capture whenever one analysed frame had no page outline (detector flicker or a dark frame), or when the outline moved more than 12% of the frame. Turning a book page or swapping a sheet in the same place leaves the outline where it was, while a flicker re-armed it at once. The same page was taken again and again.
2. **Half pages in the outline.** The page detector keeps the largest paper region. With an open book held over one page, the gutter is often too light to split the paper, so the outline covered the page plus the visible half of the next one. Book mode then split that region in two, giving one whole page and one half page.

## Page change detection (US-03.6)

Code: `lib/features/batch_capture/auto_capture.dart` (`AutoCaptureTracker`, `pageSignature`, `signatureDiff`), fed by `analyzeFrame` in `camera_frame.dart`.

- **Page signature.** For each analysed frame with a page, the page inside the outline (minus an 8% margin) is averaged into a 6 x 8 grid. Every pixel of a cell is sampled, so lines of text do not alias. Values are centred on the page mean and divided by the page contrast (floor of 8 grey levels), so exposure changes and camera movement do not change the signature. `signatureDiff` is the mean absolute difference; the same page lying still stays under about 0.3.
- **Steady.** A frame is steady when the corners moved at most 2.5% of the frame and the signature changed by at most 0.5 since the last frame. The steadiness setting (3, 5 or 8 frames) is the number of steady frames in a row needed to shoot.
- **Scene signature.** The same 6 x 8 grid is also taken over the whole frame, edge to edge (`sceneSignature`).
- **After a capture** the tracker waits ("Turn to the next page"). A frame disturbs the view when the scene signature differs by 0.4 or more from the captured frame or from the previous frame: a hand or a turning page sweeping across, or a different page lying there. Two disturbed frames in a row mean a new page. The tracker then requires the full steady count again before shooting.
- **Why the whole view and not the outline.** On the emulator (2026-10-06) a still scene was retaken about every 30 s: the detector flipped between two outline guesses, and each jump looked like a new page. Outline loss or jumps are now ignored while the view itself is unchanged. Without scene signatures (older callers, tests) the tracker falls back to the outline: lost, moved more than 12%, or page content changed by 0.7.
- **Manual shutter.** `_shoot` calls `captured()` for page modes, so a tapped page is not taken again automatically.

Why not compare the settled page with the captured one? With a 200 px preview, two pages of dense text produce nearly the same coarse signature, while a 1% outline error on the same page changes a fine signature as much. Tests with synthetic text pages showed the two overlapping, so the decision rests on the disturbance that every page turn or swap causes.

## One-page focus (US-03.7)

Code: `lib/imaging/page_focus.dart` (`focusOnePage`), called at the end of `detectPageQuad`, so it applies to the live outline, the crop found on saved photos and imported photos.

- Brightness is averaged along 100 lines across the outline (and then down), skipping the outer 10%. A seam is a dip at least 14 grey levels and 12% darker than the brightest paper 3 to 12 steps on both sides, searched between 15% and 85%. Text columns do not qualify because the paper next to them is just as dark.
- The part beyond the seam is dropped only when it runs off the frame (outline edge within 2% of the frame edge) and is at most 85% as wide as the page kept. Two whole pages in view stay together.
- Book mode: `showsSpread` treats the outline as a spread when it reaches across the middle of the frame (left edge below 40%, right edge above 60%), or when no page is found. At the shutter, a spread makes two pages split at the spine; otherwise one page, cropped by the detector. The LEFT PAGE / RIGHT PAGE guides show only for a spread.

## Tests

- `test/capture_modes_test.dart`: tracker cases (flicker and dark frames do not retake, a page turned under a still outline is taken once it settles, a page taken away counts as new, mid-turn is not steady), signature stability under camera movement and exposure, a camera-screen test feeding flicker, a dark frame and a page turn, and Book held over one page making one page.
- `test/page_focus_test.dart`: half of the next page on the right or left is trimmed, a whole spread is kept, a single page of text is untouched.

## Limits and tuning

- Thresholds were set on synthetic images; check on devices, especially fast page flips (fewer than two analysed frames disturbed) and pages with very faint gutters. A missed turn falls back to the shutter.
- Seams are searched straight across and straight down the outline only; a strongly skewed second page may stay in.
- A clipped spread whose second page shows more than 85% of its width is kept as a spread.
