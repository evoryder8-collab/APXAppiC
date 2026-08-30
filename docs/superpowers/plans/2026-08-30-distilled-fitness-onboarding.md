# Distilled Fitness Onboarding — Implementation Plan

**Goal:** Replace the existing first-run workout questionnaire with the approved consent-plus-seven-stage flow while preserving plan generation, safety routing, account ownership, and every existing programme-retention guarantee.

**Experience contract:** The mandatory path remains a provisional assessment designed for a sub-three-minute median. It uses no more than five observable choices per anchored question, always offers an honest uncertainty path, never exposes equations or pseudo-clinical precision, and never claims an Overall Fitness score from incomplete mobility coverage.

## Task 1 — Define the cross-platform assessment contract in red tests

- Add one shared JSON fixture covering unknown, ordinary, strong-self-report, and malformed answers.
- Add web and native tests for activity-level mapping, broad band bounds, self-report confidence caps, deterministic evidence idempotency, unsupported-answer rejection, and the rule that onboarding never emits an exact Overall Fitness score.
- Add source contracts for eight total screens, four movement domains, no more than five answers per movement question, `I haven't tested this`, `How APEX estimated this`, and an accessible starting-map summary.

## Task 2 — Implement the pure assessment model

- Add the same answer vocabulary, validation, band mapping, activity mapping, starting-map output, and immutable evidence drafts on web and native.
- Store only broad low-confidence self-report evidence with lower/upper bounds, the authored anchor identifier, protocol version, and `band_only` display precision.
- Emit no evidence for `not_tested`, no exceptional band from self-report, and no Overall Fitness result from the one-question mobility pulse.

## Task 3 — Integrate the native first-run flow

- Recompose onboarding as consent, About you, Goal, Normal week, Movement pulse, Setup, Train safely, and Starting map.
- Keep the existing body facts, goal choices, venue/equipment, frequency, plan horizon, and safety controls; consolidate them without removing their functionality.
- Add available-time selection and a four-page movement pulse. Persist the raw assessment version and answers inside account-owned induction metadata.
- Apply the bounded activity selection to a newly created standard profile and record normalized body/movement evidence through the guarded evidence RPC after ownership exists. A transient network failure must queue rather than block plan access.
- Preserve Reduce Motion, Dynamic Type, VoiceOver identifiers, keyboard navigation, plan generation, skip semantics after mandatory facts, and bespoke-programme authority boundaries.

## Task 4 — Localize, verify, and release

- Author every new full and constrained label in all offered native languages and strengthen localization coverage for the exact keys.
- Run focused parity/onboarding/evidence tests, all web and native tests, the complete UI suite, TypeScript, production web build, Xcode project validation, retention checks, and `git diff --check`.
- Install the exact signed build non-destructively on the connected iPhone/Watch pair and verify the first-run fixture on `APEX Lane · iPhone 17 Pro` only.
- Append `docs/REPAIR-NOTES.md`, commit separately, push both required refs, wait for GitHub Pages, and confirm the live URL returns HTTP 200.
