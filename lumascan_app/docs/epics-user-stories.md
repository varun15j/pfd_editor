# PDF Scanner & Editor App

## Product requirements: epics, user stories, features, use cases, and screenshot evidence

**Document status:** Draft product specification  
**Evidence set:** 52 mobile screenshots captured on 2 October 2026  
**Evidence ordering:** Ascending by screenshot capture time  
**Reference products observed:** OKEN-style PDF toolbox and Adobe Scan  

> This document treats the screenshots as product-research evidence. Product names, logos, promotional wording, personal account information, and third-party trademarks visible in the screenshots are not proposed for reuse. The target application should use its own brand, visual system, copy, and entitlement model.

---

## 1. Product vision

Create a mobile-first PDF scanner and editor that lets users capture paper documents, import existing images or files, enhance and reorganize pages, recognize and edit text, apply PDF utilities and security, organize documents, and export or share the finished result with clear feedback at every step.

### Product goals

1. Make a high-quality scan possible in three actions or fewer from the home screen.
2. Support both quick single-page capture and reliable high-volume, multi-page scanning.
3. Keep page correction, enhancement, OCR, and document assembly in one coherent workflow.
4. Make the status of local files, uploads, OCR, saves, and exports unmistakable.
5. Separate free and paid capabilities transparently without interrupting core tasks unnecessarily.
6. Give users direct control over privacy, analytics, network usage, local storage, and account deletion.

### Primary personas

- **Student:** Scans book pages and notes, corrects perspective, applies OCR, and shares study material.
- **Office professional:** Imports or scans forms, merges pages, signs or protects PDFs, and sends them to colleagues.
- **Field worker:** Captures receipts, IDs, forms, or business cards quickly under imperfect conditions.
- **Document archivist:** Names, tags, sorts, filters, searches, and stores a large document library.
- **Occasional user:** Needs a simple scan-to-PDF path without understanding advanced PDF terminology.

---

## 2. Information architecture

### Primary navigation

- **Home:** Recent documents, document preview, contextual actions, feature discovery.
- **Files:** All documents, folders, tags, search, sort, filter, selection, sync state.
- **Create:** Central scan/import action with document, book, ID, business-card, QR, photo-import, and high-speed options.
- **Tools:** OCR, merge, compress, sign, protect, watermark, reorder, collage, and conversion utilities.
- **Account/Settings:** Profile, storage, preferences, subscriptions, privacy, help, legal information, and sign-out.

### Core document lifecycle

`Acquire → Detect/crop → Enhance → Review/manage pages → OCR/edit → Save/sync → Organize → Export/share`

---

## 3. Epic summary and release recommendation

| ID | Epic | Outcome | Recommended phase |
|---|---|---|---|
| EP-01 | Onboarding, account, and consent | Users can start safely, understand data use, and manage identity | MVP |
| EP-02 | Library, search, and organization | Users can find and manage documents at scale | MVP |
| EP-03 | Camera capture and scan modes | Users can acquire clean pages in varied scenarios | MVP |
| EP-04 | Import and alternate acquisition | Users can create PDFs from photos, files, QR codes, and text | MVP/P1 |
| EP-05 | Review and page management | Users can correct and assemble multi-page documents | MVP |
| EP-06 | Image enhancement and annotation | Users can improve readability and add visual edits | MVP/P1 |
| EP-07 | OCR, digitization, and editable text | Users can search, copy, and correct recognized text | P1 |
| EP-08 | Advanced PDF tools and security | Users can transform, combine, sign, and protect PDFs | P1 |
| EP-09 | Save, sync, export, and sharing | Users can reliably deliver or recover their work | MVP |
| EP-10 | Monetization, AI, settings, and support | Users understand plans and control application behavior | MVP/P2 |

---

## 4. Detailed epics, features, and user stories

## EP-01 — Onboarding, account, and consent

### Features

- Welcome/onboarding carousel with concise value propositions.
- Sign-in with supported identity providers and email.
- Guest or deferred sign-in where product policy permits.
- Usage-data consent presented independently from mandatory terms.
- Profile summary, account tier, cloud-storage usage, sign-out, and account deletion.
- Links to privacy policy, terms, third-party notices, and application version.

### User stories and acceptance criteria

**US-01.1 — Understand the product before signing in**  
As a new user, I want a short explanation of scanning, editing, and sharing so that I can decide whether the app meets my needs.

- Given a first launch, when onboarding appears, then the user can advance, skip where allowed, and see progress.
- Each page has one primary message and one clear action.
- Back navigation never loses already accepted mandatory terms.

**US-01.2 — Choose a sign-in method**  
As a user, I want to authenticate using a familiar provider or email so that setup is fast.

- Available providers are labelled and accessible.
- Authentication failure preserves context and offers retry.
- The app does not imply that optional analytics consent is required for authentication.

**US-01.3 — Control usage analytics**  
As a privacy-conscious user, I want to choose whether usage data is shared.

- Consent includes a plain-language purpose statement and a learn-more link.
- Declining optional analytics does not block core scanning.
- The choice can be changed later in Preferences.

**US-01.4 — Manage my account**  
As an account holder, I want to view storage consumption, sign out, or request account deletion.

- Storage displays used and total capacity with a readable progress indicator.
- Account deletion requires explicit confirmation and explains consequences.
- Signing out warns about unsynced local work, if any.

---

## EP-02 — Library, search, and organization

### Features

- Recent/home document cards and complete file list.
- Grid and list display modes.
- Search by filename and OCR text.
- Folders and tags, including create, rename, assign, and remove.
- Sort by date or name with a visible active choice.
- Filter by scan type and relative or custom date range.
- Multi-select and contextual overflow actions.
- Local/cloud/sync state and upload progress.

### User stories and acceptance criteria

**US-02.1 — Browse documents**  
As a returning user, I want to see recent and all documents so that I can resume work quickly.

- Each row/card shows thumbnail, name, modification time, and relevant status.
- Empty, loading, offline, and error states include useful actions.
- List/grid preference persists.

**US-02.2 — Search document contents**  
As a user with many scans, I want to search filenames and recognized text.

- Results identify whether the match came from a title or page content.
- Search works incrementally and can be cleared in one action.
- Files without completed OCR remain discoverable by filename.

**US-02.3 — Organize with folders and tags**  
As an archivist, I want folders and tags so that one document can be grouped by project and subject.

