# APEX exercise enrichment — canonical report source

Date reviewed: 2026-08-24

## Scope and result

The owner-supplied encyclopedia contains 219 rows. Ten names already resolved
exactly to the canonical library. This pass converts the other 209 rows into
distinct selectable movements and adds eight researched steel-mace movements.
The resulting source catalogue has 534 movements plus 15 cardio modalities,
for 549 user-selectable entries.

This document is the human-readable research record. The machine-readable
source ledger is `data/research/exercise-enrichment-sources.json`; each added
movement carries the applicable source IDs in generated catalogue data and in
the owner CSV export.

## Method and assumptions

- Evidence was applied at the narrowest honest level. A resistance-training
  position stand supports shared programming facts across presses, rows and
  squats; it does not pretend that every named grip or implement variation has
  its own clinical trial.
- Named, consequential movement families received additional primary or
  governing-body sources: kettlebell sport, Olympic weightlifting, gymnastics,
  rope climbing, strongman, loaded carries, steel mace, CARs and Jefferson
  curls.
- The CSV name is retained as provenance. A deterministic enrichment module
  rejects count drift, duplicate IDs, unknown evidence IDs and unknown source
  families before the web or native catalogue can be generated.
- “Selectable” and “safe for automatic programming” are separate facts.
  High-consequence movements remain discoverable for manual logging but are
  marked coached-only.
- Defaults are conservative starting structures, not individualized medical or
  coaching prescriptions. Symptoms, equipment setup and demonstrated skill
  override a default.

## Execution and timing findings

| Movement family | Stored/measured facts | Default execution rule | Progression/safety decision |
| --- | --- | --- | --- |
| Dynamic resistance | Reps and signed external load | Controlled APEX muscle/mechanics tempo; ordinary starting ranges are 6–12 reps, accessories 8–15 | Progress by reps/load only when the logging-kind rule has complete facts |
| Ballistic resistance | Quality reps and load | Explosive intent; no artificial eccentric cadence; stop when speed, catch or fixation changes | No tempo; advanced kettlebell and all jerk additions are coach-gated where failure consequence is high |
| Plyometric | Contacts | 3–5 crisp contacts per set with full recovery | No automatic load progression and no tempo |
| Carry | Distance or duration plus signed load | Upright posture, controlled gait, stop on trunk lean | Pace is derived if needed and never stored; progression compares load and distance/duration rather than summing them |
| Isometric/skill hold | Duration and any applicable signed load | Continuous breathing; stop when position changes | Longer hold or more load can count only where that kind's complete-fact rule allows it |
| Mobility/stretch | Duration or quality repetitions | Slow, comfortable, pain-free range; static stretches 10–30 seconds | Quality/completion only; no automatic progressive overload |
| Balance | Supported 10–30 second attempts, then less support | Stop before loss of balance changes the task | No automatic progressive overload |
| Steel mace | Quality reps and load; carry uses distance | Light familiarisation load, clear swing arc, no imposed cadence on swings | The 360, 10-to-2, uppercut, rotational lunge and single-arm swing are coached-only because the outcome trial was supervised in elite wrestlers |

## High-consequence disposition

The following classes are kept selectable but excluded from unsupervised
automatic assignment: full planche work, ring fly, both rope climbs,
skin-the-cat/German hang, advanced and full levers, manna progression,
behind-the-neck pull-up, the three barbell jerk variants, sandbag throw, atlas
stone loading, Jefferson curl, advanced overhead kettlebell sport movements and
the complex ballistic mace movements. Their records also carry explicit
contraindications, prerequisite or environment facts where applicable.

Jefferson curl is deliberately conservative. The available randomized trial
used healthy active adults, a modified light movement, a three-second descent
and one-second return. That supports the recorded execution, not heavy loading
or use with a symptomatic spine.

## Claim-to-source ledger

