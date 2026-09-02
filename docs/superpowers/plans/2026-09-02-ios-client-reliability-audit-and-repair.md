# iOS Client Reliability Audit and Repair Plan

> Status: active on 2026-09-02. Every task is red-green-refactor, independently verified, documented in `REPAIR-NOTES`, committed, pushed, and published before the next task begins.

## Objective

Exercise APEX as a real new subscriber, returning individual, bespoke client, and coach-sponsored client. Verify that every visible action tells the truth, preserves account ownership, mutates the intended date and record, feeds the Avatar engine only when the evidence contract allows it, and remains recoverable across dismissal, relaunch, offline use, and account switching.

## Evidence standard

- Unit and integration contracts for every deterministic calculation and ownership boundary.
- XCUITest walkthroughs on `APEX Lane · iPhone 17 Pro` only; never use `BA-Studio-Lane` or a Finalova lane.
- Screenshot inspection after material transitions, not merely existence assertions.
- At least one fresh zero-state subscriber and one populated returning account.
- Exact persona calculations recorded for goal presets, BMR/TDEE provenance, macros, and activity treatment.
- No physical iPhone or Watch install while the owner is sleeping; device verification resumes only when explicitly safe.

## Task 1 — Establish the walkthrough baseline

1. Run the complete existing UI suite and preserve the result bundle.
2. Repair test-harness-only failures without weakening assertions.
3. Build a flow matrix covering auth, onboarding, plans, nutrition, food, hydration, training, Avatar, recovery, progress, Orbit, coach, settings, sync, accessibility, and account switching.
4. Record every warning, misleading action, missing return path, persistence mismatch, and inaccessible control.

Task 1 evidence: complete on 2026-09-02. The dedicated APEX lane finished 30/30 UI methods with no failures or skips; the 35-case acceptance matrix remains deliberately Pending wherever full runtime and human-discoverability proof is not yet present.

## Task 2 — Seal account and privacy boundaries

1. Prove an interrupted Orbit run cannot appear, resume, or save under another owner.
2. Clear derived Avatar synergies whenever their owning profile disappears or changes.
3. Apply account-generation plus owner guards to every long-running mutation that assigns shared session state.
4. Scope nudges, notification identifiers, read state, and pending notifications to their owner.
5. Verify A → logout → B and A → slow request → B races.

Task 2 evidence: complete on 2026-09-02. A single owner-and-generation lease now follows every audited long-running mutation and private presentation through its final publication; account boundaries synchronously clear derived state, private media, notifications, Health observers, Orbit state, coach state, and entitlement state. OAuth failure recovery revalidates an owner-scoped cache before restoring entitlements and realtime. Watch workout handoff now uses a durable per-launch causal identifier, so stop-before-start, delayed stop, disconnect, and direct A → B transitions cannot create or terminate the wrong owner's session. Independent adversarial review found and closed late Watch launch, cached OAuth, notification-delivery, and camera-dismissal races. The final dedicated APEX-lane suite passed 351/351 with no failures or skips; all 60 changed Swift files parsed and `git diff --check` passed. These source/unit results are supporting evidence only and do not promote acceptance-matrix rows that still require runtime or human-discoverability proof.

## Task 3 — Make subscriber goal and energy math total

1. Define one canonical persisted goal vocabulary shared by native and web clients.
2. Require every accepted onboarding goal to resolve to a complete set of calorie presets.
3. Verify Mifflin-St Jeor fallback, measured resting-energy evidence, activity factors, safe goal deltas, macro constraints, and explicit provenance.
4. Keep exercise energy informational unless an explicit, bounded compensation policy is selected; never silently add all burned calories to the eating target.
5. Run male, female, older-adult, high-BMI, low-activity, measured-BMR, and bespoke-plan fixtures through every preset.

## Task 4 — Guarantee onboarding and entitlement escape paths

1. A user who declines consent can leave setup or sign out without supplying health data.
2. A mandatory paywall always offers truthful purchase/restore behavior plus account recovery or logout.
3. Failed, cancelled, offline, or unavailable purchases never trap the account.
4. Required questionnaire answers remain concise, understandable, and impossible to skip accidentally.

## Task 5 — Repair policy-aware creation and editing

1. Coach-sponsored restrictions apply consistently to Simple, Advanced, Settings, Avatar, and workout creation.
2. Custom workout creation reports success only after persistence succeeds.
3. Complete the promised custom-workout lifecycle: create, reopen prefilled, edit, replace deliberately, and delete with confirmation.
4. Emptying an existing meal presents explicit delete semantics and persists the result instead of masquerading as a normal save.

## Task 6 — Preserve dates, attribution, and deletion invariants

1. Historical guided, tracked, and wearable-linked workouts retain the selected completion date.
2. Generated activity records link stably to their workout receipt.
3. Deleting a workout removes or recomputes only its generated contribution, without deleting the original Apple Health workout.
4. Nutrition, Finished Workouts, calendar, progression, and Avatar resolve the same canonical record once.

## Task 7 — Resolve high-impact functional inconsistencies

1. Recovery-plan replacement excludes rows it is about to deactivate.
2. Captured progress weight and “Include stats” affect the saved/exported result exactly as labelled.
3. Persisted profile avatars render after reopening and relaunching.
4. Marathon full and minimum-effective sessions generate meaningfully different prescriptions.
5. Invalid measured-BMR input cannot silently erase valid evidence.
6. Avatar snapshot synchronization detects component changes even when the rounded overall score is unchanged.
7. Remove duplicate settings and dead-end routes or make their behavior truthful.

## Task 8 — Deep integrated verification and release

1. Add focused UI journeys for the repaired behaviors and finish uncovered flow-matrix rows.
2. Run native unit/integration/UI, Watch, HealthKit, complication, localization, retention, web, and build checks.
3. Inspect screenshots at standard and large Dynamic Type with Reduce Motion and accessibility labels.
4. Append final evidence and remaining known limitations to `REPAIR-NOTES` and the audit report.
5. Commit, push both required refs, verify GitHub Pages and the live URL, then wait for a safe owner-approved window before physical Watch installation.
