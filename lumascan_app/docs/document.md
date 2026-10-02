# Document and PDF effects catalog

Version 1.0 · 2 October 2026 · Product and implementation reference for LumaScan

This catalog defines enhancement effects for captured documents and scanned PDF pages. It is informed by common scanner-app behavior, but the names below are LumaScan product names unless a source is explicitly cited. “Magic Color” and similar names are not standardized algorithms; the output must be defined and tested by this product.

Related: [image filters](image%20filters.md), [requirements](requirements.md), [low-level design](low-level-design.md).

## 1. Effect groups

A scanner app usually combines four kinds of operation:

1. **Geometry:** detect the page, crop, correct perspective, rotate, deskew and dewarp.
2. **Cleanup:** remove uneven illumination, shadows, stains, noise, moiré and unwanted background.
3. **Appearance:** color, grayscale, threshold, contrast, sharpening and ink-saving presets.
4. **PDF finishing:** OCR text layer, paper layout, compression, annotations, encryption and secure redaction.

Keep these operations separate in the edit recipe even when the UI presents one preset. This allows a user to change B&W to Magic Color without losing the crop or OCR alignment.

## 2. Recommended preset list

### Core presets — Release 1

| ID | Display name | Output | Best for | Intended behavior | Main risk |
|---|---|---|---|---|---|
| `original` | Original | Color | Photos, IDs, already-clean pages | Orientation and crop only; no tonal enhancement | Uneven light remains |
| `auto_document` | Auto | Color or grayscale decision | Mixed everyday documents | Analyze page and choose a conservative recipe; show the selected result, never change mode silently after save | Unpredictable results if the decision is opaque |
| `magic_color` | Magic Color | Enhanced color | Colored forms, certificates, notes, diagrams | Neutralize page cast, flatten illumination, whiten near-white paper, increase local text contrast, preserve useful ink colors | Can oversaturate stamps and highlighting |
| `clean_color` | Clean Color | Natural color | Contracts, invoices, IDs | Lighter version of Magic Color: neutral white balance, mild background cleanup and mild sharpening | May leave strong shadows |
| `lighten` | Light | Color | Dim scans, gray paper | Raise exposure/midtones and lift background while protecting black text and bright highlights | Faint pencil can disappear |
| `grayscale` | Grayscale | 8-bit gray | Text with shading, old pages | Perceptual luminance conversion plus optional contrast; preserve continuous tone | Larger than bilevel output |
| `black_white` | Black & White | 1-bit or 8-bit bilevel-looking | Clean printed text | Adaptive local threshold, despeckle and edge protection; hard white background and dark text | Photos, colored annotations and faint strokes may vanish |
| `black_white_soft` | Soft B&W | Grayscale | Faint print, pencil, receipts | Local contrast plus a soft tonal curve; avoids hard thresholding | Background may remain slightly gray |
| `ink_saving` | Ink Saving | Mostly white with dark text | Printing drafts and text-heavy pages | Remove background/color fills where safe, reduce large dark coverage, preserve character skeletons and barcodes; provide print preview | Must not weaken small text, signatures or legal marks |
| `high_contrast` | High Contrast | Color or gray | Faded copies, low-contrast text | Strong black/white-point adjustment and local contrast with highlight protection | Halos and clipped photographs |
| `whiteboard` | Whiteboard | Color | Marker boards, presentation boards | Flatten illumination, neutralize board color, suppress reflections where confidence is high, strengthen colored marker strokes | Can erase pale marker writing |
| `receipt` | Receipt | Gray or B&W | Thermal receipts | Strong local background normalization, soft thresholding and character protection | Old/faded thermal text is fragile |
| `id_safe` | ID / Original+ | Conservative color | Identity-card copies, passports | White balance, mild exposure and restrained sharpness; no aggressive threshold or color removal | Less dramatic cleanup is intentional |

