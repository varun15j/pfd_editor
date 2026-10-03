# LumaScan skill inventory

Version 1.0 · 2 October 2026

This is the engineering skill inventory required to build LumaScan. It is not a Codex `SKILL.md` package. The list consolidates the project's high-level requirements and architecture, [low-level design](docs/low-level-design.md), [document/PDF algorithms](docs/document.md), [image-filter algorithms](docs/image%20filters.md), and [screen design](docs/screen-design.md).

The **HLD** skills below are derived from [docs/high-level-design.md](docs/high-level-design.md), `README.md`, `docs/requirements.md`, and the architecture decisions in `docs/low-level-design.md`.

## Prefix convention

Every entry begins with its skill type:

| Prefix | Skill type |
|---|---|
| `HLD:` | Product architecture and system-level design |
| `MOBILE:` | Cross-platform mobile engineering |
| `FLUTTER:` | Flutter/Dart application engineering |
| `ANDROID:` | Native Android/Kotlin engineering |
| `IOS:` | Native iOS/Swift engineering |
| `INTEROP:` | Flutter/native contracts and communication |
| `CAMERA:` | Camera capture and real-time analysis |
| `CV:` | Computer vision and document geometry |
| `IMAGE:` | Image processing, rendering and color |
| `ALGORITHM:` | Processing algorithms and calibration |
| `OCR:` | Text recognition and searchable output |
| `PDF:` | PDF generation, manipulation and validation |
| `VIDEO:` | Video capture, analysis and export |
| `DATA:` | Persistence, files and indexing |
| `JOBS:` | Durable background work and recovery |
| `SECURITY:` | Security and privacy engineering |
| `UX:` | Interaction and visual design |
| `ACCESSIBILITY:` | Inclusive mobile interaction |
| `PERFORMANCE:` | Latency, memory, power and thermal work |
| `QA:` | Verification, metrics and test automation |
| `DEVOPS:` | Build, release and engineering operations |
| `RESEARCH:` | Prototype-gated future capability |

## High-level design skills

- **HLD: Cross-platform system decomposition** — Divide the product into Flutter presentation/workflow, native Kotlin and Swift capture/processing modules, local persistence, and optional future services.
- **HLD: Capability-driven architecture** — Model camera, OCR, PDF, codecs and device-specific features as discoverable capabilities instead of assuming identical Android/iOS support.
- **HLD: Offline-first product architecture** — Keep capture, editing, document storage and export usable without an account or mandatory backend.
- **HLD: Privacy-by-default architecture** — Keep document pixels, OCR text and identity data on-device by default; require explicit policy and consent for future sync.
- **HLD: Release and scope planning** — Stage document scanning, PDF/OCR, video scanning, photo-to-video and 3D work behind separate quality gates.
- **HLD: Non-destructive editing architecture** — Retain immutable originals and store versioned recipes, annotations and derived assets.
- **HLD: Adapter-based platform services** — Isolate OCR, camera, PDF, rendering and video engines behind interfaces so SDKs can be changed or capability-gated.
- **HLD: Resilient processing architecture** — Treat native jobs as durable work that survives Flutter engine detachment and supports retry, cancellation and reconciliation.
- **HLD: Local document-management architecture** — Organize documents, pages, revisions, folders, tags, OCR and exports around stable identifiers.
- **HLD: Security boundary design** — Define ownership of private assets, share copies, permissions, encryption and logs.
- **HLD: Quality-gate design** — Require measured output quality, device coverage and corpus-based validation before enabling advanced effects.
- **HLD: Third-party SDK evaluation** — Compare licensing, offline behavior, supported platforms, fidelity, binary size, privacy and maintenance for OCR/PDF/image SDKs.
- **HLD: Product-risk analysis** — Distinguish visual signatures from cryptographic signatures, black overlays from true redaction, and depth maps from complete 3D models.

## Mobile and Flutter skills

