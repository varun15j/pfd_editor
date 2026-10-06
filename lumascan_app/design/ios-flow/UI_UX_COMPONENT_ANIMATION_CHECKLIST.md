# LumaScan clickable wireframe — UI component and animation checklist

Review date: 5 October 2026  
Prototype: [prototype.html](./prototype.html)  
Flow board: [index.html](./index.html)  
Master SVG: [lumascan-batch-edit-flow.svg](../UI_UX_screen/lumascan-batch-edit-flow.svg)

## Status legend

| Mark | Meaning |
|---|---|
| ✅ Covered | Present and interactive in the clickable wireframe |
| 🟡 Partial | Represented, but intentionally simulated or missing production-level behavior |
| ⬜ Missing | Not represented in this wireframe yet |

## 1. Global prototype shell

| Component or behavior | Status | Verification |
|---|---|---|
| iPhone device frame, status bar, Dynamic Island and home indicator | ✅ Covered | Visible around every screen |
| Left screen navigator | ✅ Covered | Opens any of the eight screens |
| Previous and Next controls | ✅ Covered | Navigate the primary flow and disable at its ends |
| Keyboard navigation | ✅ Covered | Left/Right arrows move through screens; Escape closes camera settings |
| Touch and pointer swipe navigation | ✅ Covered | Horizontal swipe across the phone changes screens |
| Restart prototype | ✅ Covered | Restores initial selection, camera, filter and export state |
| Hotspot inspection | ✅ Covered | Show Hotspots outlines interactive controls |
| Interaction notes and last-action log | ✅ Covered | Inspector updates after actions |
| Forward and backward screen animation | ✅ Covered | Direction-aware slide/fade transition |
| Button press feedback | ✅ Covered | Active controls scale briefly |
| Reduced-motion support | ✅ Covered | `prefers-reduced-motion` shortens animation and transition duration |
| Browser history/deep-link routing | ⬜ Missing | Prototype state is in memory; screen IDs are not URL routes |
| Persistent state after browser reload | ⬜ Missing | Restart/reload intentionally resets the wireframe |

## 2. Screen 01 — Library

| Component, button or list | Status | Animation / behavior coverage |
|---|---|---|
| Greeting and document-library title | ✅ Covered | Static heading |
| New scan primary card | ✅ Covered | Opens Camera Preview with screen transition |
| Import quick action | 🟡 Partial | Opens camera as a flow placeholder; no system picker |
| ID copy quick action | 🟡 Partial | Opens camera; camera mode can then be changed to ID card |
| Video quick action | 🟡 Partial | Opens camera placeholder; no video workflow |
| Recent-document list rows | ✅ Covered | Rows include SVG thumbnail, title, metadata and open selection flow |
| Row press state | ✅ Covered | Shared button press animation |
| List scrolling | 🟡 Partial | Component exists; sample content does not exceed the screen height |
| Empty, loading and error list states | ⬜ Missing | Covered in specifications, not this focused flow |
| Search, sort and library filters | ⬜ Missing | Outside the batch-scan journey represented here |

## 3. Screen 02 — Camera preview