“Magic Color” should be the prominent one-tap color enhancement. “Clean Color” remains the conservative choice. “Light” should be a dedicated brightness/background preset rather than a duplicate of Auto. “Ink Saving” is an export/printing-oriented effect and should not be the default archival appearance.

### Advanced presets and cleanup — later releases

| ID | Display name | Best for | Processing intent | Release gate |
|---|---|---|---|---|
| `book` | Book | Curved book pages | Split/spread detection, page-surface dewarp, gutter-shadow correction | Geometry corpus and OCR alignment tests |
| `newspaper` | Newspaper | Newsprint and thin paper | Background removal, show-through suppression and descreening | Fine-print preservation test |
| `blueprint` | Blueprint | Blue-background technical drawings | Detect polarity and map lines/background for viewing or printing; offer Preserve blue and White background variants | Line and annotation color tests |
| `handwriting` | Handwriting | Notes and pencil | Preserve low-opacity strokes, suppress paper texture gently | Pencil/colored-pen corpus |
| `photo_document` | Photo in document | Magazine or illustrated page | Protect photo regions while cleaning text/background regions | Reliable region segmentation |
| `shadow_remove` | Remove Shadows | Folded/handheld pages | Estimate low-frequency illumination field and compensate only inside detected page | No halos across text or folds |
| `glare_reduce` | Reduce Glare | Glossy paper, ID cards | Detect clipped/near-clipped regions; reduce recoverable glare; ask for retake when detail is absent | Must not invent missing content |
| `stain_cleanup` | Remove Stains | Spots, smudges, crease marks | Mask high-confidence artifacts and fill from surrounding background | Manual review and undo |
| `finger_cleanup` | Remove Fingers | Page corners partly occluded | Remove only outside document content or high-confidence empty margins | Never reconstruct obscured text |
| `descreen` | Remove Moiré | Printed halftone photos | Frequency-aware low-pass/notch processing before sharpening/downsampling | Photo-detail comparison |
| `show_through` | Reduce Bleed-through | Thin double-sided paper | Estimate faint reverse-side content using scale/color/edge confidence | Must retain light front-side text |

Do not label an effect as glare or finger removal when it merely paints over the area. If content is physically hidden or saturated, the app should recommend a retake.

## 3. Manual document controls

Presets are starting points. Expose a compact set of controls that map predictably across platforms.

| Control | Proposed range | Neutral | Purpose | Notes |
|---|---:|---:|---|---|
| Strength | 0–100 | Preset-specific | Blend processed result with geometry-corrected original | Not meaningful for Original; do not interpolate crop |
| Light | −100…100 | 0 | Perceptual exposure/midtone adjustment | Protect paper highlights and dark text |
| Contrast | −100…100 | 0 | Tone separation | Apply after illumination normalization |
| White background | 0–100 | 0 | Increase near-white paper suppression | Mask colored/photographic regions |
| Black point | −100…100 | 0 | Text density | Avoid closing small counters such as e/a/8 |
| Color | 0–100 | 100 | Saturation of useful colors | IDs default to 100 or conservative automatic value |
| Sharpness | 0–100 | 0 | Edge clarity | Use edge-aware sharpening and cap halos |
| Noise cleanup | 0–100 | 0 | Speckle/noise reduction | Couple carefully with small text preservation |
| Threshold | 0–100 | Auto | B&W foreground/background split | Visible only in B&W modes |

Advanced controls such as threshold window size, denoise radius and morphology kernel belong in calibration/configuration, not ordinary UI.

## 4. Effect specifications

### 4.1 Magic Color

Goal: produce a clean, bright page while keeping the visual meaning of colored ink, stamps, diagrams and highlighting.

Suggested pipeline:

1. Work from the perspective-corrected, orientation-normalized image in a defined color space.
2. Estimate the paper/background illumination at a downsampled scale using a robust edge-aware or morphological background model.
3. Correct low-frequency illumination and neutralize the background color cast.
4. Build masks for text/line art, near-white paper and protected photo/color regions.
5. Whiten only probable paper, apply local contrast to probable writing, and use restrained chroma/vibrance enhancement for useful color.
6. Apply edge-aware denoise and mild sharpening at final output scale.
7. Blend with the corrected original according to Strength.