- **MOBILE: Android and iOS lifecycle management** — Handle foreground/background transitions, interruptions, permission changes, memory pressure and process termination.
- **MOBILE: Platform permission flows** — Request camera only when needed, use system pickers, recover from denial and avoid microphone permission for silent document video.
- **MOBILE: Scoped file access and sharing** — Import through platform pickers, copy inputs into controlled storage, and create bounded-lifetime share outputs.
- **MOBILE: Responsive phone/tablet layouts** — Support safe areas, rotation, compact phones, tablets, keyboards and large text.
- **MOBILE: Native resource lifecycle** — Release cameras, textures, buffers, file handles and observers on every normal/error path.
- **FLUTTER: Dart application architecture** — Implement feature controllers, use cases, repositories and dependency wiring without processing pixels in widgets.
- **FLUTTER: Riverpod state management** — Model explicit idle/loading/ready/empty/error states and feature-scoped dependencies.
- **FLUTTER: go_router navigation** — Restore entity-based routes for library, capture, crop, filters, OCR, pages, video and export.
- **FLUTTER: Drift/SQLite integration** — Manage typed document metadata, schema migrations and transactional repositories.
- **FLUTTER: Texture-backed preview UI** — Compose Flutter controls over native camera/render textures while keeping frame buffers native.
- **FLUTTER: Async UI and cancellation** — Present progress, retry and cancellation without blocking the UI isolate.
- **FLUTTER: Accessible component implementation** — Build semantic labels, focus order, selected states, 48-pixel targets and non-drag alternatives.
- **FLUTTER: Theme and design-token implementation** — Translate the deep-teal scanner design into reusable light/dark semantic components.
- **FLUTTER: Golden and integration testing** — Verify screen states, navigation, large text and core capture-to-export journeys.

## Native platform skills

- **ANDROID: Kotlin and coroutines** — Build structured native services, bounded worker queues, cancellation and exactly-once completion paths.
- **ANDROID: CameraX capture and analysis** — Configure Preview, ImageCapture, ImageAnalysis, flash/torch, lens selection and backpressure.
- **ANDROID: ML Kit integration** — Integrate text recognition and optionally the supplied document-scanner flow while preserving custom-camera requirements.
- **ANDROID: Media3 Transformer** — Compose, trim, rotate, effect and export video/photo sequences with device capability checks.
- **ANDROID: WorkManager and foreground execution** — Schedule deferrable work and select platform-compliant handling for longer user-visible jobs.
- **ANDROID: GPU/native image rendering** — Evaluate OpenGL/Vulkan/RenderEffect or optimized native processing for previews and final renders.
- **ANDROID: Keystore and private storage** — Protect future secrets and use app-private/scoped storage safely.
- **IOS: Swift concurrency** — Implement async platform services, cancellation and one-result completion behavior.
- **IOS: AVFoundation capture** — Build camera preview, still capture, recording, exposure/torch and interruption handling.
- **IOS: Vision text recognition** — Return recognized text and geometry through the normalized OCR adapter.
- **IOS: Core Image/Metal rendering** — Implement efficient, color-managed previews and full-resolution image recipes.
- **IOS: PDFKit evaluation and integration** — Generate/view/annotate PDFs while measuring limitations for advanced editing and encryption.
- **IOS: AVFoundation media composition** — Decode candidate frames and build basic photo/video exports.
- **IOS: File protection and Keychain** — Apply platform file-protection classes and store future secrets appropriately.

## Flutter/native interoperability skills

- **INTEROP: Pigeon schema design** — Define typed, versioned Dart/Kotlin/Swift messages for capabilities, capture, rendering, jobs and sharing.
- **INTEROP: Platform-channel threading** — Validate on the handler thread, dispatch expensive work, and deliver one terminal result.
- **INTEROP: Event-stream design** — Throttle detection/progress events, sequence them and ignore duplicate or out-of-order callbacks.
- **INTEROP: Texture registration** — Publish native previews to Flutter without copying full frames through message channels.
- **INTEROP: Contract version negotiation** — Fail visibly when Dart and host schemas are incompatible.
- **INTEROP: Detach/reattach recovery** — Unsubscribe events safely and reconstruct UI state from durable native job snapshots.
- **INTEROP: Error translation** — Convert native failures into stable codes, localized message keys and sanitized diagnostic context.
- **INTEROP: Cross-language fixture testing** — Verify DTO nullability, enums, numeric units and serialization with shared golden fixtures.

## Camera and capture skills

