# Profile Integrity Hotfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `standard` the fail-safe account policy, authorize bespoke nutrition and programme data only through an exact protected protocol, and stop unverified body-fat defaults from influencing energy calculations.

**Architecture:** Add an additive database policy/provenance migration, then normalize legacy clients to a conservative standard policy. Web and native resolve bespoke behavior through the same `(profile_kind, bespoke_protocol_id, persona)` triple; body fat affects lean-mass equations only when its explicit source is eligible. Existing bespoke data and historical scores remain intact.

**Tech Stack:** PostgreSQL/Supabase migrations and RLS, TypeScript/React, Swift 6.2/SwiftUI, Node test runner, XCTest, Xcode 26.

**Spec:** `docs/superpowers/specs/2026-08-30-fitness-brain-trust-architecture-design.md`

## Global Constraints

- Use only `/Users/jaxoncorrey/APXAppiC-codex-main-repair` on `codex/main-critical-repair`; do not create another worktree.
- Preserve every account-owned programme, workout, meal, hydration event, photo, legacy score, and offline outbox entry.
- `standard` is the default for database rows, missing fields, legacy caches, native decoding, web normalization, and profile recovery.
- Bespoke policy requires an exact protocol id and matching presentation persona; persona or display name alone is never authorization.
- A missing or `legacy_unverified` body-fat value cannot select a lean-mass resting-energy equation.
- Translate every new user-facing string in all offered native and web languages in the same commit, with compact forms for constrained controls.
- Use only `APEX Lane · iPhone 17 Pro` (`6907359A-18D1-46B0-87F1-13CED5CE1C46`) for Simulator work; never control BA-Studio or Finalova lanes.
- Every production-code change follows red-green-refactor. Each internal task ends with focused verification and a commit; the completed P0 project ends with the full repair note, both required pushes, Pages verification, and applicable signed-device verification.

---

### Task 1: Add the database policy and provenance boundary

**Files:**
- Create: `supabase/migrations/040_profile_integrity_policy.sql`
- Create: `tests/profile-integrity-migration.test.ts`

**Interfaces:**
- Produces: profile columns `profile_kind`, `bespoke_protocol_id`, `body_fat_source`, and `body_fat_measured_at`.
- Produces: exact protocol ids `constantine-v8.5` and `june-v8.4` for the two immutable protected owner ids already recorded in maintenance SQL.
- Preserves: the existing owner-scoped `profile` RLS policy and every existing profile row.

- [ ] **Step 1: Write the failing migration contract**

```ts
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

const sql = await readFile(
  new URL('../supabase/migrations/040_profile_integrity_policy.sql', import.meta.url),
  'utf8',
)

test('profile policy defaults to standard and body fat defaults to unknown', () => {
  assert.match(sql, /add column if not exists profile_kind text not null default 'standard'/i)
  assert.match(sql, /add column if not exists bespoke_protocol_id text/i)
  assert.match(sql, /alter column body_fat_pct drop default/i)
  assert.match(sql, /alter column body_fat_pct drop not null/i)
})

test('only immutable protected owners receive exact bespoke protocols', () => {
  assert.match(sql, /9a0fffbc-bb02-40ac-834a-d4e339b32574[\s\S]*constantine-v8\.5/i)
  assert.match(sql, /f1cc8158-0480-47c9-a2f1-bd03890182f9[\s\S]*june-v8\.4/i)
  assert.match(sql, /raise exception[\s\S]*persona/i)
  assert.doesNotMatch(sql, /where\s+persona\s+in\s*\(/i)
})

test('legacy values gain provenance without being erased', () => {
  assert.match(sql, /body_fat_source[\s\S]*legacy_unverified/i)
  assert.doesNotMatch(sql, /delete\s+from\s+(?:public\.)?profile/i)
  assert.doesNotMatch(sql, /drop\s+table/i)
})
```

- [ ] **Step 2: Run the contract and verify RED**

Run: `node --test --test-force-exit --test-isolation=none tests/profile-integrity-migration.test.ts`

Expected: FAIL because migration 040 does not exist.

- [ ] **Step 3: Add the additive, idempotent migration**

