# LumaScan: product requirements

Version 1.0 · 2 October 2026 · Status: proposed implementation baseline

## 1. Product goal

Build an Android and iOS app that turns camera captures, existing photos and document videos into readable, organized, searchable documents. Provide a separate photo-editing workflow and practical PDF tools. The reference is the category of CamScanner-style apps, not a reproduction of another product's branding or exact interface.

Chosen stack: Flutter/Dart for shared presentation and workflow, Kotlin for Android native modules, Swift for iOS native modules. No mandatory account or backend for the initial release.

### Working assumptions

- Android and iOS are both product targets; Android is the first hardware validation platform. iOS development, signing and release testing require macOS/Xcode.
- “Image clicking” means in-app photography plus system photo/file import.
- “Video scanning” means finding good document frames in a newly recorded or imported video, then creating individual pages. It is not a QR-only scanner or full 3D reconstruction.
- Photo-to-video slideshows are planned separately. Generative AI video, live collaboration, cloud sync, billing and identity verification are not initial-release requirements.
- Proposed minimum targets: Android API 26 and iOS 16. Reconfirm against the selected stable Flutter release, OCR/PDF dependencies and target-device market before implementation; these are product targets, not claims about SDK minimums.
- Initial OCR target: printed English. Add scripts/languages only when both platform adapters pass the language test corpus. Handwriting recognition is experimental and not a launch promise.
- ID scanning produces a useful copy. It does not establish that an ID is genuine or verify its holder.

## 2. Users and principal journeys

| User | Need | Successful outcome |
|---|---|---|
| Student | Capture notes, handouts, whiteboards | Ordered, legible PDF with searchable text |
| Professional | Scan contracts, receipts and forms | Named PDF with annotation/signature and convenient sharing |
| Individual | Copy an ID or passport page | Correctly cropped front/back or single-page copy, with optional copy-purpose watermark |
| Frequent scanner | Capture many pages quickly | Reviewed page set with few duplicates and easy retakes |
| Photo user | Capture and improve pictures | Reversible adjustments and a new exported image |

Primary flow: Library → scan/import → capture review → crop → enhancement → page organizer → OCR (optional) → export/share.

ID flow: select template → capture front → capture back when applicable → review each side → layout preview → optional copy watermark → export.

Video flow: record/import → select interval → analyze → review candidate frames → replace/remove/select → batch page editing → OCR/PDF.

## 3. Release scope

| Release | Scope | Exit criterion |
|---|---|---|
| R1: documents | Library, capture/import, crop/rotate, core document and photo filters, ID front/back, English OCR, PDF creation, annotation, page reorder/delete, export | End-to-end flows and recovery pass on Android and iOS reference devices |
| R1.1: PDF tools | Imported PDF merge/split/rotate, text/stroke/signature overlays, password export if engine supports it | Engine conformance and compatibility tests pass |
| R2: video | Live video scanning, imported-video page extraction, duplicate review, photo-to-video MP4, basic clip trim | Frame-selection corpus and interrupted-export tests pass |
| R3: advanced | Book dewarping, advanced stain/shadow cleanup, additional OCR scripts, optional sync, true redaction | Separate quality/SDK gates per feature |
| R4: 3D | Device capability prototype, point-cloud capture, later mesh and texture export | Measured quality on supported devices; separate requirements approved |

Release ordering is a recommendation, not a delivery-date commitment. The prototype previews R1 and R2 together to make the product direction reviewable.

## 4. Functional requirements and acceptance criteria

Priority P0 = required for assigned release; P1 = useful after the core flow; P2 = advanced optional capability.

