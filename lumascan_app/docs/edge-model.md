# Edge model: refining page detection in four phases

Started 2026-11-14 on branch `feature/edge_model`, after the research report "Document edge detection: Adobe Scan, CamScanner and LumaScan" (in the project's documents). The report sorts every way of marking a page's boundary into four approaches. This work takes them one at a time, one improvement a phase, each measured on the sample book pages and handwritten notebook pages in this repository before the next begins.

| Phase | Approach | Used by | What LumaScan gains |
| --- | --- | --- | --- |
| 1 | Classical edges: gradients, lines, contours | OpenCV scanners, Smart Engines, LumaScan's hand-made detector | The spine of an open book as a scored leaning line |
| 2 | A learned map of the page, then classical geometry on it | Dropbox, Adobe Scan, Apple Vision | *in progress* |
| 3 | Direct corner regression | Genius Scan, DocAligner, LumaScan's corner model | *to do* |
| 4 | Dense warp: flatten the page, not just crop it | CamScanner, DocTr, UVDoc | *to do* |

Earlier history of the detector and of the corner model is in `auto-crop.md`. This file covers what changed on this branch and why.

## How it is measured

**Photos.** 72 photos with the page marked by hand (corners as a fraction of the photo):

| Set | Photos | Where | Marks |
| --- | --- | --- | --- |
| Books | 20 | `sample_photos/book/` | `test/book_detection_test.dart`, to about 2% of the frame |
| Colour book | 22 | `sample_photos/colour_book/` | `test/colour_book_detection_test.dart` |
| Made edge pages | 19 | `sample_photos/edge/` | `corners.json`, exact |
| Handwritten notebook | 5 | `sample_photos/0*.jpg` | `tool/corner_model_training/data.py`, to about 3% |
| Odds book | 6 | `sample_scan_img/odds_book/` | `test/edge_samples_test.dart` |

Where a photo of an open book could fairly be cropped more than one way (either page, or the whole spread), each is listed and the best match counts.

**Score.** Overlap of the outline found with the marked page (intersection over union, 0 to 1). 0.95 is a crop a user would not touch; 0.85 needs a nudge on one side; under 0.7 is the wrong thing cropped.

**A fair test.** The model shipped in the app has seen 66 of the 72 photos in training, so it scores 0.95 on them and that says little. Every phase is therefore scored on **22 held-back photos** with a model trained without them: every 4th marked photo (5 book, 5 colour book, 5 made, 1 notebook) and the 6 odds book photos, which are never trained on. Once a phase is accepted, the model that ships is trained again on all 66.

22 photos is a small test. One photo going from wrong to right moves the mean by 0.01 to 0.02, and two training runs of the same recipe differ by about as much. Differences smaller than 0.02 are not read as gains.

**How the tests run.** The ONNX model cannot run inside `flutter test` (the native library is not there). So `tool/corner_model_training/dump_heatmaps.py` writes the model's raw output maps for all 72 photos to `test/fixtures/edge_model/`, and the Dart tests read those and run the app's own code on them: reading the maps, falling back to the hand-made detector, everything after the network. `test/edge_model_benchmark_test.dart` is the score of the whole crop; it prints the mean for each set.

```bash
flutter test test/edge_model_benchmark_test.dart test/spine_line_test.dart
```

## Baseline (2026-11-14)

The whole crop as the app made it before this branch: the corner model's outline when every corner peak is at least 0.5, otherwise the hand-made detector.

| | Books | Colour book | Made pages | Notebook | Odds book | All |
| --- | --- | --- | --- | --- | --- | --- |
| Shipped model, all 72 photos (66 seen in training) | 0.876 | 0.978 | 0.985 | 0.933 | 0.854 | 0.938 |
| **Fair: 22 held-back photos** | 0.760 | 0.873 | 0.972 | 0.787 | 0.857 | **0.862** |

On the same 22 photos the hand-made detector alone scores 0.835, and the model alone (its outline used however unsure it is) 0.875. The fair notebook score rests on a single photo.

Where the fair score is lost:

- **Open books.** With both pages in view, a corner heatmap often shows two places: the top of the spine and the far page's corner. The reading code takes the centre of everything above half the peak, which lands *between* them, in the middle of the far page (book 20: 0.63; odds 01: 0.64; odds 06: 0.77). Phase 3 deals with this.
- **Unsure corners.** A corner under a thumb or off the frame gives a weak peak; under 0.5 the model's outline is dropped for the hand-made detector's, which is usually worse (book 04: the model's own outline 0.83, the detector's 0.60).
- **One page of a spread taken for another region** (colour book 04: 0.58).

## Phase 1: classical edges

Two things were tried. One is kept.

### Tried and dropped: moving each side onto the strongest edge beside it

The idea, from the report's "refine each side of the model's outline on an edge map": the model puts a corner within a few percent of the frame; a classical edge map could then pull each side exactly onto the paper's edge.

Each side of the model's outline was tried at every pair of end shifts along its normal, one pixel apart at a 320 pixel work size, within 2% or 4% of the photo, so it could slide and turn. A candidate line was rated by the *step* across it: brightness and two colour differences just inside the line minus just outside, averaged along the line with the sign kept, so text and ruled lines cancel and a thin dark line scores nothing. A side moved only when the edge found was strong in its own right and clearly stronger than where the side was.

Result, model outlines on all 72 photos (shipped model):

| Rule | Books | Colour book | Made pages | Notebook | Odds book | All |
| --- | --- | --- | --- | --- | --- | --- |
| Outline left as the model gave it | 0.906 | 0.978 | 0.985 | 0.933 | 0.854 | **0.946** |
| Move to any clearer edge within 4% | 0.869 | 0.964 | 0.978 | 0.924 | 0.850 | 0.929 |
| Best of 72 rule sets (only sides with almost no edge under them, only onto a very strong edge, within 2%, never near the frame border) | 0.901 | 0.978 | 0.985 | 0.933 | 0.854 | 0.945 |

No rule beat leaving the outline alone, on any set. Why:

1. **A book page's edge is often not a step.** At the gutter it is paper against paper; on the lap it is cream paper against a pale cloth. The hand-marked sides themselves show a step of 1 to 10 grey levels on many book photos, where a sheet on a desk shows 60 to 200.
2. **The strongest edge nearby is often not the page's edge.** A coloured band printed inside the margin (colour book 04), the stack of pages under the top one, the soft shading at a page's rim (made page c07: the strongest step lies 1.5 to 3.5 pixels inside the true edge).
3. **The model is already as exact as its marks.** Marks are good to about 2% of the frame and the model is trained to them. On the made pages, whose corners are exact, the model scores 0.985 and snapping could not raise it.

This agrees with two earlier trials on the hand-made detector (`auto-crop.md`: "moving each corner to the strongest edge contrast nearby" and "Hough line outlines", both dropped). The experiment's code is kept outside the app, in the project files under `edge_detection_research/phase1_side_snapping/`.

### Kept: the spine as a scored leaning line (`spineLine`, `lib/imaging/book_split.dart`)

Book mode splits a photo of an open book at its spine. Until now the spine was "the darkest column in the middle third of the spread", always upright. That fails on the commonest real photo: a book on the lap with one page lying flat and the other raised. The flat page is in shade and has dark print, so the darkest column is somewhere in its text, and the spine is not upright either.

`spineLine` searches for a straight line that may lean, and rates each candidate the way Adobe's book patent rates its bind line (US 12,705,755): a score for looking like a gutter along its whole length, marked down for leaning and for lying far from the middle.

- **Candidates.** The line's top end anywhere on the spread's top side within 22% of its middle, the bottom end likewise on the bottom side, the two no more than 10% of the width apart. About 800 lines.
- **What a gutter looks like.** Two things, read at 36 points down the line (the top and bottom tenth left out, where fingers and page edges sit): a **step** in brightness from one side of the line to the other, because two pages at different angles are lit differently; and a **dip**, the line darker than the paper on both sides, because the paper curves down into the binding. The step is read twice, at 1.4% and 0.7% of the spread's width, so that of two lines over the same step the centred one wins.
- **Along the whole line.** Each is taken as what three quarters of the points show at least, the same way round. A picture, a heading or a finger over part of the spine does not hide it; a line that only crosses the gutter, or runs beside a picture for a while, scores nothing.
- **Score.** (step + 2 × dip), less 1.2% for each 1% the line's middle lies from the spread's middle, less 1% for each 1% of lean. Under 6 grey levels no line stands out, and the spread is split down the middle as before.

Brightness is smoothed down the page only, never across it: text lines blur into an even grey while the spine stays sharp.

**Result** on the eight sample photos where both pages are marked (book 15, 18, 19, 20; made spreads k01, k02, k05; odds 06), given the marked spread. Error is how far the spine found lies from the marked one, as a share of the photo's width, averaged over its two ends:

| Photo | Darkest column (before) | Scored leaning line |
| --- | --- | --- |
| Book 15 | 3.3% | 3.3% |
| Book 18 | 26.0% | 2.3% |
| Book 19 | 12.4% | 2.3% |
| Book 20 | 18.8% | 0.9% |
| Made spread k01 | 0.5% | 0.9% |
| Made spread k02 | 1.1% | 2.5% |
| Made spread k05 | 0.0% | 0.0% |
| Odds 06 | 1.5% | 2.2% |
| **Mean** | **7.9%** | **1.8%** |

The three real photos that were 12 to 26% off (the page cut through its text) are now within 2.3%. Made spread k02 is 1.4% worse: its drawn gutter shadow is a wide wedge, and the line settles on the wedge's other edge. The marks themselves are good to about 2%, so 1.8% is at the limit of what these photos can show.

It takes about 18 ms a photo on the cloud test machine, once per Book mode photo, not per preview frame.

**Limits.** The spine's ends are still put on the spread's straight top and bottom sides. Where the two pages meet in a "V" (book 18: the spine's top lies 6% of the height below the line from one outer corner to the other), each page's crop takes in a sliver above the spine. Marking the spine's own ends needs the model (phase 3). A divider the user can drag on the crop screen is not built yet.

**Tests.** `test/spine_line_test.dart`: a spine that is only a step, one that leans, one that is only a dark gutter, a blank spread (splits in the middle), a picture beside the spine (does not win), and the eight marked spreads (mean under 2.2%, none over 4%).
