# APEX Beta Access and StoreKit Implementation Plan

Date: 21 August 2026
Design: `docs/plans/2026-08-21-beta-access-storekit-design.md`

## Outcome

Ship a beta build in which an ordinary authenticated account cannot enter APEX until the account either redeems a one-use Supabase beta code or StoreKit verifies an active Premium subscription. Founding accounts remain unlocked. Historical trial fields are preserved in the database but ignored by the native app. Coach remains visible but disabled as Coming soon.

## 1. Stabilize the existing release candidate

Files:

- `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`
- `ios/APEXNative/APEX/Features/Nutrition/NutritionParityViews.swift`
- `ios/APEXNative/APEX/Features/Nutrition/MealComposerView.swift`
- `ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift`

Work:

1. Reproduce each of the four failing UI smoke assertions independently.
2. Add stable accessibility identifiers to product surfaces where the test currently depends on presentation details such as a navigation bar.
3. Repair selection-count semantics if the visible count is hidden by an accessibility container.
4. Make the workout smoke fixture select a real fixture day by semantic identifier rather than relying on a weekday that may not exist.
5. Re-run focused UI tests, then the whole existing unit and UI suite before beginning commercial-flow changes.

## 2. Replace trial access with an account-scoped beta gate

Tests first:

- Rewrite `ios/APEXNative/APEXTests/EntitlementTests.swift` to prove:
  - a normal account is locked even when historical trial fields exist;
  - founding access unlocks;
  - `beta_code_redeemed` unlocks only that profile;
  - verified Premium unlocks;
  - unverified or absent Premium remains locked;
  - Coach features are unavailable in this release;
  - an old cached profile still decodes without the new beta field.
- Add account-switch tests for `EntitlementStore` proving account A cannot unlock account B.

Implementation files:

- `ios/APEXNative/APEX/Core/Engine/Entitlement.swift`
- `ios/APEXNative/APEX/Core/Engine/EntitlementStore.swift`
- the `Profile` model source located by the project index
- `ios/APEXNative/APEX/App/AppSession.swift`
- `ios/APEXNative/APEX/App/AppRoute.swift`
- `ios/APEXNative/APEX/App/AppRootView.swift`
- `ios/APEXNative/APEX/Core/Networking/SupabaseService.swift`

Work:

1. Replace trial/developer-code access reasons with `founding`, `beta`, `premium`, and `locked`.
2. Decode `profile.beta_code_redeemed` as an optional value defaulting to false.
3. Remove the device-global UserDefaults unlock and local developer-code path.
4. Reset entitlement memory on sign-out and resolve it against the authenticated user identifier.
5. Stop creating trial timestamps for new native accounts.
6. Add a locked commercial route and ensure bootstrap resolves access before exposing the portal.
7. Create the minimum profile row needed for beta redemption immediately after first authentication, while retaining the induction flow after access is granted.
8. Refresh the server profile after a successful beta-code RPC before unlocking.

## 3. Add verified StoreKit 2 Premium purchasing

Tests first:

- Add a fake StoreKit gateway and tests for product loading, verified entitlement resolution, purchase success, cancellation, pending state, failed verification, restore, and transaction updates.
- Add route tests proving purchase success continues to induction or the portal and cancellation remains on the paywall.

Implementation files:

- add `ios/APEXNative/APEX/Core/Commerce/StoreKitService.swift`
- add `ios/APEXNative/APEX/Core/Commerce/StoreKitProducts.swift`
- add a local StoreKit configuration under `ios/APEXNative/Configuration/`
- update the Xcode project and APEX scheme to include the configuration for local tests
- update `ios/APEXNative/APEX/Features/Settings/PaywallView.swift`
- update `ios/APEXNative/APEX/App/AppSession.swift`

Work:

1. Define monthly and yearly Premium product identifiers.
2. Load product names and prices from StoreKit; never use hardcoded sale prices in purchase controls.
3. Accept only verified, non-revoked current entitlements.
4. Implement purchase, pending, cancellation, failure, transaction-update, and restore states.
5. Call `AppStore.sync()` only from the explicit Restore Purchases action.
6. Keep Coach disabled and ensure it cannot invoke StoreKit.

## 4. Build the manual three-page premium introduction

Tests first:

- Add route/UI tests proving a new locked account sees page one, can manually swipe or tap forward, and reaches the paywall on page three without access to the portal.
- Add Reduce Motion and compact-screen layout assertions where practical.

Implementation files:

- add `ios/APEXNative/APEX/Features/Onboarding/PremiumIntroductionView.swift`
- add reusable introduction page and artwork components in that folder
- update `AppRoute`, `AppRootView`, and `AppSession`
- add localized strings to the existing APEX localization source

Work:

1. Page one presents the connected metabolic day: meals, hydration, supplements, recovery, and training.
2. Page two presents guided strength, Orbit, Avatar, and context-aware adaptation.
3. Page three embeds the shipping paywall.
4. Use lightweight composited assets, restrained celestial motion, Reduce Motion support, and no automatic page advancement.
5. A returning locked account may enter directly on page three while retaining a way to revisit pages one and two.

## 5. Complete App Store subscription compliance

Files:

- `ios/APEXNative/APEX/Features/Settings/PaywallView.swift`
- add or update legal pages in the existing web application without changing its fitness behavior
- add App Store metadata/copy under `docs/app-store/`

Work:

1. Add visible Terms of Use and Privacy Policy links.
2. Add the auto-renew disclosure beside the purchase action.
3. Include Restore Purchases and a clear account-scoped beta redemption section.
4. Remove all trial claims from beta UI and metadata.
5. Add a Supabase migration revoking anon/authenticated execution of `rls_auto_enable()` while preserving internal event-trigger operation.

## 6. Produce launch artwork and listing copy

Files:

- source assets under `ios/APEXNative/APEX/Assets.xcassets/PremiumIntroduction/`
- App Store compositions under `docs/app-store/screenshots/`
- listing copy under `docs/app-store/listing-copy.md`

Work:

1. Generate four compositing assets with the image-generation workflow: food, runner, strength athlete, and performance silhouette.
2. Integrate optimized app-sized variants into the introduction.
3. Compose four truthful App Store screenshots from the shipping UI without showing the paywall.
4. Write polished English listing title support, subtitle options, promotional text, full description, keywords, privacy language, and review notes.

## 7. Verification and device handoff

1. Run entitlement, StoreKit, account-switch, meal, dayline, offline-queue, and UI tests individually.
2. Run the complete APEX iOS test suite from a clean build.
3. Build Release for the connected physical iPhone.
4. Install and launch the exact Release binary on the connected developer device.
5. Verify founding-account bypass, ordinary-account hard gate, beta redemption, purchase sandbox flow, restore, sign-out isolation, and Coach disabled state.
6. Record commit, build number, product IDs, test totals, and installed device identifier in the handoff.