Quality checks: red stamps remain red, yellow highlighter remains visible, black type does not gain halos, photographs do not become posterized, and blank paper does not show a gray gradient.

### 4.2 Light

Goal: rescue a dim document without turning highlights into blank patches.

Use a luminance curve or exposure gain with highlight roll-off. Apply it after low-frequency illumination correction. Protect dark text with a foreground mask. A simple RGB addition is insufficient because it clips paper and weakens text.

Quality checks: the page becomes brighter, small dark text remains at least as legible, and already-white areas retain texture rather than clipping.

### 4.3 Black & White

Goal: a clean, compact text page.

Use adaptive thresholding rather than one global cutoff for phone captures. Candidate approaches include local mean/Gaussian thresholding and Sauvola-style thresholds. Run background normalization first; then remove isolated speckles and fill tiny text breaks conservatively. Preserve the pre-threshold grayscale image for OCR if testing shows it recognizes better.

Quality checks: punctuation and decimal points survive, character counters remain open, light table rules remain visible, and photographs trigger a warning or protected-region behavior.

### 4.4 Ink Saving

Goal: minimize printed toner/ink while keeping information readable.

Recommended behavior:

- force the page background to white;
- remove decorative background tones and low-confidence color fills;
- convert ordinary text to dark gray or black with controlled stroke preservation;
- optionally lighten large solid regions and photos using a halftone/low-coverage mode;
- preserve barcodes, QR codes, signatures, stamps and user-marked protected regions at safe contrast;
- show estimated coverage reduction as an estimate only, measured from raster coverage rather than advertised as physical ink savings.

Two variants are useful: **Text only** for ordinary documents and **Keep graphics** for diagrams/forms. Never modify the archival source or replace a normal PDF silently.

### 4.5 Whiteboard

Goal: white or neutral board with clear marker strokes.

Segment probable marker strokes by chroma, darkness and thin-line structure. Estimate board illumination separately, whiten it, and enhance the stroke mask. Reflections without source detail cannot be recovered. Offer Original comparison because pale yellow and dry marker strokes are easily lost.

### 4.6 Shadow removal

Goal: remove gradual shadows from hands, page curvature or uneven room light.

Estimate an illumination field at a much larger scale than text. Divide or otherwise normalize luminance against that field, while using edge-aware masking to avoid treating photographs and large printed blocks as shadows. Feather boundaries. Provide Strength and allow localized manual correction later.

### 4.7 Sharpen text

Goal: improve edge readability after warp/resampling and before final encoding.

Use a mild unsharp mask, high-pass blend or edge-aware sharpening on luminance only. Scale radius to output resolution. Do not use sharpening to pretend that motion blur has been restored; severe blur should produce a retake suggestion.

### 4.8 Descreen

Goal: suppress halftone dot patterns and moiré in printed photos.

Detect periodic texture, filter before resizing/sharpening, and protect text edges. Adobe's historical scan documentation describes descreening as removal of halftone structure that can cause moiré and hurt compression/readability. Treat it as a specialized tool, not a universal default.

## 5. Geometry effects

| Effect | Behavior | Parameters / output | Acceptance focus |
|---|---|---|---|
| Auto crop | Detect the four page corners | Normalized TL/TR/BR/BL quadrilateral | No clipped content; manual fallback |
| Perspective correction | Rectify quadrilateral to a rectangle | Homography and output dimensions | Straight lines, no mirrored/wrong-order warp |
| Rotate | Exact 90° turns plus metadata normalization | Quarter turns | EXIF orientation applied once |
| Deskew | Correct small in-plane text/page angle | Proposed bounded angle, e.g. ±15° | Avoid rotating photos based on diagonal content |
| Book dewarp | Flatten curved page surface | Mesh or dense warp | Text baseline and OCR geometry |
| Split spread | Separate two book pages | Gutter line and two page quads | Preserve content near gutter |
| Margin cleanup | Remove pixels outside corrected page | Page mask / background fill | No content erasure |

