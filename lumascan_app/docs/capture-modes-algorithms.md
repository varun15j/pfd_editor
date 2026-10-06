# LumaScan capture modes: product behavior, algorithms and quality plan

Version 1.0 · 5 October 2026  
Scope: `Docs`, `Book`, `Text`, `OCR Doc`, `QR`, and `Photo` capture modes

## 1. Product decision

The camera uses the shortcut label **Docs** rather than Document. Six modes share one custom CameraX/AVFoundation preview:

| Mode | User outcome | Output |
|---|---|---|
| Docs | Capture one or many flat document pages | Corrected page images plus edit recipes |
| Book | Capture an open spread while preserving left/right order and printable book layout | Original spread, corrected left page, corrected right page and pairing metadata |
| Text | Recognize text live for quick selection, copying and structured actions | Text transcript with live bounding regions; optional reference image |
| OCR Doc | Capture a full-resolution document and run accuracy-first OCR | Original page, corrected page, editable transcript and searchable PDF text layer |
| QR | Detect and decode a QR code in the live preview | Payload, type, bounding quadrilateral and user-approved action |
| Photo | Capture a normal photo without document correction | Original photo and optional photo-edit recipe |

`Text` and `OCR Doc` are deliberately separate. Text prioritizes low-latency live feedback. OCR Doc prioritizes full-resolution accuracy, reading order, layout mapping and searchable-document export.

## 2. Shared capture pipeline

1. Acquire YUV preview frames at the device-native preview rate.
2. Keep at most one analysis frame in flight; drop stale frames rather than queueing latency.
3. Normalize orientation and map detector coordinates through the preview transform.
4. Run only the detector required by the selected mode.
5. Smooth live geometry over a short frame window.
6. Require focus, exposure and geometry stability before Auto capture.
7. Capture a full-resolution still image.
8. Re-run detection on the still image for final geometry.
9. Store the immutable original first; derive corrected pages, OCR or QR results afterward.

### Stability score

For quadrilateral corners `qᵢ,t` at frame `t`, normalized by preview diagonal `D`:

```text
cornerMotion(t) = (1 / 4D) × Σᵢ ||qᵢ,t - qᵢ,t-1||₂
stability(t) = clamp(1 - cornerMotion(t) / τmotion, 0, 1)
```

Auto capture requires:

```text
stability ≥ 0.90
focusScore ≥ calibratedFocusFloor
exposureScore ≥ calibratedExposureFloor
pageArea / frameArea ≥ 0.20
```

for a continuous hold period, initially 450–700 ms and calibrated on reference devices. Thresholds are proposed starting values, not universal constants.

After a capture, auto capture does not fire again until the page has been turned or swapped: two analysed frames in a row with no page, a jumped outline, or strongly changed page content, followed by a new steady hold. One lost or dark frame never re-arms it. A cut-off second page is trimmed from the outline in every page mode. Details: [auto-capture-and-page-focus.md](auto-capture-and-page-focus.md) (US-03.9, US-03.10).

### Focus and exposure signals

Variance of the Laplacian is a useful blur signal:

```text
focusScore = Var(Laplacian(grayscale(frame)))
```

Exposure uses the luminance histogram. Reject auto capture when clipped-dark plus clipped-light pixels exceed a calibrated fraction or when median luminance falls outside the device profile. Users can always override with the shutter.

## 3. Docs mode

1. Downscale preview frame for rectangle/contour analysis.
2. Estimate the largest plausible document quadrilateral.
3. Score candidates by area, convexity, rectangularity, edge support and temporal stability.
4. On capture, refine corners against the full-resolution still.
5. Compute a homography from the source quadrilateral to the target rectangle.
6. Warp once from the immutable original and apply the chosen enhancement recipe.

Candidate score:

```text
score = 0.30·area + 0.20·rectangularity + 0.20·edgeSupport
      + 0.15·contrast + 0.15·temporalStability
```

Weights require evaluation against a labeled page-boundary dataset.

## 4. Book mode

### User flow

- Show a center-spine guide labeled Left page / Right page.
- Capture one open spread.
- Produce two pages in reading order: left then right for left-to-right books; configurable for right-to-left books.
- Preserve the original spread and a `BookSpread` record linking both derived pages.
- Let users adjust the spine and outer corners independently before export.
- Offer print layouts: individual pages, facing-page spread and booklet-ready ordering. Never silently impose booklet imposition.

