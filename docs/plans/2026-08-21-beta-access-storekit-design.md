# APEX Beta Access, StoreKit, and Introduction Design

Date: 21 August 2026
Status: Approved for implementation

## Objective

During the private beta, APEX must not grant an automatic trial. A newly created ordinary account enters a short premium introduction and then reaches a hard paywall. The account can continue only when one of these account-scoped conditions is verified:

1. It is one of the four founding accounts.
2. It successfully redeems an unused Supabase beta code.
3. StoreKit reports an active Premium entitlement.

The Coach product remains visible as a disabled preview labelled "Coming soon" and cannot be purchased in this release.

## Access model

| Account state | APEX access | Coach purchase |
| --- | --- | --- |
| Founding account | Unlocked | Not sold yet |
| Account with `profile.beta_code_redeemed = true` | Unlocked | Not sold yet |
| Verified active StoreKit Premium subscription | Unlocked | Not sold yet |
| Existing historical trial only | Locked during beta | Not available |
| New ordinary account | Locked after the introduction | Not available |
| Expired Premium subscription without another grant | Locked | Not available |

Trial fields already present in production remain intact for forward compatibility, but they are ignored while the beta hard gate is enabled. No migration deletes historical trial data.

## Account isolation

Access is resolved for the currently authenticated Supabase user every time authentication changes. No entitlement may be stored as a device-wide boolean.

- Beta access comes only from the logged-in user's `profile.beta_code_redeemed` value.
- Founding access comes only from the logged-in user's profile.
- StoreKit access comes only from verified StoreKit transactions for the configured Premium product IDs.
- Signing out clears the in-memory access decision before another account can appear.
- Switching from an unlocked account to a locked account on the same iPhone must show the introduction or paywall immediately.
- The five family beta codes remain five independent, one-use grants for five new accounts. The four founding accounts do not consume them.

The existing Supabase `redeem_beta_code(text)` function remains the only redemption path. It atomically assigns an unused code to `auth.uid()` and updates that user's profile. The app refreshes the profile from Supabase before unlocking.

## User journey

### New ordinary signup

1. The user completes email verification/sign-in.
2. A three-page, manually swiped APEX introduction appears.
3. Pages one and two explain the connected performance system with concise, visual storytelling.
4. Page three is the paywall.
5. The user can subscribe to Premium, restore a purchase, redeem a beta code, open Terms, or open Privacy.
6. The app does not expose the portal until access is verified.
7. After access is granted, an account that still needs profile induction or consent completes those steps before entering the portal.

### Returning locked account

A returning locked account skips completed explanatory pages when appropriate and lands on the paywall. It can still revisit the introduction. It never briefly flashes the portal.

### Returning unlocked account

The app resolves access during bootstrap and proceeds to the account's correct route: induction, consent, or portal.

### Redemption

The beta-code field normalizes spaces and letter case, calls the server function, and never treats a local success flag as authority. A successful response triggers a fresh profile read. A used, invalid, or offline code leaves the account locked and shows a plain explanation without destroying the entered code.

## Introduction content

The introduction uses restrained celestial motion and composited artwork rather than embedding heavy continuously animated scenes.

1. **One connected day**: Nutrition, hydration, supplements, recovery, and training share one timeline and one metabolic picture.
2. **Training that understands context**: Guided strength work, APEX Orbit running intelligence, body signals, and adaptive decisions communicate instead of behaving like separate trackers.
3. **Choose Premium**: Monthly and yearly Premium products, disabled Coach preview, beta redemption, Restore Purchases, legal links, and subscription disclosure.

Motion must respect Reduce Motion, remain responsive on iPhone 12 through current Pro Max devices, and never delay the purchase controls.

## Premium paywall

The final page contains:

- The localized StoreKit price and billing period for monthly and yearly Premium.
- A single selected product at a time.
- A purchase button whose label reflects the selected product.
- A visible Restore Purchases action.
- A disabled Coach card labelled "Coming soon".
- A beta-code field and Redeem action at the bottom.
- Visible Terms of Use and Privacy Policy links.
- Apple's required auto-renewing subscription disclosure, including that payment is charged to the Apple ID, renewal occurs unless cancelled, and management is available in App Store account settings.
- Clear progress, success, cancellation, pending, and failure states.

The UI never displays a trial claim during the beta release.

## StoreKit authority

The native app uses StoreKit 2 and unlocks only from verified transactions. It loads product names and prices from StoreKit rather than hardcoding sale prices. Purchase and restore paths both re-evaluate `Transaction.currentEntitlements`.

Supabase subscription columns may mirror status for cross-platform presentation, but client-editable profile data is not trusted as proof of purchase. A later server-notification integration can make the web fallback subscription-aware without weakening native purchase verification. Founding and beta access already remain cross-platform because Supabase is their authority.

## Offline and failure behavior

- A previously verified StoreKit entitlement may be restored from StoreKit's signed local transaction state.
- Founding or beta access already loaded for the same authenticated account may continue through a temporary network failure, but may never transfer to another user.
- An account with no established entitlement remains locked when the network is unavailable.
- Beta redemption requires a successful server response and profile refresh.
- Purchase cancellation is not presented as an error.
- Pending purchases remain locked until StoreKit reports a verified entitlement.

## Security and privacy

- Remove the hidden, device-global developer-code unlock path.
- Never log beta codes, StoreKit transaction payloads, auth tokens, or passwords.
- Preserve RLS ownership for profiles and redemption records.
- Revoke public execution of unrelated privileged helper functions such as `rls_auto_enable()` while preserving their internal event-trigger use.
- Enable Supabase leaked-password protection before public signup if the selected auth plan supports it.

## App Store presentation

Four listing compositions will be prepared without showing the paywall:

1. Nutrition and metabolic dayline, partially integrated with premium food imagery.
2. APEX Orbit, integrated with a runner in motion.
3. Guided workout player, integrated with an athlete performing a movement.
4. Avatar and connected body intelligence, integrated with a refined human-performance silhouette.

These are marketing compositions, not fake product screens. Visible app UI remains faithful to the shipping build, and privacy-sensitive information is replaced with representative demo data.

## Acceptance criteria

1. A new non-founding account with no purchase cannot reach the portal.
2. An old `trial_started_at` value does not unlock access during beta.
3. Each founding account enters normally without consuming a beta code.
4. Each one-use beta code unlocks only its claimant account.
5. Signing out of an unlocked account and into a locked account on the same device produces a locked state.
6. A verified monthly or yearly Premium entitlement unlocks the app; unverified or expired transactions do not.
7. Restore Purchases re-evaluates current StoreKit entitlements.
8. Coach is visibly disabled and cannot trigger a purchase.
9. Terms, Privacy, and auto-renew information are visible on the paywall.
10. There is no trial wording in the beta paywall or top bar.
11. All existing meal, dayline, offline-queue, and account-isolation regression tests continue to pass.
12. The full iOS test suite passes, the release build installs on the connected iPhone, and the exact installed build is recorded before handoff.
