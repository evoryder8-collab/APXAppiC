# APEX Fitness Brain audit source ledger

This is the canonical source ledger for `2026-08-30-apex-fitness-brain-scientific-audit.md`. It separates repository observations from external evidence. Accessed 2026-08-30 unless otherwise stated.

## Repository evidence ledger

| ID | Claim supported | Repository evidence |
|---|---|---|
| C01 | Generic profile defaults to Constantine | `supabase/migrations/002_persona_profiles.sql:4-5`; `ios/APEXNative/APEX/Core/Networking/SupabaseService.swift:18-52` |
| C02 | New profile body fat and activity use database defaults | `supabase/migrations/001_schema.sql:5-18`; `ProfileCreationRequest` omits both fields |
| C03 | Constantine persona bypasses generic target math | `src/lib/nutrition.ts:217-231`; `src/lib/personalProtocol.ts:27-72`; `ios/APEXNative/APEX/Core/Engine/FitnessBrainTargets.swift:83-118` |
| C04 | Seed repair overwrites Constantine profile facts | `src/lib/seedRepair.ts:221-302`; repair is eligible below current seed version at `src/lib/seedRepair.ts:308-353` |
| C05 | Fixed baselines, floors, half-lives, weights, and age drag | `src/lib/rpg.ts:31-92`; `ios/APEXNative/APEX/Core/Engine/FitnessBrainEngine.swift:20-47` |
| C06 | Missing feed events trigger daily decay | `src/lib/rpg.ts:521-536`; `FitnessBrainEngine.swift:489-504` |
| C07 | Protein, energy, hydration, and meal timing directly change points | `src/lib/rpg.ts:355-519`; `FitnessBrainEngine.swift:328-482` |
| C08 | VO2 uses a raw linear game mapping | `src/lib/rpg.ts:140-142`; `FitnessBrainEngine.swift:71` |
| C09 | Imported strength feeds upper body only | `src/lib/rpg.ts:422-433`; `FitnessBrainEngine.swift:403-417` |
| C10 | Joint check and Apple recovery context are not score inputs | Writers/readers at `AvatarView.swift:607-625`, `AppSession.swift:2090`, `RecoveryAssessment.swift:161`; `FitnessBrainService.swift:142-176` reads only `recovery_history` and meal rhythm |
| C11 | RHR is present but not scored; steps and active energy are absent from brain input | `FitnessBrainService.swift:104-105`; no scoring reference in `FitnessBrainEngine`; `FBEngineInput` has no step/active-energy field |
| C12 | Native and web parity is deterministic | `ios/APEXNative/APEXTests/FitnessBrainParityTests.swift`; shared fixtures; current web suite 698/698 passed on 2026-08-30 |
| C13 | Daily target semantics differ by surface and profile kind | `src/pages/SimpleHome.tsx:182-195`; `src/pages/Nutrition.tsx:135-203`; `personalTargetFor` bypass at `Nutrition.tsx:147` |

## External evidence ledger

