# Web / Apple Client Parity Matrix

This is the human index for roadmap item 2.5. The versioned, machine-checked source of truth is
[`PARITY-MATRIX.json`](./PARITY-MATRIX.json); it records every comparison dimension, the production
source on both clients, and executable behavioral evidence. Screenshots are deliberately not accepted
as parity evidence.

## Decision rules

- `shared` means the user-visible rule and persisted contract agree on web and Apple clients.
- `platform_specific` means the platforms intentionally use different presentation or operating-system
  integration while preserving the same domain result.
- `not_applicable` is permitted only with a written reason and evidence.
- Every area must resolve every dimension: behavior, calculations, database reads, database writes,
  ownership/RLS, offline behavior, error behavior, localization, and date/timezone handling.
- An area is complete only when its web test, Apple test, and production implementations all exist.

## Resolved areas

| Area | Resolution | Intentional platform boundary |
| --- | --- | --- |
| Authentication and identity | Matched | Browser session storage and Apple secure session storage differ; refreshed Supabase identity, ownership, bounded replay, quarantine, and sign-out isolation do not. |
| Nine offered languages | Matched | Each client renders through its own UI framework; locale selection, fallback rules, interpolation contracts, and offered-language set are shared. |
| Simple / Advanced modes | Matched | DOM routing and SwiftUI navigation differ; the stored mode and the information each mode exposes are equivalent. |
| Date and training calendar operations | Matched | Native and browser date pickers differ; copy, clear, paste, fresh IDs, local-day ownership, and timezone boundaries are shared. |
| Nutrition glance and target modal | Matched | Presentation differs by framework; macro totals, targets, units, and date selection use the same rules. |
| Activity estimator | Matched | Control layout differs; Quick and Precise paths feed one activity result and imported activity is never counted twice. |
| Meal composer and Food Memory | Matched | Keyboard/focus mechanics are platform-specific; search, recalled amounts, nutrition math, ownership, and persisted meal shapes agree. |
| Hydration | Matched | The silhouette and controls are native/browser renderings; goal math, event ordering, preset identity, history, and offline replay agree. |
| Supplements | Matched | Swipe/context affordances differ; active-stack membership, daily completion, ownership, and log payloads agree. |
| Recovery and wearables | Matched | Apple Health is an Apple-only source and browser entry is manual; normalized records, recovery interpretation, and no-double-count rules agree. |
| Avatar | Matched | Rendering technology differs; snapshot selection, body-state calculations, dates, and user ownership agree. |
| Orbit | Matched | Background location and permission surfaces are operating-system-specific; campaign state, run recovery, distance, and ownership agree. |
| Settings | Matched | Native controls and web form controls differ; units, appearance, modes, add-ons, account scope, and persisted settings agree. |

## Executable gates

```sh
node --test tests/client-behaviour-matrix.test.ts
node ios/APEXNative/Tools/audit-client-contracts.mjs
```

The first gate rejects missing areas or dimensions, unresolved verdicts, missing source/test evidence,
and screenshot-only claims. The second audits the shared Supabase table/mutation contract, idempotent
migrations, ownership policies, activity-catalog immutability, and the narrow allowlist for bundled
Apple web renderers.