| ID | Priority / release | Requirement | Acceptance criteria |
|---|---|---|---|
| CAP-01 | P0 / R1 | Document camera with manual and auto capture | Camera opens after permission; manual shutter works even when no rectangle is found; auto mode captures only after a stable qualifying page; shows captured page count |
| CAP-02 | P0 / R1 | Quality guidance | Detect likely blur, low light, glare and clipped edges; explain retake suggestion; allow explicit user override; never claim perfect quality |
| CAP-03 | P0 / R1 | Multipage session | Add, inspect, retake and remove pages before saving; previously committed pages survive app restart; the camera discard control requires explicit confirmation before permanently deleting the current capture session |
| CAP-04 | P0 / R1 | Import photos/files | System pickers support JPEG/PNG and platform-decodable HEIC; normalize orientation; copy selected inputs to private storage; clearly report unsupported/corrupt inputs |
| CAP-05 | P1 / R1 | Capture controls | Flash/torch where available, grid, auto/manual, supported lens selection; incompatible controls disabled with reason |
| CAP-06 | P0 / R1 | Camera-preview control states | Quick controls and the settings sheet keep Batch mode, flashlight and Auto capture synchronized; Batch mode shows thumbnail/count and preserves accepted pages when disabled; the bottom-right cross is destructive and opens an explicit irreversible-discard confirmation; capture modes are separate from post-capture edit tools; every state is announced accessibly |
| CAP-07 | P0 / R1 | Book photo capture | Detect an open spread and spine; produce paired left/right pages in configured reading order; retain the original spread and pairing/layout metadata; offer manual spine/corner correction; export individual pages or an explicitly selected facing-page/booklet layout |
| CAP-08 | P0 / R1 | Capture mode selector | Camera uses the shortcut label Docs and exposes Docs, Book, Text, OCR Doc, QR and Photo; selected mode changes guidance, overlay and processing pipeline while preserving accepted pages |
| CAP-09 | P0 / R1 | No duplicate auto captures | After a capture, auto capture waits until the page is turned or swapped (two or more disturbed frames in a row) and settles again; one lost or dark frame never re-triggers; manual taps count as captures |
| CAP-10 | P0 / R1 | One-page focus | A second page partly in view and cut off by the frame is left out of the outline and saved crop in Docs, Book and OCR Doc; a whole spread stays together; Book mode makes one page when only one is in view |
| CAP-12 | P0 / R1 | Auto crop every page | The page is found by colour, edge contrast and its place in the middle of the frame (cream and coloured paper too); every page photo is cropped, to the preview outline when the photo shows none; selected pages can be auto cropped or set to the full photo in one step |
| EDIT-01 | P0 / R1 | Perspective crop and rotation | Four corner handles, zoom loupe, reset and 90° rotation; reject crossed/degenerate quadrilaterals; original remains recoverable |
| EDIT-02 | P0 / R1 | Document filters | Original, Auto, Clean Color, Grayscale, B&W, B&W Soft, High Contrast and Whiteboard; every preset control shows a thumbnail rendered from the current page so users see the expected effect before applying it; strength control appears where meaningful |
| EDIT-03 | P0 / R1 | Photo filters and adjustments | Original, Natural, Vivid, Warm, Cool, Mono; exposure, contrast, saturation, warmth and sharpness; reset and before/after |
| EDIT-04 | P0 / R1 | Batch edits and undo | Apply enhancement settings to selected/all pages; never copy crop geometry to unrelated pages; undo last action during editing; saved original remains available |
| EDIT-05 | P2 / R3 | Advanced cleanup | Shadow reduction, stain cleanup, book dewarp and finger removal each require an evaluated engine; preserve stamps/signatures; manual review before save |
| EDIT-06 | P0 / R1 | Re-edit drafts and saved documents | Opening any draft or locally saved document exposes Crop/resize and Filter on every page; users can change crop geometry, rotation, preset and strength after prior edits or export; each save creates a new recipe revision against the immutable source, autosaves atomically and supports reset/history without cumulative image degradation |
| ID-01 | P0 / R1 | ID capture templates | Generic card front/back, single-sided card, passport data page, custom document; front/back slots named clearly; no hardcoded government validation rules |
| ID-02 | P0 / R1 | ID copy layout | Front/back fit on one A4/Letter page or separate pages; user can swap sides and retake independently; passport is not forced into card ratio |
| ID-03 | P1 / R1 | Copy-purpose watermark | User enters purpose/date label; preview placement and opacity; export leaves essential fields legible; no automatic collection of ID fields |
| OCR-01 | P0 / R1 | Printed text recognition | User selects supported language; result shows editable extracted text and page mapping; unavailable model gives download/retry state |
| OCR-02 | P0 / R1 | Correct and reuse text | Copy selected/all text, edit transcript, undo edits and export TXT; edits do not silently change image pixels |
| OCR-03 | P0 / R1 | Searchable PDF | Invisible text layer is aligned with page geometry; select/search works in two independent PDF readers; original image is visible |
| OCR-04 | P1 / R3 | Additional languages | Display capability-driven language list; expose unsupported combinations before processing; validate mixed-language samples |
| OCR-05 | P0 / R1 | Live Text mode | Recognize and track visible text regions with low latency; let users tap/copy text or choose a safe structured action; fall back to still-image OCR when live scanning is unavailable |
| OCR-06 | P0 / R1 | OCR Doc mode | Run accuracy-first OCR on the full-resolution corrected page; preserve blocks/lines/words and coordinates, reading order and user corrections; create an aligned searchable-PDF text layer while retaining the page image |
| QR-01 | P0 / R1 | QR capture mode | Restrict detection to QR in QR mode; show a tracked boundary and decoded summary; deduplicate repeated reads; require explicit user action before opening URLs, joining Wi-Fi or invoking another payload action |
| LIB-01 | P0 / R1 | Local document library | Rename, sort, search title/OCR, favorite, folders and tags; recent scans persist without account |
| LIB-02 | P0 / R1 | Trash and restore | Delete moves document to trash; restore preserves assets/order; permanent deletion explains scope and requires confirmation; propose 30-day trash retention |
| LIB-03 | P0 / R1 | Save/resume drafts | Leaving workflow saves committed captures and edit state; reopening offers Resume draft; no silently lost completed pages; each new scan or import starts a new document, and earlier ones stay on Home to reopen and add pages |
| PDF-01 | P0 / R1 | PDF generation | A4/Letter/fit-to-image, portrait/landscape, margins, quality presets, page order and actual final file size |
| PDF-02 | P0 / R1 | Page organization | Reorder, rotate, duplicate, add and delete; reorder also works with accessible Move up/down commands |
| PDF-03 | P0 / R1 | Annotation | Draw, highlight and add text or a signature image/stroke; editable before export; flattened output preview; signature is visual, not a certificate-based digital signature |
| PDF-04 | P0 / R1.1 | Existing PDF tools | Import, inspect password-protected state, merge/split/rotate; preserve vector/text content when engine supports it; disclose any rasterization |
| PDF-05 | P1 / R1.1 | Protected export | Password entry/confirmation and re-open test if chosen engine supports it; no password in logs or analytics |
| PDF-06 | P2 / R3 | True redaction | Remove hidden text and image content, not just draw a black rectangle; release only after extraction/rendering tests pass |
| EXP-01 | P0 / R1 | Export and share | PDF, JPEG/PNG page images and TXT; choose save/share; expose progress/cancel; no share sheet before file is complete |
| EXP-02 | P0 / R1 | Export quality | Compact/Balanced/Print presets, estimated size labeled as estimate, final size measured; OCR/text readability checked at each preset |
| VID-01 | P0 / R2 | Video input | Record silently or choose video; trim interval up to proposed 3 minutes; no microphone permission for document scanning |
| VID-02 | P0 / R2 | Page extraction | Sample frames, score blur/glare/framing, group probable duplicates, retain best candidates with timestamps; no automatic deletion of uncertain candidates |
| VID-03 | P0 / R2 | Candidate review | Thumbnail grid, selected count, suggested quality flags; user can deselect, inspect neighbors and manually add missed frames |
| VID-04 | P0 / R2 | Video lifecycle | Stop/save partial valid input on interruption where supported; resume analysis from durable checkpoints; explain that background continuation varies by OS |
| MOV-01 | P1 / R2 | Photos to video | Reorder selected images, duration, aspect ratio, optional user audio, MP4 export; capability-gate codecs/resolution |
| MOV-02 | P1 / R2 | Basic video editing | Trim, rotate and fit/crop; preview matches output; no full multitrack editor promised |
| SET-01 | P0 / R1 | Settings | Default quality/paper/language, storage usage, permission access, model downloads, privacy info and accessibility preferences |
| SYS-01 | P0 / R1 | Work offline | Capture/edit/export available without account; OCR works once required models are installed; first-use download needs an explicit state |
| SYS-02 | P0 / R1 | Failure recovery | Low storage, denied camera, invalid input, unsupported feature and interrupted job each have an actionable recovery state |

