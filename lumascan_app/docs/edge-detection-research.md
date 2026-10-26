# Fast page boundary detection: source review and implementation

Reviewed 26–27 October 2026. The ranking below is an engineering recommendation
for LumaScan, not a measured speed/accuracy comparison of these repositories.

## Open-source shortlist

| Repository | Algorithm / capability | Fit for this app |
|---|---|---|
| [OpenCV](https://github.com/opencv/opencv) | Canny/Sobel gradients, morphology, contours, polygon approximation, line fitting and optical flow | Strong native building blocks for a small-frame detector. Combine edge evidence with colour segmentation and quadrilateral validation; Canny alone does not identify which edges belong to paper. OpenCV 4.5+ uses Apache-2.0. |
| [st235 DocumentsScanner](https://github.com/st235/HSE.CVforMobileDevices.DocumentsScanner) | Android/C++ OpenCV document-scanner example; contour approach and an alternative Hough implementation | Useful native Android reference. The author reports preferring the contour path. MIT. Benchmark on our images before replacing the Dart detector. |
| [OSS Document Scanner](https://github.com/ossappscollective/OSS-DocumentScanner) | Android/iOS scanner using OpenCV, including its native image-processing integration | Useful complete mobile integration reference. Repository license is MIT; review bundled dependencies separately if importing code. |
| [DocsaidLab DocAligner](https://github.com/DocsaidLab/DocAligner) | Learned four-corner localization, including heatmap models and mobile-oriented backbones; ONNX inference | Candidate fallback for clutter, shadows and weak borders. Needs model/runtime integration and phone benchmarks; do not infer device FPS from desktop inference. Apache-2.0 repository. Verify the chosen model artifact's terms too. |

Two additional research references:

* [Andrew Campbell's OpenCV Document Scanner](https://github.com/andrewdcampbell/OpenCV-Document-Scanner)
  combines Canny, line-segment detection and contour candidates in Python.
  Useful for algorithm comparison, not a drop-in Flutter preview engine. A
  repository license was not verified in this review, so no code was copied.
* [DocScanner](https://github.com/fh2019ustc/DocScanner) addresses dense document
  rectification/dewarping. Its [license](https://github.com/fh2019ustc/DocScanner/blob/main/LICENSE.md)
  permits non-commercial use and requires permission for commercial use; it is
  a research reference, not a permissively licensed dependency for this app.
  Curved-page dewarping belongs after capture, with a separate performance budget.

Primary references: [OpenCV license](https://opencv.org/license/),
[Campbell detector source](https://github.com/andrewdcampbell/OpenCV-Document-Scanner/blob/master/scan.py),
[DocAligner model design](https://github.com/DocsaidLab/DocAligner#model-design),
[OSS Document Scanner license](https://github.com/ossappscollective/OSS-DocumentScanner/blob/master/LICENSE).

## Implemented in this change

The app already combines Otsu white-paper segmentation, colour-seeded and
background-distance masks, morphology, connected components, convex hulls,
quadrilateral fitting, colour/luminance edge scoring and single-page gutter
selection. Imported colour images used these features, but the custom camera
converted every frame to grayscale first. Its existing colour-image tests did
not exercise that actual camera conversion.

The preview now preserves Android packed NV21 chroma and iOS BGRA RGB values.
It converts only the sampled 200-pixel-long-side image, then detects at 160 px.
No full-resolution RGB allocation, new model, native dependency or third-party
source code is introduced. Tests cover NV21 VU ordering, limited-range YUV,
stride padding, all four rotations, luma-only fallback and background rejection.
Tracking signatures and the low-light gate still use the original grayscale
values; only boundary detection uses colour.
The Basic plan deliberately retains its existing grayscale/basic detector;
colour-aware detection follows the existing Smart Scan entitlement.

Corner refinement now caches row prefix sums for the binary mask. Each trial
outline scores each scanline with two prefix lookups instead of rescanning all
interior pixels. The integer score, trial order and tie-breaking are unchanged.

Detection remains off the UI thread, with one analysis in flight and stale
frames dropped. The current 150 ms scheduling interval caps detection updates
at about 6.7 Hz; it does not cap the camera's own preview FPS. Five stable
analyzed frames gate automatic capture. This change does not promise 30 FPS
boundary inference. Measure camera delivery, isolate transfer, detection and
painting together in a profile build on the intended phone before tightening
that interval.

Book mode retains existing gutter splitting after capture. A four-corner crop
cannot flatten a curved book page, and similar-colour paper on a similar-colour
desk, clipped corners, glare, strong motion blur and arbitrary clutter remain
hard cases. Manual crop remains available. No new learned fallback or dewarping
model has been shipped in this change.

## Reproducible sample coverage

| Corpus | Count | Purpose |
|---|---:|---|
| `sample_photos/*.jpg` | 5 | Existing real handwritten page photographs; matched reference scans |
| `sample_photos/book/*.jpg` | 20 | Existing real B&W book photos with manually marked page/spread alternatives |
| `sample_scan_img/odds_book/*.jpg` | 6 | Existing real colour craft-book photos, available in the developer sample menu |
| `sample_photos/edge_cases/*.png` | 8 | New deterministic synthetic white/black/coloured sheets and multicolour forms, with independent exact corners |

Generate the synthetic fixtures with `dart run tool/generate_edge_samples.dart`.
They include an equal-brightness colour boundary that fails through the former
grayscale preview path. They are synthetic regression fixtures, not substitutes
for real-phone validation. All four sample sets are bundled and importable in
Settings > Developer. Existing original photographs are unchanged.

Run from `lumascan_app`:

```powershell
flutter pub get
flutter test test/colour_preview_test.dart test/book_detection_test.dart test/page_detection_test.dart test/multi_colour_page_test.dart test/held_page_test.dart test/capture_modes_test.dart test/sample_pages_test.dart --reporter expanded
flutter analyze
flutter build apk --debug
```

The new preview test writes `build/edge_detection/synthetic_preview.json` with
per-format corners and median/p95 host timings. Timing excludes image decoding,
fixture creation, isolate startup/transfer and UI work; it is not phone latency.
Synthetic corners must be within 3.5% of the frame in each axis. Blank frames
must return no page. Existing book tests require mean IoU >= 0.80 and at least
8/20 pages at IoU >= 0.85, against their hand-labelled alternatives.

Before asserting production accuracy, annotate the six colour book photographs
independently, expand real coloured-sheet captures on light/dark/textured desks,
and measure IoU, corner error, misses, false positives and p95 latency separately
on each group. Hold the phone over each page and turn book pages to verify
jitter, acquisition time and duplicate-capture suppression. A passing synthetic
test or successful APK build does not establish those device results.