- Users can create, edit, delete, and assign labels.
- Deleting a folder or tag does not silently delete its documents.
- Duplicate names and invalid characters receive inline validation.

**US-02.4 — Sort and filter files**  
As a user, I want to narrow the library by type and date and order it predictably.

- Current sort/filter state is visible and resettable.
- Custom date range validates that From is not later than To.
- Filter and sort selections survive rotation and navigation within the library.

---

## EP-03 — Camera capture and scan modes

### Features

- Camera permission guidance and camera preview with a horizontally scrollable Docs, Book, Text, OCR Doc, QR and Photo mode selector.
- Auto edge detection, perspective correction, and automatic capture.
- Manual shutter, flashlight/torch control, and visible on/off state.
- Camera-preview quick controls for Batch mode, Auto capture, and flashlight, synchronized with a capture-settings sheet.
- Optional 3 × 3 alignment grid, capture-mode selector, accepted-page thumbnail, and Batch-mode page counter.
- Document, book, ID card, business card, QR, and high-speed modes.
- Book-mode center divider and paired-page capture.
- High-speed continuous capture with pause/resume and page counter.
- Stability/page-change prompts and manual-capture fallback.
- Optional post-capture border adjustment and automatic straightening.
- Book-spread capture with spine guidance, left/right page pairing, reading direction, original-spread retention and print-layout choices.
- Two distinct text modes: low-latency live Text and full-resolution accuracy-first OCR Doc.
- QR-only detection mode with tracked reticle, decoded summary, duplicate suppression and user-confirmed payload actions.
- Page-change detection: auto capture takes each page once and waits for the page to be turned or swapped.
- One-page focus: a second page only partly in view is left out of the page outline, in every page mode.

### User stories and acceptance criteria

**US-03.1 — Scan a standard document**  
As a user, I want the app to detect the page and capture it automatically.

- A detected quadrilateral is visible before capture.
- Capture waits for adequate stability and focus.
- The user can override auto-capture with the shutter.
- Poor detection provides clear guidance rather than repeatedly firing.

**US-03.2 — Scan an open book**  
As a student, I want one photo of an open book to become two corrected pages.

- Book mode displays labeled Left page / Right page regions and a detected center-spine guide before capture.
- One accepted spread creates two paired pages while retaining the immutable original-spread image.
- Each side can be cropped and corrected independently; low-confidence spine detection opens manual spine placement rather than guessing.
- Output order follows the configured left-to-right or right-to-left reading direction.
- The document stores spread pairing so export can produce individual pages, facing-page spreads or an explicitly requested booklet-print layout without losing order.

**US-03.3 — Scan multiple pages quickly**  
As a high-volume user, I want continuous capture and pause controls.

- The captured-page count updates after every accepted page.
- Pause stops new captures without discarding the batch.
- The app detects unchanged scenes and prompts the user to turn the page or tap to capture.
- A thumbnail opens the captured-page review.

**US-03.4 — Capture IDs and business cards**  
As a field user, I want a mode tuned for small structured documents.

- ID mode guides front/back acquisition and preserves correct pairing.
- Business-card mode frames the card and can hand recognized contact data to the review flow.
- Sensitive document handling follows the application privacy policy.

**US-03.5 — Control the camera preview**
As a user preparing a scan, I want the important capture options on the camera preview so that I can change capture behavior without entering an editing workflow.

- The preview provides quick controls for Batch mode, flashlight/torch, and Auto capture, each with a text or semantic on/off state rather than color alone.
- The settings sheet repeats and stays synchronized with those quick controls, and also provides an optional alignment grid and a path to additional capture preferences.
- Batch mode on keeps the preview open after each accepted page and displays the accepted-page thumbnail and page count. Turning it off preserves already captured pages and returns the next accepted page to review.
- Auto capture on waits for a stable qualifying page and updates the guidance message. Auto capture off keeps edge guidance but requires the shutter.
- Flashlight is disabled with an accessible reason when the active camera does not provide a torch; changing lenses re-evaluates availability.
- The Document, ID card, and Photo choices describe capture modes only. Crop, filters, markup, and other post-capture edit commands do not appear in the camera preview.
- The bottom-right cross is a destructive discard control, not Done, Save or Back. Tapping it opens a blocking confirmation that asks whether to discard the photos and states that the photos and current capture changes cannot be restored.
- “Keep photos” closes the confirmation with no state change. Only “Discard photos” clears the current capture session and returns to Library; both actions have explicit accessible labels.
- The settings sheet closes via its close control, backdrop, system back action, or Escape in the HTML reference without changing saved toggle values.
- Preview controls meet the 48 logical-pixel target, announce name/role/state, support 200% text size, and remain reachable above safe areas.

**US-03.6 — Scan live text**
As a user, I want to point the camera at text and quickly copy or use recognized content without first creating a document.

- Text mode highlights stable recognized regions and minimizes flicker by tracking regions across frames.
- Users can tap a region to copy text or choose a safe structured action for a URL, phone number, email, date or address.
- Text processing stays on-device by default and never opens a URL or invokes an external action without a user tap.
- Unsupported live-scanner devices offer still-image OCR rather than a nonfunctional mode.

**US-03.7 — Capture a document for accurate OCR**
As a user, I want a high-quality document image plus editable and searchable text that preserves the page layout.

- OCR Doc mode captures and perspective-corrects a full-resolution page before accuracy-oriented recognition.
- Results retain blocks, lines, words, bounding geometry, reading order, confidence and user corrections.
- Searchable PDF export aligns an invisible text layer with the visible page image; the original image remains recoverable.
- Model download, progress, cancellation, low-confidence review and retry states are visible.

**US-03.8 — Scan a QR code safely**
As a user, I want the camera to read a QR code and explain its payload before I act on it.

- QR mode restricts recognition to QR codes, displays a tracked reticle and suppresses repeated identical reads.
- The result identifies URL, Wi-Fi, contact, email, phone, SMS or plain-text payloads when the engine provides structured data.
- The app shows the destination or action and requires explicit confirmation; it never automatically opens a link or joins a network.
- Unreadable codes keep the preview active and provide distance, focus or lighting guidance.


**US-03.9 — Never capture the same page twice**  
As a high-volume user scanning 20 to 50 pages, I want auto capture to take each page once, so I do not have to delete duplicates.