- **CAMERA: Document viewfinder design** — Overlay normalized quadrilaterals and guidance on a correctly transformed preview.
- **CAMERA: Auto-capture state machine** — Combine stable geometry, quality gates, cooldown and page-change detection without double captures.
- **CAMERA: Manual capture fallback** — Allow capture when detection fails and route the page to manual cropping.
- **CAMERA: Capture-quality estimation** — Estimate blur, glare, exposure, clipped edges and page coverage without making unsupported guarantees.
- **CAMERA: Backpressure control** — Keep only the latest analysis frame and always close/release image buffers.
- **CAMERA: Multi-page session management** — Commit page assets atomically and retain prior pages through interruptions.
- **CAMERA: ID capture guidance** — Implement separate front/back/passport slots with conservative image processing.
- **CAMERA: Document-video capture** — Record without audio by default, validate the container and recover usable partial input where supported.
- **CAMERA: Device capability testing** — Measure supported resolutions, concurrent use cases, torch behavior and thermal limitations on real devices.

## Computer-vision and geometry skills

- **CV: Page-boundary detection** — Find and score a document quadrilateral under clutter, shadows and partial edges.
- **CV: Quadrilateral validation** — Enforce finite normalized coordinates, corner order, convexity, minimum area and nonintersection.
- **CV: Perspective rectification** — Compute a homography and output size while preserving text geometry.
- **CV: Deskew estimation** — Detect small page/text angles and correct them without reacting to intentional diagonal content.
- **CV: Page-orientation detection** — Combine capture metadata and content cues without applying EXIF rotation twice.
- **CV: Book/spread detection** — Find a gutter, split pages and protect content close to the binding.
- **CV: Page-surface dewarping** — Estimate a mesh/dense warp for curved pages and retain coordinate transforms for OCR.
- **CV: Region segmentation** — Separate probable paper, text, line art, photos, colored marks, shadows and artifacts.
- **CV: Blur and motion estimation** — Detect low-acutance or motion-damaged frames and recommend retake when recovery is unsafe.
- **CV: Glare detection** — Identify clipped or near-clipped glossy regions and distinguish recoverable tone from missing content.
- **CV: Perceptual hashing** — Group visually similar video candidates while avoiding reliance on hash distance alone.
- **CV: Frame-quality ranking** — Rank video frames by sharpness, exposure, glare, framing and motion.

## Document-processing algorithms

- **ALGORITHM: Magic Color enhancement** — Normalize illumination and paper color, protect color marks/photos, increase text contrast and whiten probable background.
- **ALGORITHM: Clean Color enhancement** — Apply conservative white balance, background cleanup and sharpening suitable for forms and IDs.
- **ALGORITHM: Light enhancement** — Raise midtones with highlight roll-off and dark-text protection.
- **ALGORITHM: Grayscale conversion** — Use perceptual luminance rather than an unweighted RGB average.
- **ALGORITHM: Adaptive B&W thresholding** — Use local thresholds such as mean/Gaussian or Sauvola-style logic after background normalization.
- **ALGORITHM: Soft B&W rendering** — Retain continuous tone and faint strokes while increasing local text contrast.
- **ALGORITHM: Ink Saving rendering** — Whiten background, reduce safe solid coverage, and preserve text, signatures, stamps and machine-readable codes.
- **ALGORITHM: Whiteboard enhancement** — Flatten board illumination while retaining faint and colored marker strokes.
- **ALGORITHM: Receipt enhancement** — Normalize thermal-paper background and protect faded characters.
- **ALGORITHM: ID-safe enhancement** — Limit processing to restrained white balance, light correction and sharpening.
- **ALGORITHM: Shadow-field correction** — Estimate low-frequency illumination and normalize it without interpreting photos or printed blocks as shadow.
- **ALGORITHM: Glare handling** — Reduce only recoverable glare and request retake for saturated missing detail.
- **ALGORITHM: Stain/smudge cleanup** — Detect high-confidence artifacts and fill from surrounding background with manual review.
- **ALGORITHM: Bleed-through suppression** — Reduce faint reverse-side content while preserving light front-side writing.
- **ALGORITHM: Descreening** — Detect and suppress periodic halftone/moire structure before resize and sharpening.
- **ALGORITHM: Morphological text cleanup** — Remove isolated speckles and repair tiny breaks without closing character counters.
- **ALGORITHM: Edge-aware text sharpening** — Improve acutance at final scale while limiting halos and noise.
- **ALGORITHM: Preset-strength blending** — Blend a corrected original and full preset in an appropriate color/perceptual space.
- **ALGORITHM: Protected-region processing** — Exclude photos, stamps, signatures, barcodes and user-selected regions from destructive cleanup.
- **ALGORITHM: Algorithm versioning** — Persist preset/filter versions so saved documents remain reproducible after tuning changes.

