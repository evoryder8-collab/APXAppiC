# Fitness Brain Trust Architecture Design

Date: 2026-08-30
Status: owner-approved; implementation planning in progress
Audit: `docs/superpowers/audits/2026-08-30-apex-fitness-brain-scientific-audit.md`
Evidence ledger: `docs/superpowers/audits/report-source.md`

## Purpose

Rebuild APEX's cross-domain Fitness Brain so that the gamified experience remains enjoyable while every physiological-looking result is traceable, carries an explicit confidence or coverage state, and is derived only from evidence that can validly represent it.

The implementation must protect the product's central promise: training, nutrition, hydration, recovery, sleep, body measurements, and wearable activity can inform one coherent experience without pretending that every input directly changes every physical capacity.

## Non-negotiable principles

1. **No invented measurements.** Unknown body fat, resting energy, VO2, sleep, HRV, load, water, pain, or performance remains unknown.
2. **No bespoke identity leakage.** Ordinary subscribers can never inherit Constantine, June, Matthew, or Iulian protocols through a schema default, cache fallback, decoder fallback, or seed repair.
3. **No false precision.** A low-confidence estimate is a range with a confidence label, not an exact integer presented as fact.
4. **No missing-data punishment.** Missing, denied, stale, offline, or unlogged data lowers coverage and confidence; it does not manufacture physiological decline.
5. **Constructs stay separate.** Capacity, readiness, adherence, health context, and game progression are distinct state layers.
6. **Cross-domain effects are bounded and explainable.** Nutrition, hydration, and recovery can influence readiness, recommendations, and adaptation confidence; they cannot instantly create strength, endurance, flexibility, or joint-health points.
7. **Raw evidence survives.** Every estimate retains source, time, protocol, units, freshness, confidence, and the receipts that explain it.
8. **Gamification remains honest.** XP rewards useful actions and consistency. Fitness estimates describe supported capacity. The UI never labels XP as measured physiology.
9. **Existing account data is preserved.** Legacy snapshots, programmes, workout history, nutrition history, hydration, photos, and bespoke protocols remain account-owned and recoverable.
10. **Parity is mandatory.** Native and web use the same model version, invariants, fixtures, reference tables, and source-quality rules.

## Onboarding experience constraint

Scientific quality must not turn signup into an examination.

### Mandatory path

- Target median completion: **three minutes or less**, excluding authentication, legal reading, and optional Health permission dialogs.
- Target 90th percentile completion: **five minutes or less**.
- One clear decision per screen or compact card; no dense clinical forms.
- A maximum of five visible choices for any anchored question.
- Every question offers **“Not sure”** or **“I haven't tested this”** when uncertainty is legitimate.
- Questions use enjoyable, everyday language. Scientific terminology appears only in optional explanations.
- No appearance-based, shaming, or identity-based wording such as “chicken legs.”
- No initial exact score where the evidence supports only a broad band.
- Reduce Motion, Dynamic Type, VoiceOver, Switch Control, localization, and authored compact labels are part of the same implementation.

### Progressive disclosure

The default signup creates a safe provisional baseline. After the person reaches the app, APEX offers a non-blocking **Calibrate my baseline** journey that can be completed now, later, or in several short visits.

The optional journey can import measurements or guide field tests. It must never delay plan access, invalidate a skipped answer, or imply failure when the person chooses not to test.

The Avatar places a compact **Edit** control directly above the Stats lanes. It has a minimum 44-point touch target and the accessibility label **Calibrate my baseline**. Activating it presents the resumable long-form calibration in a sheet or adaptive popup without navigating away from the Avatar. The same entry point and evidence rules apply to standard and bespoke accounts; calibration may refine physiological estimates but cannot replace or authorize a bespoke programme or nutrition protocol.

## System model

### 1. Account policy

Introduce an explicit profile policy independent from display persona:

```text
ProfilePolicy
  kind: standard | bespoke
  bespoke_protocol_id: String?
```

- `standard` is the database, native, web, cache, decoder, and recovery default.
- A standard profile always uses anthropometric/measurement-based energy logic and generated training logic.
- `bespoke` requires a known protocol identifier installed only for the protected founding accounts.
- Display name and persona presentation cannot select calorie or training policy.
- Seed upgrades require `kind == bespoke` and the expected protocol id. A persona string alone is insufficient.
- Actual bespoke identities are migrated using the immutable account identifiers already guarded by maintenance scripts. The migration aborts if the expected identity does not match exactly.

Existing `persona` values remain temporarily for presentation and backward decoding, but cease to be an authorization or nutrition-policy key.

### 2. Measurement evidence

Introduce an account-owned evidence record:

```text
FitnessEvidence
  id: UUID
  user_id: UUID
  metric: MetricKind
  value: Double
  unit: String
  source: EvidenceSource
  protocol: String?
  device: String?
  measured_at: Instant
  imported_at: Instant
  confidence: low | medium | high
  metadata: JSON
  supersedes_id: UUID?
```

Initial metric kinds cover body mass, body-fat percentage, resting energy, VO2, resting heart rate, HRV, sleep duration, field-test results, exercise performance, and region-specific mobility.

Initial source kinds:

- indirect calorimetry;
- DEXA measurement;
- DEXA-derived estimate;
- laboratory/clinical test;
- supported device estimate;
- guided APEX field test;
- structured self-report;
- user-entered external result;
- legacy unverified value.

Evidence is immutable. A correction creates a superseding record. Raw historical account data is never silently rewritten.

### 3. Domain estimates

```text
DomainEstimate
  domain: Domain
  value: Double?
  lower_bound: Double?
  upper_bound: Double?
  reference_scale: String
  confidence: unavailable | low | medium | high
  coverage: Double
  freshness: current | aging | stale
  evidence_ids: [UUID]
  explanation_receipts: [Receipt]
  model_version: Int
  as_of: LocalDate
```

Domains initially include cardiorespiratory capacity, upper strength, lower strength, region-specific mobility, balance/function where applicable, and a non-clinical overall fitness band.

- Unknown is represented by `value == nil`, not 50.
- Self-report can create only a broad low-confidence band.
- Objective or standardized evidence narrows the band.
- A newer high-quality source can supersede a weaker anchor without deleting it.
- Overall Fitness is emitted only when minimum coverage is met. Otherwise the UI says **Building your baseline**.

### 4. Readiness

Readiness is a short-lived daily state derived from available sleep, personal HRV/RHR trends, soreness, fatigue, stress, illness flags, and recent training load.

- It uses personal baselines rather than universal HRV or resting-heart-rate thresholds.
- Missing wearable data produces unknown/partial readiness, not poor readiness.
- Consumer sleep stages and energy expenditure never receive laboratory-level confidence.
- Readiness can adjust today's volume, intensity, recovery advice, and caution. It cannot rewrite capacity.

### 5. Adherence and game progression

Behavioral achievements live in a separate model:

- planned training completed;
- recovery work completed;
- nutrition target range followed;
- hydration target approached;
- sleep routine recorded;
- measurements supplied;
- useful streaks and long-term consistency.

These can award APEX XP, achievements, visual evolution, and synergy receipts. Labels must say what happened: “Protein target supported recovery” rather than “Strength +15%.”

### 6. Health context

Pain, recent operation, symptoms, contraindications, and clearance requirements are safety inputs. They shape plan generation and field-test eligibility. They are not collapsed into a diagnosis-like Health score.

The current Health and Joint Health lanes transition to honest names and descriptions during the UI phase. Historical values remain viewable as legacy game scores but do not masquerade as validated health measurements.

## Energy and body-composition policy

### Resting energy precedence

