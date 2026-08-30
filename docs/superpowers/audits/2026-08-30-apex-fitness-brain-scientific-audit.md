# APEX Fitness Brain scientific and systems audit

Date: 2026-08-30  
Scope: native and web scoring engines, energy targets, onboarding, HealthKit ingestion, avatar presentation, persistence, parity tests, and the proposed initial fitness assessment  
Status: audit complete; redesign requires owner approval before implementation

## Executive verdict

APEX has a strong product concept and an unusually good technical foundation for a cross-domain fitness system: one account owns its data, events are replayed deterministically, web and native implementations are held to parity, imported workouts are deduplicated, and the UI can explain which rule fired.

The current numerical model is **not yet scientifically validated, ultra-accurate, or safe to market as a physiological measurement**. It is a deterministic gamified heuristic. Several constants are arbitrary, several collected signals never reach the score, missing telemetry is treated like biological deterioration, and generic subscribers can currently inherit Constantine's bespoke profile and calorie protocol.

The concept is worth protecting. The correct path is not to throw it away; it is to separate measured capacity, short-term readiness, adherence, and health context, then attach confidence, provenance, freshness, and uncertainty to every result.

### Audit ratings

| Area | Current assessment | Reason |
|---|---:|---|
| Product differentiation | Strong | Cross-domain, account-owned, explainable event history is genuinely distinctive. |
| Determinism and client parity | Strong | Native and web replay the same inputs and parity tests pin identical output. |
| Data provenance | Mixed | Some imports and receipts are traceable; score inputs do not consistently retain source quality or uncertainty. |
| Scientific construct validity | Weak | Capacity, readiness, behavior, and health are mixed into the same point system. |
| Individual calibration | Weak | Fixed persona baselines, floors, weights, and half-lives dominate the result. |
| Missing-data safety | Unsafe | Missing observations lower scores through decay even when no detraining is known. |
| New-subscriber calorie safety | Release blocker | A generic signup can receive Constantine's fixed targets and fabricated 23% body fat. |
| Marketing-claim readiness | Not ready | “Physiological,” “calibrated,” and exact-looking scores exceed the evidence. |

## What is already sound

1. **The event architecture is appropriate.** `FitnessBrainService` converts owned records into a pure engine input, and the engine replays from a baseline date. This is auditable and reproducible.
2. **Cross-platform parity is real.** Swift and TypeScript use matching rules and fixtures. The current web suite completed 698/698 tests during this audit.
3. **Account isolation and deduplication are thoughtful.** Linked Apple Health evidence is not counted as a second workout, hidden imports are excluded from scoring, and owner/day guards exist.
4. **The system can explain itself.** Synergy events record which rule changed a result. This is the right mechanism for future evidence receipts.
5. **The calorie engine contains useful building blocks.** Mifflin-St Jeor, a lean-mass equation, goal factors, protein/fat floors, wearable deduplication, and longitudinal calibration hooks are present.

These strengths show that the “one brain” idea is feasible. They do not validate the current numbers.

## Release-blocking correctness findings

### P0.1 — Generic accounts can become Constantine

The database migration sets `persona` to `constantine` by default. Native `ProfileCreationRequest` does not send a generic persona. It sends the subscriber's sex, weight, height, birthdate, and goal, but omits persona, activity level, body fat, and BMR source. The resulting profile is therefore decoded as Constantine.

That has three consequences:

- `personalTargetFor` and `FitnessBrainTargets.personalProtocols` select Constantine's fixed bespoke tables before using the subscriber's body measurements.
- Seed repair considers the account eligible for Constantine upgrades and can replace body and nutrition facts with 71 kg, 177 cm, 22.5% body fat, BMR 1680, and fixed targets.
- Constantine-only programme, activity, and copy branches can become visible to an ordinary subscriber.

A controlled calculation during the audit produced this result:

| Profile | Persona | Recomp target | Protein | Fat |
|---|---|---:|---:|---:|
| Female, 45 kg, 150 cm, age 20 | `constantine` | 2,450 kcal | 150 g | 75 g |
| Male, 120 kg, 195 cm, age 60 | `constantine` | 2,450 kcal | 150 g | 75 g |
| Same 45 kg profile | generic engine | 1,542 kcal | 95 g | 43 g |
| Same 120 kg profile | generic engine | 3,264 kcal | 252 g | 91 g |

The first two rows prove that body inputs are bypassed, not merely weighted poorly.

Required correction: introduce an explicit ordinary-account persona/profile kind, make it the database and client default, gate bespoke repair by immutable account identity rather than a mutable persona string, and migrate affected ordinary accounts without touching the actual bespoke accounts.

### P0.2 — Onboarding fabricates a body-fat measurement

The questionnaire does not ask for body-fat percentage, yet the schema defaults it to 23%. Both energy engines treat any value between 0% and 75% as credible and choose the lean-mass equation over Mifflin-St Jeor. The UI then describes the result as based on the person's “body-fat entry.”

Unknown body fat must be `null`, not 23. A user-entered or imported value needs method, date, and source. Without it, the engine should use an anthropometric equation and show an estimated range.

### P0.3 — Missing telemetry is interpreted as detraining

The code says that days without data never punish, but each unfed stat decays daily toward a fixed floor. Starting from the default baseline, the pure decay terms produce approximately:

| No qualifying event for | Health | Joint | Flexibility | Endurance | Upper | Lower |
|---:|---:|---:|---:|---:|---:|---:|
| 7 days | 52.3 | 52.7 | 34.8 | 40.0 | 57.8 | 40.6 |
| 30 days | 42.5 | 46.9 | 29.0 | 32.7 | 52.7 | 37.1 |
| 60 days | 40.3 | 42.1 | 28.1 | 30.5 | 48.9 | 34.6 |

The separate age drag lowers several domains further. The engine cannot tell whether the person stopped training, trained outside APEX, denied Health access, lost connectivity, or simply did not log. Missingness should widen the estimate and reduce confidence; only affirmative evidence of changed capacity should move the capacity estimate.

## Scientific-model findings

### P1.1 — The score mixes different constructs

Current “Health,” “Joint Health,” flexibility, endurance, and strength numbers combine:

- slow-changing physical capacity;
- same-day recovery/readiness;
- logging and meal-timing adherence;
- hydration behavior;
- inferred training exposure; and
- health-adjacent context.

For example, hitting 2.5 L water raises Health immediately and adds 10% Endurance XP on a T25 day. Hitting protein adds 15% Strength XP that day. Completing meals near a calorie target raises Health. These may be useful behavior prompts, but they are not direct measurements of cardiovascular health, strength, or tissue adaptation.

The replacement model must keep four separate layers:

1. **Capacity** — strength, cardiorespiratory fitness, mobility, balance, and work capacity; changes slowly and requires performance evidence.
2. **Readiness** — sleep, soreness, fatigue, stress, resting-heart-rate and HRV trends; changes quickly and modifies today's recommendation, not anatomy.
3. **Behavior/adherence** — training consistency, nutrition, hydration, recovery-session completion, and plan adherence.
4. **Health context** — symptoms, pain, contraindications, and risk flags; never collapsed into a consumer “health diagnosis.”

### P1.2 — Fixed baselines and weights are uncalibrated

The default baseline is 60 Health, 55 Joint, 40 Flexibility, 45 Endurance, 60 Upper, and 42 Lower. Other named personas receive other fixed blocks. Overall Fitness is always 25% strength, 20% endurance, 20% joint, 20% health, and 15% flexibility. Floors and half-lives are also fixed for everyone.

No cohort, norm table, outcome study, or calibration dataset supports those values. A deterministic number can still be arbitrary. Overall weighting also changes the meaning of the composite; it needs a declared construct and validation, not aesthetic balancing.

### P1.3 — VO2 mapping ignores age, sex, modality, and uncertainty

