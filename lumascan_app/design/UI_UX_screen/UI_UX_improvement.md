# UI/UX Improvement Findings

Review date: 2 October 2026  
Status: Findings documented; proposed corrections remain open.  
Scope: 52 reference screenshots, 10 epics, 38 user stories, 10 use cases, and the related LumaScan requirements and design documents.

## 1. Review conclusion

The specification covers the main scanning journey well, but needs revision before development handoff. The most important issues are conflicting release scope, ambiguity about OCR text editing, incorrect screenshot-to-story assignments, and incomplete acceptance criteria. The reference interfaces also expose opportunities to improve keyboard editing, tool discovery, save visibility, tutorials, and sharing feedback.

The screenshot gallery was checked during review: all 52 image references resolve, each image appears once in the gallery, and Screen-01 through Screen-52 retain chronological order. This confirms file integrity; the semantic mappings still need the corrections below.

This review evaluates documentation and visible screen states. Runtime performance, interaction accessibility, processing reliability, and exported PDF quality require application testing. A visible button or promotional tile demonstrates an entry point or advertised capability, not a verified successful workflow.

## 2. Source documents

- [Screenshot-derived epics, stories, features, and use cases](./PDF_App_Epics_User_Stories_Features_Use_Cases.md)
- [LumaScan product requirements](../../docs/requirements.md)
- [Screen design and interaction specification](../../docs/screen-design.md)
- [Low-level design, including OCR alignment and export behavior](../../docs/low-level-design.md)
- [LumaScan feature direction](../../LumaScan_features.md)

Source references below use section names and stable story/screen IDs so they remain useful as documents change.

## 3. Priorities and status

- **High:** Resolve before implementation planning or design handoff; the issue affects scope, architecture, data behavior, or a core task.
- **Medium:** Resolve before the affected screen or feature is accepted; the issue affects usability, traceability, or testability.
- All findings are **Open**. Priority is a review recommendation, not an approved release assignment.

| ID | Finding | Priority | Affected areas |
|---|---|---|---|
| F-01 | Product and release scope conflict across documents | High | EP-01, EP-09, EP-10 |
| F-02 | OCR recognition, transcript correction, and visible text replacement are conflated | High | EP-07, UC-05 |
| F-03 | Epic and story release priorities contradict one another | High | EP-03, EP-07, EP-08 |
| F-04 | Some screenshot-to-story assignments are incorrect | Medium | Screens 26, 28, 46, 51 |
| F-05 | Observed evidence and proposed behavior are mixed | Medium | Evidence index and acceptance criteria |
| F-06 | Stories combine separate jobs and leave feature coverage gaps | Medium | EP-03, EP-04, EP-05, EP-08, EP-10 |
| F-07 | Acceptance criteria and exception flows are incomplete | High | All epics; UC-02 through UC-10 |
| UX-01 | Keyboard editing leaves too little readable document space | High | Screens 20–21; US-07.2 |
| UX-02 | Horizontal editor tools are difficult to discover | Medium | Screens 16–17; EP-05, EP-06 |
| UX-03 | Trial promotion displaces the primary save action | High | Screens 32–33; EP-09, EP-10 |
| UX-04 | Tutorial overlays obscure task context | Medium | Screens 27, 36–37 |
| UX-05 | Saving, uploading, and sharing need distinct states | High | Screens 34–39; EP-09 |
| UX-06 | Navigation and visual-system definitions conflict | High | Feature direction, screen design, screenshot specification |
| UX-10 | App stays on the splash screen although the Flutter UI is built and idle | High | App start and resume; Android debug build on a real device |

## 4. Product, epic, and story findings

### F-01 — Product and release scope conflict

**Evidence:** The screenshot specification's MVP checklist includes sign-in, upload status, offline retry, sign-out, and account deletion. Its epic summary puts accounts and save/sync in MVP. The product requirements specify no mandatory account or backend for the initial release; cloud sync and billing are excluded from initial scope. Screen design S12 also describes no signup gate.

**Impact:** Teams can build incompatible onboarding, storage, networking, and entitlement assumptions. Competitor research can unintentionally expand the initial release.

**Recommended improvement:** Establish an authoritative product baseline and identify the screenshot document as research plus proposed backlog. Give every account, cloud, billing, and AI capability an explicit release and dependency. State whether account-free capture, editing, OCR, and export are supported.

**Completion criteria:**