## Image-filter and color skills

- **IMAGE: Linear-light processing** — Apply exposure and light calculations in linear values with sufficient precision.
- **IMAGE: Color management** — Read profiles, choose a working space, handle wide-gamut/HDR input and attach the export profile.
- **IMAGE: White-balance correction** — Implement temperature/tint and sampled/automatic neutral correction.
- **IMAGE: Tone-curve design** — Implement brightness, contrast, highlights, shadows, whites, blacks and fade with predictable neutral values.
- **IMAGE: Saturation and vibrance** — Adjust chroma without uncontrolled channel clipping or oversaturating already-strong colors.
- **IMAGE: Local contrast** — Implement clarity, texture and dehaze at distinct spatial scales with halo control.
- **IMAGE: Edge-aware denoise** — Reduce luminance/chroma noise while preserving text, handwriting and fine texture.
- **IMAGE: Output sharpening** — Scale radius to final dimensions and sharpen luminance to avoid color fringes.
- **IMAGE: Monochrome channel mixing** — Produce neutral/warm/cool monochrome with controlled contrast.
- **IMAGE: LUT/color-matrix rendering** — Implement creative looks with versioned, tested transforms.
- **IMAGE: Grain and vignette** — Apply deterministic grain after resizing and feathered vignette as optional finishing effects.
- **IMAGE: Alpha-safe compositing** — Preserve transparency for PNG/background-removal outputs.
- **IMAGE: Image-format encoding** — Export compatible JPEG, PNG and capability-gated HEIF/HEIC with metadata policy.
- **IMAGE: Preview/final equivalence** — Use the same recipe semantics at preview and export resolution.
- **IMAGE: Render-cache design** — Cache thumbnails/previews by source revision, recipe and renderer version.

## OCR skills

- **OCR: On-device recognizer integration** — Manage installed/downloadable models and expose only supported languages.
- **OCR: Input-render selection** — Choose geometry-corrected grayscale/color input based on measured recognition quality instead of the display preset.
- **OCR: Layout and reading-order extraction** — Preserve text blocks, polygons, lines and page mapping.
- **OCR: Coordinate normalization** — Convert Android/iOS recognizer coordinates into canonical top-left normalized page geometry.
- **OCR: Searchable-PDF mapping** — Transform OCR geometry into PDF coordinates after crop, rotate, margins and paper layout.
- **OCR: Transcript correction model** — Separate recognizer output from user-corrected text and define alignment behavior.
- **OCR: Revision invalidation** — Invalidate or reuse OCR only according to geometric and tonal edit rules.
- **OCR: OCR indexing** — Maintain a full-text index of the current approved transcript and remove stale/trashed entries.
- **OCR: Accuracy evaluation** — Measure word/character error rate on fixed scripts, layouts, numbers and punctuation.

## PDF skills

- **PDF: Raster-page PDF generation** — Build A4, Letter and fit-to-image documents with explicit margins, orientation and page order.
- **PDF: Searchable OCR layer creation** — Add invisible/selectable text while keeping the scan image visible.
- **PDF: Page-tree manipulation** — Merge, split, rotate, duplicate, reorder and delete without unnecessary rasterization.
- **PDF: Mixed-page normalization** — Fit or fill pages to chosen paper sizes without silent cropping.
- **PDF: Adaptive image compression** — Select color/grayscale/bilevel encoding and Compact/Balanced/Print quality targets.
- **PDF: Monochrome encoding** — Evaluate lossless-compatible bilevel compression and avoid unsafe symbol substitution.
- **PDF: Annotation modeling** — Store and render ink, highlight, text and visual signatures in canonical page geometry.
- **PDF: Annotation flattening** — Produce a flattened derivative while preserving an editable source revision.
- **PDF: Watermark and page-number composition** — Apply visible marks with explicit page range, position and opacity.
- **PDF: Password encryption** — Protect output, avoid password logging and reopen the result to verify it.
- **PDF: Secure redaction** — Remove underlying text/image data and verify by extraction, object inspection and rendering.
- **PDF: Vector-preservation analysis** — Detect vector/text PDFs and disclose any operation that rasterizes them.
- **PDF: PDF/A conformance** — Embed required resources and validate archival output with a conformance checker.
- **PDF: Reader compatibility testing** — Validate output rendering, search and selection in independent readers.
- **PDF: Malformed-input handling** — Parse untrusted PDFs off the UI thread with limits and controlled errors.

