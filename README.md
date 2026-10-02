# LumaScan — product and engineering design

Working product name. Prepared 2 October 2026 for a Flutter app with native Kotlin (Android) and Swift (iOS) modules.

This repository currently contains a specification and interactive screen prototype, not a working scanner or Flutter application. All preview content is fictional; camera, OCR, processing and exports are simulated.

## Deliverables

- [Requirements and acceptance criteria](docs/requirements.md)
- [High-level design](docs/high-level-design.md)
- [Detailed low-level design](docs/low-level-design.md)
- [Screen specifications and navigation](docs/screen-design.md)
- [Document and PDF effects catalog](docs/document.md)
- [Image filter catalog](docs/image%20filters.md)
- [Scanning flow implementation](docs/scanning-flow.md) — Flutter code for capture, crop, filters and PDF export, with run and permission setup.
- [Engineering skill inventory](skills.md) — prefixed skills derived from HLD, LLD, algorithms, UX and verification documents.
- [PNG screen-design board](design/lumascan-screen-design.png) — six high-fidelity screens at 1536×1024.
- [Premium screen board v2](design/lumascan-premium-design.png) — the six screens restyled with dark mode and glass camera controls; source in [design/premium](design/premium/index.html).
- [Interactive screen prototype](design/index.html) — open directly in a browser; no installation or internet needed.

The prototype has 12 selectable screens. Try Library → Scan → Capture → Crop → Filters → Pages → Export. Also try ID front/back capture, video candidate selection, OCR correction, photo adjustments and permission/error states.

## Decisions

Flutter owns screens and workflow; native modules own capture and expensive media operations. Documents stay on-device by default. Document scanning, photo editing, ID layouts, OCR and PDF creation form Release 1. Video-to-document scanning and photo-to-video creation form Release 2. True 3D reconstruction is an independent later phase.

The specifications distinguish proposed product behavior from SDK capabilities and identify decisions that require device prototypes. No dependency installation, account connection, cloud deployment, production code or real document processing is included in this design delivery.

## Verification

Run `node design/verify.cjs` for the prototype's source/logic checks. The 46 checks passed, covering screen templates, crop validation, navigation, sample capture, page editing/undo, ID side swapping, video selection, photo reset and cancellation. JavaScript syntax was also checked.

Visual browser verification was not completed because permission to access the local preview was denied. The checks do not verify browser layout, accessibility in a real browser, or any native processing. Open `design/index.html` directly to review the visual design; the files have no remote resource dependencies.