1. Valid recent indirect calorimetry, under a recorded protocol.
2. DEXA-derived resting-energy estimate when the report supplies one, labeled as an estimate.
3. APEX equation selected for the available inputs and population.

DEXA body composition may improve an estimate but does not become indirect calorimetry. The app stores method and date instead of one ambiguous “Measured BMR” value.

### Unknown body fat

- New profiles store no body-fat value or source.
- Legacy default 23% values without provenance are retained as legacy evidence but ignored by energy calculations until confirmed.
- A person can confirm a value and choose its source: DEXA, BIA/scale, calipers, professional estimate, or self-estimate.
- Only source categories permitted by the energy policy can select a lean-mass equation.

### TDEE and activity energy

- The default calorie target is a stable rolling target, not a volatile daily wearable number.
- Planned activity is represented once in the base activity model.
- Wearable active energy never adds blindly on top of already assumed activity.
- A high-activity adjustment is bounded, transparent, and applied only to expenditure above the baseline assumption.
- The default does not eat back 100% of wearable calories.
- Longitudinal calibration uses sufficiently complete intake and weight trends, bounded adjustment steps, and an explicit confidence state.
- Pregnancy, breastfeeding, eating-disorder risk, underage users, and clinically complex cases require separate guarded policies rather than generic deficit/surplus math.

## Fitness capacity inputs

### Cardiorespiratory capacity

Evidence order:

1. CPET/laboratory VO2 with mode and date;
2. supported device VO2 estimate with device metadata;
3. standardized field-test result selected for safety and capability;
4. structured non-exercise estimate;
5. anchored self-report.

Raw VO2 is retained. Reference interpretation must declare the published reference table or validated estimator version and use its required age band, sex classification, and test mode. APEX never maps all people with `VO2 × constant`.

### Strength

- Exercise-specific performance uses load, repetitions, RIR, range/standard, equipment, body mass where relevant, and movement identity.
- Upper and lower estimates require region-relevant evidence.
- Generic wearable “strength training” duration is training exposure, not proof of upper-body capacity.
- Unverified imported strength can support adherence and workload context but cannot invent a body-region capacity gain.

### Mobility

- Mobility is region-specific: posterior chain/hip, ankle, shoulder, and other explicitly tested regions.
- A single splits claim cannot represent total-body flexibility.
- Pain or unsafe range routes to safety guidance, not a lower moral or game score.
- Self-report anchors describe observable comfortable movement and produce broad confidence only.

### Balance and function

Balance/function appears only for populations and protocols with applicable evidence. It remains optional for a young trained user unless relevant to their goal or safety history.

## Distilled onboarding flow

The mandatory flow contains seven compact stages after consent:

1. **About you** — birthdate, sex used for applicable equations, height, weight, unit preferences.
2. **What are we building?** — goal and preferred pace, with safe boundaries.
3. **Your normal week** — enjoyable anchored activity/workday choices and current training frequency.
4. **Your movement pulse** — a short swipeable set of four observable anchors covering stamina, upper-body work, lower-body work, and mobility. Each accepts “not tested.”
5. **Your setup** — venue, equipment, days, and available time.
6. **Train safely** — pain, recent operation, symptoms, and clearance routing in plain language.
7. **Your starting map** — show provisional bands, confidence, what informed them, and one button to create the plan.

The flow reuses information already entered and removes redundant questions. The user never sees equations, percentiles, confidence calculations, or protocol jargon unless they open **How APEX estimated this**.

### Example tone

Avoid:

> Rate your flexibility from 1 to 10.

Use:

> Which feels most like your comfortable range today?

Then show no more than five visual/text anchors, for example:

- Everyday movement feels restricted.
- I move comfortably through normal daily ranges.
- I comfortably reach deep squat and hip-hinge positions.
- I train deep ranges such as full splits or advanced mobility work.
- I have a measured result or specialist practice to add.

The exact anchors are protocol-specific, localized, and safety-reviewed. They do not directly equal a displayed score.