Crop and perspective correction happen before appearance effects. A geometric edit invalidates OCR geometry and annotations unless they can be reprojected safely.

## 6. PDF document effects and finishing

These operations change the PDF or the page composition rather than only the visible raster filter.

| PDF effect/tool | What it does | Destructive? | Required behavior |
|---|---|---:|---|
| Searchable OCR | Adds an invisible/selectable text layer aligned to the page image | No, when added as a layer | Test selection/search and coordinate alignment in two readers |
| Background cleanup | Rerenders scanned page imagery with a document effect | Yes for derivative image | Preserve original PDF; disclose rasterization if source was vector |
| Adaptive page compression | Chooses bilevel/grayscale/color treatment by page or region | Can be lossy | Preview quality and resulting size; never call estimated size exact |
| Downsampling | Reduces image pixel dimensions/DPI | Yes | Compact/Balanced/Print presets with minimum OCR readability |
| Monochrome compression | Encodes bilevel pages efficiently | No visual loss if lossless codec | Validate decoder compatibility; avoid risky symbol substitution modes |
| Deskew/dewarp | Corrects raster page geometry | Yes for derivative | Rebuild OCR/annotation coordinates |
| Paper layout | Places page image on A4, Letter or fit-to-image canvas | No source change | Physical margins, orientation and scale are explicit |
| Page normalization | Makes mixed pages a chosen paper size | No source change | Offer Fit and Fill; never crop silently |
| Annotation flattening | Renders ink, highlight, text and signature appearance into output | Yes in flattened copy | Keep editable document revision separately |
| Watermark | Adds visible purpose/status text | Yes in derivative | Position, opacity, pages and print preview are explicit |
| Header/footer/page number | Adds generated labels | Yes in derivative | Avoid OCR/text overlap and page bounds |
| Password encryption | Restricts opening or permissions | No visual effect | Never log/store password; reopen output as a test |
| Secure redaction | Removes underlying text/image content and adds appearance | Yes | Verify by text extraction, object inspection and rendering; black rectangles are not redaction |
| PDF/A archival profile | Produces a standards-conforming archival derivative | Depends on conversion | Validate with a conformance checker; embed required fonts/color data |

For imported PDFs, do not convert vector text pages into images merely to apply a scanner filter without explicit disclosure. Offer “Enhance scanned pages” only to pages detected as predominantly raster, or export a clearly labeled flattened copy.

## 7. Processing order

Use one deterministic pipeline for previews and final output:

```text
decode + validate
→ apply source orientation once
→ lens correction (if calibrated and enabled)
→ crop / perspective / deskew / dewarp
→ working color-space conversion
→ noise and moiré treatment
→ illumination / shadow normalization
→ region masks (paper, text, photo, color marks)
→ selected document preset
→ manual tonal controls
→ output-scale sharpening
→ annotation and watermark composition
→ OCR layer mapping
→ encode / PDF compress / validate
```

OCR may use a separate rendered branch chosen by recognition tests, but its coordinates must refer to the final geometry. Do not OCR a hard-thresholded page by default if grayscale provides better recognition.

## 8. Recipe model

Every saved edit is a versioned recipe, not an overwrite of the captured original.

```json
{
  "schemaVersion": 1,
  "presetId": "magic_color",
  "presetVersion": 1,
  "strength": 0.72,
  "geometry": {
    "cropQuad": [[0.08, 0.06], [0.93, 0.07], [0.95, 0.94], [0.06, 0.93]],
    "quarterTurns": 0,
    "deskewDegrees": -0.8
  },
  "adjustments": {
    "light": 0.08,
    "contrast": 0.12,
    "whiteBackground": 0.34,
    "blackPoint": 0.05,
    "color": 0.95,
    "sharpness": 0.18,
    "noiseCleanup": 0.1
  },
  "protectedRegions": []
}
```