Implement these exact invariants:

```sql
alter table public.profile
  add column if not exists profile_kind text not null default 'standard',
  add column if not exists bespoke_protocol_id text,
  add column if not exists body_fat_source text,
  add column if not exists body_fat_measured_at date;

alter table public.profile alter column body_fat_pct drop default;
alter table public.profile alter column body_fat_pct drop not null;

update public.profile
set body_fat_source = 'legacy_unverified'
where body_fat_pct is not null and body_fat_source is null;
```

Use a `DO $$` block to abort when either protected UUID exists under the wrong persona, update only the exact Constantine and June UUIDs to their exact protocols, and add idempotent checks for:

```text
profile_kind in ('standard', 'bespoke')
standard => bespoke_protocol_id is null
bespoke => bespoke_protocol_id is not null
body_fat_source in ('dexa', 'bia_scale', 'calipers', 'professional_estimate', 'self_estimate', 'legacy_unverified') or null
body_fat_pct is null or between 2 and 70
```

- [ ] **Step 4: Verify GREEN and migration hygiene**

Run: `node --test --test-force-exit --test-isolation=none tests/profile-integrity-migration.test.ts`

Expected: PASS with three tests.

Run: `git diff --check`

Expected: exit 0.

- [ ] **Step 5: Commit the database contract**

```bash
git add supabase/migrations/040_profile_integrity_policy.sql tests/profile-integrity-migration.test.ts
git commit -m "fix: add fail-safe profile policy"
```

---

### Task 2: Enforce the policy in the web application

**Files:**
- Create: `src/lib/profilePolicy.ts`
- Create: `tests/profile-integrity.test.ts`
- Modify: `src/lib/types.ts`
- Modify: `src/lib/personalProtocol.ts`
- Modify: `src/lib/nutrition.ts`
- Modify: `src/lib/activity.ts`
- Modify: `src/lib/seedRepair.ts`
- Modify: `src/store/AppStore.tsx`
- Modify: `src/data/seed.ts`
- Modify: `src/data/personaSeeds.ts`
- Modify: `src/pages/Settings.tsx`
- Modify: `src/pages/Nutrition.tsx`
- Modify: `src/lib/translations.ts`
- Modify: `tests/personal-protocol.test.ts`
- Modify: `tests/seed-repair.test.ts`

**Interfaces:**
- Produces: `resolveProfilePolicy(profile): ResolvedProfilePolicy`.
- Produces: `bespokeProtocolFor(profile): 'constantine-v8.5' | 'june-v8.4' | null`.
- Produces: `bodyFatIsEnergyEligible(profile): boolean`.
- Consumes: migration 040 columns while safely defaulting legacy caches to `standard` and `legacy_unverified`.

- [ ] **Step 1: Write failing web policy regressions**

Cover these concrete behaviors with real profiles:

```ts
assert.equal(personalTargetFor({
  persona: 'constantine', profile_kind: 'standard', bespoke_protocol_id: null,
  goal: 'recomp', activity_level: 'moderate',
}), null)

assert.deepEqual(personalTargetFor({
  persona: 'constantine', profile_kind: 'bespoke', bespoke_protocol_id: 'constantine-v8.5',
  goal: 'recomp', activity_level: 'moderate',
}), { kcal: 2450, tdee: 2550, proteinG: 150, fatG: 75, carbsG: 294 })

assert.equal(personalTargetFor({
  persona: 'june', profile_kind: 'bespoke', bespoke_protocol_id: 'constantine-v8.5',
  goal: 'bulk', activity_level: 'moderate',
}), null)
```

Also assert that:

- a 45 kg standard woman and 120 kg standard man no longer resolve the same Constantine target;
- `23% + legacy_unverified` uses Mifflin-St Jeor;
- the same numeric value with `dexa`, `bia_scale`, `calipers`, or `professional_estimate` may use Katch-McArdle;
- `self_estimate` remains visible but does not select Katch-McArdle;
- standard profiles cannot run bespoke seed repair even if `persona === 'constantine'`;
- exact bespoke policy still upgrades Constantine and June definitions without rewriting history.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `node --test --test-force-exit --test-isolation=none tests/profile-integrity.test.ts tests/personal-protocol.test.ts tests/seed-repair.test.ts`