- One scope table specifies local-only, account-required, network-required, and optional behavior.
- Requirements, epic summary, MVP checklist, and screen routes agree on initial-release scope.
- No core scan flow implicitly uploads content or requires authentication contrary to that scope.

### F-02 — OCR and text editing need separate contracts

**Evidence:** US-07.2 and UC-05 describe directly editing recognized regions and saving a searchable PDF or editable format. The low-level design, section 8, specifies that transcript corrections do not replace image pixels and that unaligned freeform corrections cannot silently become an aligned PDF text layer. Screen design S07 follows the transcript model.

**Impact:** Users and developers may expect visible text replacement when the implementation only changes copy/search text. Exported visible content and searchable content could disagree.

**Recommended improvement:** Separate these capabilities:

| Capability | Expected result |
|---|---|
| Recognize text | OCR results linked to the source page and revision |
| Correct a transcript | Changes copy, TXT export, and approved search text; image remains unchanged |
| Export a searchable PDF | Adds a geometrically aligned text layer under the page image |
| Add text annotations | Places new visible text over a page |
| Replace visible page text | Changes the visible document content; requires its own processing and layout specification |

**Completion criteria:** Each capability has separate acceptance criteria and release placement. The UI explains what Save changes. Crop/rotation invalidation, correction alignment, and export handling follow one documented policy.

### F-03 — Release priorities are inconsistent

**Evidence:** EP-07 is P1 in the epic summary, but basic OCR/searchable PDF is in the MVP checklist. The screenshot backlog postpones ID capture and signatures, while the product requirements include ID front/back and visual signature annotation in R1.

**Impact:** Estimation and release acceptance cannot use a consistent definition of done.

**Recommended improvement:** Assign release and priority to individual stories. Derive epic summaries and feature lists from those assignments. Separate basic OCR from advanced visible text editing and basic annotation from advanced PDF editing.

**Completion criteria:** Every planned story has one release, a priority, dependencies, and a matching screen reference. Summary tables contain no conflicting assignments.

### F-04 — Screenshot mappings need correction

The following mappings were introduced during the earlier filename assignment and require revision:

| Screen | Current assignment | What the screenshot actually shows | Recommended correction |
|---|---|---|---|
| [26](./US-04.2-Add-Pages-To-An-Existing-Document_EP-04_Screen-26.jpg) | US-04.2: Add pages to an existing document | Global create menu over the file library | Associate with a creation-menu story and link its capture/import/combine branches |
| [46](./US-01.1-Understand-The-Product_EP-01_Screen-46.jpg) | US-01.1: Understand the product before signing in | About, version, and legal information | Add a dedicated About/legal story |
| [51](./US-01.1-Understand-The-Product_EP-01_Screen-51.jpg) | US-01.1: Understand the product before signing in | Browser help center | Add a dedicated Help/support story |
| [28](./US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-28.jpg) | US-03.3; index calls it loading/transition | Almost entirely black image | Mark purpose unconfirmed; chronological proximity alone does not establish its state |

**Recommended improvement:** Keep stable Screen-NN identifiers. Maintain a many-to-many mapping table containing primary story, secondary stories, observed state, and evidence confidence. A filename represents only the primary relationship.

**Completion criteria:** Correct the assignments, index descriptions, and any affected filenames/links together. Preserve screen sequence and verify all links again. Do not invent new story IDs until the backlog has been updated.

### F-05 — Evidence and proposed requirements are mixed

**Evidence:** Screen 06 shows a Continue action and a notice that analytics preferences can be changed later; it does not show a decline option. Screens 03–04 show tool shortcuts, not completed merge, signing, or password-protection operations.

**Impact:** Readers may treat proposed acceptance criteria as observed competitor behavior or validated capabilities.

**Recommended improvement:** Label each claim as a visible control, an observed workflow/state, or a proposed requirement. Record unknown behavior explicitly. Requirements such as declining analytics can remain valid product proposals without being attributed to the screenshot.

**Completion criteria:** Each feature has an evidence classification and source. Successful processing, offline behavior, restoration, and backend behavior are not claimed solely from a button or promotional tile.

### F-06 — Story boundaries and feature coverage need refinement

**Evidence and proposed changes:**

- Split US-04.3 into QR scanning and text extraction.
- Split US-03.4 into ID capture and business-card capture.
- Split US-05.3 into page reordering and page deletion/recovery.
- Separate EP-10 responsibilities for settings/support, monetization, and AI.
- Add explicit acceptance coverage for collage, PDF page extraction, document renaming, and editable-format export.
- Give Help and About/legal dedicated stories to support Screens 46 and 51.

