# Plans: Basic, Pro and Gold

Added 2026-10-07. Code: `lib/domain/plan.dart`, `planProvider` and `planIncludesProvider` in `lib/app/preferences.dart`, the debug switch in `lib/debug/plan_switcher_tile.dart`.

## The plans

| Plan | Price | Includes |
| --- | --- | --- |
| Basic | free | everything in the app today |
| Pro | paid | Basic, plus smart scanning and text PDF (below) |
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

## Compress to a target size (`PlanFeature.targetSize`, Pro and Gold)

The Send PDF sheet has **Fit under a size** with 200 KB, 500 KB, 1 MB and 2 MB, for upload forms such as government portals. `PdfShrinker.makeUnder` renders the saved PDF at steps of `CompressionStep.ladder` (2000 px at quality 85 down to 480 px at quality 30), measures each copy and keeps the sharpest one that fits, in at most five tries. A kilobyte counts as 1000 bytes, so the copy fits forms that count either way. A PDF already under the limit is sent as it is. When even the smallest step is too big (many pages), the sheet shows the smallest size and a second tap sends it anyway. The copy is rendered from the saved PDF, so anything burned into it (masks, signatures, drawings) stays; text in the copy cannot be selected. On Basic the option shows a Pro badge and opens the upgrade pop-up.

## Which plan the app uses

- `purchasedPlan` in `lib/domain/plan.dart` is the one config variable. It is `AppPlan.basic` until billing exists; billing will replace it with the plan the store reports. Change it there to try a plan in any build.
- **Debug builds** can switch plans without buying: swipe in from the left edge to open the debug panel, then choose Real, Basic, Pro or Gold under Plan. The choice is saved on the device (`AppSettings.debugPlan`). Real follows `purchasedPlan`. Release builds ignore the choice completely.
- Code asks `ref.watch(planIncludesProvider(PlanFeature.smartScan))`; it never reads the plan name.

## Adding a feature to a plan

Add a value to `PlanFeature` with its lowest plan, and gate the code on `planIncludesProvider`. Tests set the plan with `appSettingsProvider.notifier.setDebugPlan(...)` (tests run as debug builds).