`vo2ToStat` maps VO2max to a game score with `VO2 × 1.35`, clamps it to 20–95, and pulls Endurance halfway to the anchor. Cardiorespiratory norms vary materially by age, sex, and test modality. Consumer-watch estimates also have device and context error. A defensible result should retain the raw value, source, date, test mode, device, and confidence, then compare against an appropriate reference distribution.

### P1.4 — Strength is not measured as strength

The engine mainly uses session type, duration, top-load increases, and a fixed XP amount. Repetitions, reserve in reps, range of motion, body mass, volume, movement pattern, and exercise-specific history do not form a normalized capacity estimate. A higher top load can reflect a different rep range, technique, machine, or exercise revision.

An imported HealthKit strength workout feeds only upper-body strength, even when the session was lower-body or full-body. This is a classification error.

### P1.5 — Flexibility and joint status are weakly grounded

Any mobility-classified session feeds a single global Flexibility stat. That cannot distinguish hamstrings, hips, ankles, shoulders, or spine. Sit-and-reach-like self-report is not a valid total-body flexibility measure. The weekly joint check is stored under `avatar_joint_check`, but the scoring service never reads it.

Mobility should be region-specific. Pain and joint function should affect safety and recommendations, not be converted into a false tissue-health score.

### P1.6 — Collected sleep and recovery data do not reach the avatar as claimed

Apple sleep duration and HRV are stored under `apple_recovery_context`; the Fitness Brain reads only `recovery_history`. Resting heart rate is passed into the engine model but used only for advice, not the score. Steps and active energy are used elsewhere but not as Fitness Brain inputs. The app therefore collects or displays several signals that the avatar calculation does not actually use.

Even after wiring them, consumer wearable sleep stages, HRV, and energy expenditure need personal baselines and uncertainty. They should support readiness trends, not produce exact physiological truth.

### P1.7 — Nutrition and hydration effects use unsupported short-term causality

Adequate protein and energy availability matter over repeated training blocks. Hydration can affect performance when hypohydration is meaningful. The evidence does not justify an immediate universal +15% Strength XP, -15% Strength XP, +10% Endurance XP, or a fixed 2.5 L threshold for every body and environment.

Nutrition should influence recovery/adaptation confidence over rolling periods. Hydration targets should remain individualized by body size, exercise, environment, and observed sweat loss where available. Food water should be reported separately from beverages so it informs total water without falsely suggesting that the user has completed a drinking target.

### P1.8 — Daily calorie behavior is inconsistent

For an ordinary profile, Simple Mode uses a profile-level activity multiplier. Nutrition switches to a computed activity day only when activity blocks exist; wearable calories alone do not activate that path. Bespoke profiles bypass both and use fixed tables. This creates different target semantics across screens and account types.

APEX should not automatically “eat back” 100% of consumer-wearable calories. Wearable energy expenditure is too noisy for that. The default should be a stable target built from a calibrated rolling TDEE. A bounded high-activity adjustment may be offered when observed expenditure materially exceeds the activity already assumed, with the policy visible and user-controlled.

## Domain-by-domain audit matrix

| Domain | Available evidence | Current scoring use | Correct future role |
|---|---|---|---|
| Workouts | session type, duration, sets, reps, load, RIR, device metrics | Mostly type/duration and top-load change | Exercise-specific performance model, volume/load history, modality and confidence |
| Cardiorespiratory fitness | watch VO2, cardio duration/distance | Raw VO2 linear map; duration XP | Age/sex/mode reference percentile plus raw trend and source confidence |
| Strength | sets, reps, load, body mass, exercise identity | Top load and session-class XP | Relative and exercise-specific capacity; never infer lower/upper from generic HealthKit strength |
| Mobility | mobility sessions; proposed self-report | One global XP lane | Region-specific measured range or bounded structured estimate |
| Joint/pain | induction safety answers, weekly joint check | Overrides reduce Joint; weekly check unused | Safety constraints and symptom trend; not a diagnosis score |
| Sleep | Apple duration/context, manual recovery | Apple context mostly disconnected | Readiness trend against personal baseline, with device quality and freshness |
| HRV/RHR | Apple HRV/RHR | RHR advice only; HRV disconnected | Personal-baseline readiness context, not population-grade capacity |
| Nutrition | energy, protein, meal rhythm | Same-day XP multipliers and Health points | Rolling energy availability/adherence and recovery context |
| Hydration | drinks, food water, target, activity | Fixed threshold in brain | Personalized total-water context; drinks and food-water remain visually distinct |
| Body composition | weight, default body fat, optional BMR | Default 23% treated as measured | Nullable, sourced, dated measurements with uncertainty |
| Missing data | absence of an event | Daily biological decay | Hold estimate, lower confidence, mark stale; do not invent decline |