## 5. Filter behavior

All filters are recipes stored against an immutable original. Preview is lower resolution; export rerenders from the original. “Original” removes enhancement but keeps the user's crop unless Reset all edits is chosen.

The same editor and recipe model are used for newly captured pages, resumed drafts and saved library documents. Saving or exporting does not flatten the only editable copy: reopening a saved document restores its latest crop and filter controls, while the immutable source and earlier recipe revisions remain available according to retention policy. Imported PDFs can offer this behavior only for pages for which LumaScan owns or has retained a raster source; capability limits must be explained rather than silently rasterizing unrelated PDF content.

### Filter-preview thumbnail loading

- Each filter tile contains a visual thumbnail of the current page with that filter applied; text and selected-state styling supplement the image and remain accessible.
- Prioritize the full document preview. Begin thumbnail work only after the current page preview reaches ready state; thumbnails must never delay opening the editor or interacting with the main preview.
- Render only visible or near-visible tiles first. Queue remaining carousel thumbnails during idle time, with a small concurrency limit appropriate to device memory and thermal state.
- Use a reduced-resolution source suitable for the rendered tile size. Do not decode or process the full-resolution original separately for every filter tile.
- Cache by `pageRevisionId + geometryHash + filterId + filterVersion + representativeStrength + thumbnailSize`. Reuse cached results when reopening the page and invalidate only keys affected by a recipe, filter-version or size change.
- Cancel or ignore stale thumbnail jobs when the user changes page, crop, revision or leaves the editor. Generation IDs prevent an older result from replacing the current page's thumbnail.
- Show a lightweight neutral placeholder or shimmer until a thumbnail is ready. Failure of one thumbnail leaves the filter selectable, shows a retry/fallback state and does not block the editor.
- Generate representative preset previews at the preset's recommended strength; live strength changes update the large preview first and do not regenerate every tile on each slider movement.