**Impact:** Combined stories are difficult to estimate, assign, and accept independently; some listed features have no testable delivery unit.

**Completion criteria:** Each story describes one independently verifiable user outcome. A feature-to-story matrix identifies complete coverage or explicitly deferred scope, including dependencies and release assignments.

### F-07 — Acceptance criteria and exception flows are incomplete

**Evidence:** Criteria use phrases such as “quickly,” “predictable,” and “where supported.” UC-01 includes actor, preconditions, exceptions, and postconditions; UC-02 through UC-10 mostly list successful steps. The product requirements already provide more concrete performance and capacity targets.

**Impact:** Different implementations could satisfy the prose while behaving differently in common failure and interruption states.

**Recommended improvement:** Use explicit expected outcomes and defined capability checks. Extend each use case with preconditions, success state, cancellation, partial success, failure recovery, and retained data. Reference existing measurable targets rather than creating competing ones.

**Completion criteria:**

- Capture/import define limits, invalid inputs, permission failure, and interrupted-session recovery.
- Crop and batch edits define valid geometry, operation scope, and undo behavior.
- OCR defines unavailable model/language, empty results, cancellation, and stale-result handling.
- Export defines output format, progress, cancellation, storage failure, and actual completion.
- Sharing distinguishes file preparation and handoff from delivery confirmed by another application.
- Performance targets identify reference devices, input sizes, and measurement method.

## 5. Epic-by-epic assessment

| Epic | Required refinement |
|---|---|
| EP-01 — Account/onboarding | Establish optional account behavior; separate onboarding, sign-out/deletion, and legal/help flows |
| EP-02 — Library | Add rename, trash/restore, batch actions, sort direction, and precise filter rules |
| EP-03 — Capture | Separate modes; define duplicate suppression, quality feedback, and interruption recovery |
| EP-04 — Import | Define formats, selection order, limits, and partial-import failures |
| EP-05 — Page management | Specify retake replacement, accessible reorder controls, undo scope, and last-page deletion |
| EP-06 — Enhancement | Require recoverable originals; define batch scope and distinguish image cleanup from annotation erasing |
| EP-07 — OCR | Separate recognition, transcript correction, searchable export, and visible text replacement |
| EP-08 — PDF tools | Add extraction/collage coverage; define preservation of existing text, vectors, and annotations |
| EP-09 — Save/share | Distinguish local save, export, upload, and sharing; define cancellation and conflict behavior |
| EP-10 — Settings/AI/billing | Separate ownership and define purchase, expiry, AI failure, and preference persistence states |

These are proposed changes to the specification, not findings that the current app necessarily lacks the capabilities.

## 6. Design, UI, and UX findings

### UX-01 — Preserve readable text while the keyboard is open

**Evidence:** [Screen 20](./US-07.2-Correct-Recognized-Text_EP-07_Screen-20.jpg) shows a large selected region; [Screen 21](./US-07.2-Correct-Recognized-Text_EP-07_Screen-21.jpg) shows the page dramatically reduced with the keyboard open while the promotional banner occupies substantial space.

**Impact:** The user cannot comfortably inspect the text being edited and may lose selection context.

**Recommended improvement:** Define a keyboard-specific editor layout. Preserve useful zoom and selection, bring the active region above the keyboard, and collapse secondary content. Keep formatting available without obscuring the caret or active line.

**Completion criteria:** Opening/closing the keyboard preserves selection and document position. The active line remains visible while typing, changing formatting, and using enlarged text. Verify on small screens and in landscape.

### UX-02 — Improve editor tool discovery

**Evidence:** [Screen 16](./US-06.2-Remove-Unwanted-Marks_EP-06_Screen-16.jpg) and [Screen 17](./US-05.3-Reorder-Or-Delete-Pages-Safely_EP-05_Screen-17.jpg) expose different portions of a horizontally scrolling toolbar, with truncated or partially offscreen labels.

**Impact:** Users can miss editing actions or confuse image cleanup, annotation erasing, and page operations.

**Recommended improvement:** Group actions into Page, Enhance, Text, and Annotate. Keep frequent actions visible and provide an explicitly labelled More tools entry. Use complete labels and persistent selected states.

**Completion criteria:** Every supported tool is reachable through an identifiable control. Labels remain understandable at enlarged text sizes, screen readers announce state, and destructive actions have explicit wording.

### UX-03 — Preserve a clear save path around premium features

