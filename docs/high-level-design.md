# LumaScan: high-level design

Version 1.0 · 2 October 2026 · Design specification, not compiled implementation

Related: [requirements](requirements.md), [low-level design](low-level-design.md), [screen design](screen-design.md).

## 1. System overview

LumaScan is an offline-first Android and iOS app. Flutter owns screens, navigation and workflow state. Platform adapters own the camera, image processing, OCR and PDF work. Documents never leave the device unless the user shares or exports them. There is no backend in Release 1.

```mermaid
flowchart TD
  subgraph Presentation
    SCR[Screens and widgets] --> CTL[Riverpod controllers]
  end
  subgraph Domain
    UC[Use cases] --> IF[Models and service interfaces]
  end
  subgraph Adapters
    DB[Drift + private file store]
    SCAN[ScannerService: OS scanner now, custom camera at M7]
    PDF[PdfService: pdf writes, pdfrx views]
    OCR[OcrService: ML Kit / Vision]
    NAT[Native media module via Pigeon]
  end
  CTL --> UC
  IF --> DB
  IF --> SCAN
  IF --> PDF
  IF --> OCR
  SCAN -.-> NAT
```

Dependencies point down only. Widgets never open files, call packages or write the database.

## 2. Subsystems

| Subsystem | Responsibility | MVP implementation | Later |
|---|---|---|---|
| Capture | Produce page images with optional corner quads | cunning_document_scanner (ML Kit / Vision) | Custom CameraX / AVFoundation surface (ADR-008) |
| Library | Documents, pages, folders, trash, search | Drift + private asset store | Full-text OCR search |
| Image editing | Crop, rotate, filters as recipes on immutable originals | Dart/native render per LLD section 7 | Advanced cleanup, dewarp |
| Annotation | Ink, highlight, text, signature overlays | App-owned overlay, flattened at export | Stamping into imported PDFs |
| PDF output | Build and export scan PDFs | `pdf` package | Encryption via R1.1 engine |
| PDF input | View, search, reorder and merge PDFs | pdfrx | Write engine from spike (ADR-014) |
| OCR | Text with geometry per page | Not in MVP | google_mlkit_text_recognition / Vision |
| Jobs | Long-running export, OCR, video work | Dart isolates with progress streams | Native job ledger (LLD section 12) |

## 3. Cross-cutting principles

- **Offline and private:** no account, no network upload, no document content in telemetry.
- **Non-destructive:** originals are immutable; edits are versioned recipes and annotation rows.
- **Adapters and capabilities:** every engine sits behind an interface and advertises what it supports, so packages can be swapped and missing features disabled with a reason.
- **Crash safe:** committed pages survive process death; exports write to a temp file and rename atomically.

## 4. Data flow: scan to PDF

1. User starts a scan; `ScannerService` returns staged images (and quads when available).
2. Asset store copies them into private storage; Drift inserts Page and PageRevision rows in one transaction.
3. User edits: crop, filter and annotations update recipes and Annotation rows only.
4. Export snapshots page order and revisions, renders each page in an isolate, writes the PDF with the `pdf` package, flattens annotations, then enables Share.

## 5. Delivery

Milestones M0 to M7 and their gates are in [low-level design section 16](low-level-design.md#16-verification-and-delivery-gates). The MVP is complete at M4.

## 6. Open decisions

- Confirm the MVP may ship with the OS scanner screen before the custom camera (ADR-010).
- Confirm whether the app earns revenue, which decides Syncfusion eligibility (ADR-014).
- Confirm minimum OS targets (proposed Android API 26, iOS 16).
