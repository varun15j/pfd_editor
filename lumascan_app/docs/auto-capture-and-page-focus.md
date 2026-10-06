# Auto capture page change and one-page focus

Covers US-03.9, US-03.10 and US-03.11, use cases UC-11 and UC-12, and requirements CAP-09, CAP-10 and CAP-11 (see `epics-user-stories.md` and `requirements.md`). Added to the continuous camera on 2026-10-06.

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

## A page held too long (US-03.11)

Reported on the OnePlus (2026-10-06): holding a page in front of the camera for 30 to 60 seconds before turning it took the same page several times.

**Cause.** The hand drifts and the light changes a little each frame. No single frame differs much from the one before, but the scene signature drifts more than 0.4 away from the captured frame, so the tracker counted every frame as disturbed and re-armed. `test/held_page_test.dart` replays a book photo drifting 20 x 40 px and fading by a fifth over 400 frames (about a minute): the old tracker took it twice.

**Fix, two layers.**

1. **Follow drift.** While waiting for the next page, every quiet frame (scene changed less than 0.15 from the frame before) becomes the new reference. Slow drift never adds up to a new page; only a sharp change, such as a hand or a page sweeping over the view, still re-arms. The fallback without scene signatures follows the outline and page signature the same way.
2. **Read the page.** With auto capture on, each new photo in Docs, Book and OCR Doc is read with OCR in the background (`PageIdentity` in `page_identity.dart`), and compared with the photo before:
   - page numbers: lines holding only a number ("28", "- 28 -", "(28)", "Page 28"). Different numbers mean a different page.
   - first and last lines, compared allowing for misread letters (edit distance, 80% alike).
   - words of three letters or more: two readings of one page share at least 60% (40% with the same page number); different pages of one book share far fewer.
   A photo auto capture took of the same page again is removed from the draft (undo brings it back) and the camera says "Same page as page N, not kept". Photos taken with the shutter are always kept, and retakes are never checked. Pages with too little text (fewer than six words: photos, blank pages, scripts ML Kit cannot read) are always kept.

Comparing pixel signatures was tried first on the 20 book photos: pages 28 and 30 of the open book differ by 0.14 on a fine 24 x 32 whole-frame grid, while one page moved by 3% differs by up to 0.25, so pixels cannot tell a page from its neighbour. Text can.

## One-page focus (US-03.7)

Code: `lib/imaging/page_focus.dart` (`focusOnePage`), called at the end of `detectPageQuad`, so it applies to the live outline, the crop found on saved photos and imported photos.

- Brightness is averaged along 100 lines across the outline (and then down), skipping the outer 10%. A seam is a dip at least 14 grey levels and 12% darker than the brightest paper 3 to 12 steps on both sides, searched between 15% and 85%. Text columns do not qualify because the paper next to them is just as dark.
- The part beyond the seam is dropped only when it runs off the frame (outline edge within 2% of the frame edge) and is at most 85% as wide as the page kept. Two whole pages in view stay together.
- Book mode: `showsSpread` treats the outline as a spread when it reaches across the middle of the frame (left edge below 40%, right edge above 60%), or when no page is found. At the shutter, a spread makes two pages split at the spine; otherwise one page, cropped by the detector. The LEFT PAGE / RIGHT PAGE guides show only for a spread.

## Tests

- `test/capture_modes_test.dart`: tracker cases (flicker and dark frames do not retake, a page turned under a still outline is taken once it settles, a page taken away counts as new, mid-turn is not steady), signature stability under camera movement and exposure, a camera-screen test feeding flicker, a dark frame and a page turn, and Book held over one page making one page.
- `test/held_page_test.dart`: a book photo held and drifting for a minute is taken once; after that, turning to the next page still takes it.
- `test/page_identity_test.dart`: page numbers, first and last lines, the same page read with misread letters, the next page, and a form with alike text but another page number.
- `test/capture_modes_test.dart`: the same page taken twice by auto capture is kept once with the toast; taken twice with the shutter, both are kept.
- `test/page_focus_test.dart`: half of the next page on the right or left is trimmed, a whole spread is kept, a single page of text is untouched.

## Limits and tuning

- Thresholds were set on synthetic images; check on devices, especially fast page flips (fewer than two analysed frames disturbed) and pages with very faint gutters. A missed turn falls back to the shutter.
- Seams are searched straight across and straight down the outline only; a strongly skewed second page may stay in.
- The repeat check needs ML Kit text (Latin script). Each auto-captured photo is read once more in the background, which adds background work per page; its cost on a phone is not measured yet.
- Two auto captures of the same page with a different page taken by hand in between are both kept: each photo is compared only with the photo just before.
- A clipped spread whose second page shows more than 85% of its width is kept as a spread.