## Direct answer: does a DEXA-reported BMR help?

Yes, **if APEX records what that number actually is**.

- A DEXA scan measures body composition. A BMR/RMR printed on many DEXA reports is usually an equation applied to measured lean mass; it is not a direct metabolism measurement.
- Indirect calorimetry measures respiratory gas exchange and is the stronger resting-energy input when performed under suitable conditions.
- A DEXA-derived estimate can still improve on a height/weight-only equation for some people, especially when body composition is unusual, but it carries equation and population error.

APEX should accept three distinct sources:

1. `indirect_calorimetry_measured` — highest confidence, with test date and protocol;
2. `dexa_derived_estimate` — medium confidence, with the report's equation if known;
3. `apex_formula_estimate` — Mifflin-St Jeor or an appropriate lean-mass equation, with a displayed range.

It should never label all three “measured BMR.” A DEXA-derived BMR may outperform a generic formula, but it does not eliminate the need to calibrate TDEE against several weeks of weight and intake trend.

## Direct answer: will a new subscriber currently get a decent target?

**No—not reliably in the current build.** The Constantine persona collision and fabricated 23% body fat prevent that guarantee.

After those are fixed, age, sex used for the equation, height, weight, goal, and a genuinely selected activity level can produce a reasonable *starting estimate*. It must be presented as an estimate, not a promise. The system should then calibrate cautiously from at least several weeks of sufficiently complete intake and weight data, with bounds on each adjustment.

This can become better than a formula-only calorie tracker because APEX can combine a sourced resting-energy input, planned activity, observed activity, weight trend, intake adherence, and recovery. The advantage comes from longitudinal calibration and provenance—not from making the initial number look more precise.

## Proposed scientific architecture

Every domain result should be a state estimate, not a naked integer:

```text
DomainEstimate
  value or range
  unit / reference scale
  confidence (low, medium, high)
  coverage
  source type and source id
  measured_at
  valid_until / freshness
  uncertainty
  explanation receipts
```

Rules:

- Objective performance evidence outranks a structured field test; a field test outranks anchored self-report; unknown remains unknown.
- New evidence updates only the domain it can validly represent.
- Readiness may alter today's prescription but cannot instantly rewrite capacity.
- Missing data lowers confidence and freshness; it does not lower capacity.
- Cross-domain effects must be directional recommendations or bounded modifiers supported by evidence, not invented exact physiology.
- The Overall Fitness result appears only when coverage is adequate and always shows its domain composition. Otherwise APEX shows “Building your baseline” with a provisional range.

## Proposed onboarding assessment

The enjoyable slider idea is compatible with science if sliders are **anchored to observable evidence** and never converted directly into false precision.

### Route 1 — Quick estimate (about 2–3 minutes)

Use structured, low-confidence anchors:

- recent training frequency and modalities;
- recent uninterrupted walk/run capacity with time or distance anchors;
- recent strength performance using selectable movements and actual reps/load where known;
- region-specific mobility tasks, with “not tested” and “pain/unsafe” options;
- balance/functional capacity appropriate to age and safety status;
- current sleep, soreness, fatigue, and stress for readiness only.

Output: broad ranges and low confidence, never a cold 50.

### Route 2 — Guided field assessment (about 8–12 minutes)

After a safety screen, offer age- and capability-appropriate tests:

- cardiorespiratory: 2 km walk, 6-minute walk, 12-minute run/walk, or another validated route selected by safety and training status;
- upper strength: handgrip when a dynamometer exists; otherwise record an appropriately standardized performance test with lower confidence;
- lower function/strength: chair-stand route for suitable users, or relative-load history for trained users;
- mobility: joint-specific active range tasks rather than a single “flexible” identity question;
- balance: optional single-leg stance where the available norms are applicable.

Output: narrower ranges with test name, protocol, date, and confidence.

### Route 3 — Import evidence

Allow recent laboratory or device results:

- VO2/CPET or supported field-test result;
- indirect-calorimetry RMR;
- DEXA body composition and DEXA-derived RMR, separately labeled;
- grip, lift, run, walk, and mobility results;
- HealthKit history for trend context.

Output: highest available confidence per domain, never globally high confidence merely because one domain has strong evidence.

### Better wording than “chicken legs”

Ask about lower-body performance, not appearance:

> Which best describes your current lower-body capacity?

Then offer observable routes such as recent squat/split-squat performance, repeated chair stands, stair tolerance, or “I have not tested this.” Appearance and self-esteem do not measure force production.

### Better flexibility design

Do not ask one 1–10 “How flexible are you?” question and map 8 to 78 points. Single-item self-rating has weak individual agreement, and splits do not measure every region. Ask separate safe anchors for posterior chain, hip, shoulder, and ankle mobility. A gymnast or contortionist can report advanced discipline-specific capacity, but that should not imply universally healthy joints or high readiness.

## Three implementation approaches

### A — Evidence Ladder state estimator (recommended)

Build the domain-estimate model above; keep capacity, readiness, behavior, and health context separate; migrate existing data into low-confidence legacy estimates; show provenance and uncertainty.

Benefits: scientifically honest, extensible, differentiating, and compatible with future calibration.  
Tradeoff: largest schema and UI change.

### B — Conservative Rules Engine v2

Retain the current replay architecture but remove persona leakage, fabricated measurements, arbitrary half-life decay, and unsupported XP claims. Add confidence/freshness and use validated norm tables for the first assessment.

Benefits: faster and lower migration risk.  
Tradeoff: still a rules engine and less capable of principled evidence fusion.

### C — Data-calibrated personalized model

Collect representative longitudinal outcomes, define target constructs, pre-register evaluation metrics, and train/calibrate models only after enough high-quality data exists. Run in shadow mode before any user-facing influence.

Benefits: strongest eventual personalization.  
Tradeoff: not an immediate solution; without a representative outcome dataset it would automate current assumptions.

Recommended sequence: **P0 correctness hotfix → B as a safe bridge → A as the product architecture → C only after prospective validation.**

## Verification and validation gates

The redesigned brain should not ship exact scores until it passes:

1. **Construct definition:** what each domain means, what it explicitly does not mean, and its target population.
2. **Unit and provenance contracts:** no source-less body fat, BMR, VO2, sleep, HRV, load, or water values.
3. **Missingness tests:** denial, device loss, offline periods, and incomplete logging cannot fabricate decline.
4. **Account-isolation tests:** no bespoke identity or target can cross into a generic account.
5. **Criterion tests:** compare domain estimates to accepted measurements where feasible.
6. **Calibration tests:** predicted ranges must contain observed outcomes at the promised frequency.
7. **Subgroup tests:** age, sex used for reference equations, body size, training status, disability, and device source.
8. **Temporal tests:** readiness reacts quickly; capacity cannot jump implausibly overnight.
9. **Prospective shadow run:** calculate old and new models without changing recommendations, then review disagreement and failure cases.
10. **Claim review:** UI and marketing copy must distinguish estimate, measurement, trend, behavior, and clinical advice.

## Required next decision

No scoring implementation should begin until the owner chooses the migration architecture. The recommendation is to approve the staged sequence above, beginning with the P0 generic-profile and unknown-body-fat correction, then designing the Evidence Ladder onboarding and state model.

The complete evidence ledger is in [`report-source.md`](report-source.md).