Expected: FAIL because profile policy fields and gates do not exist.

- [ ] **Step 3: Add shared policy resolution**

Implement `src/lib/profilePolicy.ts` with conservative decoding:

```ts
export type ProfileKind = 'standard' | 'bespoke'
export type BespokeProtocolID = 'constantine-v8.5' | 'june-v8.4'
export type BodyFatSource =
  | 'dexa' | 'bia_scale' | 'calipers' | 'professional_estimate'
  | 'self_estimate' | 'legacy_unverified'

export function bespokeProtocolFor(profile: ProfilePolicyInput): BespokeProtocolID | null {
  if (profile.profile_kind !== 'bespoke') return null
  if (profile.persona === 'constantine' && profile.bespoke_protocol_id === 'constantine-v8.5') return 'constantine-v8.5'
  if (profile.persona === 'june' && profile.bespoke_protocol_id === 'june-v8.4') return 'june-v8.4'
  return null
}

export function bodyFatIsEnergyEligible(profile: BodyFatPolicyInput): boolean {
  return typeof profile.body_fat_pct === 'number'
    && Number.isFinite(profile.body_fat_pct)
    && profile.body_fat_pct >= 2
    && profile.body_fat_pct <= 70
    && ['dexa', 'bia_scale', 'calipers', 'professional_estimate'].includes(profile.body_fat_source ?? '')
}
```

Extend `Profile` with nullable body fat and optional legacy-safe policy/provenance fields. Normalize missing cached policy to `standard`, clear any standard profile's protocol id, and normalize numeric body fat only when non-null.

- [ ] **Step 4: Gate targets, activity math, and seed repair**

Change `personalTargetFor` to select its table from `bespokeProtocolFor`, not `persona`. Change `computeTargets` and `activityBmr` to call `bodyFatIsEnergyEligible`. Return `bmrKatch: null` when no eligible lean-mass evidence exists and render the Katch reference only when non-null.

Make `shouldRepairSeedDefinitions` and `repairSeedDefinitions` return no repair for standard or mismatched policies. Mark authored Constantine and June seed profiles with exact bespoke policy ids; other seed profiles receive explicit policy values but no personal nutrition authorization unless a protected protocol exists.

The missing-profile upsert in `AppStore` must send:

```ts
profile_kind: 'standard',
bespoke_protocol_id: null,
body_fat_pct: null,
body_fat_source: null,
```

- [ ] **Step 5: Keep body-fat editing honest**

When a previously unknown value is adjusted in Settings, start at 20% and mark it `self_estimate`; never infer DEXA/BIA from the number. Show localized copy that a self-estimate is stored but formula selection remains conservative until a measured source is added through baseline calibration. Do not remove the existing body-fat control.

- [ ] **Step 6: Verify focused and full web suites**

Run: `node --test --test-force-exit --test-isolation=none tests/profile-integrity.test.ts tests/profile-integrity-migration.test.ts tests/personal-protocol.test.ts tests/seed-repair.test.ts`

Expected: PASS.

Run: `npm test`

Expected: all repository/web tests pass with zero failures.

Run: `npm run build`

Expected: TypeScript and the production Vite build exit 0.

- [ ] **Step 7: Commit the web enforcement**

```bash
git add src/lib/profilePolicy.ts src/lib/types.ts src/lib/personalProtocol.ts \
  src/lib/nutrition.ts src/lib/activity.ts src/lib/seedRepair.ts \
  src/store/AppStore.tsx src/data/seed.ts src/data/personaSeeds.ts \
  src/pages/Settings.tsx src/pages/Nutrition.tsx src/lib/translations.ts \
  tests/profile-integrity.test.ts tests/personal-protocol.test.ts tests/seed-repair.test.ts
git commit -m "fix: isolate standard web profiles"
```

---

### Task 3: Enforce the policy in the native application

