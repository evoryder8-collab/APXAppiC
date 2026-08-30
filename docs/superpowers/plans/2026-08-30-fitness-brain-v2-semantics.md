# Fitness Brain v2 Semantics Implementation Plan

> **Execution rule:** Complete this project as a shadow, non-presentational model before adding evidence persistence, onboarding questions, or the Avatar calibration sheet.

**Goal:** Introduce one cross-platform semantic boundary that keeps capacity, readiness, adherence, adaptation support, and health context distinct while representing missingness, confidence, coverage, freshness, and provenance honestly.

**Architecture:** Add pure TypeScript and Swift implementations driven by one JSON parity fixture. The v2 layer accepts already-normalized domain estimates; it does not infer measurements from legacy RPG points. It composes a non-clinical Overall band only when cardiorespiratory capacity, upper strength, lower strength, and at least two mobility regions meet the documented coverage gate. The shipped v1 Avatar remains unchanged while v2 runs in tests/shadow preparation.

**Safety boundary:** No v2 type authorizes a bespoke protocol, modifies nutrition targets, rewrites legacy snapshots, diagnoses health, or treats missing data as decline.

---

## Task 1: Pin the cross-platform contract red

**Files:**

- Create: `tests/fitness-brain-v2-semantics.test.ts`
- Create: `ios/APEXNative/APEXTests/FitnessBrainV2SemanticsTests.swift`
- Create: `ios/APEXNative/APEXTests/Fixtures/fitness-brain-v2-semantics.json`
- Modify: `ios/APEXNative/APEXNative.xcodeproj/project.pbxproj`

Define parity scenarios for:

1. entirely missing evidence;
2. broad structured self-report;
3. complete supported/standardized evidence;
4. one missing mobility region;
5. insufficient core-domain coverage;
6. stale evidence and confidence caps;
7. low readiness, low adherence, and safety flags leaving capacity unchanged;
8. duplicate or malformed estimates failing closed.

Run the focused web and native tests and retain the expected red result before implementation.

## Task 2: Implement web semantics

**Files:**

- Create: `src/lib/fitnessBrainV2.ts`

Implement:

- model version `2`;
- explicit capacity domains and the `apex_capacity_percentile_v2` reference scale;
- `unavailable | low | medium | high` confidence and `current | aging | stale` freshness;
- immutable evidence IDs and explanation receipts;
- fail-closed estimate validation;
- structured-self-report and legacy confidence/band-width caps;
- freshness confidence caps;
- multi-region mobility composition;
- Overall coverage threshold and non-clinical presentation band;
- separate readiness, adherence XP, adaptation support, and health context state;
- deterministic canonical ordering and no mutation of caller input.

Run the focused web contract to green.

## Task 3: Implement native semantics and parity

**Files:**

- Create: `ios/APEXNative/APEX/Core/Engine/FitnessBrainV2Semantics.swift`
- Modify: `ios/APEXNative/APEXNative.xcodeproj/project.pbxproj`

Mirror the web contract with pure `Codable`, `Sendable`, `Equatable` types and deterministic composition. Decode the shared fixture and prove exact parity for values, bounds, confidence, coverage, freshness, bands, and layer separation.

Run focused native tests on `APEX Lane · iPhone 17 Pro` only.

## Task 4: Guard legacy presentation and verify

**Files:**

- Modify: `tests/fitness-brain-v2-semantics.test.ts`
- Modify: `ios/APEXNative/APEXTests/FitnessBrainV2SemanticsTests.swift`

Add source contracts proving:

- v1 `RpgSnapshot`/`FBSnapshot` remains untouched and is not converted into v2 capacity;
- v2 has no persona, profile-policy, calorie-target, or programme-authority field;
- no missing-input fallback emits `50`;
- health context exposes flags/receipts, never a diagnosis-like score;
- adherence and adaptation cannot alter capacity estimates.

Run focused contracts, full web/native suites, production web build, and `git diff --check`.

## Task 5: Document and release

Append `docs/REPAIR-NOTES.md`, commit this project separately, push both required refs, confirm GitHub Pages, and verify the live URL. Evidence persistence is the next project; distilled onboarding and the Avatar **Edit / Calibrate my baseline** sheet remain gated until persistence and source normalization exist.
