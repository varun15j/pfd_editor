# Scan credits

Basic and Pro spend credits to scan, import and export. Gold has unlimited
credits (`PlanFeature.unlimitedCredits`).

## Rules

All values are in `lib/app/credit_config.dart`.

| What | Credits |
| --- | --- |
| New install | +100, once |
| Each photo scanned (camera, system scanner, ID card side) | -5 |
| Each import (photos, a PDF, a file from a cloud account) | -5 per import, however many pages |
| Each export (new PDF, text PDF, JPG set, Word file) | -5 |
| Sharing the app from Settings > Credits | +20, once a day |

- 100 credits are 20 photos.
- A retake replaces a page and is free. Book mode makes two pages from one photo and costs one scan.
- Exporting the same unchanged scan again reuses the saved file and is free. A failed PDF export gives its credits back.
- An action is blocked when the balance cannot cover it, and the "Not enough credits" sheet offers packs, sharing and Gold.
  The system scanner returns several pages at once: it needs one photo's credits to open, and the balance stops at 0 if the pages cost more.

## Storage

`credits.db` (SQLite), in the app's own data:

- `credit_account`: one row, the balance and when the account was made.
- `credit_ledger`: one row per change (reason, amount, balance after, time, note, store purchase id).
  The purchase id is unique, so a purchase the store reports twice is counted once.

Settings > Credits shows the balance and the ledger.

## Buying credits

Each pack is a **consumable in-app product** (not a subscription). Basic and
Pro buy different products, so each plan has its own price:

| Plan | Google Play ID | App Store ID | Credits |
| --- | --- | --- | --- |
| Basic | `credits_basic_100` | `lumascan.credits.basic.100` | 100 |
| Basic | `credits_basic_500` | `lumascan.credits.basic.500` | 500 |
| Pro | `credits_pro_100` | `lumascan.credits.pro.100` | 100 |
| Pro | `credits_pro_500` | `lumascan.credits.pro.500` | 500 |

These IDs and pack sizes are placeholders. Create the products in Play Console
(Monetize with Play > Products > In-app products) and App Store Connect
(In-App Purchases > Consumable), set the prices there, and change the IDs in
`credit_config.dart` if they differ. Android packs are consumed as soon as they
are bought, so they can be bought again; one that was paid but not consumed is
counted at the next start.

## Limits without a server

Release 1 is local-first, so credits live only on the phone:

- Uninstalling or clearing app data starts a new account with 100 credits.
- Share rewards are based on the share sheet, not on someone installing.
  A real referral reward (credits when a friend installs with your link) needs
  a server that checks the Play Install Referrer and an account to credit.
- Bought credits are not restored on a new phone.

A small backend (account id, server-side ledger, purchase token checks with the
Google Play Developer API) fixes all three.