## Video and media skills

- **VIDEO: Native video decoding** — Decode scaled frames using presentation timestamps and handle variable-frame-rate input.
- **VIDEO: Adaptive frame sampling** — Sample an interval densely enough for page changes without decoding every frame.
- **VIDEO: Candidate grouping** — Combine perceptual similarity, geometry and optional OCR similarity to group probable duplicates.
- **VIDEO: Neighbor-frame replacement** — Retain nearby alternatives so users can replace a blurred suggested frame.
- **VIDEO: Review-first selection** — Preserve uncertain candidates for human selection rather than silently deleting them.
- **VIDEO: Checkpointed analysis** — Persist decode/analysis position and candidate metadata for interruption recovery.
- **VIDEO: Codec capability negotiation** — Advertise only decoders, encoders, resolutions and containers supported on the device.
- **VIDEO: Photo-to-video composition** — Arrange stills, durations, aspect treatment and optional user audio into MP4.
- **VIDEO: Basic clip editing** — Trim, rotate and fit/crop with preview/output equivalence.
- **VIDEO: Thermal and storage limits** — Adjust analysis rate and stop safely at input/page/storage limits.

## Data and job-system skills

- **DATA: Relational schema design** — Model Document, Page, PageRevision, Asset, OCR, Annotation, Draft, VideoSession, Candidate, Export and Job entities.
- **DATA: SQLite transactions and constraints** — Enforce page order, revision uniqueness, foreign keys and atomic reorder operations.
- **DATA: Schema migration** — Upgrade and roll back metadata safely with fixture-based migration tests.
- **DATA: Atomic asset commit** — Stage, close/checksum, atomically rename and commit metadata with an idempotent capture identifier.
- **DATA: Orphan reconciliation** — Recover unacknowledged valid manifests and remove expired unreferenced staged files after a grace period.
- **DATA: Reference-aware garbage collection** — Delete derived/source assets only when no live page, undo revision, export or job references them.
- **DATA: Trash and restore** — Preserve asset ownership/order during recoverable deletion and remove index entries appropriately.
- **DATA: Full-text search** — Index current titles and approved OCR transcripts while excluding stale revisions.
- **DATA: Asset-path security** — Store relative allowlisted paths and reject traversal/arbitrary filesystem commands.
- **DATA: Metadata minimization** — Strip location from exports by default and avoid storing sensitive content in analytics.
- **JOBS: Durable native job ledger** — Make queued/running/terminal states authoritative outside transient Flutter state.
- **JOBS: Idempotent submission** — Reuse client request IDs and reject the same ID with conflicting payload.
- **JOBS: Sequenced progress events** — Report stage and completed/total units with event sequence numbers.
- **JOBS: Cooperative cancellation** — Cancel at safe chunks, resolve success/cancel races atomically and remove incomplete outputs.
- **JOBS: Revision compare-and-swap** — Prevent an old render/OCR job from overwriting a newer page revision.
- **JOBS: Export snapshotting** — Freeze page order, revisions, OCR and annotations at submission time.
- **JOBS: Crash recovery** — Reconcile native terminal jobs and committed assets after process restart.

## Security and privacy skills

