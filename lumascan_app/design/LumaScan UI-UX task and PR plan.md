# LumaScan UI/UX task and PR plan

Oct 2, 2026 · Varun

Source: [LumaScan UI/UX task and PR plan](https://claude.ai/code/artifact/12ce432b-0760-4e7f-b770-cf411fc26f89). Status as of Oct 3, 2026.

## Summary

The spec's UI/UX work fits into **17 PRs in 8 groups**, shipped in 4 waves. Each PR covers screens that share code, so review stays small and nothing waits on a backend.

- Each PR gets its own feature branch, cut from the latest `design/prototype-polish-hld`. Each PR targets that branch, and no PR is force-pushed once it is open.
- Every PR ships with widget tests, `flutter analyze` clean, and the accessibility checks from section 6 of the spec (labels, 48 dp targets, 200% font scale).
- Backend-heavy items are left out of this plan: sign-in, cloud sync, links, subscriptions, OCR and AI. Their screens come later, once those decisions are made (see the last section).
- Release 1 is local-first: everything here runs on the device, with no account or server.
- The visual target is the premium board in `design/premium`. PR A1 turns it into Flutter theme tokens first, so every later PR uses the same look.

## Where the app is today

The app has a working one-draft scan flow and a PDF editor, but no document library, settings or onboarding. Most of the UI/UX gap is in the screens around the flow, not the flow itself.

| Spec area | What exists in `lumascan_app` | Gap |
| --- | --- | --- |
| Navigation (IA) | One home screen (`pages_screen.dart`) that is also the draft | No Home / Files / Create / Tools / Settings shell |
| EP-02 Library | Exported PDFs are written to `exports/`, but nothing lists them | No list or grid, search, sort, filter, folders or tags |
| EP-03 Capture | Native scanner (ML Kit / VisionKit) with camera permission dialogs | No mode picker; book, ID, QR and high-speed modes depend on the custom camera decision |
| EP-04 Import | "Import from photos" button; Dart page detector (PR #4) not wired in | No ordered multi-select, auto-crop toggle or add-pages sheet |
| EP-05 Review | Page list with crop, rotate and delete; undo; four-corner crop | No large preview with filmstrip, no loupe, no edge handles |
| EP-06 Enhance | Filter screen with Apply to all; PDF editor has pen, highlight, text and signature | No before/after compare, scope picker or manual sliders |
| EP-08 Tools | Sign and organize pages inside the PDF editor | No Tools hub; merge, compress, protect and watermark are missing |
| EP-09 Save/share | Export sheet with page size, quality and system share | No document naming, size estimate or draft restore after the app is killed |
| EP-01 / EP-10 | Nothing | No onboarding, consent, settings, storage or about screens |

## PR plan

Seventeen PRs, each one branch off `design/prototype-polish-hld`. Size: S is about 1 day, M 2 to 3 days and L about a week. A PR can start once everything in its Depends on column has merged.

| PR | Group | Scope | Stories | Branch | Depends on | Size | Wave | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A1 | Foundation | Design system and app shell: theme tokens from design/premium, light and dark, bottom nav (Home, Files, Create, Tools, Settings), shared empty/loading/error and premium-marker widgets | IA, NFR accessibility | `claude/ui-design-system` | - | L | 1 | Merged (#6) |
| A2 | Foundation | Local document library model: saved documents with name, pages, thumbnail, type, dates, folder, tags; drafts autosaved | US-02.1, US-09.1 | `claude/ui-document-store` | - | M | 1 | Open (#7) |
| B1 | Library | Home and Files: recent cards, list/grid toggle, rows with thumbnail, name, time and status, multi-select, rename, delete with undo | US-02.1 | `claude/ui-library-browse` | A1, A2 | L | 2 | Open (#9) |
| B2 | Library | Search, sort and filter: incremental filename search, sort sheet, type and date filters with range check, visible reset | US-02.2, US-02.4 | `claude/ui-library-search` | B1 | M | 3 | Not started |
| B3 | Library | Folders and tags: create, rename, delete, assign; inline name validation; deleting a folder keeps its documents | US-02.3 | `claude/ui-folders-tags` | B1 | M | 3 | Not started |
| C1 | Capture | Create sheet and capture entry: scan, import photos, edit PDF; camera-permission guide with import fallback; scan tips | US-03.1, UC-01 | `claude/ui-create-sheet` | A1 | S | 2 | Not started |
| C2 | Capture | Photo import: ordered multi-select, auto-crop toggle using the Dart detector, bad images reported, add pages to an existing document | US-04.1, US-04.2 | `claude/ui-photo-import` | C1, PR #4 | M | 3 | Not started |
| D1 | Review | Page review: large preview with filmstrip, synced page counter, disabled first/last arrows, undo/redo, unsaved-exit guard | US-05.2, US-05.3 | `claude/ui-page-review` | A1 | L | 2 | Not started |
| D2 | Review | Crop precision: magnifier loupe, edge handles, handles that stay visible when zoomed, detector quad as the starting crop | US-05.1 | `claude/ui-crop-precision` | D1 | M | 3 | Not started |
| D3 | Review | Enhance: preset carousel with clear selection, press-and-hold before/after, scope picker (this page, selected, all), brightness and contrast sliders | US-06.1 | `claude/ui-enhance` | D1 | M | 3 | Not started |
| D4 | Review | Markup polish: shared colour and thickness picker, selected-tool state, scrollable toolbar; markup on scanned pages | US-06.3 | `claude/ui-markup` | D1 | M | 4 | Not started |
| E1 | Save/share | Save flow: name the document (default pattern), quality with estimated size, save progress, success only after the file is written | US-09.1, US-09.2 | `claude/ui-save-flow` | A2 | M | 3 | Not started |
| E2 | Save/share | Send PDF: original or smaller copy, name and size shown before handoff, system share fallback; share-link entry hidden until a backend exists | US-09.4, UC-09 | `claude/ui-send-pdf` | E1 | S | 4 | Not started |
| F1 | Settings | Settings: capture and filter defaults, file naming, keep originals, theme, storage with clear cache (keeps saved files), help, about and legal | US-10.3, US-10.4, US-01.4 (local parts) | `claude/ui-settings` | A1 | M | 2 | Not started |
| F2 | Settings | Onboarding and consent: 3-page intro with skip and progress, optional analytics choice shown separately and changeable in Settings, shown once | US-01.1, US-01.3 | `claude/ui-onboarding` | F1 | S | 4 | Not started |
| G1 | Tools | Tools hub and merge: tool grid (sign, reorder, merge); merge with source list, page counts, reordering and locked or broken file warnings | US-08.1, UC-07 | `claude/ui-tools-merge` | A1, A2 | L | 4 | Not started |
| H1 | Quality | Accessibility and polish sweep: 200% font scale, screen-reader labels, contrast, golden tests for each main screen | Section 6 NFRs | `claude/ui-a11y-sweep` | All above | M | 4 | PR open |

### PR waves

| Wave | PRs | Starts after |
| --- | --- | --- |
| 1 | A1 design system and bottom-nav shell, A2 local document store and autosave | - |
| 2 | B1 Home/Files, C1 Create sheet, D1 page review, F1 Settings | A1 (B1 also needs A2) |
| 3 | B2 search/sort/filter, B3 folders/tags, C2 photo import, D2 crop loupe, D3 enhance, E1 save flow | Its wave 2 parent (E1 needs only A2) |
| 4 | D4 markup, E2 send PDF, F2 onboarding/consent, G1 tools hub and merge, H1 accessibility sweep | Its parent (H1 needs all others) |

PRs in the same wave don't depend on each other, so they can be built in parallel threads. Each wave starts once the PRs it depends on have merged.

## Tasks per PR

Each PR is done when every task below is ticked, its widget tests pass and `flutter analyze` is clean.

### A1 Design system and app shell

- [ ] Turn the colours, type scale, radii and spacing from `design/premium` into `ThemeData` tokens, with a light and a dark scheme
- [ ] Add a bottom-nav shell: Home, Files, a centre Create button, Tools and Settings; the current draft screen opens from Create
- [ ] Add shared widgets: empty state, loading skeleton, error with retry, premium badge (icon plus text, not colour alone)
- [ ] Set a 48 dp minimum touch target and semantic labels on every icon-only button

### A2 Local document library model

- [ ] Store each saved document's name, page count, thumbnail, scan type, created and modified dates, folder and tags in a local index
- [ ] Autosave the draft after every change and restore it after the app is killed
- [ ] Give the UI a provider with a list of documents and a single document

### B1 Home and Files

- [ ] Home: recent documents as cards, plus discovery cards (import photos, merge) that can be dismissed
- [ ] Files: list and grid views; the chosen view is remembered
- [ ] Each row shows thumbnail, name, modified time and status
- [ ] Long-press to multi-select; overflow menu with rename, share and delete (delete can be undone)
- [ ] Empty, loading and error states with an action

### B2 Search, sort and filter

- [ ] Search box that filters as you type and clears in one tap; matches by file name (page text waits for OCR)
- [ ] Sort sheet (date or name, either direction) with the active choice shown
- [ ] Filter sheet: scan type plus date (7 days, 30 days, custom); custom rejects From later than To
- [ ] Active sort and filter shown as chips with Reset, kept across rotation and tab changes

### B3 Folders and tags

- [ ] Create, rename and delete folders and tags; names checked inline for duplicates and bad characters
- [ ] Assign one folder and any number of tags from a row or a multi-selection
- [ ] Deleting a folder or tag asks first and never deletes its documents

### C1 Create sheet and capture entry

- [ ] Create sheet with Scan document, Import photos and Edit a PDF
- [ ] Camera-permission guide that explains why, links to Settings and offers photo import instead
- [ ] One-time scan tips (lighting, flat page, dark background) that can be dismissed

### C2 Photo import

- [ ] Ordered multi-select that shows each photo's position number
- [ ] Auto-crop toggle that applies `detectPageQuad` (PR #4) to each photo before review
- [ ] Unreadable images listed in a message without cancelling the good ones
- [ ] Add pages sheet (camera or photos) on an existing document; new pages land at the end and can be moved

### D1 Page review

- [ ] Large page preview with a horizontal filmstrip; tapping a thumbnail selects and centres it
- [ ] Page counter that always matches the selected page; first and last arrows disabled at the ends
- [ ] Retake, rotate, duplicate and delete in one toolbar; undo and redo in the app bar
- [ ] Ask before leaving with unsaved changes; removing the last page asks whether to discard the document

### D2 Crop precision

- [ ] Magnifier loupe above the finger while dragging a corner
- [ ] Edge handles that move a whole side
- [ ] Handles stay the same size when zoomed in
- [ ] Start from the detected page quad, with a Reset to detected button

### D3 Enhance

- [ ] Preset carousel (Original, Auto colour, Grayscale, B&W, Whiteboard) with the selected one marked by both a check and a border
- [ ] Press and hold to see the original
- [ ] Scope picker (this page, selected pages, all pages) before applying
- [ ] Brightness and contrast sliders with a reset

### D4 Markup polish

- [ ] One colour and thickness picker shared by pen, highlighter and text
- [ ] Selected tool always visible in a scrollable toolbar
- [ ] Markup available on scanned pages, reusing the PDF editor's annotation layer

### E1 Save flow

- [ ] Name field with a default name pattern (for example, Scan 2026-10-02 14.30)
- [ ] Quality options with an estimated file size each
- [ ] Progress while saving; the success message appears only after the file is fully written
- [ ] Save button disabled while saving, so repeated taps don't make duplicates

### E2 Send PDF

- [ ] Share sheet with Send PDF and Send smaller copy, showing file name and size for each
- [ ] System share sheet as the handoff; success or failure reported without touching the saved file
- [ ] Share-link option left out until there is a backend (the spec keeps link and file separate)

### F1 Settings

- [ ] Preferences: default filter, auto-crop on import, keep original images, file name pattern, theme
- [ ] Storage: space used and a Clear cache action that shows the space it frees and keeps saved PDFs
- [ ] Help, about (version) and legal links
- [ ] Each setting says whether it affects existing files

### F2 Onboarding and consent

- [ ] 3-page intro (scan, edit, share) with progress dots, Skip and Next
- [ ] Optional usage-analytics choice on its own screen; declining never blocks scanning
- [ ] Shown once and replayable from Settings; analytics choice changeable in Settings

### G1 Tools hub and merge

- [ ] Tools grid: Sign, Reorder pages, Merge PDFs; tools not yet built are hidden rather than shown disabled
- [ ] Merge picks PDFs from the library or device and shows each one's page count
- [ ] Drag to reorder sources; locked or broken files flagged before merging
- [ ] Merge result saved as a new document; originals kept

### H1 Accessibility and polish sweep

- [x] Every main screen tested at 200% font scale with no clipped labels
- [x] Screen-reader pass: names, roles and state on every control
- [x] Contrast check against WCAG AA in light and dark
- [x] Golden tests for Home, Files, Review, Crop, Enhance, Save and Settings

## Not in these PRs, and decisions needed

These spec items need a backend or an open decision first, so they are left out of the 17 PRs:

- **Sign-in, cloud sync, upload progress and share links** (US-01.2, US-01.4, US-09.3): no backend chosen yet.
- **Plans, paywall and restore purchases** (EP-10, US-10.1, US-10.2): depend on the revenue decision. A1 adds the premium badge so it can be used later.
- **OCR, text editing and search inside page text** (EP-07, part of US-02.2): no OCR engine chosen.
- **Book, ID card, business card, QR and high-speed modes** (US-03.2 to US-03.4): the native scanner doesn't offer them, so they depend on the custom-camera decision.
- **Compress, password protect and watermark** (US-08.2, US-08.4, US-08.5): need the PDF write engine from ADR-014, or they would save pages as images.
- **AI features** (US-10.5): P2 in the spec.

Decisions that change this plan:

- [ ] Is the `design/premium` v2 board the visual target for A1, or the PC prototype?
- [ ] Built-in scanner first, or a custom camera? A custom camera adds a Capture group of about 4 PRs.
- [ ] Revenue model: decides which tools get the premium badge.
- [ ] ADR-014 write engine: unlocks compress, protect and watermark as a second Tools PR.