| Component, button or state | Status | Animation / behavior coverage |
|---|---|---|
| SVG camera/document preview | ✅ Covered | Embedded SVG; brightness responds to Flashlight |
| Close camera | ✅ Covered | Returns to Library |
| Guidance chip | ✅ Covered | Changes between stability and manual-shutter guidance |
| Camera settings button | ✅ Covered | Opens animated iOS-style bottom sheet |
| Batch mode quick control | ✅ Covered | Synchronized on/off state; hides/shows page count |
| Flashlight quick control | ✅ Covered | Synchronized state and preview brightness change |
| Auto capture quick control | ✅ Covered | Synchronized state and guidance change |
| Alignment grid setting | ✅ Covered | Adds/removes animated-state 3 × 3 overlay |
| Settings-sheet synchronized switches | ✅ Covered | Batch, Flash, Auto and Grid stay synchronized with preview |
| Settings sheet close button, backdrop and Escape | ✅ Covered | Each dismisses the sheet without clearing values |
| Docs / Book / Text / OCR Doc / QR / Photo selector | ✅ Covered | Horizontally scrollable selector; selected mode changes guidance, overlay and shutter behavior |
| Docs mode | ✅ Covered | Default document preview and page capture |
| Book mode | ✅ Covered | Left/right regions, center-spine guide and two-page capture feedback |
| Text mode | ✅ Covered | Animated live-text region highlights and text-capture feedback |
| OCR Doc mode | ✅ Covered | Searchable-text-layer indicator and accuracy-OCR capture feedback |
| QR mode | ✅ Covered | QR reticle, detected state and safe payload feedback |
| Photo mode | ✅ Covered | Photo-specific guidance without document-mode labeling |
| Capture thumbnail and count badge | ✅ Covered | The entire page icon, image and count badge form one touch target; tapping anywhere opens Captured photos |
| Captured photos preview sheet | ✅ Covered | Shows all scanned-page thumbnails, page numbers, Close, Continue scanning and Review all actions |
| Shutter button | ✅ Covered | Press animation, white capture flash and incrementing count |
| Bottom-right destructive cross | ✅ Covered | Replaces Back/Done and opens confirmation; accessible label states that all captured photos and changes will be discarded |
| Irreversible-discard confirmation | ✅ Covered | Dialog asks “Discard the photos?”, explains that photos cannot be restored, and offers Discard photos / Keep photos |
| Confirmed discard behavior | ✅ Covered | Clears page count, page selection and capture state, then returns to Library with feedback |
| Cancelled discard behavior | ✅ Covered | Closes the dialog and keeps all photos and settings intact |
| More capture settings | 🟡 Partial | Produces in-phone feedback; no secondary settings screen |
| Unsupported flashlight/lens state | ⬜ Missing | Requirement documented; hardware simulation not included |
| Auto-capture countdown/stability ring | ⬜ Missing | Auto behavior is represented by state and guidance only |
| Book manual spine adjustment | ⬜ Missing | Guide and paired capture are shown; manual drag correction belongs in review |
| Text region tap/copy sheet | 🟡 Partial | Detection highlights and capture feedback are shown; region action sheet is specified but not rendered |
| OCR progress/review screen | 🟡 Partial | Mode and capture state are shown; full OCR review remains the existing OCR screen specification |
| QR payload confirmation sheet | 🟡 Partial | Reticle and result feedback are shown; typed payload action sheet is specified but not rendered |
| Camera permission, denied and low-light states | ⬜ Missing | Specified elsewhere; not part of this happy-path prototype |

## 4. Screen 03 — Page selection

| Component, button or list | Status | Animation / behavior coverage |
|---|---|---|
| Selection-count navigation title | ✅ Covered | Updates after each page tap |
| Back/Cancel navigation | ✅ Covered | Returns through prototype history |
| Select All / Clear All | ✅ Covered | Toggles all six sample pages |
| Two-column page grid | ✅ Covered | Six SVG page thumbnails |
| Individual page selection | ✅ Covered | Check badge, border and selection pulse |
| Empty-selection state | ✅ Covered | Batch toolbar becomes disabled |
| Enhance action | ✅ Covered | Opens matching contextual action sheet |
| Rotate action | ✅ Covered | Opens rotate sheet; actions show Undo feedback |
| Organize action | ✅ Covered | Opens organize sheet and routes to organizer |
| More action | ✅ Covered | Opens OCR/export/details choices with feedback |
| Grid scrolling | ✅ Covered | Page area extends beneath the fixed toolbar and can scroll |
| Long-press range selection | ⬜ Missing | Tap selection only |
| Drag-selection across thumbnails | ⬜ Missing | Not required for the current mobile flow |

## 5. Screen 04 — Batch action sheet