**Evidence:** [Screen 32](./US-05.1-Correct-Page-Boundaries_EP-05_Screen-32.jpg) and [Screen 33](./US-05.2-Review-A-Multi-Page-Document_EP-05_Screen-33.jpg) present Free trial in the location used for the primary save action in earlier screens.

**Impact:** Users may be uncertain whether their captured pages are saved or whether declining a trial loses their work.

**Recommended improvement:** Keep draft/save status explicit. Define the result of cancelling a premium operation, losing entitlement, or declining an offer. Show feature restrictions before substantial effort where possible and provide a clear way to return to the retained draft.

**Completion criteria:** Cancelling a paywall preserves committed captures. The UI states which edits or export choices require entitlement and provides the allowed next action. The primary action accurately describes its outcome.

### UX-04 — Keep tutorials contextual and dismissible

**Evidence:** [Screen 27](./US-03.3-Scan-Multiple-Pages-Quickly_EP-03_Screen-27.jpg) and sharing tutorial Screens 36–37 cover substantial portions of the working screen.

**Impact:** Guidance competes with the content and can interrupt a fast capture or sharing task.

**Recommended improvement:** Use brief contextual guidance anchored to the relevant control. Define dismissal, completion persistence, and replay behavior. Pause automatic capture while a blocking tutorial prevents meaningful camera interaction.

**Completion criteria:** Users can dismiss guidance and resume the same task state. Completed tutorials do not recur unexpectedly. Focus is managed correctly while a modal tutorial is open and restored when it closes.

### UX-05 — Distinguish saving, exporting, uploading, and sharing

**Evidence:** [Screen 34](./US-09.4-Send-A-PDF-Attachment_EP-09_Screen-34.jpg) associates leaving the editor to share with cloud saving. Screen 35 shows upload progress; Screens 36–39 offer link and attachment paths.

**Impact:** Users may not know whether a document exists locally, requires an upload, is publicly accessible by link, or has actually been sent.

**Recommended improvement:** Define separate states and copy for local draft saved, export preparing, file ready, upload queued/uploading/failed, link ready, and share handoff. Explain link access before creation. Give attachment sharing a clear path consistent with the chosen offline policy.

**Completion criteria:** An upload failure does not erase a locally saved file. Sharing is enabled only for a ready artifact. Cancelling the system share sheet preserves the file. The app does not report recipient delivery without evidence from the destination.

### UX-06 — Choose one navigation and visual system

**Evidence:** Screen design section 1 specifies teal actions, warm-gray surfaces, and Library/Scan/Tools/Settings navigation. The feature direction specifies navy/cyan/violet and Home/Library/Settings with a global capture action. The screenshot specification introduces Home, Files, Create, Tools, and Account/Settings. It also specifies 44-pixel targets while existing requirements and screen design use 48 logical pixels.

**Impact:** Designers and developers can produce inconsistent screens and duplicate destinations. Accessibility acceptance can vary depending on which document is followed.

**Recommended improvement:** Select one destination model, distinguish global actions from destinations, standardize Library versus Files terminology, and establish a single semantic token source. Reconcile the touch-target requirement with the existing 48-logical-pixel baseline.

**Completion criteria:** Screen routes, navigation diagrams, component names, color tokens, spacing, typography, target sizes, and accessibility criteria agree across the specification and design documents. Define light/dark, loading, disabled, focused, selected, and error states for shared components.

### UX-10 — App stays on the splash screen after the window is recreated

**Status:** Open. Root cause analysis (RCA) done on 6 October 2026. The fix is not yet confirmed.

**Scenario (seen twice, both with the same signature):**

1. A debug build is started from Android Studio on a real phone: model CPH2661, Android 16 (API 36), Flutter 3.47.6 / Dart 3.13.5, Impeller renderer on. The branch is `claude/project-thread-d2sa4n` (Batch scan).
2. The app opens and draws its first frame normally (09:33:29 on the device).
3. The screen turns off or the app leaves the foreground (window surface released at 09:33:52).
4. The app returns to the foreground. Android creates a new `MainActivity` window in the same process (09:34:01). The phone also rotates to landscape and back (09:34:06 to 09:34:10).
5. From then on the phone shows only the launch (splash) screen, and the app never moves on to Home.

**What was checked (evidence):**

