# Plans: Basic, Pro and Gold

Added 2026-10-07. Code: `lib/domain/plan.dart`, `planProvider` and `planIncludesProvider` in `lib/app/preferences.dart`, the debug switch in `lib/debug/plan_switcher_tile.dart`.

## The plans

| Plan | Price | Includes |
| --- | --- | --- |
| Basic | free | everything in the app today |
| Pro | paid | Basic, plus smart scanning (below) |
| Gold | paid | everything in Pro, plus Gold features (none defined yet) |

A plan includes a feature when it is at least the feature's lowest plan (`AppPlan.includes`). So Gold always has what Pro has.

## Smart scanning (`PlanFeature.smartScan`, Pro and Gold)

- page detection by paper colour, edge contrast and the middle of the frame (`docs/auto-crop.md`)
- auto crop of every camera photo, and the preview outline as a fallback crop
- Auto crop and Full photo for many pages at once in Batch Review
- the held-page repeat check, run only when the phone has room (`docs/auto-capture-and-page-focus.md`)
- the next page taken sooner after a page turn

Basic scans the original way: white-paper detection only, the page found in each photo, and the shutter and Auto work as before.

## Which plan the app uses

- `purchasedPlan` in `lib/domain/plan.dart` is the one config variable. It is `AppPlan.basic` until billing exists; billing will replace it with the plan the store reports. Change it there to try a plan in any build.
- **Debug builds** can switch plans without buying: swipe in from the left edge to open the debug panel, then choose Real, Basic, Pro or Gold under Plan. The choice is saved on the device (`AppSettings.debugPlan`). Real follows `purchasedPlan`. Release builds ignore the choice completely.
- Code asks `ref.watch(planIncludesProvider(PlanFeature.smartScan))`; it never reads the plan name.

## Adding a feature to a plan

Add a value to `PlanFeature` with its lowest plan, and gate the code on `planIncludesProvider`. Tests set the plan with `appSettingsProvider.notifier.setDebugPlan(...)` (tests run as debug builds).