### Spread detection

1. Detect the outer spread quadrilateral `Qspread`.
2. Rectify the spread to a front-facing plane.
3. Estimate the spine `x = xs(y)` using a weighted combination of:
   - center-region luminance valley;
   - vertical edge/crease evidence;
   - text-line termination density;
   - symmetry prior around the spread center.
4. Fit a robust line or low-order curve using RANSAC.
5. Split the rectified spread along the fitted spine.
6. Estimate separate left and right page boundaries.
7. Apply page-specific perspective correction and optional dewarping.

Spine candidate objective:

```text
J(x) = w₁·darkValley(x) + w₂·verticalEdge(x)
     + w₃·lineBreakDensity(x) + w₄·centerPrior(x)
xs = argmax J(x)
```

### Curvature correction

For Release 1, use piecewise vertical displacement estimated from detected text baselines and page edges. Advanced cylindrical/surface dewarping is enabled only after quality evaluation. Preserve the unwarped original and expose manual correction whenever confidence is low.

### Print-layout preservation

Store:

```text
BookSpread {
  spreadId,
  originalImage,
  readingDirection,
  leftPageId,
  rightPageId,
  spinePath,
  outerQuad,
  captureSequence
}
```

Normal PDF export uses logical page order. Facing-page export recreates the paired spread. Booklet printing is a separate explicit option that pads to a multiple of four and uses sheet mapping:

```text
sheet k front: [N - 2k, 1 + 2k]
sheet k back:  [2 + 2k, N - 1 - 2k]
```

for padded page count `N` and zero-based sheet `k`; binding edge and reading direction change the final orientation.

## 5. Text mode — live OCR

Purpose: quickly recognize text in the viewfinder and let the user tap, select or copy it.

1. Analyze adaptive preview frames, initially 5–10 fps with one frame in flight.
2. Use latency-oriented recognition (`fast`/balanced platform path).
3. Track recognized regions across frames using intersection-over-union and transcript similarity.
4. Display highlights only after short temporal confirmation to avoid flicker.
5. Let users tap a region to copy text or invoke safe structured actions for URL, phone, email, date or address.
6. Never open URLs or perform external actions without a user tap.

Region match:

```text
match = 0.65·IoU(boxₜ, boxₜ₋₁) + 0.35·textSimilarity(sₜ, sₜ₋₁)
```

Show a stable highlight after `match ≥ 0.70` for at least two observations. Values must be tuned against device tests.

## 6. OCR Doc mode — accuracy and layout

Purpose: create editable text and searchable PDFs while preserving the visual document.

1. Capture and perspective-correct the full-resolution page.
2. Estimate orientation; rotate before OCR.
3. Select recognition languages explicitly or use a constrained user preference list.
4. Run the accuracy-oriented recognizer with language correction where supported.
5. Retain blocks, lines, words, symbols, bounding boxes, corner points and confidence.
6. Infer reading order by columns, vertical overlap and script direction.
7. Normalize whitespace without destroying tables or line structure.
8. Store transcript edits separately from raw engine output.
9. Build a searchable PDF by placing an invisible text layer over the page image using the same page-coordinate transform.

Coordinate transform from image pixel `(x, y)` to PDF point `(X, Y)`:

```text
X = x × pdfWidth / imageWidth
Y = pdfHeight - (y + h) × pdfHeight / imageHeight
W = w × pdfWidth / imageWidth
H = h × pdfHeight / imageHeight
```

The PDF origin conversion accounts for image top-left versus PDF bottom-left coordinates. Rotation and crop transforms must be composed before placement.

### OCR quality metrics

Evaluate with ground truth rather than confidence alone:

```text
CER = (substitutions + deletions + insertions) / groundTruthCharacters
WER = (substitutions + deletions + insertions) / groundTruthWords
```

Also measure reading-order accuracy, table-cell association, text-layer alignment error and user correction time. Low-confidence lines are marked for review rather than silently accepted.

## 7. QR mode