- After a capture the guidance reads "Turn to the next page" and the shutter ring stays empty until a different page is in view.
- A page counts as new only after the view is disturbed for at least two analysed frames in a row: the outline is lost, jumps, or the content over it changes strongly (a hand or a turning page sweeping across).
- A single lost or dark frame (detector flicker, a shadow) never counts as a new page.
- Turning a book page under a still outline is detected from the content changing, not only from the outline moving.
- The new page is taken only once it has settled again: corners and content still for the steadiness setting (3, 5 or 8 frames), so a page caught mid-turn is never taken.
- A manual shutter tap also counts as taking the page in view, so auto capture does not take it again.
- Taking the sheet away for two frames or more and putting one back always counts as a new page.

**US-03.10 — Outline only the page in focus**  
As a user holding the camera over one page, I want the outline and the crop to cover that page only, not half of the page next to it.

- Applies to Docs, Book and OCR Doc, to the live outline and to the crop saved with the page, and to imported photos.
- When a second page joins the page at a gutter or sheet edge and runs off the edge of the frame, and the visible part is narrower than the page (at most 85% of its width), it is left out.
- When both pages are fully in view (an open book spread), they are kept together.
- Book mode makes two pages only when the outline reaches across the middle of the frame (both pages in view); held over one page, it makes one page and hides the LEFT PAGE / RIGHT PAGE guides.
- The user can still adjust the crop by hand in page review.

**US-03.12 — Every page photo is cropped to the page**  
As a user scanning a book or sheets of any colour, I want every photo cropped to the page in the middle of the frame, and to crop or uncrop many pages at once.

- The page is found by its colour against the background, the contrast across its edges and its place in the middle of the frame, so cream, yellowed or coloured paper is found too.
- The outline on the preview does not flicker out when the page is lost for a moment.
- A photo in which no page is found is cropped to the outline that was on the preview.
- In Batch Review, Crop offers Auto crop, Full photo or Adjust each page for the selected pages; Auto crop and Full photo are one undo step each.

---

## EP-04 — Import and alternate acquisition

### Features

- Import one or multiple images from the device gallery.
- “Show only documents” gallery filter.
- Auto-crop imported photos with manual adjustment.
- Import supported document/PDF files.
- Create scans from photos and add imported pages to an existing document.
- QR scanning and image-to-text shortcuts.
- Duplicate detection and deterministic import order.

### User stories and acceptance criteria

**US-04.1 — Create a PDF from photos**  
As a user with existing page photos, I want to select several images and create one ordered PDF.

- Multi-selection displays selection order.
- Auto-crop can be toggled before import.
- The user can reorder pages before saving.
- Unsupported or inaccessible images are reported without cancelling valid selections.

**US-04.2 — Add pages to an existing document**  
As a user editing a scan, I want to append camera captures or gallery images.

- The add-page action offers available sources.
- New pages appear in a predictable position and can be moved.
- Existing page edits are preserved.

**US-04.3 — Scan a QR code or extract text**  
As a user, I want quick specialized acquisition without entering the full scan workflow.

- QR results are previewed before opening or copying.
- Image-to-text shows recognition progress and allows copy/export.
- Unsafe URLs receive an appropriate warning.

---

## EP-05 — Review and page management

### Features

- Large page preview and horizontal thumbnail filmstrip.
- Previous/next navigation and current page count.
- Crop with draggable corner and edge handles.
- Retake, rotate, resize, delete, duplicate, insert, and reorder pages.
- Batch selection and batch transformations where safe.
- Undo/redo within the editing session.
- Save/exit safeguards for unsaved changes.
- Reopen both drafts and saved library documents with Crop/resize and Filter still available.

### User stories and acceptance criteria

**US-05.1 — Correct page boundaries**  
As a user, I want to refine detected corners so that only the document is included.

- Handles remain visible and touch-friendly at all zoom levels.
- A magnified loupe or equivalent precision aid appears during adjustment.
- Applying a crop updates the preview without degrading the source unnecessarily.

**US-05.2 — Review a multi-page document**  
As a user, I want to inspect every page before saving.

- The page indicator always reflects the selected thumbnail.
- Tapping a thumbnail selects and centers it.
- Disabled previous/next controls communicate the beginning or end.

**US-05.3 — Reorder or delete pages safely**  
As a user, I want to fix page order and remove mistakes.

- Drag-and-drop or a reorder screen clearly previews final order.
- Deletion of one or many pages is undoable or confirmed.
- The last remaining page cannot be removed without confirming document deletion or cancellation.

**US-05.4 — Re-crop a draft or saved document**
As a user, I want to reopen any editable document and adjust its crop area again so that I can fix boundaries discovered later.

- Draft and saved-document page editors expose Crop/resize in the persistent toolbar.
- Opening Crop starts from the latest saved quad and provides detected-edges, full-image, manual corner/edge adjustment, rotation and reset.
- Saving creates a recipe revision against the retained source, autosaves atomically and does not compound resampling artifacts.
- If the original source is unavailable, the UI clearly explains the limitation before editing.

---

## EP-06 — Image enhancement and annotation

### Features

- Preset filters: original/auto-color, light text, grayscale, and whiteboard.
- Manual exposure, contrast, brightness, saturation, and detail controls.
- Background cleanup and magic eraser.
- Markup tools for pen, highlight, shapes, text, color, and undo/redo.
- Resize/page-size control.
- Apply to current page, selected pages, or all pages.
- Non-destructive edit history where feasible.
- Filter changes remain available after draft autosave, document save and PDF export.

### User stories and acceptance criteria

**US-06.1 — Improve readability with one tap**  
As an occasional user, I want automatic enhancement presets.

- The current preset is visibly selected.
- Preview updates quickly and can be compared with the original.
- Applying a preset to all pages requires an explicit scope selection.

**US-06.4 — Change a previously applied filter**
As a user, I want to reopen a draft or saved document and replace its previous enhancement without rescanning.

- The editor offers Original, Auto Color, Enhanced Color, Bright, Grayscale and B&W, with the current recipe visibly selected.
- A filter can be reset independently of crop and rotation; Reset all edits is a separate confirmed action.
- Preview and final export render from the immutable source plus the latest recipe, not from an already filtered derivative.
- Saving updates the editable document revision and preserves earlier revisions for undo/history according to retention policy.

**US-06.2 — Remove unwanted marks**  
As a user, I want to erase background clutter without damaging nearby text.

- The eraser offers brush-size control and a before/after preview.
- Undo restores the exact prior state.
- Original source data remains recoverable until final destructive export, where supported.

