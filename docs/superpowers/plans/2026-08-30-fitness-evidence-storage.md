# Fitness Evidence Storage and Normalization Implementation Plan

> **Scope:** Fitness Brain trust architecture — Project 3 only. This project adds immutable, account-owned evidence storage and deterministic source normalization. It does not expose scoring UI, replace the legacy engine, alter bespoke protocols, or change calorie targets.

## Goal

Give Fitness Brain v2 a trustworthy evidence boundary: every measurement carries its source, protocol, unit, measurement time, import time, confidence ceiling, and correction lineage. Unknown values remain unknown. A correction creates a successor instead of rewriting history.

## Hard invariants

- Evidence is owned by exactly one authenticated account and is never visible cross-account.
- Authenticated clients cannot manufacture clinical, DEXA, indirect-calorimetry, or trusted-device provenance.
- User submissions are admitted only through a constrained RPC and are normalized to low-confidence self-report or external-result evidence.
- Direct client update and delete are unavailable; corrections append a same-owner successor.
- Client retries are idempotent by `(user_id, client_idempotency_key)`.
- Metric/unit pairs and broad physiological bounds fail closed.
- Source confidence is capped at the database boundary and identically on web and native clients.
- Existing profile and HealthKit history is preserved; backfill only adds evidence.
- The v1 engine and existing snapshots remain untouched.

## Task 1: Lock the database contract with failing tests

**Files**

- Add `tests/fitness-evidence-migration.test.ts`
- Add `supabase/migrations/041_fitness_evidence.sql`

**Red assertions**

- Immutable table, owner/lineage foreign keys, object-only metadata, timestamps, source/confidence checks, metric/unit checks, and idempotency uniqueness exist.
- RLS permits owner reads but no direct authenticated insert/update/delete.
- The recording RPC derives `auth.uid()`, accepts only user-reportable sources, and never accepts a confidence argument.
- Legacy profile/settings and HealthKit-derived metrics are inserted idempotently without mutating their source tables.

**Green implementation**

- Create `fitness_evidence` with constrained enumerations and indexes.
- Add the owner-select policy and revoke direct mutations.
- Add `record_user_fitness_evidence(...)` as a locked-down `security definer` function.
- Backfill existing body-fat, custom-BMR, weight, VO2 max, and resting-heart-rate facts with conservative provenance.

## Task 2: Define one normalization contract for web and native

**Files**

- Add `ios/APEXNative/APEXTests/Fixtures/fitness-evidence-normalization.json`
- Add `src/lib/fitnessEvidence.ts`
- Add `tests/fitness-evidence-normalization.test.ts`
- Add `ios/APEXNative/APEX/Core/Engine/FitnessEvidence.swift`
- Add `ios/APEXNative/APEXTests/FitnessEvidenceTests.swift`
- Update the Xcode project to compile the implementation and copy the fixture.

**Red assertions**

- Supported source aliases normalize deterministically.
- Unsupported sources, units, ranges, malformed metadata, future measurement dates, and confidence escalation fail closed.
- Correction candidates require a same-metric predecessor and preserve account ownership.
- Web and Swift emit the same normalized summary for every shared fixture scenario.

**Green implementation**

- Add immutable evidence and submission models.
- Implement source confidence ceilings, metric/unit validation, range validation, and correction validation as pure functions.

## Task 3: Hydrate evidence read-only and expose the constrained write path

**Files**

- Update `src/lib/types.ts`
- Update `src/store/AppStore.tsx`
- Update `ios/APEXNative/APEX/Core/Models/APEXModels.swift`
- Update `ios/APEXNative/APEX/Core/Networking/SupabaseService.swift`
- Add or update focused store/network payload tests.

**Red assertions**

- Evidence is fetched only for the active account and is retained in account-scoped offline state.
- It is absent from generic mutable table unions and mutation queues.
- New user evidence calls the constrained RPC; no generic table upsert exists.
- Dashboard decoding remains backward compatible when cached evidence is absent.

**Green implementation**

- Add `fitness_evidence` to `AppData` and `DashboardData` with empty defaults.
- Fetch it separately from mutable list tables and subscribe read-only to owner-filtered changes.
- Add dedicated web/native recording methods that invoke the RPC.

## Task 4: Prove the real boundary and release

- Run focused web and native tests.
- Apply the migration twice to an isolated PostgreSQL database and prove idempotency, owner isolation, privilege denial, retry deduplication, same-owner corrections, and conservative backfill.
- Run the full web and native suites plus production builds.
- Apply migration `041` to the linked production project using the direct migration file after preflight counts; verify postflight counts and constraints.
- Re-run retention/integrity queries, append `docs/REPAIR-NOTES.md`, commit, and push both required refs.
- Confirm the GitHub Pages workflow succeeds and the live site returns HTTP 200.
