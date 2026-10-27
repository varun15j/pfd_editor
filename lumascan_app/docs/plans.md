# Plans: Basic, Pro and Gold

Added 2026-10-07. Code: `lib/domain/plan.dart`, `planProvider` and `planIncludesProvider` in `lib/app/preferences.dart`, the debug switch in `lib/debug/plan_switcher_tile.dart`.

## The plans

| Plan | Price | Includes |
| --- | --- | --- |
| Basic | free | everything in the app today; exported PDFs carry a small "Scanned with LumaScan" mark |
| Pro | paid | Basic, plus smart scanning, text PDF, auto mask, no watermark and page numbers (below) |
| Gold | paid | everything in Pro, plus Gold features (none defined yet) |

A plan includes a feature when it is at least the feature's lowest plan (`AppPlan.includes`). So Gold always has what Pro has.

## Smart scanning (`PlanFeature.smartScan`, Pro and Gold)

- page detection by paper colour, edge contrast and the middle of the frame (`docs/auto-crop.md`)
- auto crop of every camera photo, and the preview outline as a fallback crop
- Auto crop and Full photo for many pages at once in Batch Review
- the held-page repeat check, run only when the phone has room (`docs/auto-capture-and-page-focus.md`)
- the next page taken sooner after a page turn

Basic scans the original way: white-paper detection only, the page found in each photo, and the shutter and Auto work as before.

## Text PDF (`PlanFeature.textPdf`, Pro and Gold)

OCR turns a draft, a saved document or any PDF of photos into a PDF of real text, with pictures kept as images (`docs/ocr-text-pdf.md`). On Basic the buttons are visible and open the upgrade pop-up (`ensurePlan` in `lib/ui/upgrade_dialog.dart`).

## Auto mask (`PlanFeature.autoMask`, Pro and Gold)

On-device OCR finds Aadhaar, VID, PAN, voter ID, passport and driving licence numbers on a page and hides all but their last four characters (`docs/id-masking.md`). Drawing a mask by hand is on every plan, including Basic, because hiding your own ID number is basic privacy (Varun, 2026-10-26).

## Watermark and page numbers (`PlanFeature.noWatermark`, `PlanFeature.pageNumbers`, Pro and Gold)

Decided by Varun on 2026-10-27.

- **Basic**: every scan PDF saved from the export sheet, and every ID card copy, has "Scanned with LumaScan" in small grey text at the bottom right of each page. The text is `exportWatermark` in `lib/app/app_info.dart`, built from `appName`, so renaming the app renames the mark. The export sheet says so under the quality choices.
- **Pro and Gold**: no mark. The export sheet has a **Page numbers** switch that prints "2 / 5" at the bottom centre of each page. On Basic the switch shows "Page numbers · Pro" and opens the upgrade pop-up.
- On A4 and Letter the text sits in the page margin. A page that fits its image has no margin, so the text gets a small white backing over the scan.
- Not marked: text PDFs (Pro only, so never Basic), JPG export, PDFs saved from the PDF editor, merged and compressed PDFs, and Word files. These can follow if Varun wants Basic to mark them too.

Code: `ExportOptions.watermark` and `ExportOptions.pageNumbers` in `lib/export/pdf_exporter.dart`; the sheet decides both from the plan.

## The app's name

`appName` in `lib/app/app_info.dart` is the one place the name is set. Every screen, the PDF creator field, the watermark and the Android launcher label (read by `android/app/build.gradle.kts`) follow it. iOS reads its home-screen name and camera notes from `APP_DISPLAY_NAME` in `ios/Flutter/AppName.xcconfig`; `test/app_name_test.dart` fails if that differs from `appName`, or if a screen spells the name out instead of using `appName`.

## Compress to a target size (`PlanFeature.targetSize`, Pro and Gold)

The Send PDF sheet has **Fit under a size** with 200 KB, 500 KB, 1 MB and 2 MB, for upload forms such as government portals. `PdfShrinker.makeUnder` renders the saved PDF at steps of `CompressionStep.ladder` (2000 px at quality 85 down to 480 px at quality 30), measures each copy and keeps the sharpest one that fits, in at most five tries. A kilobyte counts as 1000 bytes, so the copy fits forms that count either way. A PDF already under the limit is sent as it is. When even the smallest step is too big (many pages), the sheet shows the smallest size and a second tap sends it anyway. The copy is rendered from the saved PDF, so anything burned into it (masks, signatures, drawings) stays; text in the copy cannot be selected. On Basic the option shows a Pro badge and opens the upgrade pop-up.

## Document password (`PlanFeature.password`, Pro and Gold)

Add password (Library menu) and Send with password (Send sheet) make a copy of a saved PDF that asks for a password when opened, encrypted with AES-256 (`docs/document-password.md`). On Basic both are listed with a Pro badge and open the upgrade pop-up.

## Split PDF and extract pages (`PlanFeature.splitPdf`, Pro and Gold)

Split one PDF into several, every few pages or by typed ranges, or copy chosen pages into a new PDF (`docs/split-pdf.md`). Offered in Tools ("Split PDF") and the Library menu ("Split or extract pages"); on Basic both show Pro and open the upgrade pop-up. Merging stays on every plan.

## Which plan the app uses

- The real plan is `purchasedPlanProvider` (`lib/app/purchases.dart`): the plan the app store says this account paid for. It starts on the last plan the store reported (saved in `settings/plan.json`, Basic the first time), then asks the store at every start. Buying, restore and the store setup are in `docs/in-app-purchases.md`.
- **Debug builds** can switch plans without buying: swipe in from the left edge to open the debug panel, then choose Real, Basic, Pro or Gold under Plan. The choice is saved on the device (`AppSettings.debugPlan`). Real follows the store. Release builds ignore the choice completely.
- Code asks `ref.watch(planIncludesProvider(PlanFeature.smartScan))`; it never reads the plan name.

## Adding a feature to a plan

Add a value to `PlanFeature` with its lowest plan, and gate the code on `planIncludesProvider`. Tests set the plan with `appSettingsProvider.notifier.setDebugPlan(...)` (tests run as debug builds).