| Source ID | Claim supported | Source |
| --- | --- | --- |
| `acsm_resistance_2002` | Rep ranges, progression, rest and controlled resistance execution | [ACSM position stand](https://pubmed.ncbi.nlm.nih.gov/11828249/) |
| `acsm_resistance_2026` | Current strength, hypertrophy and power summary; gradual progression | [ACSM 2026 infographic](https://www.acsm.org/wp-content/uploads/2026/03/Resistance-Training-Position-Stand-infographic.pdf) |
| `aha_flexibility` | Slow, comfortable 10–30 second stretching without bouncing | [American Heart Association](https://www.heart.org/en/healthy-living/exercise-and-physical-activity/fitness-basics/flexibility-exercise-stretching) |
| `aha_balance` | Supported-to-unsupported balance progression and short holds | [American Heart Association](https://www.heart.org/en/healthy-living/exercise-and-physical-activity/fitness-basics/balance-exercise) |
| `nsca_plyometric` | Low-volume, quality-first plyometric contacts | [NSCA](https://www.nsca.com/education/articles/kinetic-select/plyometric-exercises/) |
| `nsca_loaded_carries` | Carry variants, posture, and time/distance dosing | [NSCA](https://www.nsca.com/education/articles/nsca-coach/increase-hip-and-trunk-stability-with-loaded-carries/) |
| `nsca_weightlifting_2023` | Staged coached teaching of weightlifting derivatives | [NSCA position statement](https://dxpprod.nsca.com/globalassets/about/position-statements/weighlifting-for-sports-performance.pdf) |
| `crossfit_gymnastics_guide` | Strength prerequisites before advanced ring and kipping skills | [CrossFit Gymnastics Course guide](https://assets.crossfit.com/pdfs/seminars/SMERefs/Gymnastics/GymnasticsCourse_SeminarGuide.pdf) |
| `crossfit_rope_climb` | Foot-clamp progression and controlled rope climbing | [CrossFit rope-climb standard](https://www.crossfit.com/essentials/the-rope-climb-wrapping) |
| `world_gymnastics_mag_2025` | Identity and competition recognition of planche, lever and ring holds | [World Gymnastics Code of Points](https://www.gymnastics.sport/publicdir/rules/files/en_1.1%20-%20MAG%20Code%20of%20Points%202025-2028.pdf) |
| `iwf_tcrr_2025` | Jerk lockout, receiving and completion standards | [IWF 2025 rules](https://iwf.sport/wp-content/uploads/downloads/2025/05/IWF-TCRR-2025-as-of-01-June-2025.pdf) |
| `ikmf_kettlebell_rules` | Kettlebell clean/jerk/snatch rack and fixation standards | [IKMF rules](https://www.ikmf-world.com/rules/rules-during-performance/rules-as-athletes/) |
| `ace_kettlebell_study` | Coached use of core kettlebell movement families | [ACE-sponsored study summary](https://www.acefitness.org/continuing-education/prosource/equipment-special-issue/4992/ace-sponsored-research-study-kettlebell-training-kicks-butt/) |
| `ace_kettlebell_swing` | Ballistic hip-hinge and quality-stop mechanics | [ACE swing technique](https://www.acefitness.org/continuing-education/certified/january-2025/8788/the-ace-do-it-better-series-the-two-handed-kettlebell-swing/) |
| `steel_mace_rct_2026` | Named mace movements and supervised training structure | [Randomized trial](https://pubmed.ncbi.nlm.nih.gov/41566515/) |
| `onnit_steel_mace` | Named mace mechanics including 360, uppercut and overhead walking | [Onnit technique overview](https://www.onnit.com/blogs/the-edge/the-steel-mace-benefits-and-uses) |
| `world_strongman_rules` | Strongman event identity and completion standards | [World Strongman rules](https://worldstrongman.org/rules-regulations/) |
| `nsca_higher_risk_resistance` | Gradual coached introduction for Olympic, strongman and high-power work | [NSCA risk guidance](https://www.nsca.com/education/articles/ptq/the-safest-and-riskiest-forms-of-resistance-training/) |
| `jefferson_curl_rct_2024` | Modified Jefferson-curl tempo in healthy active adults | [Randomized trial](https://pmc.ncbi.nlm.nih.gov/articles/PMC11212372/) |
| `hip_cars_rct_2026` | Slow hip CARs through available range and acute hip-ROM outcome | [Randomized trial](https://pubmed.ncbi.nlm.nih.gov/42517070/) |
| `hyrox_race_format` | Official eight-station HYROX order | [HYROX race format](https://hyrox.com/the-fitness-race/) |

## Known evidence gaps and conservative handling

| Gap | Handling in APEX |
| --- | --- |
| No trial validates all 209 named variations independently | Shared facts come from family-level guidance; the app makes no variation-specific efficacy claim |
| Shoulder and ankle CAR outcome evidence is thinner than hip CAR evidence | They use only the general slow, pain-free quality rule; the hip outcome is not generalized to those joints |
| Universal loaded-carry volume/load thresholds are not established | Store measured distance/duration and load; avoid a universal bodyweight percentage |
| Steel-mace outcome evidence is from supervised elite male wrestlers | Do not use the study's 20% body-mass load as a default; complex ballistic entries are coached-only |
| World Gymnastics and sport rules define recognition, not beginner dosage | Competition standards identify mechanics; conservative holds and prerequisite/coaching gates define APEX dosage |
| Jefferson-curl evidence does not support symptomatic or heavy spinal flexion | Coach-gated, light, graded execution with a lumbar-flexion contraindication and no automatic progression |