- Restrict the detector to QR when QR mode is selected for lower latency.
- Analyze adaptive preview frames and track the same payload across frames.
- Require either repeated agreement or one high-confidence still result before presenting the action.
- Display the detected quadrilateral and a human-readable payload summary.
- Classify URL, Wi-Fi, contact, email, phone, SMS and plain text payloads.
- Never execute a payload automatically. Show the destination/action and require confirmation.
- Deduplicate repeated reads with `(format, rawValue)` plus a cooldown window.

Acceptance gate:

```text
accept if identicalPayloadCount ≥ 2 within 500 ms
       or stillImageDecode succeeds
```

The timing is a starting value subject to device evaluation.

## 8. Platform approach

| Capability | Android | iOS |
|---|---|---|
| Custom preview | CameraX Preview + ImageAnalysis + ImageCapture | AVFoundation capture session and video-data output |
| Document geometry | App-owned OpenCV/native image pipeline or evaluated detector | Vision rectangle detection plus app-owned geometry pipeline |
| Text mode | ML Kit Text Recognition v2 | VisionKit `DataScannerViewController` where supported; Vision fallback |
| OCR Doc | ML Kit Text Recognition v2 on full-resolution corrected image | Vision `VNRecognizeTextRequest` accurate path |
| QR | ML Kit Barcode Scanning configured for QR only | VisionKit data scanner or `VNDetectBarcodesRequest` |

The supplied ML Kit document-scanner UI can remain an optional shortcut, but it cannot implement this exact custom mode selector and overlay. The six-mode experience therefore depends on the custom-camera ADR.

## 9. Quality and performance targets

| Measure | Initial target |
|---|---|
| Preview | Aim for 30 fps; analysis adapts to 5–10 fps |
| Analyzer queue | One frame in flight |
| QR feedback | Median under 500 ms on reference devices when code is readable |
| Text highlight | Median under 700 ms; stable rather than flickering |
| OCR Doc | No main-thread work; cancellable progress by page |
| Book split | ≥ 95% correct left/right order on evaluation set; manual spine correction always available |
| Boundary error | Report mean corner error normalized by page diagonal |
| OCR | Report CER/WER by language, print quality and document type |

Targets are hypotheses until measured on supported Android and iOS reference devices.

## 10. Failure and recovery states

- No book spine: keep the spread as one page and offer manual spine placement.
- One side missing: capture as one page; do not invent the other side.
- OCR model unavailable: keep the image, show Download/Retry, and queue OCR without blocking save.
- Unsupported live text device: offer still-image OCR Doc mode.
- QR undecodable: keep preview active and suggest distance, focus or lighting changes.
- Unsupported flashlight: disable it with a text explanation.
- Thermal pressure: reduce analyzer rate before reducing still-capture quality.
- Discard: show the irreversible confirmation defined in S02; never discard automatically.

## 11. Verification plan

- Book set: flat books, thick books, glossy pages, curved pages, skew, left/right-to-left scripts and partial spreads.
- OCR set: receipts, forms, books, tables, handwriting samples, low contrast, rotation and supported scripts.
- QR set: size/distance grid, blur, glare, rotation, damaged codes and malicious-looking URL payloads.
- Measure latency, false capture, split correctness, boundary error, CER, WER, reading order and user correction time.
- Run offline and privacy tests; image/text/QR processing stays on-device by default.

## 12. Primary technical references

- [Google ML Kit document scanner](https://developers.google.com/ml-kit/vision/doc-scanner): automatic capture, edge detection, rotation and on-device document processing.
- [Google ML Kit Text Recognition v2](https://developers.google.com/ml-kit/vision/text-recognition/v2): text blocks, lines, elements, symbols, geometry, confidence and supported scripts.
- [Google ML Kit barcode scanning](https://developers.google.com/ml-kit/vision/barcode-scanning): on-device QR/barcode recognition, format restriction and structured payloads.
- [Apple VisionKit camera data scanning](https://developer.apple.com/documentation/visionkit/scanning-data-with-the-camera): live text/code recognition, quality levels, highlighting and device availability.
- [Apple Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images): fast and accurate recognition paths, languages, correction and custom words.
- [Apple Vision barcode detection](https://developer.apple.com/documentation/vision/vndetectbarcodesrequest): barcode observations and configurable symbologies.

Competitive scanner applications informed the category expectations, but this design does not copy a competitor’s branding or exact interface. Technical decisions above are based on official platform capabilities and must be validated with LumaScan’s own data.