**US-06.3 — Annotate a page**  
As a reviewer, I want to add notes and highlights.

- Markup supports color and thickness choices.
- Annotation placement remains accurate after rotation or resize.
- Exported PDFs preserve annotations according to selected flattening settings.

---

## EP-07 — OCR, digitization, and editable text

### Features

- OCR on save and on demand.
- Configurable recognition language.
- Searchable-text PDF generation.
- Recognized text overlay with region selection.
- Edit, insert, delete, and format recognized text.
- Font style, size, emphasis, alignment, and color controls where supported.
- OCR progress, confidence/failure states, and retry.
- Copy text and export to editable formats.

### User stories and acceptance criteria

**US-07.1 — Make a scan searchable**  
As a user, I want OCR so that I can search and copy text from a scan.

- OCR may run in the background with visible status.
- Failed pages are identified individually and can be retried.
- The image remains available even if OCR fails.

**US-07.2 — Correct recognized text**  
As a user, I want to edit OCR errors directly on the page.

- Editable regions are clearly outlined.
- Zoom and keyboard appearance do not make the active region unreachable.
- Changes support undo/redo and preserve a predictable visual layout.

**US-07.3 — Choose OCR language**  
As a multilingual user, I want to choose the recognition language.

- The current language is visible in Preferences and the OCR flow.
- Unsupported language combinations are explained.
- Changing the language does not silently overwrite prior OCR; reprocessing is explicit.

---

## EP-08 — Advanced PDF tools and security

### Features

- Merge/combine PDFs or scans.
- Reorder, extract, insert, and delete pages.
- Compress PDFs with size/quality estimates.
- Add signatures.
- Add open-password or permission protection.
- Add text/image watermarks.
- PDF collage/contact-sheet creation.
- Convert to editable document format where supported.

### User stories and acceptance criteria

**US-08.1 — Combine documents**  
As an office user, I want to merge multiple files into one ordered PDF.

- Source documents and page counts are shown before merge.
- Users can reorder sources and optionally individual pages.
- Password-protected or corrupt inputs are reported before processing.

**US-08.2 — Compress a PDF**  
As a user, I want a smaller file for email or upload.

- Compression options describe the quality tradeoff.
- Estimated and final sizes are shown.
- The source is retained unless the user explicitly chooses replacement.

**US-08.3 — Sign a document**  
As a user, I want to place a reusable signature on selected pages.

- Signature creation, placement, scaling, and deletion are clear.
- Reuse of a stored signature requires appropriate local security.
- The app distinguishes a visual signature from a cryptographic digital signature.

**US-08.4 — Protect a PDF**  
As a user, I want to require a password before the PDF can be opened.

- Password strength and confirmation are validated.
- The app clearly states that forgotten passwords cannot necessarily be recovered.
- Passwords never appear in logs or analytics.

**US-08.5 — Add a watermark**  
As a document owner, I want to mark pages as confidential, draft, or branded.

- Text/image, opacity, rotation, placement, and page scope are configurable.
- A full preview is shown before export.

---

## EP-09 — Save, sync, export, and sharing

### Features

- Local draft/autosave and explicit PDF save.
- Configurable output quality/compression.
- Cloud upload and sync with progress and retry.
- Share link with explicit access explanation.
- Send PDF copy, compressed copy, or system share sheet.
- Direct app shortcuts where available.
- Export to device storage and editable document formats.
- Offline queue and conflict handling.

### User stories and acceptance criteria

**US-09.1 — Save without losing work**  
As a user, I want the app to preserve edits even when interrupted.

- Draft state is restored after process termination or accidental navigation.
- Save progress and completion are explicit.
- A failed upload does not delete the local document.
- Every new scan or photo import from Home, the Create button, Library or Tools starts a new document. The document that was open before is kept, listed on Home with its page count and whether it was saved as a PDF, and opening it again lets the user read it and add pages to it. Adding pages from inside an open document still adds to that document.

**US-09.2 — Choose output quality**  
As a user, I want to balance readability and file size.

- Each option includes an understandable quality label and estimated size.
- Premium-only options are marked before selection.
- The user can return to editing without losing the chosen settings.

**US-09.3 — Share a link**  
As a collaborator, I want to send a link instead of a large attachment.

- Before link creation, the app states who will have access.
- Users can copy the link or invoke a supported share target.
- Link creation errors are recoverable, and access can be revoked where the backend permits.

**US-09.4 — Send a PDF attachment**  
As a user, I want to share the actual PDF through another app.

- The app distinguishes link sharing from file attachment.
- File name, size, and compression choice are shown before handoff.
- The system share sheet is available as a fallback.

---

## EP-10 — Monetization, AI, settings, and support

### Features

- Plan comparison and free-trial offer.
- Contextual premium indicators without obscuring basic controls.
- Restore purchases and manage subscriptions.
- Optional AI assistant and generative summary.
- Theme, capture, OCR, naming, filters, storage, network, and telemetry preferences.
- Clear-cache workflow that preserves saved/downloaded files.
- Help center, support forum, rating, and app-sharing links.
- About/version/legal screen.

### User stories and acceptance criteria

**US-10.1 — Understand free versus paid capabilities**  
As a free user, I want to know what requires payment before committing effort.

- Premium features carry a consistent visual marker.
- Paywalls state the benefit, trial terms, renewal cadence, and price before purchase.
- Core navigation and already-created documents remain accessible after dismissing an offer.

**US-10.2 — Restore or manage a subscription**  
As a subscriber, I want to restore purchases and manage billing.

- Restore gives clear success, no-purchase, and error results.
- Manage Subscription opens the correct platform account destination.
- Entitlement state refreshes without requiring app reinstall.

**US-10.3 — Configure capture and OCR defaults**  
As a frequent user, I want preferred behavior applied automatically.

- Preferences include border adjustment, straightening, OCR-on-save, language, default filename, default filter, and original-image retention.
- Changes take effect on subsequent scans and clearly state whether existing files are affected.

**US-10.4 — Manage storage and network use**  
As a user with limited storage or mobile data, I want control over caching and cellular uploads.

- Clear Cache shows estimated recoverable space and excludes saved/downloaded documents.
- Cellular-data settings apply to upload, OCR, and AI operations as defined.
- Queued work resumes when an allowed network is available.

**US-10.5 — Use AI features by choice**  
As a user, I want AI assistance only when enabled and appropriate.