| Component or behavior | Status | Animation / behavior coverage |
|---|---|---|
| Dimmed page context behind sheet | ✅ Covered | Background remains visible |
| Bottom-sheet entrance animation | ✅ Covered | Sheet slides upward with backdrop fade |
| Selected-page count | ✅ Covered | Uses live selection count |
| Enhance choices | ✅ Covered | Route to Enhance screen |
| Rotate choices | ✅ Covered | Left/right/crop choices provide action feedback and Undo |
| Organize choices | ✅ Covered | Route to Organize screen |
| More choices | 🟡 Partial | OCR, export and details are represented by feedback only |
| Close and Cancel | ✅ Covered | Return to previous screen |
| Drag-to-dismiss sheet gesture | ⬜ Missing | Sheet uses buttons/backdrop rather than draggable physics |

## 6. Screen 05 — Crop & resize

| Component or behavior | Status | Animation / behavior coverage |
|---|---|---|
| Draft and saved-document entry | ✅ Covered | Library provides Continue draft and editable saved cards |
| Persistent Crop and Filter actions | ✅ Covered | Both remain visible in the document editor toolbar |
| Reopen current crop | ✅ Covered | Crop screen displays the latest crop state |
| Detected edges and Full image | ✅ Covered | Both presets change the crop quad |
| Crop-area resizing | ✅ Covered | Slider updates crop geometry and percentage live |
| Four corner handles | ✅ Covered | Visible touch handles represent manual corner adjustment |
| Rotate and reset | ✅ Covered | Rotate gives feedback; Reset restores detected edges |
| Save recipe revision | ✅ Covered | Returns to editor with original-retained confirmation |
| Direct corner dragging | 🟡 Partial | Handles are represented; the wireframe uses a slider for deterministic resizing |
| Magnifier loupe | ⬜ Missing | Planned for native precision interaction |

## 7. Screen 06 — Filters

| Component or behavior | Status | Animation / behavior coverage |
|---|---|---|
| Before/after preview and compare divider | ✅ Covered | Visual compare composition is present |
| Original, Auto Color, Enhanced Color, Bright, Grayscale and B&W | ✅ Covered | Selected state and browser preview treatment update live |
| Effect thumbnail on every filter tile | ✅ Covered | Each tile previews the current document with its own visual treatment |
| Deferred thumbnail loading | ✅ Covered | Prototype images use native lazy loading and async decoding; product requirement adds post-preview scheduling and caching |
| Strength slider | ✅ Covered | Percentage updates continuously |
| Save filter revision | ✅ Covered | Scope uses selected-page count and returns to the editor |
| Reset filter independently | ✅ Covered | Returns to Original without changing crop |
| Draft/saved re-entry | ✅ Covered | Status note confirms both document states remain editable |
| Back navigation | ✅ Covered | Returns through history |
| Actual image-filter rendering | 🟡 Partial | Filter state changes, but the embedded SVG pixels are not processed |
| Draggable compare divider | ⬜ Missing | Divider is static in this wireframe |
| Press-and-hold original | ⬜ Missing | Compare representation is used instead |

## 8. Screen 07 — Organize

| Component, button or list | Status | Animation / behavior coverage |
|---|---|---|
| Vertical page list | ✅ Covered | Four rows with SVG thumbnails and drag affordances |
| Page-row selection | ✅ Covered | Selected row updates on tap |
| Duplicate selected page | ✅ Covered | Shows in-device confirmation and Undo action |
| Move selected page to end | ✅ Covered | Shows in-device confirmation and Undo action |
| Delete selected page | ✅ Covered | Opens destructive confirmation modal |
| Confirm and cancel deletion | ✅ Covered | Both paths are interactive |
| Timed Undo feedback | 🟡 Partial | Undo button is present for 4.2 seconds; data model is illustrative |
| Save page order | ✅ Covered | Advances to Export |
| Real drag-and-drop reordering | ⬜ Missing | Drag handle is visual; Move action is the accessible fallback |
| Animated row relocation | ⬜ Missing | Requires real list-order mutation first |

## 9. Screen 08 — Export

