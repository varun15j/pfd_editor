# Edge model: refining page detection in four phases

Started 2026-11-14 on branch `feature/edge_model`, after the research report "Document edge detection: Adobe Scan, CamScanner and LumaScan" (in the project's documents). The report sorts every way of marking a page's boundary into four approaches. This work takes them one at a time, one improvement a phase, each measured on the sample book pages and handwritten notebook pages in this repository before the next begins.

| Phase | Approach | Used by | What LumaScan gains |
| --- | --- | --- | --- |
| 1 | Classical edges: gradients, lines, contours | OpenCV scanners, Smart Engines, LumaScan's hand-made detector | The spine of an open book as a scored leaning line |
| 2 | A learned map of the page, then classical geometry on it | Dropbox, Adobe Scan, Apple Vision | The model also draws the page's area; an outline is used when corners and area agree |
| 3 | Direct corner regression | Genius Scan, DocAligner, LumaScan's corner model | A corner seen in two places is read as two; Book mode gets both pages of an open book |
| 4 | Dense warp: flatten the page, not just crop it | CamScanner, DocTr, UVDoc | The flattening measured on 48 real pages for the first time; strongly curled pages are no longer skipped |

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

**How the tests run.** The ONNX model cannot run inside `flutter test` (the native library is not there). So `tool/corner_model_training/dump_heatmaps.py` writes the model's raw output maps for all 72 photos to `test/fixtures/edge_model/`, and the Dart tests read those and run the app's own code on them: reading the maps, falling back to the hand-made detector, everything after the network. `test/edge_model_benchmark_test.dart` is the score of the whole crop; it prints the mean for each set. Two sets of maps are kept: `v1_heldback` (the model as it was before this branch, trained without the 22 photos) and `v2_heldback` (the model of phases 2 and 3, trained without them).

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

## Phase 2: a learned map of the page

Dropbox, Adobe and Apple do not ask a network for corners. They ask it for a picture: which pixels are page, or which are page edge. Geometry on that picture then gives the outline. The picture can be checked against itself in a way four numbers cannot.

### What changed

**The model draws the page as well as its corners.** The last layer of the corner model was widened from four output maps to six: the four corner heatmaps as before, the page's **area** (1 inside the page, 0 outside) and the page's **outline** (a line along its four sides). Everything before the last layer is shared, so the model is no larger to speak of (4.78 MB) and no slower. The two new maps start from nothing and learn from the same hand marks (`MAPS=corners+page` in `train.py`, the default). Only five maps are shipped: the outline map helps in training, but nothing in the app reads it (see "Tried and dropped").

**The app checks the corners against the area** (`pageOutline`, `lib/imaging/corner_model.dart`). For an outline read from the corners, its *agreement* is its overlap with the area map, 0 to 1. It is used three ways:

1. **An unsure corner no longer throws the outline away.** Before, any corner peak under 0.5 sent the photo to the hand-made detector. Now the outline is still used when agreement is 0.87 or more: the corner is under a thumb or off the frame, but the page is plain to see (book 12: weakest corner 0.49, agreement 0.89, crop 0.85 to 0.91).
2. **Corners with no page between them are dropped.** Under 0.5 agreement the outline is not used however sure the corners are.
3. **It chooses between readings** when a corner shows in two places (phase 3).

### Result

The fair test: 22 held-back photos, models trained without them.

| | Books | Colour book | Made pages | Notebook | Odds book | All |
| --- | --- | --- | --- | --- | --- | --- |
| Baseline | 0.760 | 0.873 | 0.972 | 0.787 | 0.857 | 0.862 |
| Model with page maps, old rule (every corner at least 0.5) | 0.804 | 0.893 | 0.966 | 0.759 | 0.902 | 0.886 |
| **Model with page maps, corners checked against the area** | 0.854 | 0.894 | 0.966 | 0.800 | 0.924 | **0.905** |

The model in these two rows is kept outside the repository (its maps are in the project files under `edge_detection_research/phase2_3_model/`); the tests run on phase 3's model, which replaced it. The last row also has phase 3's way of reading the corners in it; the two were built together because rule 3 needs both. Taken one at a time the steps are each about the size of the noise (0.02). Together, 0.862 to 0.905 is twice the noise, and it comes from the photos that were wrong: book 04 0.60 to 0.82, book 20 0.63 to 0.88, odds 01 0.64 to 0.88. No photo got worse by more than 0.03.

**Frames with no page.** 74 frames with no page in them (34 crops of the sample photos' backgrounds, 30 plain gradients, 10 noise): the new rule gives an outline on 4 and the old rule on 5. Three of the four are crops that hold the unmarked facing page of a book, where an outline is right. One is a pencil box on a desk, which both rules take for a page.

### Tried and dropped

- **An outline from the area map alone** (the largest four-sided shape round the area, the way Dropbox reads its edge map): 0.882 on the fair test, below the corners (0.893 with the same model) on every set but books. The area map's rim is soft where the corner peaks are sharp. It is not used as a fallback either: where the corners fail, it fails too (odds 01: 0.67, the hand-made detector 0.88).
- **The outline map.** Reading sides off it would be phase 1's side snapping with a learned edge map. Phase 1 showed the corners are already as exact as the hand marks, so there is nothing for it to add on these photos. It stays in training only.

## Phase 3: corner regression

The corner model is this approach already: four heatmaps, one per corner. Two things were wrong with how it was trained and read, both on open books.

### What changed

**A corner in two places is read as two** (`readCornerPeaks`, `readPageOutlines`). With both pages of a book in view, the top right corner of "the page" is at the spine if the left page is meant and at the far edge if the spread is meant, and the heatmap shows both. The old reading took the centre of everything above half the peak, which is a point between the two, on neither (book 20: 0.63). Now each blob of a heatmap is a *place* (up to three per corner), every choice of one place per corner that makes a sound four-sided shape is a *reading*, and the readings are ranked by how strongly their corners stand out times their agreement with the area map (or, for a model without one, how nearly parallel their opposite sides are). On the old model alone this takes the fair score from 0.862 to 0.873, books from 0.760 to 0.809.

**The model is trained to show every marked corner** (`PLACES=every`, the default). Where a photo lists more than one right outline (either page, or the spread), training used only the first, so the model learned to hide the other page's corners, and Book mode could not get at them. Now the corner heatmaps are taught the corners of every marked outline, while the area map still shows the first, the page a user would most likely want.

**Book mode asks for both pages** (`CornerModel.find(image, spread: true)`, used by `splitSpread` and by the camera preview in Book mode). It takes the reading that reaches across the middle of the frame and is at least one and a half times the size of the first choice, when each of its corners stands out by 0.4 or more. Otherwise it gets the usual outline. Before, the model in Book mode marked one page of a real open book, so the app took the book for a single page and did not split it.

### Result

Usual crop, fair test (22 held-back photos):

| | Books | Colour book | Made pages | Notebook | Odds book | All |
| --- | --- | --- | --- | --- | --- | --- |
| Phase 2 model (first marked outline only) | 0.854 | 0.894 | 0.966 | 0.800 | 0.924 | 0.905 |
| **Trained on every marked corner (the recipe that ships)** | 0.815 | 0.898 | 0.972 | 0.792 | 0.939 | **0.902** |

The same, within the noise: teaching the model the other page's corners costs the usual crop nothing.

Book mode, on the eight sample photos of an open book with both pages marked. Overlap of the outline with the whole spread:

| Photo | Asked the usual way | Book mode |
| --- | --- | --- |
| Book 15 | 0.479 | 0.863 |
| Book 18 | 0.513 | 0.964 |
| Book 19 | 0.536 | 0.929 |
| Book 20 (held back) | 0.647 | 0.924 |
| Made spreads k01, k02, k05 | 0.997, 0.987, 0.989 | the same |
| Odds 06 (held back) | 0.616 | 0.616 |
| **Mean** | **0.720** | **0.909** |

A real open book is now found whole on four of five photos, where it was found whole on none. Only two of the eight were held back from training, so this is weaker evidence than the fair test: book 20 shows it carries over to an unseen photo of the same book, odds 06 (another book, its far page's corners at 0.34 to 0.36) shows it does not yet carry over to a book the model has never seen. More open-book photos from other books are what this needs.

On the 64 photos of a single page, Book mode gives the same outline as the usual way on 63. The one that changes is book 12, an open book with only its right page marked, where Book mode takes both pages, as it should.

**Tests.** `test/corner_model_test.dart`: a corner in two places, the area map choosing the page, Book mode taking both pages and keeping a single page, and the rules of `pageOutline`. `test/edge_model_benchmark_test.dart`: the fair score of the whole crop for the old and the new model (at least 0.86 and 0.89), Book mode on the eight spreads (at least 0.88), and Book mode leaving single pages alone.

## The model that ships (`assets/models/lcnet100_256_lumascan_v2.onnx`)

Trained on all 66 marked photos with phase 2's page maps and phase 3's corners (`train.py 1 1500`, 37 minutes on four CPU cores), then written out with the five maps the app reads. 4.79 MB, 11 KB more than v1.

The whole crop on all 72 photos, as the app makes it. 66 of them were seen in training, so only the odds book column is a fair one:

| | Books | Colour book | Made pages | Notebook | Odds book | All |
| --- | --- | --- | --- | --- | --- | --- |
| v1 with the app as it was | 0.876 | 0.978 | 0.985 | 0.933 | 0.854 | 0.938 |
| **v2 with the app as it is now** | 0.918 | 0.975 | 0.987 | 0.908 | **0.941** | 0.955 |

The odds book, which no model was trained on, goes from 0.854 to 0.941. The hand-made detector now steps in on 1 of the 72 photos. The notebook's 0.933 to 0.908 is five photos the model has seen, with marks good to 3%; the fair notebook score is under "Handwritten notebook pages" below.

**Not measured.** Speed on a phone. The network is the same up to its last layer, which now makes five maps instead of four, and reading the maps adds a few passes over 128 x 128 cells, so no real change is expected; it has not been timed on the OnePlus.

## Handwritten notebook pages

There are five handwritten notebook photos in the repository, and the fair test above holds back only one of them (0.787 before, 0.792 after: no change). A fairer reading, with all five held back from training, is being run and will be added here.

## Phase 4: dense warp (flattening the page)

The first three approaches end with four corners, and four corners can only undo a tilt. A page in an open book also curves, so after the crop its lines of text still bow and slope. The fourth approach moves every part of the page by its own amount. CamScanner does this with a network; LumaScan already had a hand-made version, `flattenBookPage` (`lib/imaging/book_fix.dart`, part of Book page fix on Pro), which had never been measured on real pages.

### How it is measured

48 page pictures: every book, colour book and odds book photo, cropped at its hand-marked corners. On each, the lines of text are found and two numbers are read:

- **Bow**: how far a line's middle strays from the best straight line through it, as a share of the page height. A flat printed page reads about 0.08% (the colour book), which is the floor of this measure.
- **Slope**: how far the lines lean from level, in degrees.

Pages with fewer than three lines of text (full-page pictures) are left out, which leaves 42 or 43. The scripts are in the project files under `edge_detection_research/phase4_flatten/`.

### Result

| | Books (18) | Colour book (18) | Odds book (6) |
| --- | --- | --- | --- |
| Cropped only | bow 0.185%, slope 3.05° | 0.093%, 0.82° | 0.244%, 2.59° |
| Flattened, before this branch | 0.118%, 1.04° | 0.092%, 0.63° | 0.174%, 2.15° |
| **Flattened, now** | 0.118%, **0.67°** | 0.092%, 0.63° | 0.174%, 2.15° |

So the existing flattening was already doing its job on the book pages: it takes out a third of the bow and two thirds of the slope, and leaves the flat colour book pages alone. This is the first time that has been put in numbers.

**The improvement: strongly curled pages.** The flattening gave up on a page when any band of its lines bent by more than 10% of the page height, on the reading that so much must be a mismatch. Book page 14, a page curling up off a thick book, bends by 11%, so the worst page in the set was the one left untouched. The limit is now 16% (`_mostBend`). Page 14 goes from a slope of 7.4° to 0.9°, and the text line finder, which could follow 5 of its lines before, follows 11. No other page changes.

### Tried and dropped

- **A second pass over the flattened page.** No gain (books 0.122%, 1.06°). What is left after one pass is at the floor of the measure.
- **Using one band of text for the whole page.** Picture pages with text only at the top or bottom (four of the six odds book pages) are skipped, because the bend must be followed in at least two bands. Letting one band stand for the whole page lowered their slope from 2.15° to 1.68° but left the bow as it was and tilted pictures elsewhere on the page. Not worth the risk.

### Not done: a dewarping network

The research report names UVDoc (MIT licence, 32 MB of weights) as the open model nearest to what CamScanner does. Its code and weights were downloaded for a comparison on the same 48 pages, but running downloaded third-party code was stopped by the safety rules of the cloud machine this work ran on, and needs Varun's say-so. Until it is measured, nothing can be said about whether it would beat 0.118% on these pages, which are only mildly curved; it would add 32 MB to the app and about a second a page.

**Tests.** `test/book_fix_test.dart`: "a page curling up strongly is flattened too" (a bend of an eighth of the page height, which the old limit refused).