- **Process and window:** `adb shell dumpsys activity` shows `MainActivity` resumed, focused and visible. The app is running, not crashed.
- **Android side:** `adb logcat` repeats `VRI[MainActivity]: performTraversals: cancelAndRedraw ... predraw_io.flutter.embedding.android.FlutterActivityAndFragmentDelegate$2` about every 11 ms. The Flutter embedding holds back drawing the Android window until Flutter reports a frame for the new view, so the splash theme stays on screen.
- **Dart side, through the Dart VM service of the running debug session:**
  - The `main` isolate is runnable and not paused: the last pause event is `Resume`.
  - The isolate's call stack is empty. Dart is idle, not looping, blocked or stopped on an exception.
  - `ext.flutter.debugDumpApp` shows the full tree already built: `LumaScanApp`, `StartGate`, `AppShell`, `HomeScreen`.
  - `didSendFirstFrameEvent` and `didSendFirstFrameRasterizedEvent` are both `true`. The first frame was drawn for the original window only.
  - `ext.ui.window.impellerEnabled` is `true`.
- **Recovery test:** calling `ext.ui.window.scheduleFrame` once made the engine draw a frame. The predraw loop stopped at once and a screenshot showed the Home screen in the dark theme colours.
- **Not related to app code:** nothing on the start path touches the new Batch scan camera. The `StartGate` provider had already finished.

**Root cause:** after the activity and surface are recreated, the Flutter engine does not draw into the new surface on its own. Dart has nothing marked dirty, so it does not ask for a frame, and the Android embedding keeps waiting for one. The app is alive and correct, but the window never receives a frame. The trigger is the activity or surface recreation (screen off and on, plus rotation) on this device. Impeller on Android 16 is the most likely engine-side factor, but this has not been proven yet.

**Impact:** a user who locks the phone or switches apps can come back to a splash screen that never goes away. The only way out is a touch that forces a redraw, or killing the app. To the user, this looks like a hang.

**Recommended improvement:**

1. **Confirm the engine factor:** reproduce once with Impeller off (`flutter run --no-enable-impeller`, or `io.flutter.embedding.android.EnableImpeller=false` in the debug manifest). If the problem goes away, report it to Flutter with the logs above, and keep Impeller off on affected devices until there is an engine fix.
2. **Add an app-side safeguard:** when the app returns to the foreground (`AppLifecycleState.resumed`) or the view's metrics change, ask for one frame (`WidgetsBinding.instance.scheduleFrame()`). This is cheap and keeps the window from waiting forever.
3. **Decide orientation:** lock the app to portrait unless landscape is a product requirement. This removes the rotation part of the trigger.
4. **Add a regression check:** a device test that starts the app, turns the screen off and on, rotates, and checks that Home is visible within 2 seconds.

**Completion criteria:** on the CPH2661 and one other Android 14+ phone, 20 cycles of screen off/on, app switch and rotation never leave the splash screen visible for more than 2 seconds. No `predraw` loop appears in logcat after resume.

## 7. Recommended revision sequence

1. **Resolve product scope:** Choose the authoritative release baseline and settle account, offline, cloud, billing, and AI placement (F-01, F-03).
2. **Define content behavior:** Separate OCR/transcript/text replacement, PDF preservation, and save/export semantics (F-02, F-07, UX-05).
3. **Repair traceability:** Correct screenshot assignments, label evidence confidence, and add missing stories (F-04, F-05, F-06).
4. **Unify design:** Adopt one navigation model and token system, then refine keyboard, toolbar, save, and tutorial layouts (UX-01 through UX-06), and fix start and resume rendering (UX-10).
5. **Complete acceptance coverage:** Add error, empty, interrupted, cancelled, and partial-success states to each affected use case (F-07).
6. **Validate implementation:** Test real-device interactions, accessibility, processing recovery, and generated files against the reconciled criteria.

## 8. Handoff checklist

- [ ] One authoritative scope and release matrix is identified.
- [ ] Every feature maps to a story, release, dependency, and acceptance criteria.
- [ ] OCR output and visible editing behavior are explicitly separated.
- [ ] Screens 26, 28, 46, and 51 have corrected evidence descriptions and mappings.
- [ ] Proposed behavior is distinguishable from screenshot observations.
- [ ] All use cases define interruption, failure, cancellation, and retained-data behavior.
- [ ] Navigation, terminology, tokens, and target sizes are consistent.
- [ ] Keyboard editing, tool discovery, premium cancellation, and sharing states have reviewable designs.
- [ ] All 52 screenshot links still resolve after any future renaming.
- [ ] Runtime and output-quality validation results are recorded separately from visual review.