- Generative AI can be disabled independently.
- Before first use, the app explains what content is sent and retained.
- AI output is labelled, can be copied, and does not modify source documents without confirmation.

---

## 5. End-to-end use cases

### UC-01 — Scan and save a single document

**Primary actor:** User  
**Preconditions:** Camera permission is available; sufficient device storage exists.  
**Trigger:** User taps the central Create/Scan action.

**Main flow**

1. User selects Document mode.
2. App opens the camera and detects page boundaries.
3. App captures automatically when stable, or the user taps the shutter.
4. App applies perspective correction and opens page review.
5. User adjusts the crop, rotates if needed, and selects an enhancement preset.
6. User confirms the page and names the document.
7. App saves a local draft/PDF, optionally runs OCR, and uploads according to preferences.
8. Library shows the new document and final sync state.

**Alternate/exception flows**

- Detection fails: user captures manually and adjusts all four corners.
- Camera permission denied: app explains how to enable it and offers photo import.
- Upload fails: local save succeeds and upload is queued with retry.

**Postconditions:** A usable PDF exists locally; cloud state is known.

### UC-02 — Scan a multi-page book or batch

1. User opens the camera preview and enables Batch mode from a quick control or the synchronized settings sheet.
2. User chooses Book/Document as supported, optionally enables the alignment grid, and chooses Auto capture or manual shutter.
3. Book mode shows a center divider; Batch mode keeps the camera open for continuous capture.
4. Each accepted capture increments the visible page count and updates the thumbnail.
5. The user pauses, disables Batch mode, or manually triggers capture when prompted; pages already accepted are preserved.
6. The user opens review, removes bad pages, retakes pages, and fixes ordering.
7. The user applies a filter to selected pages or the whole document.
8. The document is saved as one PDF.

### UC-03 — Scan an ID or business card

1. User selects ID Card or Business Card.
2. App displays an appropriately sized guide.
3. For an ID, the app requests front and back; for a business card, it captures one or both sides.
4. App corrects perspective and performs OCR where enabled.
5. User reviews sensitive data and chooses save/export.

### UC-04 — Create a PDF from existing photos

1. User selects Create from Photos.
2. Gallery optionally filters to likely document images.
3. User selects multiple images in the desired sequence.
4. App auto-crops selected images.
5. User corrects crops, reorders pages, applies enhancements, and saves.

### UC-05 — OCR and edit scanned text

1. User opens a saved scan and selects Digitize/Edit Text.
2. App checks or asks for recognition language.
3. OCR runs with progress and page-level status.
4. Recognized regions become selectable.
5. User edits text and applies supported formatting.
6. User saves changes as a searchable PDF or exports to an editable format.

### UC-06 — Find and organize documents

1. User opens Files.
2. User searches by title or OCR text, or filters by type/date.
3. User sorts by name/date.
4. User selects one or more documents and assigns a folder or tag.
5. The library updates while preserving active search/filter context.

### UC-07 — Combine, reorder, and compress PDFs

1. User opens Tools and selects Combine Files.
2. User selects local or cloud PDFs/scans.
3. App validates the inputs and shows source order/page counts.
4. User reorders sources/pages and confirms merge.
5. User selects compression quality with an estimated output size.
6. App creates a new document and preserves originals.

### UC-08 — Sign, watermark, and protect a PDF

1. User opens a document and selects the required tool.
2. User creates/chooses a signature or watermark and positions it.
3. User selects applicable pages.
4. User optionally sets and confirms an open password.
5. App previews the result and exports a protected copy.

### UC-09 — Share a link or PDF attachment

1. User selects Share from a document or library row.
2. App offers Share Link and Share PDF as distinct choices.
3. For a link, the app explains access and creates a copyable URL.
4. For a PDF, the user chooses original or compressed output.
5. App invokes a direct target or the system share sheet.
6. Success/failure is reported without deleting or altering the source.

### UC-10 — Configure preferences and manage the account

1. User opens Account/Settings.
2. User changes theme, capture, OCR, file-naming, filter, network, or analytics preferences.
3. User views storage and clears only recoverable cache.
4. User reviews subscription state, restores purchases, or opens plan management.
5. User accesses help/legal information, signs out, or initiates account deletion.

### UC-11 — Scan a book page by page with auto capture

1. User opens the camera in Docs, Book or OCR Doc with Auto on.
2. The page is outlined; once still, it is taken and the guidance reads "Turn to the next page".
3. While the same page stays in view, nothing more is taken, even if the outline flickers or the light dips for a moment.
4. User turns the page. The turning page sweeps over the view, so the app counts the page as changed.
5. When the new page has settled, it is taken. Steps 3 to 5 repeat for every page.
6. If the app misses a turn, the user taps the shutter; that page is not taken again automatically.

### UC-12 — Scan one page with the next page partly in view

1. User holds the camera over the left page of an open book, or over one sheet lying next to another; part of the second page shows at the edge of the frame.
2. The outline hugs only the page in focus; the cut-off part is left out.
3. In Book mode the app makes one page from the photo instead of a left and a right page.
4. When the user moves back so both pages are fully in view, the outline covers both and Book mode makes two pages again.
5. The saved page is cropped to the same page the outline showed; the user can still adjust it in review.

---

## 6. UX and non-functional requirements

### Accessibility

- Support system font scaling without clipped labels or unreachable controls.
- Provide accessible names, roles, state, and hints for every icon-only control.
- Maintain at least WCAG AA contrast for text and essential controls.
- Do not convey premium status, selection, sync state, or errors by color alone.
- Use touch targets of at least 44 × 44 logical pixels.
- Support screen readers, switch access, and logical focus order.

### Responsiveness and performance

- Camera preview should appear promptly after permission is granted.
- Provide immediate feedback for every capture, save, upload, OCR, merge, and export action.
- Large operations must be cancellable where data integrity permits.
- Thumbnail rendering and long library lists should use incremental loading.
- Memory pressure must not discard an unsaved batch.

### Reliability and recovery

- Autosave edit sessions and captured pages locally.
- Use resumable or retryable uploads.
- Never show a successful save before the file is durably written.
- Expose actionable errors with retry, work-offline, or change-setting options.
- Prevent duplicate output when the user taps a primary action repeatedly.

### Security and privacy