- **SECURITY: Sensitive-document threat modeling** — Analyze loss, leakage, malicious input, debug logs, share copies and app-switcher exposure.
- **SECURITY: App-private storage** — Apply platform file protection and exclude temporary working files from inappropriate backup.
- **SECURITY: Secure temporary-file lifecycle** — Bound the lifetime of previews, decoded media and share copies.
- **SECURITY: Input validation** — Limit pixel dimensions, page counts, video duration/size and decompression expansion.
- **SECURITY: Parser isolation and limits** — Process codecs/PDFs away from UI state and fail safely on malformed inputs.
- **SECURITY: Secret handling** — Use Keychain/Keystore for passwords or future tokens and never persist plaintext export passwords.
- **SECURITY: Privacy-safe telemetry** — Collect opt-in stage/error/count metrics without filenames, OCR text, identity fields or images.
- **SECURITY: Secure redaction verification** — Prove removed content cannot be recovered through text extraction or PDF objects.
- **SECURITY: Share-boundary awareness** — Explain that files copied to external destinations follow the receiving app's lifecycle.

## UX and accessibility skills

- **UX: Scanner information architecture** — Organize Library, Scan, Tools, Settings and contextual document editing.
- **UX: Capture guidance design** — Communicate hold steady, move closer, blur, glare, page added and retake states concisely.
- **UX: Filter-discovery design** — Separate document effects from photo styles and make Original/Before visible.
- **UX: Batch-edit design** — Apply enhancement to selected/all pages without copying unrelated crop geometry.
- **UX: ID front/back workflow** — Guide required sides, retakes, swaps, paper layout and optional purpose watermark.
- **UX: Video candidate review** — Present timestamps, quality warnings, selected count and alternatives clearly.
- **UX: OCR correction workflow** — Make recognized text editable without implying that the page pixels changed.
- **UX: Page organizer interaction** — Support reorder, rotate, duplicate, delete, annotate and add-page operations.
- **UX: Export configuration** — Reveal format-relevant controls, distinguish estimated/final size and enable share only after completion.
- **UX: Error-recovery writing** — Provide direct actions for permission denial, low storage, missing models, unsupported input and interruptions.
- **UX: Reversible destructive actions** — Use trash/undo and explain permanent deletion scope.
- **UX: Capability-disabled states** — Explain why a feature is unavailable instead of substituting hidden behavior.
- **ACCESSIBILITY: Screen-reader semantics** — Label camera controls, crop corners, filters, progress, selections and page actions.
- **ACCESSIBILITY: Non-drag alternatives** — Provide nudge/move-up/move-down controls for crop and reordering.
- **ACCESSIBILITY: Dynamic type** — Verify layouts at 200% text scale and avoid clipped critical actions.
- **ACCESSIBILITY: Contrast and redundant cues** — Pair color with text/icons and meet readable contrast in light/dark/camera surfaces.
- **ACCESSIBILITY: Focus and modal management** — Restore focus, trap it in dialogs where appropriate and preserve logical reading order.

## Performance and reliability skills

- **PERFORMANCE: Frame-budget management** — Target fluid preview while analysis runs at an adaptive lower rate.
- **PERFORMANCE: Bounded memory processing** — Stream large pages/documents instead of decoding every full-resolution bitmap at once.
- **PERFORMANCE: Preview generation control** — Debounce sliders, assign generation IDs and discard stale results.
- **PERFORMANCE: GPU/CPU profiling** — Select native render paths from measurements rather than assumptions.
- **PERFORMANCE: Cache design** — Use bounded LRU caches for thumbnails/previews and respond to memory pressure.
- **PERFORMANCE: Thermal adaptation** — Reduce analysis/render rate when the OS reports thermal stress.
- **PERFORMANCE: Battery-aware camera use** — Stop analysis offscreen and close inactive sessions promptly.
- **PERFORMANCE: Benchmark methodology** — Report P50/P95 with device, OS, thermals, input dimensions and model/renderer version.
- **PERFORMANCE: Export streaming** — Render/compress page by page, finalize atomically and measure final file size.

## Verification and delivery skills