| Category | Presets / tools | Design intent |
|---|---|---|
| Documents | Auto, Clean Color | Improve readability while retaining useful color |
| Documents | Grayscale, B&W, B&W Soft, High Contrast | Different responses to faint print and background texture |
| Documents | Whiteboard | Neutralize board background and improve marker readability; warn for faint strokes |
| Photos | Natural, Vivid, Warm, Cool, Mono | Tone and color styles; separate from aggressive document cleanup |
| Manual | Exposure, contrast, saturation, warmth, sharpness | Reversible normalized sliders with neutral defaults |
| Advanced | Shadow/stain cleanup, dewarp | Optional, visibly capability-gated; no synthetic replacement of document content |

For ID mode default to Original or conservative Clean Color. Avoid filters that obscure fine print, portrait detail or security patterns. User previews every exported copy.

## 6. Nonfunctional requirements

The following are proposed acceptance targets, not measured performance claims. Benchmarks must record device model, OS, thermals, input size, model version and percentile.

| Area | Target and measurement |
|---|---|
| Responsiveness | Main controls respond within 100 ms in ordinary editing; processing never blocks Flutter's UI isolate |
| Preview | Aim for 30 fps camera preview; run analysis at adaptive 5–10 fps with only one frame in flight |
| Filter preview | P95 within 250 ms for a 1280-pixel long-edge preview on reference midrange devices |
| Capture readiness | Camera becomes usable within 2 seconds warm / 4 seconds cold excluding permission dialogs and model downloads |
| OCR | Initial target P95 under 3 seconds/page for a clear English printed A4 sample after model load; report word error rate on fixed corpus rather than a blanket accuracy percentage |
| Export | Initial target under 15 seconds for 10 scanned pages at Balanced on reference devices; progress visible within 500 ms |
| Memory | Stream full-resolution page processing; no entire-document bitmap preload; test 50-page sessions and low-memory recovery |
| Capacity | R1 target 50 pages/document and 25 MB/photo input; larger imports require downsample/limit guidance. R2 video target ≤3 min, ≤500 MB, analysis ≤1080p after native scaling |
| Reliability | No loss of committed source images after forced termination; each job completion commits once |
| Accessibility | Minimum 48 logical-pixel interactive targets, readable contrast, screen-reader labels, 200% text-scale support, no color-only status |
| Privacy | Local by default; no document pixels, OCR text, names or ID fields in telemetry; analytics opt-in |
| Security | Private app storage and OS file protection; transient shared copies removed on a bounded schedule; optional biometric lock later |
| Battery | Pause camera analysis offscreen; bounded worker queues; thermal throttling reduces analysis rate |

