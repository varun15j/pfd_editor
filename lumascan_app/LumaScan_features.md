# LumaScan v2 — product features and UX direction

Prepared 2 October 2026. This is an original product direction informed by public descriptions of Adobe Scan, not a screen-for-screen copy. Adobe names, visual assets, icons, wording, and proprietary interaction details must not appear in LumaScan.

## Executive direction

LumaScan v2 should feel like a camera that quietly produces a useful document, not an image editor that asks the user to repair every page. The primary path is:

**Capture → Review → Save → Find or act**

Automation should handle edge detection, capture timing, perspective correction, cleanup, naming suggestions, and OCR. Manual controls remain easy to reach when confidence is low, but they should not interrupt a successful scan.

Three product promises guide the design:

1. **Paper to clean PDF in seconds.** The default path requires minimal physical and cognitive effort.
2. **The user stays in control.** Every automatic crop, enhancement, name, and document classification can be corrected.
3. **A scan becomes useful.** Search, extracted text, organization, sharing, signing, and contextual actions matter as much as capture.

## Research findings

### Functional model

Adobe Scan's current public listing emphasizes high-speed multi-page capture, automatic border detection and straightening, OCR, editable text, cleanup or magic erasing, brightness and contrast controls, page reordering, PDF/JPEG output, folders, password protection, business-card contact extraction, cloud access, Office export, and AI summaries/questions. It also promotes finding likely documents in the photo library. These features show that a mature scanner spans four jobs: accurate capture, document repair, retrieval, and downstream action.

The earlier product design is especially useful because it explains the reasoning behind the feature set. Adobe's team modeled the full journey from physical context through digitization, use, and later reuse. It aimed to reduce both physical and cognitive effort: automatic capture and cleanup lead, while manual editing is available rather than mandatory. The library separates recent work from the complete collection and adds search and sorting for delayed retrieval.

The public portfolio describes a simple information architecture with three major areas: **Capture, Review, and File List**. It also documents several lessons worth carrying into LumaScan:

- Make automatic and manual capture states visible; hidden manual capture hurts discoverability.
- Coachmarks can be missed when capture is fast. Prefer persistent, contextual status and progressive disclosure.
- Explain an automatic crop only when confidence is uncertain; do not interrupt every successful capture.
- Keep single-page scanning very short while allowing the same flow to scale to books and document stacks.
- Use detected document type to offer the next action, such as creating a contact from a business card.

## Current LumaScan baseline

Already implemented or represented in the current Flutter app:

- Camera scanning through the platform document scanner.
- Gallery import.
- Automatic page-edge detection and perspective correction.
- Manual four-corner crop and page rotation.
- Multi-page drafts with reorder, delete, undo, and add-more.
- Original, Magic Color, Grayscale, and B&W filters.
- Apply-filter-to-all while preserving page-specific crop and rotation.
- Reopen drafts or saved documents to re-crop/resize and replace a previous filter; saves create non-destructive recipe revisions from the retained original.
- PDF export with A4, Letter, or fit-to-image sizing and quality options.
- Open and edit an existing PDF.
- Pen, highlight, text, erase, signature, page organization, and save-as-new-PDF.

Important current gaps:

- Drafts and the scan library do not survive restart.
- There is no OCR, full-text search, folder system, or document classification.
- There is no custom live camera UI, capture-confidence feedback, or explicit Auto/Manual mode.
- Enhancement lacks brightness, contrast, cleanup/eraser, and curved-page straightening.
- Exported edited PDFs rasterize the source pages, losing original selectable text.
- There are no contextual actions for receipts, IDs, forms, or business cards.

## V2 information architecture

Use four primary destinations and one global capture action:

| Destination | Purpose |
|---|---|
| **Home** | Recent scans, continue draft, quick actions, processing status |
| **Library** | All scans, folders, search, sort, filters, multi-select |
| **Capture** | Camera-first flow with Auto/Manual and document mode |
| **Profile & Settings** | Local/cloud policy, OCR language, export defaults, privacy |

The main navigation uses Home, Library, and Settings. A prominent centered Scan button remains reachable from Home and Library. Capture is a task, not a permanent navigation tab.

## Core v2 flow

### 1. Home

- Continue unfinished draft at the top when one exists.
- Primary actions: **Scan**, **Import photos**, **Edit PDF**.
- Recent files show thumbnail, name, page count, timestamp, and processing state.
- Suggested action appears only when useful: Share, Sign, Add contact, or Review crop.
- No promotional carousel in the critical path.

### 2. Capture

- Full-screen camera with a clear document boundary and four visible corner anchors.
- Persistent Auto/Manual segmented control.
- Camera-mode picker: Docs, Book, Text, OCR Doc, QR and Photo. Docs is the compact document shortcut; Book preserves paired left/right pages and print layout; Text is live low-latency recognition; OCR Doc is full-resolution accuracy OCR with searchable output; QR previews and confirms decoded actions.
- Auto mode detects type without blocking capture.
- Status language is short and actionable: **Find a document**, **Hold steady**, **Move closer**, **Capturing**, **Page 3 saved**.
- Haptic and visual confirmation after each page.
- Thumbnail stack opens the review tray; a page counter supports long sessions.
- Flash, gallery import, and accessibility labels remain visible.
- When crop confidence is high, continue silently. When it is low, mark the thumbnail and ask for review after capture.

### 3. Review

