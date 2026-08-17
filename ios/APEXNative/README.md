# APEX Native for iOS

APEX Native is the SwiftUI counterpart to the existing APEX browser app. It is a true native client, not a `WKWebView` wrapper. The browser deployment remains the compatibility fallback, while both clients read and write the same Supabase project.

## Shared-data contract

- Authentication uses Supabase Auth.
- User-owned rows remain isolated by existing `auth.uid()` RLS policies.
- Catalog rows such as `activity_types` are shared and authenticated-read-only.
- Native mutations use the same tables, dates, field names, stable IDs, and idempotency keys as the browser client.
- Supabase Realtime refreshes changes made by the other client.
- A protected local dashboard cache and owner-scoped outbox keep logging available while offline.
- No service-role key or account password belongs in the iOS bundle.

The contract audit can be run from this directory:

```sh
node Tools/audit-client-contracts.mjs
```

## Native capabilities

- SwiftUI persona carousel and Supabase sign-in
- Advanced and low-friction Simple portal modes
- Adaptive Nutrition, activity estimation, Food Memory, barcode capture, meal/supplement/water logs
- Transition and Main training programmes, deload handling, workout logging, and SceneKit muscle hologram
- Avatar statistics and private visual-progress comparisons
- APEX Orbit route planning, MapKit navigation, recoverable live runs, GPX, debriefs, private route history, shoes, segments, posters, and adaptive marathon campaigns
- HealthKit import/export for authorized activity, workouts, water, and recovery signals
- English, Romanian, and Thai localization
- Accessibility-aware motion and native Dynamic Type-friendly layouts
- App privacy manifest and explicit Health, location, camera, and photo-library purpose strings

## Local configuration

1. Install XcodeGen if needed.
2. Run `npm ci` in this directory to install the localization-audit parser.
3. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig`.
4. Add the production Supabase URL and publishable/anonymous key. Never add a service-role key.
5. Generate the project:

```sh
xcodegen generate
```

6. Open `APEXNative.xcodeproj` and select the `APEX` scheme.

`Config/Secrets.xcconfig`, build products, Derived Data, and user-specific Xcode state are ignored by Git.

## Signing and HealthKit

The production target uses bundle identifier `ch.apexperformance.APEX`, Apple team `UG979XDY72`, and the HealthKit/background-delivery entitlements in `APEX/APEX.entitlements`.

For a normal device or App Store build, sign into the corresponding Apple Developer account in Xcode Settings, enable HealthKit for the explicit App ID, and let Xcode create a matching provisioning profile. A wildcard development profile cannot carry HealthKit.

## Verification

Generate localizations before testing:

```sh
node Tools/generate-localizations.mjs
node Tools/audit-localizations.mjs
node Tools/audit-runtime-content.mjs
node Tools/audit-runtime-swift-content.mjs
```

Run unit and UI tests from Xcode or with:

```sh
xcodebuild -project APEXNative.xcodeproj -scheme APEX \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

The UI-test fixture exists only in Debug builds and never signs in or touches production data.