## 7. Permissions and data handling

Ask for camera access only when capture begins. Offer import if it is denied. Use platform pickers for file/photo selection instead of broad storage permissions where available. Microphone access is only relevant if the user enables audio recording in a later video-making feature.

No network upload occurs in the base product. Model downloads disclose size and download state. A future sync feature requires a separate explicit opt-in and conflict policy. Saving to a share destination creates a copy whose lifecycle is controlled by the destination application.

Keep source images, crop recipes and rendered versions distinct. Exclude temporary media from OS backups; decide separately whether a user-enabled document backup is supported. Strip location metadata from exports by default. ID content must not appear in app-switcher previews where platform protection permits.

## 8. Out of scope and decision gates

- Full editing/reflow of existing PDF paragraphs is not equivalent to adding text annotations. It needs a separately selected PDF content-editing SDK and budget.
- Secure redaction and certificate-based digital signing are not represented by visual overlays.
- 3D depth capture does not automatically yield a textured 3D model. Prototype devices, reconstruction engine and output quality separately.
- Advanced cleanup, PDFs and OCR must pass an SDK licensing and offline-capability review before dependencies are locked.
- Native quick-scan interfaces have limited customization. The full design requires a custom CameraX/AVFoundation capture surface; built-in document-scanner flows are optional shortcuts.
- Trial device set should include low/mid/high Android hardware, an iPhone near the supported minimum and a current iPhone. Feature parity is tested by output quality, not assumed from shared Flutter UI.

## 9. Acceptance test packs

1. Capture corpus: flat paper, curved paper, receipt, whiteboard, shadows, glare, faint print, landscape page and rotated import.
2. ID corpus: fictional front/back cards, passport-like sample, skew, damaged edge and reflective surface. No real personal identity data needed.
3. OCR corpus: known English ground truth, mixed font sizes, tables, two columns, numbers, punctuation and out-of-scope handwriting.
4. PDF corpus: scanned, vector, mixed-size, password-protected, malformed and annotated PDFs.
5. Video corpus: static hold, page turns, revisited page, near-identical forms, motion blur, changing exposure and a missed-detection frame.
6. Resilience: app termination after capture, during render/OCR/export, storage exhaustion, permission revocation, rapid repeat taps, engine detach and thermal pressure.

## 10. Official technical references

References checked 2 October 2026. Product targets and architecture choices above are proposals, not claims that one SDK implements every requirement.

- [Flutter platform integration](https://docs.flutter.dev/platform-integration/platform-channels): native communication and host platform implementations.
- [Pigeon](https://pub.dev/packages/pigeon): typed Dart/Kotlin/Swift communication code generation.
- [ML Kit Document Scanner](https://developers.google.com/ml-kit/vision/doc-scanner/android): Android supplied scanner flow, JPEG/PDF results and dynamically delivered components; its UI is not an arbitrary custom camera UI.
- [CameraX image analysis](https://developer.android.com/media/camera/camerax/analyze): camera image analysis and backpressure behavior.
- [ML Kit Text Recognition](https://developers.google.com/ml-kit/vision/text-recognition/v2): text recognition and supported scripts.
- [Media3 Transformer](https://developer.android.com/media/media3/transformer): Android media transformation/export.
- [Apple VisionKit document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller), [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images), [AVFoundation](https://developer.apple.com/documentation/avfoundation), and [PDFKit](https://developer.apple.com/documentation/pdfkit): candidate iOS platform adapters; validate detailed deployment requirements during implementation.
- [ARCore Depth](https://developers.google.com/ar/develop/depth): depth input and device capability constraints for the later 3D investigation.