- Encrypt sensitive local metadata and credentials using platform facilities.
- Use encrypted transport for cloud, OCR, and AI requests.
- Ask for the minimum necessary media, camera, and notification permissions.
- Exclude recognized document content, passwords, and signatures from analytics.
- Explain public-link access before link creation.
- Provide retention and deletion behavior for local, cloud, OCR, and AI data.

### Content and interaction quality

- Use consistent verbs: **Scan**, **Import**, **Save PDF**, **Share link**, and **Send PDF**.
- Premium gates must appear before expensive user effort whenever predictable.
- Toolbars should prioritize the most frequent actions and allow horizontal discovery without hiding the selected state.
- Tutorials and “What’s new” overlays must be dismissible and not recur after completion unless reset.
- Destructive actions require confirmation or undo.

---

## 7. Suggested MVP boundary

### MVP

- Onboarding, sign-in, and consent.
- Document capture with auto-detect, manual capture, flash, crop, rotate, retake, and multi-page support.
- Photo import and page reordering/deletion.
- Auto-color, grayscale, and whiteboard filters.
- Local save, basic OCR/searchable PDF, filename editing, and library search.
- List/grid library, sort, date/type filter, folders or tags.
- PDF export, system sharing, upload status, and offline retry.
- Core settings, storage/cache management, help, legal, sign-out, and delete-account entry.

### Post-MVP / P1

- Book, ID, business-card, QR, and high-speed scan modes.
- Advanced OCR editing and editable-format export.
- Merge, compress, signature, password, watermark, resize, and collage tools.
- Link sharing and cross-device cloud sync.
- Full markup and cleanup/magic-eraser tooling.

### P2 / Experimentation

- Generative summaries and document question-answering.
- Smart document classification and suggested folders/tags.
- Contact extraction from business cards.
- Automated quality scoring and duplicate detection.

---

## 8. Screenshot evidence index — ascending capture time

| # | Time | Observed screen/capability | Source file |
|---:|:---:|---|---|
| 01 | 22:21:14 | Document library, sync, list/grid, search, select, create | `US-02.1-Browse-Documents_EP-02_Screen-01.jpg` |
| 02 | 22:21:27 | Tag list, edit, add tag, item count | `US-02.3-Organize-With-Folders-And-Tags_EP-02_Screen-02.jpg` |
| 03 | 22:22:35 | Scan/import shortcuts: ID, document, book, QR, OCR, files, collage, watermark | `US-04.3-Scan-QR-Or-Extract-Text_EP-04_Screen-03.jpg` |
| 04 | 22:22:48 | PDF utilities: merge, compress, signature, password, reorder | `US-08.1-Combine-Documents_EP-08_Screen-04.jpg` |
| 05 | 22:31:22 | Onboarding/sign-in providers, analytics disclosure | `US-01.2-Choose-A-Sign-In-Method_EP-01_Screen-05.jpg` |
| 06 | 22:31:28 | Mobile-app usage consent dialog | `US-01.3-Control-Usage-Analytics_EP-01_Screen-06.jpg` |
| 07 | 22:31:54 | Premium plan comparison, trial cadence, crop/modify/resize/cleanup | `US-10.1-Understand-Free-Versus-Paid_EP-10_Screen-07.jpg` |
| 08 | 22:31:58 | OCR, compression, combine, password premium capabilities | `US-10.1-Understand-Free-Versus-Paid_EP-10_Screen-08.jpg` |
| 09 | 22:32:36 | Document capture tutorial, scan modes, auto-capture | `US-03.1-Scan-A-Standard-Document_EP-03_Screen-09.jpg` |
| 10 | 22:33:06 | Book capture and center-divider guidance | `US-03.2-Scan-An-Open-Book_EP-03_Screen-10.jpg` |
| 11 | 22:33:45 | Business-card capture mode | `US-03.4-Capture-IDs-And-Business-Cards_EP-03_Screen-11.jpg` |
| 12 | 22:33:58 | Gallery import, document-only filter, auto-crop | `US-04.1-Create-A-PDF-From-Photos_EP-04_Screen-12.jpg` |
| 13 | 22:34:28 | Review/editor with page thumbnails and core actions | `US-05.2-Review-A-Multi-Page-Document_EP-05_Screen-13.jpg` |
| 14 | 22:35:03 | Enhancement filter selection | `US-06.1-Improve-Readability-With-One-Tap_EP-06_Screen-14.jpg` |
| 15 | 22:35:07 | Filter carousel continuation | `US-06.1-Improve-Readability-With-One-Tap_EP-06_Screen-15.jpg` |
| 16 | 22:35:51 | Advanced editor tools: text, filters, eraser, adjust, markup | `US-06.2-Remove-Unwanted-Marks_EP-06_Screen-16.jpg` |
| 17 | 22:35:56 | Cleanup, resize, delete, reorder-related tool strip | `US-05.3-Reorder-Or-Delete-Pages-Safely_EP-05_Screen-17.jpg` |
| 18 | 22:36:11 | Save quality/compression and premium treatment | `US-09.2-Choose-Output-Quality_EP-09_Screen-18.jpg` |
| 19 | 22:38:10 | OCR processing to make text editable | `US-07.2-Correct-Recognized-Text_EP-07_Screen-19.jpg` |
| 20 | 22:38:43 | Editable OCR region and text-format controls | `US-07.2-Correct-Recognized-Text_EP-07_Screen-20.jpg` |
| 21 | 22:39:02 | OCR text editing with keyboard and formatting toolbar | `US-07.2-Correct-Recognized-Text_EP-07_Screen-21.jpg` |
| 22 | 22:39:38 | Document detail/home actions: Share, Word, Digitize, More | `US-09.3-Share-A-Link_EP-09_Screen-22.jpg` |
| 23 | 22:39:41 | All scans, folders, selection, sort | `US-02.1-Browse-Documents_EP-02_Screen-23.jpg` |
| 24 | 22:39:48 | Sort by date/name | `US-02.4-Sort-And-Filter-Files_EP-02_Screen-24.jpg` |
| 25 | 22:39:56 | Filter by type and date range | `US-02.4-Sort-And-Filter-Files_EP-02_Screen-25.jpg` |
| 26 | 22:40:10 | Create menu: combine, photos, high-speed, scan | `US-04.2-Add-Pages-To-An-Existing-Document_EP-04_Screen-26.jpg` |
| 27 | 22:40:47 | High-speed scan tutorial and pause control | `US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-27.jpg` |
| 28 | 22:40:54 | Loading/transition state | `US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-28.jpg` |
| 29 | 22:41:34 | High-speed multi-page capture and page counter | `US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-29.jpg` |
| 30 | 22:41:45 | Slow-capture fallback prompt | `US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-30.jpg` |
| 31 | 22:41:55 | Page-change detection prompt | `US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-31.jpg` |
| 32 | 22:43:34 | Page 13/13 review, crop handles, thumbnail strip | `US-05.1-Correct-Page-Boundaries_EP-05_Screen-32.jpg` |
| 33 | 22:43:41 | Full page preview and page navigation | `US-05.2-Review-A-Multi-Page-Document_EP-05_Screen-33.jpg` |
| 34 | 22:44:02 | Leave-to-share confirmation and cloud-save disclosure | `US-09.4-Send-A-PDF-Attachment_EP-09_Screen-34.jpg` |
| 35 | 22:44:20 | File upload/progress state | `US-09.1-Save-Without-Losing-Work_EP-09_Screen-35.jpg` |
| 36 | 22:44:23 | Link-sharing tutorial and direct targets | `US-09.3-Share-A-Link_EP-09_Screen-36.jpg` |
| 37 | 22:44:28 | PDF attachment-sharing tutorial | `US-09.4-Send-A-PDF-Attachment_EP-09_Screen-37.jpg` |
| 38 | 22:44:34 | Share link versus PDF copy/compressed copy | `US-09.3-Share-A-Link_EP-09_Screen-38.jpg` |
| 39 | 22:44:43 | Additional direct/system share targets | `US-09.4-Send-A-PDF-Attachment_EP-09_Screen-39.jpg` |
| 40 | 22:45:03 | Feature-discovery card: folders | `US-02.3-Organize-With-Folders-And-Tags_EP-02_Screen-40.jpg` |
| 41 | 22:45:06 | Feature-discovery card: combine scans | `US-08.1-Combine-Documents_EP-08_Screen-41.jpg` |
| 42 | 22:45:11 | Feature-discovery card: import photos | `US-04.1-Create-A-PDF-From-Photos_EP-04_Screen-42.jpg` |
| 43 | 22:45:13 | Feature-discovery card: premium capabilities | `US-10.1-Understand-Free-Versus-Paid_EP-10_Screen-43.jpg` |
| 44 | 22:45:26 | Settings/profile/plans/about/preferences/subscriptions/support | `US-01.4-Manage-My-Account_EP-01_Screen-44.jpg` |
| 45 | 22:45:29 | Settings continuation and sign-out | `US-01.4-Manage-My-Account_EP-01_Screen-45.jpg` |
| 46 | 22:45:38 | About/version/legal information | `US-01.1-Understand-The-Product_EP-01_Screen-46.jpg` |
| 47 | 22:45:51 | Capture, AI, and OCR preferences | `US-10.3-Configure-Capture-And-OCR-Defaults_EP-10_Screen-47.jpg` |
| 48 | 22:45:58 | Naming, default filter, originals, data, cache preferences | `US-10.4-Manage-Storage-And-Network-Use_EP-10_Screen-48.jpg` |
| 49 | 22:46:00 | Cache clearing, usage analytics, crash reporting | `US-10.4-Manage-Storage-And-Network-Use_EP-10_Screen-49.jpg` |
| 50 | 22:46:06 | Subscription tiers, AI assistant, restore/manage purchases | `US-10.2-Restore-Or-Manage-A-Subscription_EP-10_Screen-50.jpg` |
| 51 | 22:46:33 | Browser help center and top questions | `US-01.1-Understand-The-Product_EP-01_Screen-51.jpg` |
| 52 | 22:46:54 | Account storage and account deletion | `US-01.4-Manage-My-Account_EP-01_Screen-52.jpg` |