- Large page preview with a horizontal thumbnail strip.
- Primary action: **Save PDF**. Secondary tools: Add page, Crop, Rotate, Enhance, Clean up, Organize, Delete.
- Suggested file name from OCR/date/document type, always editable.
- Batch actions: enhance all, rotate selected, delete selected.
- Hold to compare the processed page with the original.
- Low-confidence crop gets a visible **Check edges** badge rather than a modal interruption.

### 4. Save and completion

- Save sheet defaults to PDF and remembers the user's last quality/page-size choices.
- Options: PDF or JPEG, page size, quality, searchable text, password, destination.
- Saving is resilient and atomic. The file appears in Home immediately with background OCR status.
- Completion screen offers Share, Open, Extract text, Sign, Move to folder, and Done.

### 5. Library and retrieval

- Recent and All views, plus user folders.
- Search scans file names and OCR text.
- Sort by newest, oldest, name, or page count.
- Filter by type, folder, favorite, date, or processing state.
- List/grid toggle and multi-select for move, share, export, or delete.
- Offline-first metadata and thumbnails; cloud sync is optional and explicit.

## Feature backlog

### P0 — make the scanner dependable

- Persistent drafts and document library.
- Custom camera surface with Auto/Manual capture.
- Capture stability and confidence feedback.
- Review workspace with thumbnail strip and batch editing.
- Searchable PDF OCR with language selection.
- File naming, rename, folders, search, sort, and multi-select.
- Brightness, contrast, and stronger automatic cleanup.
- Share/save destination handling and reliable background processing.
- Accessibility: 48 dp targets, TalkBack labels, logical focus, dynamic type, high contrast, reduced motion.

### P1 — make scans actionable

- Document classification: document, receipt, ID, book, whiteboard, business card.
- Receipt actions: extracted total/date/vendor and exportable structured data.
- Business-card contact extraction with a confirmation form.
- ID front/back guided capture and a safe combined layout.
- Form detection with Fill & Sign handoff to LumaScan's editor.
- Copy/export recognized text.
- Password-protected PDFs and optional biometric app lock.
- Cleanup brush for fingers, stains, punch holes, shadows, and unwanted marks.
- Book mode with curved-page flattening and split-page capture.

### P2 — intelligence and ecosystem

- On-device summary and key-point extraction where supported.
- Ask questions about a scan with clear privacy and processing disclosures.
- Suggested next actions based on type and content.
- Optional encrypted sync and cross-device access.
- Export to editable document/spreadsheet formats after OCR validation.
- Duplicate detection and smart grouping of related receipts or pages.

## Interaction and visual design system

### Visual character

LumaScan should be calm, precise, and recognizably its own product. Use deep ink/navy surfaces, clean white document canvases, cyan as the capture/edge color, and violet only for intelligent suggestions or premium actions. Avoid Adobe red, Adobe typography, and mirrored Adobe screen compositions.

- 8 pt spacing grid; 16–24 px page margins.
- Rounded rectangles with restrained elevation, not heavy glass effects over documents.
- Document preview receives the strongest visual contrast.
- One dominant action per screen.
- Icons use a consistent rounded-line family with text labels for destructive or ambiguous actions.
- Motion communicates capture, processing, and successful save; it never delays input.

### Automation language

- State what is happening, not what the technology is: **Edges found**, not **AI detected geometry**.
- Pair uncertainty with an action: **Check the top edge**.
- Do not use repeated tutorial overlays. Teach in place and only when the behavior first becomes relevant.
- Preserve an obvious undo path for delete, crop reset, filter, and automatic naming.

### Accessibility and privacy

- Never rely on color alone for crop confidence or selection.
- Provide shutter alternatives for motor accessibility and volume-key capture where supported.
- Allow automatic capture to be disabled permanently.
- Explain whether OCR or intelligent features run on-device or remotely before upload.
- Keep originals private and local by default; cloud sync requires a deliberate opt-in.
- Provide deletion, retention, and export controls in plain language.

## Success metrics

- Median time from opening Capture to saving a clean one-page PDF.
- Percentage of pages accepted without manual crop correction.
- Auto-capture cancellation or switch-to-manual rate.
- Scan completion rate for 1, 5, and 20-page sessions.
- OCR search success and correction rate.
- Percentage of saved scans successfully retrieved after 7 and 30 days.
- Crash-free capture/export sessions and background-processing failure rate.
- Accessibility task-completion rate with TalkBack and large text.

## Delivery sequence

1. Persist drafts and documents; establish the Home/Library data model.
2. Build the custom capture shell around the existing scanner abstraction.
3. Add Review and batch-edit architecture while reusing current crop/filter rendering.
4. Integrate OCR and searchable-PDF export; index text locally.
5. Add folders, search, sorting, and multi-select.
6. Add document-type modes and contextual actions.
7. Add cleanup/book processing, security controls, and optional sync.
8. Add intelligent summaries only after privacy, quality, and failure handling are explicit.

## Sources

- [Adobe Scan Google Play listing](https://play.google.com/store/apps/details?id=com.adobe.scan.android) — current public feature descriptions, consulted 2 October 2026.
- [Exploring the Design Principles Behind Adobe Scan](https://blog.adobe.com/en/publish/2018/07/30/exploring-the-design-principles-behind-adobe-scan) — journey mapping, automation, cognitive-effort reduction, and retrieval principles.
- [Adobe Scan Designs by Amy Casillas](https://www.behance.net/gallery/75701065/Adobe-Scan-Designs) — Capture/Review/File List architecture and documented design iterations.
- [Adobe Acrobat mobile scan documentation](https://www.adobe.com/devnet-docs/acrobat/ios/en/scan.html) — editing, reordering, crop, color, rotate, and page deletion workflow.