| ID | Evidence and audit use | Source |
|---|---|---|
| E01 | Mifflin-St Jeor is among the more reliable common resting-energy equations, but individual prediction error remains and indirect calorimetry removes equation error. | [Frankenfield et al., systematic review, PMID 15883556](https://pubmed.ncbi.nlm.nih.gov/15883556/) |
| E02 | DXA body composition can improve energy-expenditure prediction, but it remains prediction rather than direct metabolism measurement. | [Kistorp et al., PMID 10865713](https://pubmed.ncbi.nlm.nih.gov/10865713/) |
| E03 | REE was measured by indirect calorimetry and predicted from DXA/BIA fat-free mass; the body-composition method and equation matter. | [Korth et al., PMID 17136038](https://pubmed.ncbi.nlm.nih.gov/17136038/) |
| E04 | In muscular physique athletes, many weight- and FFM-based equations showed unacceptable individual validity against indirect calorimetry. | [Tinsley et al., PMID 30240568](https://pubmed.ncbi.nlm.nih.gov/30240568/) |
| E05 | Directly measured peak VO2 reference values vary by age, sex, and test mode. | [FRIEND updated reference standards, PMID 34809986](https://pubmed.ncbi.nlm.nih.gov/34809986/) |
| E06 | Several walk/run field tests have useful criterion validity, but they estimate rather than directly measure cardiorespiratory fitness. | [Mayorga-Vega et al., systematic review/meta-analysis, PMID 26987118](https://pubmed.ncbi.nlm.nih.gov/26987118/) |
| E07 | Adult field-test review supports selected cardiorespiratory tests and handgrip; sit-and-reach/toe-touch are not valid for a combined hamstring/lower-back construct. | [Criterion-related validity of adult field tests](https://pmc.ncbi.nlm.nih.gov/articles/PMC8397016/) |
| E08 | Sit-and-reach has moderate hamstring but low lumbar validity and cannot represent total-body flexibility. | [Mayorga-Vega et al., PMID 24570599](https://pubmed.ncbi.nlm.nih.gov/24570599/) |
| E09 | A single self-rated fitness item has poor individual agreement with measured fitness. | [Ortega et al., PMID 29665613](https://pubmed.ncbi.nlm.nih.gov/29665613/) |
| E10 | Detraining effects vary by training status and duration; VO2 decline is not one universal daily half-life. | [Bosquet et al./updated meta-analysis, PMID 36017396](https://pubmed.ncbi.nlm.nih.gov/36017396/) |
| E11 | Subjective wellness can be sensitive for monitoring training response, but it is a monitoring construct rather than measured physical capacity. | [Saw et al., systematic review, PMID 26423706](https://pubmed.ncbi.nlm.nih.gov/26423706/) |
| E12 | Adults should generally sleep at least seven hours regularly; duration is one input, not a complete readiness score. | [AASM/Sleep Research Society consensus](https://www.aasm.org/resources/pdf/adultsleepdurationconsensus.pdf) |
| E13 | Consumer wearable sleep estimates differ from polysomnography and should be interpreted as trends rather than exact sleep architecture. | [Systematic review/meta-analysis, PMID 39484805](https://pubmed.ncbi.nlm.nih.gov/39484805/) |
| E14 | Apple Watch validation evidence is strongest for some heart-rate measures; sleep, steps, and especially energy expenditure remain variable. | [Living systematic review, PMID 41513748](https://pubmed.ncbi.nlm.nih.gov/41513748/) |
| E15 | Hydration needs vary with body size, sweat rate, environment, intensity, and duration; individualized plans are recommended. | [NATA fluid replacement position statement, PMID 28985128](https://pubmed.ncbi.nlm.nih.gov/28985128/) |
| E16 | No single hydration measure is sufficient in every context; combined assessment is preferable. | [Hydration-status methods review, PMID 33126891](https://pubmed.ncbi.nlm.nih.gov/33126891/) |
| E17 | Protein supports resistance-training adaptation over weeks; benefits tend to plateau around a total intake near 1.6 g/kg/day, not an immediate daily strength-point bonus. | [Morton et al., meta-analysis, PMID 28698222](https://pubmed.ncbi.nlm.nih.gov/28698222/) |
| E18 | Prolonged energy deficit can impair lean-mass gains, while strength outcomes are not equivalent to a universal same-day penalty. | [Murphy & Koehler, meta-analysis, PMID 34623696](https://pubmed.ncbi.nlm.nih.gov/34623696/) |
| E19 | Prediction-model assessment requires attention to participants, predictors, outcomes, and analysis; validation is separate from implementation. | [PROBAST, PMID 30596875](https://pubmed.ncbi.nlm.nih.gov/30596875/) |
| E20 | A measurement instrument needs a clearly defined construct, population, relevance, comprehensiveness, and comprehensibility. | [COSMIN content-validity methodology](https://pmc.ncbi.nlm.nih.gov/articles/PMC5891557/) |
| E21 | Missing-data handling can bias prediction models and must be designed and reported explicitly. | [Systematic review of missing data in prediction studies](https://pmc.ncbi.nlm.nih.gov/articles/PMC8527348/) |
| E22 | MyFitnessPal describes initial goals as anthropometric/activity estimates adjusted for desired weight change. | [MyFitnessPal official help](https://support.myfitnesspal.com/hc/en-us/articles/360032625391-How-does-MyFitnessPal-calculate-my-initial-goals) |
| E23 | YAZIO describes formula-based targets from height, weight, gender, and age and acknowledges individual variation. | [YAZIO official help](https://help.yazio.com/hc/en-us/articles/360013795878-How-many-calories-can-I-eat-if-I-want-to-lose-weight) |
| E24 | YAZIO exposes a setting to include or exclude activity calories, illustrating that “eat back” is a policy choice rather than a physiological certainty. | [YAZIO official activity-calorie help](https://help.yazio.com/hc/en-us/articles/360002474498-Why-do-my-calorie-goal-and-nutrient-goals-change) |
| E25 | One-leg stance norms depend on age, sex, and protocol and are best established for older adults. | [Unipedal balance systematic review/meta-analysis, PMID 30017097](https://pubmed.ncbi.nlm.nih.gov/30017097/) |

## Search and selection notes

- Technical and health claims preferentially use peer-reviewed systematic reviews, validation studies, consensus statements, and official product documentation.
- Evidence was used to bound claims, not to invent exact questionnaire cut points where suitable normative data are absent.
- The audit does not treat association with health outcomes as proof that a field test precisely measures an individual or that changing an app score changes health.
- The proposed field-test routes require protocol-level design, contraindication handling, localization, and population-specific norm selection during the approved design phase.