---

## 9. Screenshot gallery — ascending capture time

The gallery is deliberately chronological so that product flows can be reconstructed from capture time. Images are linked relatively so the document remains portable with the `UI_UX_screen` folder.

### 01 — 22:21:14 — Document library

![Document library](./US-02.1-Browse-Documents_EP-02_Screen-01.jpg)

### 02 — 22:21:27 — Tags

![Tags](./US-02.3-Organize-With-Folders-And-Tags_EP-02_Screen-02.jpg)

### 03 — 22:22:35 — Scan and import tools

![Scan and import tools](./US-04.3-Scan-QR-Or-Extract-Text_EP-04_Screen-03.jpg)

### 04 — 22:22:48 — PDF utilities

![PDF utilities](./US-08.1-Combine-Documents_EP-08_Screen-04.jpg)

### 05 — 22:31:22 — Onboarding and sign-in

![Onboarding and sign-in](./US-01.2-Choose-A-Sign-In-Method_EP-01_Screen-05.jpg)

### 06 — 22:31:28 — Usage consent

![Usage consent](./US-01.3-Control-Usage-Analytics_EP-01_Screen-06.jpg)

### 07 — 22:31:54 — Premium comparison, page one

![Premium comparison page one](./US-10.1-Understand-Free-Versus-Paid_EP-10_Screen-07.jpg)

### 08 — 22:31:58 — Premium comparison, page two

![Premium comparison page two](./US-10.1-Understand-Free-Versus-Paid_EP-10_Screen-08.jpg)

### 09 — 22:32:36 — Document capture tutorial

![Document capture tutorial](./US-03.1-Scan-A-Standard-Document_EP-03_Screen-09.jpg)

### 10 — 22:33:06 — Book capture

![Book capture](./US-03.2-Scan-An-Open-Book_EP-03_Screen-10.jpg)

### 11 — 22:33:45 — Business-card capture

![Business-card capture](./US-03.4-Capture-IDs-And-Business-Cards_EP-03_Screen-11.jpg)

### 12 — 22:33:58 — Gallery import

![Gallery import](./US-04.1-Create-A-PDF-From-Photos_EP-04_Screen-12.jpg)

### 13 — 22:34:28 — Review and edit

![Review and edit](./US-05.2-Review-A-Multi-Page-Document_EP-05_Screen-13.jpg)

### 14 — 22:35:03 — Filters

![Filters](./US-06.1-Improve-Readability-With-One-Tap_EP-06_Screen-14.jpg)

### 15 — 22:35:07 — Filter carousel

![Filter carousel](./US-06.1-Improve-Readability-With-One-Tap_EP-06_Screen-15.jpg)

### 16 — 22:35:51 — Advanced editing tools

