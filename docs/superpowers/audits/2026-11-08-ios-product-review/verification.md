# What was verified

The audit used the checked-in iOS, Watch, Edge Function and database sources at `45f58e1`. Apple simulators, compiled native calculations, a disposable PostgreSQL database and read-only production catalogue and schema queries provided independent checks.

## iPhone

The iPhone 17 Pro simulator on iOS 26.5 ran 192 selected tests from the APEX scheme. Xcode’s final result bundle recorded **188 passed and four failed**, comprising 184/185 native tests and 4/7 UI journeys. The results below are from this run.

| UI journey | Observed outcome |
| --- | --- |
| First-time subscriber | Passed the “Your normal week” screen, reviewed the starting map, and generated a plan in the individual preview. |
| Client and trial | Passed the developer preview access journeys. Actual billing and an external invitation delivery were outside this run. |
| Custom workouts | Created, reopened, edited, deliberately replaced and deleted a workout in the simulator. |
| Quick Log from yesterday | Both Simple and Advanced opened the logger on the selected date. |
| Guided workout after a failed save | The repaired draft reopened with the same recorded reps. Retrying reached receipt editing, which attempted a remote write with no user edit and tripped the local fixture’s isolation guard. The test failed waiting for Done. See the receipt finding. |
| Portal navigation | Reached Nutrition, opened calorie targets and navigated the dayline and activity section. Then the test searched for the old Supplements disclosure. Supplements is now a visible section. The subsequent Orbit and Avatar navigation steps in this particular journey were not reached. |
| Food Memory and presets | Reached Breakfast, the preset controls and food selection. The test subsequently looked for the old row identifier on its compact Remove button. The control now has its own delete identifier. Compact deletion and undo still need verification with the current selector. |

The one failed native test searched the source text for an exact sequence of words in the wearable-link condition. The current condition also checks for a finish time; independent session ownership and calendar-day tests passed. Replace the text match with an assertion about the dated receipt and its linked activity. [Native assertion](../../../../ios/APEXNative/APEXTests/HealthImportParityTests.swift#L279) · [Current Supplements section](../../../../ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift#L149) · [Current meal control](../../../../ios/APEXNative/APEX/Features/Nutrition/MealComposerView.swift#L1235)

The XCTest failure stack for the guided retry pointed from the receipt’s update operation into outbox replay and the debug guard in the network service. The local fixture prevented a server write. There was no matching test of a crash on a physical release build. [Isolation guard](../../../../ios/APEXNative/APEX/Core/Networking/SupabaseService.swift#L80)

## Watch, food and backend

- On a Watch SE 40 mm simulator running watchOS 26.5, the custom amount opened from the hydration screen. A horizontal swipe increased it, reversing the swipe restored it, and the +/− controls remained usable after scrolling. The test did not log water. The separate Swift supplement harness passed all **52 checks**, including owner isolation, day rollover, pending changes surviving relaunch and ordering duplicate messages. Physical Watch pairing, HealthKit permissions and watch-face refresh timing remain device-only checks.
- The live public food catalogue returned seeded bread, sunflower bread and extra virgin olive oil for the corresponding everyday queries. Native and server ranking code were run separately with synthetic branded items to distinguish a missing food from an iOS post-processing problem.
- The linked Supabase project reported healthy. Row-level security was enabled on all **61 tables in the public schema**. The health advisor returned no findings. These checks describe service and schema state; application authorization was tested separately. The native contract checker found 38 table references and 32 native mutation tables mirrored by the web client. The latest recovery-meal compatibility migration was present.
- Compiled Swift and matching TypeScript calculations reproduced the new-account decline, hydration mismatch and premature deficit feedback. A separate Swift run reproduced the eating-pattern grouping issue. These tests establish app behavior, not clinical validation of the scores.
- A disposable PostgreSQL 15.18 instance with synthetic owners, authenticated roles and the repository migrations reproduced the meal edit and coaching findings. The relevant deployed database function bodies matched the local definitions after normalising whitespace. The production checks read schema metadata and public food data only. No customer records were inspected or changed.

## Release checks

The repository test command ran **1,015 tests: 985 passed and 30 failed**. Two failures came from PostgreSQL shared-memory restrictions in the test sandbox; both passed when rerun in isolated local databases. The other 28 remained unresolved in this audit. Examples include file URLs containing `Fitness%20App` passed to filesystem tools, source-text assertions that hard-code old UI structure, and translation expectations still keyed to “APEX.” These failures are not evidence of 28 user-facing defects. The Pages workflow builds the site and probes two database column contracts. It does not run this suite or the native UI journeys. [Path handling example](../../../../tests/food-knowledge-corpus.test.ts#L152) · [Release workflow](../../../../.github/workflows/deploy.yml)

Before expanding distribution, verify these four outcomes with fixtures: ending a coaching relationship stops future sharing; editing one older ingredient preserves every other ingredient; opening a receipt produces zero writes; and an unobserved account stays unscored. Then cover double-tapping Quick Log, branded food searches, and the personalised hydration goal. Keep the relevant user journeys in the release checks once their selectors and isolation are reliable.
