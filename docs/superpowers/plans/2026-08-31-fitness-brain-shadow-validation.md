# Fitness Brain v2 Project 6 — Shadow Validation and Transition Plan

**Goal:** Run Fitness Brain v2 beside the shipped v1 engine, collect only privacy-bounded validation facts, prove the scientific separation invariants continuously, and keep v1 presentation locked until explicit scientific, privacy, claim, subgroup, and owner review gates pass.

**Non-goals:** This project does not replace any visible Avatar score, infer physiology from legacy game points, upload raw HealthKit values or evidence identifiers to analytics, activate v2 automatically, or alter bespoke programme/nutrition authority.

## Task 1 — Shared shadow-observation contract

1. Add a shared JSON fixture covering standard and bespoke accounts, absent evidence, conservative self-report, conflicting evidence, rejected domains, and invariant probes.
2. Add failing web and native parity tests before implementation.
3. Implement native/web composers that:
   - admit only current, account-owned, non-superseded evidence on the declared v2 reference scale;
   - map only metrics that validly represent a v2 domain;
   - leave general flexibility and unsupported raw measurements unavailable instead of inventing anatomical mobility estimates;
   - run readiness, adherence, adaptation, and missing-data counterfactuals to detect cross-domain leakage;
   - emit only bucketed legacy/v2 disagreement, coverage, confidence, source-count, issue-code, and invariant-code facts;
   - exclude user IDs, raw measurements, evidence/receipt IDs, names, dates of birth, workout names, and HealthKit payloads from the observation body.

## Task 2 — Privacy-safe persistence

1. Add an additive migration for owner-scoped daily shadow observations with one idempotent row per account/platform/day/model version.
2. Constrain every bucket, issue code, source-count object, platform, version, and demographic cohort at the database boundary.
3. Permit authenticated writes only through a security-definer RPC that derives `user_id` from `auth.uid()`; allow owners to read their own row and deny direct mutation.
4. Add a service-role-only aggregate review view grouped by coarse age band, sex group, profile kind, platform, confidence, coverage, and disagreement.
5. Add static migration contracts and repeatable PostgreSQL integration coverage for RLS, idempotency, malformed/private payload rejection, account isolation, and non-destructive reruns.

## Task 3 — Dual-run integration with legacy presentation locked

1. Run the shadow composer after each deterministic v1 replay on native and web.
2. Queue the daily RPC through the existing durable, account-scoped offline outbox; suppress unchanged duplicate writes and cancel work across account-generation changes.
3. Keep `rpg_snapshots` and every visible Avatar consumer on model v1. Add architecture tests that fail if Avatar imports or renders the shadow state.
4. Do not surface shadow disagreements to users yet; this stage measures the model, not the person.

## Task 4 — Controlled activation and claim audit

1. Add a deterministic rollout gate that remains `shadow_only` unless minimum sample, subgroup, coverage, outlier, invariant, scientific-review, privacy-review, claim-review, and explicit owner-approval requirements all pass.
2. Require zero impossible cross-domain invariant violations. Statistical thresholds are operational rollout safeguards, not proof of physiological validity.
3. Add a claim ledger defining approved language (training estimate, confidence, coverage, provenance, uncertainty) and prohibited language (clinical diagnosis, injury prediction, guaranteed accuracy, or scientifically proven exact scores).
4. Add source scans that prevent prohibited claims from entering production UI/marketing surfaces.

## Task 5 — Integrated release gate

1. Run focused fixture, migration, persistence, privacy, claim, rollout, account-switching, and v1-retention tests.
2. Run full web, native unit, native UI, localization, production-build, and retention suites on `APEX Lane · iPhone 17 Pro` only.
3. Apply the additive migration to production only after isolated PostgreSQL execution passes twice; verify catalog, grants, policies, and zero loss of account-owned rows.
4. Build/install/launch the exact signed build on `iConstantine Main`; do not deploy the unchanged Watch companion separately.
5. Append `docs/REPAIR-NOTES.md`, commit Project 6 separately, push both required refs, confirm the exact GitHub Pages run, and verify the live URL.