**Files:**
- Modify: `ios/APEXNative/APEX/Core/Models/APEXModels.swift`
- Modify: `ios/APEXNative/APEX/Core/Networking/SupabaseService.swift`
- Modify: `ios/APEXNative/APEX/Core/Engine/FitnessBrainModels.swift`
- Modify: `ios/APEXNative/APEX/Core/Engine/FitnessBrainTargets.swift`
- Modify: `ios/APEXNative/APEX/Core/Engine/FitnessBrainService.swift`
- Modify: `ios/APEXNative/APEX/Features/Nutrition/EnergyEngine.swift`
- Modify: `ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift`
- Modify: `ios/APEXNative/APEX/Features/Settings/SettingsView.swift`
- Modify: `ios/APEXNative/APEXTests/EnergyEngineTests.swift`
- Modify: `ios/APEXNative/APEXTests/SupabasePayloadContractTests.swift`
- Modify: `ios/APEXNative/APEXTests/FitnessBrainParityTests.swift`
- Modify: every offered `ios/APEXNative/APEX/Resources/*.lproj/Localizable.strings`
- Modify: every offered `ios/APEXNative/APEX/Resources/*.lproj/LocalizableShort.strings` when the constrained label is introduced

**Interfaces:**
- Produces: native `ProfileKind`, `BespokeProtocolID`, and `BodyFatSource` Codable enums.
- Produces: `Profile.resolvedPolicy`, `Profile.authorizedBespokeProtocol`, and `Profile.hasEnergyEligibleBodyFat`.
- Consumes: the exact same source and protocol strings as TypeScript and migration 040.

- [ ] **Step 1: Write failing native policy tests**

Add XCTest cases proving:

```swift
XCTAssertFalse(EnergyEngine.usesPersonalProtocol(profile(
    weight: 70, persona: .constantine, profileKind: .standard,
    bespokeProtocolID: nil
)))

XCTAssertTrue(EnergyEngine.usesPersonalProtocol(profile(
    weight: 70, persona: .constantine, profileKind: .bespoke,
    bespokeProtocolID: .constantineV85
)))
```

Also prove a mismatched persona/protocol falls back to formula targets, a missing policy decodes as standard, `legacy_unverified` body fat selects Mifflin, a DEXA-sourced value selects Katch, and `ProfileCreationRequest` encodes `profile_kind=standard`, a null protocol, and no invented body-fat value.

- [ ] **Step 2: Run focused native tests and verify RED**

Run:

```bash
xcodebuild test -project ios/APEXNative/APEXNative.xcodeproj -scheme APEX \
  -destination 'platform=iOS Simulator,id=6907359A-18D1-46B0-87F1-13CED5CE1C46' \
  -only-testing:APEXTests/EnergyEngineTests \
  -only-testing:APEXTests/SupabasePayloadContractTests \
  -only-testing:APEXTests/FitnessBrainParityTests
```

Expected: FAIL on the missing policy/provenance contracts.

- [ ] **Step 3: Add conservative native decoding and creation**

Add optional decoded storage fields so old caches remain readable, with computed resolution defaulting to `.standard`. Make `bodyFatPercent` optional. `ProfileCreationRequest` explicitly encodes standard policy and never sends a body-fat value the onboarding did not collect.

Keep remote profile writes owner-scoped and preserve the existing rule that settings-backed `custom_bmr` is omitted from `RemoteProfilePayload`.

- [ ] **Step 4: Gate both native target engines**

Update `EnergyEngine.personalTargets` and `FitnessBrainTargets.computeTargets` to require the exact authorized protocol. Update `EnergyEngine.bmr` and `FitnessBrainTargets` to use lean mass only for eligible body-fat sources. Make `FBTargets.bmrKatch` optional so an unavailable reference is represented by `nil`, not a fabricated value.

Update Settings as on web: the first manual adjustment starts at 20%, records `.selfEstimate`, and shows fully localized conservative-source guidance without removing the control.

- [ ] **Step 5: Verify native GREEN, localization, and build**

Run the focused test command from Step 2.

Expected: PASS.

Run:

