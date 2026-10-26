# In-app purchases: Pro and Gold

Added 2026-10-26. Basic is free; Pro and Gold are auto-renewing subscriptions bought in the phone's app store. Gold includes Pro. The full Play Console walkthrough (developer account, payments profile, testers) is in the project's `billing/play-billing-setup.md`.

## Where things are

| What | File |
| --- | --- |
| Product IDs, which plan each unlocks, legal links | `lib/app/store_config.dart` (the one file to edit) |
| Common interface every store implements | `PurchaseService` in `lib/domain/purchases.dart` |
| Shared plugin code (purchase stream, finishing purchases) | `lib/data/purchases/in_app_purchase_service.dart` |
| Google Play (Android) | `lib/data/purchases/google_play_purchase_service.dart` |
| App Store (iOS) | `lib/data/purchases/app_store_purchase_service.dart` |
| Plan state, buy, restore | `purchasesProvider` and `purchasedPlanProvider` in `lib/app/purchases.dart` |
| Plans screen | `lib/features/plans/paywall_screen.dart` (Settings > Plan, and Upgrade in the upgrade pop-up) |

`purchaseServiceProvider` picks Google Play on Android, the App Store on iOS, and no store elsewhere (desktop, tests). Prices are never in the app: each store sends them in the buyer's currency.

## How the plan is decided

1. At start the app shows the last plan the store reported (`settings/plan.json`), so it works offline.
2. It then asks the store which subscriptions are active (a silent restore) and switches to the best one, or Basic. A plan that expired, was cancelled and ran out, or was refunded drops away at the next start.
3. A purchase unlocks its plan when the store reports it paid. A pending payment (common with UPI) unlocks nothing until it completes, even if that happens after the app was closed.
4. Every paid purchase is finished (acknowledged). Google refunds purchases that are not acknowledged within three days.
5. Restore purchases (on the plans screen) asks again and says what it found.

The debug panel's Plan row still overrides all of this in debug builds.

There is no server check yet (Release 1 is local-first), so the app trusts what the store reports on the phone. The P1 backend should verify purchase tokens with the Google Play Developer API and App Store Server API.

## Google Play

- Products: subscription `lumascan_pro` with base plans `pro-monthly` and `pro-yearly`; subscription `lumascan_gold` with `gold-monthly` and `gold-yearly`.
- A free-trial offer on a base plan is used automatically for buyers Play says can get it, and the paywall shows "7-day free trial".
- Pro to Gold replaces the Pro subscription (`ReplacementMode.chargeProratedPrice`): Gold starts at once and unused Pro time lowers the first charge. Gold to Pro, cancelling and switching monthly/yearly are done in Play Store > Payments & subscriptions (Manage subscription on the plans screen opens it).
- Billing Library 8 comes with `in_app_purchase_android` 0.5.x (required by Play from 31 August 2026). Needs Flutter 3.44 or newer.

### Release signing

Play rejects bundles signed with the debug key. Create an upload keystore once and keep it backed up and out of git:

```
keytool -genkey -v -keystore F:\keys\lumascan-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `android/key.properties` (git-ignored):

```
storeFile=F:/keys/lumascan-upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

`android/app/build.gradle.kts` uses it for release builds when the file exists, and falls back to the debug key otherwise. Build with `flutter build appbundle --release` and upload to the internal testing track; products can only be created after Play has seen a bundle with billing in it.

### Testing

Install from the internal testing link on a phone whose Play account is a licence tester. Test cards never charge, and test subscriptions renew every few minutes. Try: buy Pro, upgrade to Gold, a pending purchase with the slow test card, cancel and wait for it to lapse, reinstall and restore, airplane mode at start.

## App Store

- App Store Connect > your app > Subscriptions: create one subscription group (for example "LumaScan Plans") with four products: `lumascan.pro.monthly`, `lumascan.pro.yearly`, `lumascan.gold.monthly`, `lumascan.gold.yearly`. Change the IDs in `store_config.dart` if you pick others.
- Rank the Gold products above the Pro products in the group, so Pro to Gold is an upgrade that starts at once with a prorated refund. Nothing extra is passed in code for it.
- Uses StoreKit 2 (the plugin's default on iOS 15+). Restore returns only current entitlements, which is how expired plans drop away. LumaScan targets iOS 16, so the StoreKit 1 fallback is not relied on.
- Sign the Paid Applications agreement and add banking and tax details in App Store Connect before products work. Test with a Sandbox account (Settings > App Store > Sandbox Account on the iPhone) or a StoreKit configuration file in Xcode.

## Before release (both stores)

- Fill in `termsUrl` and `privacyUrl` in `store_config.dart`; both stores require these links on a subscription screen.
- The plans screen already shows the price, period, automatic renewal and how to cancel.
- Gold has no Gold-only features yet, so its card lists "Everything in Pro". Add `PlanFeature` values with `AppPlan.gold` before selling Gold.