![Advanced editing tools](./US-06.2-Remove-Unwanted-Marks_EP-06_Screen-16.jpg)

### 17 — 22:35:56 — Cleanup and page tools

![Cleanup and page tools](./US-05.3-Reorder-Or-Delete-Pages-Safely_EP-05_Screen-17.jpg)

### 18 — 22:36:11 — Save quality

![Save quality](./US-09.2-Choose-Output-Quality_EP-09_Screen-18.jpg)

### 19 — 22:38:10 — OCR processing

![OCR processing](./US-07.2-Correct-Recognized-Text_EP-07_Screen-19.jpg)

### 20 — 22:38:43 — Editable OCR region

![Editable OCR region](./US-07.2-Correct-Recognized-Text_EP-07_Screen-20.jpg)

### 21 — 22:39:02 — OCR text keyboard editing

![OCR text keyboard editing](./US-07.2-Correct-Recognized-Text_EP-07_Screen-21.jpg)

### 22 — 22:39:38 — Document actions

![Document actions](./US-09.3-Share-A-Link_EP-09_Screen-22.jpg)

### 23 — 22:39:41 — All scans

![All scans](./US-02.1-Browse-Documents_EP-02_Screen-23.jpg)

### 24 — 22:39:48 — Sort options

![Sort options](./US-02.4-Sort-And-Filter-Files_EP-02_Screen-24.jpg)

### 25 — 22:39:56 — Filter options

![Filter options](./US-02.4-Sort-And-Filter-Files_EP-02_Screen-25.jpg)

### 26 — 22:40:10 — Create menu

![Create menu](./US-04.2-Add-Pages-To-An-Existing-Document_EP-04_Screen-26.jpg)

### 27 — 22:40:47 — High-speed tutorial

![High-speed tutorial](./US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-27.jpg)

### 28 — 22:40:54 — Loading state

![Loading state](./US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-28.jpg)

### 29 — 22:41:34 — High-speed capture

![High-speed capture](./US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-29.jpg)

### 30 — 22:41:45 — Manual-capture fallback prompt

![Manual-capture fallback prompt](./US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-30.jpg)

### 31 — 22:41:55 — Page-change prompt

![Page-change prompt](./US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-31.jpg)

### 32 — 22:43:34 — Crop and multi-page review

![Crop and multi-page review](./US-05.1-Correct-Page-Boundaries_EP-05_Screen-32.jpg)

### 33 — 22:43:41 — Page preview

![Page preview](./US-05.2-Review-A-Multi-Page-Document_EP-05_Screen-33.jpg)

### 34 — 22:44:02 — Share confirmation

![Share confirmation](./US-09.4-Send-A-PDF-Attachment_EP-09_Screen-34.jpg)

### 35 — 22:44:20 — Upload progress

![Upload progress](./US-09.1-Save-Without-Losing-Work_EP-09_Screen-35.jpg)

### 36 — 22:44:23 — Link-sharing tutorial

![Link-sharing tutorial](./US-09.3-Share-A-Link_EP-09_Screen-36.jpg)

### 37 — 22:44:28 — Attachment-sharing tutorial

![Attachment-sharing tutorial](./US-09.4-Send-A-PDF-Attachment_EP-09_Screen-37.jpg)

### 38 — 22:44:34 — Share choices

![Share choices](./US-09.3-Share-A-Link_EP-09_Screen-38.jpg)

### 39 — 22:44:43 — More share targets

![More share targets](./US-09.4-Send-A-PDF-Attachment_EP-09_Screen-39.jpg)

### 40 — 22:45:03 — Folder feature card

![Folder feature card](./US-02.3-Organize-With-Folders-And-Tags_EP-02_Screen-40.jpg)

### 41 — 22:45:06 — Combine scans feature card

![Combine scans feature card](./US-08.1-Combine-Documents_EP-08_Screen-41.jpg)

### 42 — 22:45:11 — Import photos feature card

![Import photos feature card](./US-04.1-Create-A-PDF-From-Photos_EP-04_Screen-42.jpg)

### 43 — 22:45:13 — Premium feature card

![Premium feature card](./US-10.1-Understand-Free-Versus-Paid_EP-10_Screen-43.jpg)

### 44 — 22:45:26 — Settings and profile

![Settings and profile](./US-01.4-Manage-My-Account_EP-01_Screen-44.jpg)

### 45 — 22:45:29 — Settings continuation

![Settings continuation](./US-01.4-Manage-My-Account_EP-01_Screen-45.jpg)

### 46 — 22:45:38 — About and legal

![About and legal](./US-01.1-Understand-The-Product_EP-01_Screen-46.jpg)

### 47 — 22:45:51 — Capture, AI, and OCR preferences

![Capture, AI, and OCR preferences](./US-10.3-Configure-Capture-And-OCR-Defaults_EP-10_Screen-47.jpg)

### 48 — 22:45:58 — File, network, and cache preferences

![File, network, and cache preferences](./US-10.4-Manage-Storage-And-Network-Use_EP-10_Screen-48.jpg)

### 49 — 22:46:00 — Cache and diagnostics preferences

![Cache and diagnostics preferences](./US-10.4-Manage-Storage-And-Network-Use_EP-10_Screen-49.jpg)

### 50 — 22:46:06 — Subscriptions and AI plan

![Subscriptions and AI plan](./US-10.2-Restore-Or-Manage-A-Subscription_EP-10_Screen-50.jpg)

### 51 — 22:46:33 — Help center

![Help center](./US-01.1-Understand-The-Product_EP-01_Screen-51.jpg)

### 52 — 22:46:54 — Account and storage

![Account and storage](./US-01.4-Manage-My-Account_EP-01_Screen-52.jpg)

---

## 10. Traceability notes

- EP-02 is supported primarily by screenshots 01–02, 22–25, 35, and 40.
- EP-03 is supported primarily by screenshots 09–11 and 27–33.
- EP-04 is supported primarily by screenshots 03, 12, 26, and 42.
- EP-05 and EP-06 are supported primarily by screenshots 13–18 and 32–33.
- EP-07 is supported primarily by screenshots 03, 08, 19–22, and 47.
- EP-08 is supported primarily by screenshots 04, 08, 17, 26, and 41.
- EP-09 is supported primarily by screenshots 18, 22, and 34–39.
- EP-01 and EP-10 are supported primarily by screenshots 05–08 and 43–52.

This mapping is evidence traceability, not a recommendation to duplicate either reference product’s exact user interface.