```bash
xcodebuild test -project ios/APEXNative/APEXNative.xcodeproj -scheme APEX \
  -destination 'platform=iOS Simulator,id=6907359A-18D1-46B0-87F1-13CED5CE1C46' \
  -only-testing:APEXTests
```

Expected: all native unit tests pass.

Run: `npm test && npm run build && git diff --check`

Expected: full web/repository tests and production build pass; no whitespace errors.

- [ ] **Step 6: Commit native parity**

```bash
git add ios/APEXNative/APEX/Core/Models/APEXModels.swift \
  ios/APEXNative/APEX/Core/Networking/SupabaseService.swift \
  ios/APEXNative/APEX/Core/Engine/FitnessBrainModels.swift \
  ios/APEXNative/APEX/Core/Engine/FitnessBrainTargets.swift \
  ios/APEXNative/APEX/Core/Engine/FitnessBrainService.swift \
  ios/APEXNative/APEX/Features/Nutrition/EnergyEngine.swift \
  ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift \
  ios/APEXNative/APEX/Features/Settings/SettingsView.swift \
  ios/APEXNative/APEXTests/EnergyEngineTests.swift \
  ios/APEXNative/APEXTests/SupabasePayloadContractTests.swift \
  ios/APEXNative/APEXTests/FitnessBrainParityTests.swift \
  ios/APEXNative/APEX/Resources/*.lproj/Localizable.strings \
  ios/APEXNative/APEX/Resources/*.lproj/LocalizableShort.strings
git commit -m "fix: isolate standard native profiles"
```

---

### Task 4: Apply, verify, document, and publish P0

**Files:**
- Modify: `docs/REPAIR-NOTES.md`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: a deployed schema, exact signed build, retained-account verification, two synchronized remote refs, and a successful Pages deployment.

- [ ] **Step 1: Apply migration 040 to the linked Supabase project**

Use the repository's authenticated Supabase workflow. Because the linked project has a known legacy migration-history mismatch, do not rewrite migration history. Execute migration 040 idempotently against project `rrzcrcjsbkmidlafrhfv`, then query only aggregate invariants:

```text
profile rows with null profile_kind = 0
standard rows with non-null bespoke_protocol_id = 0
bespoke rows with null bespoke_protocol_id = 0
known Constantine UUID resolves constantine-v8.5 when present
known June UUID resolves june-v8.4 when present
legacy numeric body-fat rows without a source = 0
```

- [ ] **Step 2: Run retention and account-isolation verification**

Verify standard fixtures never receive bespoke calories/programmes, both protected accounts retain their exact authored plans and targets, existing workout/meal/hydration histories are unchanged, and account switching cannot reuse another owner's cached policy.

- [ ] **Step 3: Build and install the exact signed app**

Build for the connected iPhone using automatic signing, install it with `xcrun devicectl`, and launch it without clearing app data. Confirm the embedded Watch app still builds. Use only the APEX Simulator lane for any UI automation.

- [ ] **Step 4: Append the repair ledger**

Record schema invariants, red-green evidence, focused/full test counts, build result, exact device result, protected-account retention, commit SHAs, and the next stage: Fitness Brain v2 semantics.

- [ ] **Step 5: Final verification and publication**

Run:

```bash
git diff --check
npm test
npm run build
git status --short --branch
```

Commit the ledger, push `HEAD:codex/main-critical-repair` and `HEAD:main`, wait for the matching GitHub Pages workflow to succeed, and verify `https://evoryder8-collab.github.io/APXAppiC/` returns HTTP 200.

Expected: clean worktree, both remote refs at the final SHA, successful Pages workflow, and live HTTP 200.

---

## Follow-on project plans

After P0 ships, create and execute one plan at a time for:

1. Fitness Brain v2 semantics.
2. Immutable evidence storage and normalization.
3. Distilled sub-three-minute onboarding.
4. Avatar **Edit** → **Calibrate my baseline** long-form sheet for standard and bespoke accounts.
5. Shadow validation, legacy presentation, claim review, and controlled activation.

The calibration entry point is an approved requirement, not optional backlog. It is sequenced after the evidence model so the questionnaire writes provenance-bearing evidence instead of another temporary settings blob.