- **QA: Requirements traceability** — Connect functional IDs and acceptance criteria to implementation and test cases.
- **QA: Capture-corpus testing** — Cover flat/curved pages, receipts, whiteboards, shadows, glare, faint print and rotation.
- **QA: Image golden testing** — Compare perspective, orientation, color, threshold and cleanup outputs against versioned references.
- **QA: OCR ground-truth testing** — Measure recognition error and layout/coordinate accuracy across fonts and structures.
- **QA: PDF conformance testing** — Check search/select, page geometry, encryption, redaction and rendering in multiple readers.
- **QA: Video-corpus testing** — Cover page turns, repeats, near-duplicate forms, blur, exposure change and missed frames.
- **QA: Resilience/fault-injection testing** — Terminate during capture/render/OCR/export and simulate low storage, model failure and permission revocation.
- **QA: Property testing** — Validate quadrilateral convexity, normalized coordinates, recipe identity values and deterministic output.
- **QA: Cross-language contract testing** — Keep Dart/Kotlin/Swift DTOs and error codes compatible.
- **QA: Accessibility testing** — Test screen readers, switch/keyboard access where applicable, contrast and large text.
- **QA: Real-device matrix testing** — Verify low/mid/high Android devices and minimum/current iPhones.
- **QA: Performance regression testing** — Track capture readiness, filter-preview latency, OCR/export time, memory and thermals.
- **DEVOPS: Flutter multi-platform build pipeline** — Build, sign and test Android/iOS artifacts with pinned toolchains.
- **DEVOPS: Dependency/license governance** — Pin native/Flutter libraries, scan licenses and document SDK obligations.
- **DEVOPS: Reproducible algorithm assets** — Version LUTs, models, preset definitions and test corpora with renderer releases.
- **DEVOPS: Release observability** — Monitor privacy-safe error codes, job failures and performance regressions.

## Future research skills

- **RESEARCH: ARCore depth prototyping** — Measure supported Android devices, depth quality and capture guidance.
- **RESEARCH: iOS depth/LiDAR capability study** — Define supported hardware and equivalent native inputs.
- **RESEARCH: Point-cloud fusion** — Align depth/color frames into a stable scene or object point cloud.
- **RESEARCH: Mesh reconstruction** — Convert fused geometry into watertight or usable meshes with measurable error.
- **RESEARCH: Texture mapping** — Project camera imagery onto reconstructed surfaces with seam/exposure correction.
- **RESEARCH: 3D export compatibility** — Evaluate GLB/GLTF, OBJ and STL outputs by product use case.
- **RESEARCH: 3D quality evaluation** — Measure scale accuracy, completeness, drift and device-specific failure modes.

## Suggested ownership map

| Role | Primary prefixes | Supporting prefixes |
|---|---|---|
| Product/solution architect | `HLD:` | `SECURITY:`, `DATA:`, `QA:` |
| Flutter engineer | `FLUTTER:`, `MOBILE:` | `INTEROP:`, `UX:`, `ACCESSIBILITY:` |
| Android engineer | `ANDROID:`, `CAMERA:` | `INTEROP:`, `VIDEO:`, `JOBS:` |
| iOS engineer | `IOS:`, `CAMERA:` | `INTEROP:`, `VIDEO:`, `JOBS:` |
| Computer-vision engineer | `CV:`, `ALGORITHM:` | `IMAGE:`, `PERFORMANCE:`, `QA:` |
| Imaging/color engineer | `IMAGE:`, `ALGORITHM:` | `CV:`, `PDF:`, `QA:` |
| OCR engineer | `OCR:` | `CV:`, `PDF:`, `DATA:` |
| PDF engineer | `PDF:` | `OCR:`, `SECURITY:`, `DATA:` |
| QA engineer | `QA:` | Every implementation prefix |
| Security/privacy engineer | `SECURITY:` | `DATA:`, `PDF:`, `DEVOPS:` |
| Product/UX designer | `UX:`, `ACCESSIBILITY:` | `HLD:`, `QA:` |
| Build/release engineer | `DEVOPS:` | `MOBILE:`, `SECURITY:`, `QA:` |

## Implementation priority

1. **Foundation:** `HLD:`, `FLUTTER:`, `INTEROP:`, `DATA:`, `JOBS:`, `SECURITY:`.
2. **Release 1 capture:** `ANDROID:`, `IOS:`, `CAMERA:`, core `CV:` geometry.
3. **Release 1 enhancement/export:** core `ALGORITHM:`, `IMAGE:`, `OCR:`, `PDF:`.
4. **Release 1 product quality:** `UX:`, `ACCESSIBILITY:`, `PERFORMANCE:`, `QA:`, `DEVOPS:`.
5. **Release 2 media:** `VIDEO:` plus extended job/performance testing.
6. **Later work:** advanced cleanup algorithms and `RESEARCH:` 3D capabilities.
