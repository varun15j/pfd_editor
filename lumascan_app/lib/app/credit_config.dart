// Credit rules: what a new install starts with, what scanning, importing and
// exporting cost, what sharing the app earns, and the credit packs each plan
// can buy. Edit the values here.
//
// Prices are not set here. Each pack is a consumable in-app product, priced
// in Play Console (Monetize with Play > Products > In-app products) and App
// Store Connect, and the store sends the price in the buyer's currency.
// Basic and Pro buy different products, so each can have its own rate.
// Setup steps are in docs/credits.md.
import '../domain/credits.dart';
import '../domain/plan.dart';

const creditRules = CreditRules(
  welcomeCredits: 100,
  costs: {CreditAction.scan: 5, CreditAction.importing: 5, CreditAction.exporting: 5},
  shareReward: 20,
  shareRewardsPerDay: 1,
  // PLACEHOLDER product IDs and pack sizes: waiting on Varun for the real
  // packs and prices. Gold is left out: it has unlimited credits.
  packs: {
    AppPlan.basic: [
      CreditPack(credits: 100, googlePlayId: 'credits_basic_100', appStoreId: 'lumascan.credits.basic.100'),
      CreditPack(credits: 500, googlePlayId: 'credits_basic_500', appStoreId: 'lumascan.credits.basic.500'),
    ],
    AppPlan.pro: [
      CreditPack(credits: 100, googlePlayId: 'credits_pro_100', appStoreId: 'lumascan.credits.pro.100'),
      CreditPack(credits: 500, googlePlayId: 'credits_pro_500', appStoreId: 'lumascan.credits.pro.500'),
    ],
  },
);

/// The text sent when the app is shared from Settings > Credits.
const shareAppLink = 'https://play.google.com/store/apps/details?id=com.mobi.scanner';
