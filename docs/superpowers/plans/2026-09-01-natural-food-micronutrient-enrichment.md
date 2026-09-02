# Natural Food Micronutrient Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hydrate the essential generic natural-food catalogue with bounded, whole-record micronutrient evidence from approved official datasets and surface it consistently on web and native.

**Architecture:** A deterministic offline generator produces reviewed exact target-to-donor links and a bounded deployment payload. Production evidence attaches only to unchanged global curated rows, while web and native coalesce the evidence-rich server copy into the identical local provider record before duplicate removal.

**Tech Stack:** Node.js/TypeScript, Python corpus tooling, PostgreSQL/Supabase, React, Swift/SwiftUI, XCTest/Node test runner.

**Spec:** `docs/superpowers/specs/2026-09-01-natural-food-micronutrient-enrichment-design.md`

## Global Constraints

- Never commit or ship the raw 1.8 GB source bundle.
- Never invent, blend, or zero-fill missing micronutrients.
- Never overwrite private, user-created, branded-label, or historical logged-food evidence.
- Runtime evidence transfer uses exact provider and food identity, never fuzzy names.
- Preserve all existing account ownership, preparation, basis, quantity, localization, and nutrition behavior.

---

### Task 1: Lock the cross-platform enrichment contract

**Files:**
- Create: `tests/food-evidence-enrichment.test.ts`
- Create: `ios/APEXNative/APEXTests/FoodEvidenceEnrichmentTests.swift`
- Modify: `src/lib/food.ts`
- Modify: `ios/APEXNative/APEX/Core/Engine/FoodHydration.swift`

**Interfaces:**
- Produces web `enrichLocalFoodsWithNutrientEvidence(localResults, serverResults)`.
- Produces native `FoodNutrientEvidence.enrichLocalFoods(_:with:)`.

- [ ] Write red fixtures for compatible strawberry enrichment and every rejection boundary.
- [ ] Run focused web/native tests and capture the expected missing-helper failures.
- [ ] Implement exact-identity, evidence-precedence, basis/preparation/brand, and macro-fingerprint guards.
- [ ] Make web `mergeExtendedFoodResults` and native `AppSession.searchFoods` enrich before deduplication.
- [ ] Re-run the focused contract tests until green.

### Task 2: Generate reviewed official-source evidence

**Files:**
- Create: `tools/food_corpus/build_natural_food_evidence.mjs`
- Create: `tools/food_corpus/tests/natural_food_evidence.test.mjs`
- Create: `docs/food-corpus/natural-food-evidence-manifest.json`

**Interfaces:**
- Consumes staged `records.ndjson` and `nutrients.ndjson` plus `COMMON_FOODS`.
- Produces a deterministic manifest and SQL payload from approved source keys.

- [ ] Add red generator tests for code canonicalization, strict preparation and fingerprint matching, ambiguity rejection, and one-record provenance.
- [ ] Implement bounded canonical evidence projection without copying raw source bundles.
- [ ] Generate candidates for the nine natural-food categories and incorporate the two independent reviewed crosswalk reports.
- [ ] Verify every approved row has one donor, valid units/status, a source reference, and no more than 96 observations.
- [ ] Record category coverage and explicit rejection reasons in the manifest.

### Task 3: Deploy evidence without rewriting ownership or history

**Files:**
- Create: `supabase/migrations/048_natural_food_micronutrient_evidence.sql`
- Modify: `supabase/functions/food-lookup/index.ts` only if the existing complete-row response cannot preserve evidence.
- Test: `tests/food-corpus-edge-integration.test.ts`

**Interfaces:**
- Consumes the generator's reviewed provider-ID payload.
- Produces evidence-rich global curated rows returned by `search_food_catalog`.

- [ ] Add migration assertions for empty-target-only updates, exact provider/ID/fingerprint guards, and exclusion of owner, brand, barcode, and non-approved rows.
- [ ] Apply the generated payload without changing target macros or `updated_at`.
- [ ] Run the migration in a rollback transaction against production structure, then apply it idempotently through the established direct-query path.
- [ ] Verify live source counts and representative searches across all nine categories.

### Task 4: Retain evidence and verify the user flow

**Files:**
- Modify: `src/store/FoodStore.tsx`
- Modify: `ios/APEXNative/APEX/App/AppSession.swift`
- Modify: `docs/REPAIR-NOTES.md`
- Modify: `ios/APEXNative/APEX.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes the exact enriched read model from Tasks 1–3.
- Produces account-safe cached evidence and immutable future meal snapshots.

- [ ] Cache only exact compatible server copies after the active-account/generation guard succeeds.
- [ ] Prove account switching and stale searches cannot leak or overwrite evidence.
- [ ] Run complete web, native, localization, Food Memory, nutrient-pattern, persistence, and UI suites.
- [ ] Verify Strawberry, broccoli/leaf, chicken, salmon, egg, lentil, rice, and almonds display their reported Vitamins and Minerals on `APEX Lane · iPhone 17 Pro` only.
- [ ] Append source, coverage, rejection, test, deployment, and device evidence to `REPAIR-NOTES`.
- [ ] Advance the build monotonically, install and launch the signed build on the connected iPhone, commit, push both required refs, confirm GitHub Pages, and verify the live URL.