| Component or behavior | Status | Animation / behavior coverage |
|---|---|---|
| PDF, JPG and PNG format cards | ✅ Covered | Selected state and output filename update |
| Small, Recommended and Best quality rows | ✅ Covered | Radio-style selection and size estimate update |
| Searchable-text/OCR switch | ✅ Covered | Real toggle with semantic pressed state |
| Filename and estimated-size summary | ✅ Covered | Updates from format and quality selection |
| Export button | ✅ Covered | Starts animated processing state |
| Save progress | ✅ Covered | Animated circular progress from 0–100% |
| Cancel export | ✅ Covered | Returns safely to Export configuration |
| Failure/retry state | ⬜ Missing | Current animation demonstrates success and cancellation |
| Storage warning state | ⬜ Missing | Documented requirement, not simulated here |

## 10. Screen 09 — Completion

| Component or behavior | Status | Animation / behavior coverage |
|---|---|---|
| SVG success illustration | ✅ Covered | Appears after progress reaches 100% |
| Actual format, page count and file size | ✅ Covered | Derived from prototype selections |
| Share button | 🟡 Partial | Shows in-device feedback; system share sheet is not invoked |
| Save to Files button | 🟡 Partial | Shows in-device confirmation; no file is written |
| Back to Library | ✅ Covered | Returns to the first screen |
| Success transition | ✅ Covered | Processing state changes to completion after 100% |
| Share-sheet animation | ⬜ Missing | Requires either a simulated share sheet or native integration |

## 10. Cross-screen animation coverage

| Animation or feedback pattern | Status | Screens |
|---|---|---|
| Directional screen transition | ✅ Covered | All eight screens |
| Button press/touch feedback | ✅ Covered | All interactive controls |
| Bottom-sheet entrance and backdrop fade | ✅ Covered | Camera settings, batch actions |
| Toggle transition | ✅ Covered | Camera settings, OCR |
| Selection pulse | ✅ Covered | Page selection |
| Camera shutter compression and white flash | ✅ Covered | Camera preview |
| Live capture-count update | ✅ Covered | Camera preview |
| Modal confirmation | ✅ Covered | Delete page |
| Snackbar/toast entrance and timed dismissal | ✅ Covered | Rotate, organize, share, save and placeholder actions |
| Undo affordance | ✅ Covered | Rotate and organize feedback |
| Slider live feedback | ✅ Covered | Enhance strength |
| Progress animation | ✅ Covered | Export |
| Success-state reveal | ✅ Covered | Completion |
| Drag-and-drop list physics | ⬜ Missing | Organize |
| Draggable before/after comparison | ⬜ Missing | Enhance |
| Drag-to-dismiss bottom sheet | ⬜ Missing | Batch action and camera settings sheets |
| Error shake/retry animation | ⬜ Missing | Export/camera error states |
| Skeleton/loading animation | ⬜ Missing | Library and page loading states |

## 11. Review result

The wireframe covers the complete happy path and the principal touch feedback: navigation, camera toggles, capture, page selection, action sheets, enhancement controls, safe deletion, export progress, cancellation and success. It is suitable for interaction review and development handoff.

The remaining gaps are advanced gesture physics and exception-state demonstrations rather than blockers for reviewing the main flow. Recommended next additions, in order:

1. Real drag-and-drop page reordering with animated row movement and keyboard/screen-reader alternatives.
2. Draggable before/after comparison divider.
3. Export failure/retry and low-storage states.
4. Camera permission-denied, unsupported-flash and low-light states.
5. Simulated iOS share sheet and secondary camera-settings page.
6. Library empty/loading/error states and skeleton animation.

## 12. Verification checklist

- [x] Eight declared screens have render functions.
- [x] All primary flow navigation targets resolve.
- [x] All linked HTML, CSS, JavaScript and SVG assets exist.
- [x] JavaScript passes syntax validation.
- [x] Stylesheets have balanced blocks.
- [x] Camera quick controls and settings controls stay synchronized.
- [x] Empty selection disables batch actions.
- [x] Export supports progress, cancellation and completion.
- [x] Reduced-motion preference is handled.
- [ ] Visual regression screenshots are automated.
- [ ] Production camera, image processing, file writing and native sharing are connected; this remains a design wireframe.