## Calibrate my baseline

After onboarding, APEX offers three optional routes:

1. **Connect what you already track** — import HealthKit and supported results.
2. **Add a recent result** — DEXA, calorimetry, VO2, grip, lift, run/walk, or mobility measurement.
3. **Try a guided check** — short field tests selected by age, safety answers, equipment, and training status.

Each check explains duration, equipment, stop conditions, and what it can and cannot estimate. It can be paused and resumed. Declining it has no penalty.

## Legacy migration

- Preserve all existing RPG snapshots with their original model version and label them **Legacy APEX score** when viewed after migration.
- Create v2 estimates from retained evidence and event history without rewriting old snapshots.
- Existing values without provenance enter as `legacy_unverified` and cannot receive high confidence.
- Missing periods do not replay as detraining.
- Bespoke plans and targets remain protected, but their avatar capacity estimates follow the same evidence standards as every other account.
- Rollback disables v2 presentation and restores the prior read path without deleting v2 evidence or estimates.

## Error and offline behavior

- Every write is owner-scoped and replay-safe.
- Evidence imports use stable source identifiers and idempotency keys.
- A denied permission leaves the corresponding source unavailable and keeps manual routes working.
- Stale wearable transfers cannot supersede newer evidence.
- Unsupported units, impossible ranges, malformed dates, and unknown protocols are rejected at the boundary.
- Offline evidence is stored locally under the authenticated account and syncs through the existing durable outbox.
- One malformed source cannot prevent unrelated domains from resolving.

## Validation requirements

### Deterministic contracts

- Native/web parity for profile policy, evidence normalization, domain state, readiness, adherence XP, energy targets, and explanations.
- Golden fixtures cover young/older, small/large, novice/trained, standard/bespoke, missing/denied/stale data, and account switching.

### Scientific invariants

- Missing data never lowers capacity.
- Readiness cannot alter capacity.
- Adherence XP cannot alter capacity.
- A source cannot affect a domain it does not validly represent.
- Higher-quality evidence narrows or supersedes a weaker estimate without erasing history.
- An overall result cannot have higher confidence than its required domains permit.
- No body-fat or resting-energy method is inferred from a numeric value alone.
- Wearable energy is counted at most once.

### Release validation

- Run the new engine in shadow mode beside the legacy engine before changing existing-user presentation.
- Record disagreements, coverage, confidence, source distribution, and impossible transitions without storing private raw health data in analytics.
- Review subgroup behavior and outliers before enabling v2 by default.
- Exact scores remain provisional until prospective calibration supports their interpretation.
- Marketing and UI copy pass a claim audit before release.

## Implementation sequence

This architecture is implemented as separately releasable projects:

1. **Profile integrity hotfix** — standard/bespoke policy, safe profile creation, body-fat provenance, protocol gating, migration, and regression coverage.
2. **Fitness Brain v2 semantics** — separate capacity, readiness, adherence XP, health context, confidence, freshness, and missingness.
3. **Evidence storage and normalization** — account-owned immutable evidence records and source hierarchy.
4. **Distilled onboarding** — the sub-three-minute provisional flow with authored localization and accessibility.
5. **Calibrate my baseline** — the Avatar Edit entry point, imports, and safe optional field-test routes.
6. **Shadow validation and transition** — dual-run telemetry, legacy presentation, claim review, and controlled activation.

Every project receives its own TDD cycle, tests, repair note, commit, push to both required refs, GitHub Pages deployment, and applicable APEX-lane/physical-device verification before the next project begins.

## Explicit exclusions

- No clinical diagnosis, injury prediction, disease-risk score, or treatment advice.
- No opaque machine-learning model trained on synthetic or insufficient data.
- No one-number replacement for raw evidence and domain detail.
- No mandatory lengthy fitness battery during signup.
- No destructive rewrite of historical account data.
- No raw HealthKit data in web analytics or public logs.