Normalized values are recommended in storage even when the UI displays −100…100 or 0…100. Include `presetVersion` so results do not change silently after the algorithm is updated.

## 9. UX rules

- Always show Original comparison and Reset.
- Generate thumbnails from the same source crop, using a fast preview scale.
- Make processing reversible and rerender export from the original.
- Apply to all copies only appearance/cleanup settings; never copy one page's crop to another page.
- For IDs, default to `id_safe`; warn before B&W or Ink Saving because fine print and security detail may be removed.
- Label advanced cleanup as unavailable when the installed engine cannot perform it. Do not substitute a weaker effect under the same name.
- When a filter removes probable content, show a nonblocking warning and allow Keep original.
- Save the selected preset and manual changes per page. Batch mode must support selected pages, not only all pages.

## 10. Quality and regression tests

Use a fixed corpus containing clean print, faint print, pencil, colored highlighting, stamps, signatures, photos, barcodes, receipts, newsprint, whiteboards, shadows, glossy glare, book curvature and show-through.

Measure:

- OCR word/character error rate before and after each preset;
- foreground recall for punctuation, thin strokes and table rules;
- color difference for protected stamps/highlights/IDs;
- background uniformity without halos;
- estimated ink coverage for Ink Saving and legibility after real printing;
- barcode/QR decode success before and after processing;
- output size and render time at Compact/Balanced/Print;
- preview/final consistency and determinism;
- OCR/annotation alignment after crop, rotate, deskew and layout.

No preset ships because it “looks good” on one example. Define a pass threshold for each document class and retain before/after golden images.

## 11. Recommended release set

Release 1 presets: Original, Auto, Magic Color, Clean Color, Light, Grayscale, B&W, Soft B&W, Ink Saving, High Contrast, Whiteboard, Receipt and ID / Original+. Include crop, rotate, deskew, strength, before/after, batch apply and immutable originals.

Release 2 candidates: shadow removal, descreen, handwriting, newspaper, show-through reduction and specialized blueprint mode. Book dewarp, glare/stain/finger cleanup require stronger quality gates.

## 12. Sources and terminology notes

Checked 2 October 2026:

- [Apple Notes scanning](https://support.apple.com/en-my/guide/ipod-touch/iph653f28965/ios) documents Color, Grayscale, Black & White and Photo scan filters, plus crop, rotate, markup and signatures.
- [OneDrive mobile scanning](https://support.microsoft.com/en-us/onedrive/scan-a-whiteboard-document-business-card-or-photo-in-onedrive-for-ios) describes Whiteboard, Document, Business Card and Photo modes, lighting adjustments, grayscale, crop, rotate, text and highlighting.
- [Microsoft Lens documentation](https://support.microsoft.com/en-us/lens/microsoft-lens-for-android) describes document/whiteboard/photo modes, shadow and angle correction, filters and PDF export. Microsoft also states Lens retirement began in 2026, so this is design precedent rather than a future dependency.
- [Adobe Scan/Acrobat mobile help](https://www.adobe.com/devnet-docs/acrobat/ios/en/scan.html) describes crop, color adjustment, rotation, page ordering and OCR/PDF output.
- [Adobe's cleanup announcement](https://blog.adobe.com/en/publish/2019/10/15/adobe-adds-new-pdf-capabilities-to-acrobat-reader-and-scan) describes cleanup of creases, folds, stains, smudges and stray marks.
- [ML Kit Document Scanner](https://developers.google.com/ml-kit/vision/doc-scanner) documents automatic capture, edge/rotation detection, filters, shadow/stain cleanup and JPEG/PDF results in Google's supplied Android flow.

Competitor names and implementations can change. This document defines LumaScan behavior; it does not assert that every referenced app provides every effect listed here.
