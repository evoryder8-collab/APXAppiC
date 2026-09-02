# APEX iOS Client Reliability Audit

Date: 2026-09-02
Status: in progress
Simulator lane: `APEX Lane · iPhone 17 Pro` (`6907359A-18D1-46B0-87F1-13CED5CE1C46`)

## Scope and evidence standard

This audit treats a screen appearing without a crash as insufficient evidence. Each flow must prove, where applicable:

1. the control performs the action its label promises;
2. the resulting data belongs to the active account and selected date;
3. the change survives dismissal, relaunch, and synchronization;
4. derived nutrition, training, recovery, and Avatar values consume the intended fact exactly once;
5. restricted clients receive an explicit explanation instead of a silent no-op;
6. incomplete, denied, offline, malformed, or legacy data fails safely;
7. a visible success state is backed by a completed mutation rather than an optimistic dismissal;
8. content remains readable without clipping, misleading defaults, or invented precision.

The working flow matrix is maintained in `.planning/WALKTHROUGH.md`. Automated UI evidence is retained under `build/apex-client-audit/`.

## Baseline execution

The complete native UI suite was run against the dedicated APEX simulator lane only.

- Initial run: 29 passed, 1 failed.
- Failure: the test attempted to tap the upper clipped quarter of the expanded Fitness Plan disclosure after scrolling.
- Product state at failure: the disclosure was correctly expanded and visible below the safe interaction boundary.
- Test repair: visibility now uses the actual scroll viewport top instead of a hard-coded screen coordinate.
- Focused rerun: 1 passed, 0 failed.
- Final clean rerun: 30 passed, 0 failed, 0 skipped on `APEX Lane · iPhone 17 Pro` (iOS 26.5); test execution time was 1,165.655 seconds.
- Effective baseline: 30/30 smoke UI-test methods pass. This is partial regression evidence, not completion of the Task 1 flow matrix.

Result bundles:

- `build/apex-client-audit/APEXUI-baseline.xcresult`
- `build/apex-client-audit/APEXUI-portal-rerun.xcresult`
- `build/apex-client-audit/APEXUI-task1-final.xcresult`

The retained screenshots show a readable target-energy sheet, Nutrition dayline, Avatar/Visual Progress hierarchy, and weekly joint check without visible clipping in those exercised states.

### Baseline diagnostics retained for repair work

- `testFivePortalNavigationAndCoreScreens` spent about 251 seconds in repeated scroll attempts around an already-present but non-hittable element. The final assertion passed, so this is a harness-efficiency problem rather than a product-flow verdict. The result summary also marks one outlier-duration run.
- Xcode emitted a `DebuggerLLDB.DebuggerVersionStore.StoreError` launch warning because no debugger version was available. All 30 tests still launched and completed; this is retained as test-infrastructure evidence rather than hidden.
- Compilation emitted actor-isolation warnings in `ProfileAvatarPicker.swift` and `VisualProgressView.swift`, plus ineffective `nonisolated(unsafe)` warnings in `ProgressCameraView.swift`. They are recorded for the appropriate implementation task; Task 1 intentionally changes no product behavior.

## Task 1 acceptance-matrix evidence

The acceptance matrix is maintained in `.planning/WALKTHROUGH.md`. It now binds every pending runtime case to a deterministic persona, active owner, selected date, precondition/actions/destination, mutation/reopen/downstream assertion, negative branch, screenshot/result-bundle artifact, automated evidence, and human-discoverability evidence. The matrix adds focused pending subflows for authentication/legal exits, onboarding failure atomicity, delayed private-food search, Avatar account-boundary races, progress-photo permission/ownership, interrupted Orbit/account switching, account-generation mutations, Health/camera/location denial, and a true unseeded launch.

Two evidence lanes are mandatory:

1. **Automated/runtime:** destination assertions, owner/date/persistence/downstream effects, result bundle, and screenshots.
2. **Human/discoverability:** a 1–5 certainty rating, return-destination check, and hesitation note for onboarding, nutrition logging, custom-workout lifecycle, and Avatar/recovery/progress/Orbit journeys.

The current `APEXSmokeUITests` source has 30 methods. It provides partial fixture/preview coverage for selected onboarding, portal, nutrition, hydration, calendar, player/receipt, Avatar/calibration/recovery, settings-layout, and sync-issue paths. It does not establish real authentication, account switching, coach/client publication, location-backed Orbit, system-permission denial, adaptive accessibility, or a no-seed fresh-install journey. Related unit tests remain supporting logic evidence, not UI-flow or discoverability proof.

### Task 1 Layer 1 static navigation findings

The following are static source-review findings, kept separate from runtime observations. No flow is marked passed on the basis of these findings.

1. **P1 · NO-EDIT-PATH — saved custom workouts cannot reopen in an editable builder.** A saved day routes to read/start-only `WorkoutDayView`; the builder creates blank workouts only. Missing arrow: saved custom day → editable builder → explicit Save changes/Delete. This blocks the required F10 lifecycle and constrains F17 recovery customization.
2. **P1 · ORPHANS-ENTITY — coach-restricted custom-workout creation discards a draft and opens a lock after rejected save.** The authoring control is not capability-gated; the rejected mutation is followed by success/dismissal UI. Missing arrow: capability check before authoring, or confirmed persisted save → Custom Workouts. This affects F10/F21.
3. **P1 · ORPHANS-ENTITY — “Build a workout” can silently replace a saved same-weekday workout.** Saving reuses its day ID and deletes prior exercise rows without an applicable replacement warning. Missing arrow: fresh day/date, or explicit replacement confirmation → intentional update. This affects F10.
4. **P2 · DEAD-END — Orbit Home recent-run rows show a chevron but do not navigate.** The corresponding Library rows open historical debrief; Home rows are inert. Missing arrow: Orbit Home recent run → historical debrief. This affects F19 and its discoverability pass.
5. **P2 · NESTED-NAV — historical Orbit debrief is pushed inside its own navigation stack.** A Library link pushes a wrapper whose debrief view owns another stack, risking a second navigation bar and an incorrect Back path. This affects F19 history/reopen assertions.

## Confirmed defects

### P0 — noncanonical native onboarding goal can crash the web client

Native onboarding accepts and persists `general`. The web nutrition context expects `rebuild`, `muscle`, `fat_loss`, `strength`, or `endurance`. The plan-preset switch is not total and a caller immediately invokes `.find` on the potentially undefined result. A standard subscriber who finishes native onboarding can therefore load a record that breaks global web target computation.

Required repair:

- canonicalize new native writes;
- tolerate legacy aliases at every read boundary;
- make goal and plan-week normalization total;
- backfill aliases only after tolerant clients ship;
- prove native-to-web and web-to-native parity with malformed legacy inputs.

### P0 — interrupted Orbit state crosses an account boundary

The Orbit location manager is a singleton with an in-memory draft owner and recoverable state. The account-boundary reset does not detach that singleton. A second account can encounter the previous account's interrupted run, and continuing it risks saving under the wrong active owner.

Required repair:

- stop active timing/location work at the boundary;
- clear in-memory ownership and samples without deleting the previous owner's persisted draft;
- expose recoverability only for the requested owner;
- restore the original owner's draft after switching back;
- prove that account B cannot see, continue, cancel, or save account A's run.

### P0 — Avatar synergy state can survive account switching

The account boundary does not clear the published brain-synergy collection. Recalculation exits early when the new account has no usable profile/input, leaving the previous account's results visible.

Required repair:

- clear derived brain state synchronously at every account boundary;
- make every early-return path publish an honest empty state;
- generation-gate late computation results;
- prove a profileless account never inherits another account's Avatar evidence.

### P0 — late asynchronous mutations can land after an account switch

Profile-image uploads, coach invitation/scope mutations, and progress-photo uploads do not consistently capture both owner and account generation. A request started by account A can complete after account B becomes active.

Required repair:

- capture owner and generation at mutation start;
- reject late success and failure completions after a boundary;
- keep remote object paths owner-scoped;
- prove UI state and persisted metadata cannot cross accounts.

### P0 — a delayed food search can return another account's private food

Native Food Memory captures local results before awaiting the public provider. Those local rows are not filtered by `Food.ownerUserID`, and the continuation does not verify the active owner and account generation before returning them. If account A searches and account B becomes active during the await, B can receive A's private food result.

Required repair:

- filter private foods to the captured owner while retaining global rows;
- validate both owner and generation after every search await and on the offline-error path;
- never cache or render a stale search completion;
- prove account A's private food cannot appear for account B under success, failure, or cancellation timing.

### P1 — adult calorie prescriptions are offered to under-19 users

The questionnaire permits age 13, then applies adult Mifflin/Katch logic, adult protein rules, and aggressive fat-loss factors. The existing `BMR × 1.05` lower bound is labelled as a safety floor even though it is not a universal evidence-based safety threshold.

Required repair:

- fail closed from automated deficit prescriptions outside the validated adult scope;
- collect relevant life-stage state before automated targets;
- explain why professional guidance is required instead of inventing a number;
- rename or remove the unsupported safety claim.

### P1 — minimum macros can exceed the displayed calorie target

At sufficiently low targets, fixed protein and fat minima can consume more energy than the displayed daily target. Carbohydrate is clamped to zero but the contradiction remains visible as if it were a valid prescription.

Required repair:

- define a single cross-client macro-energy invariant;
- detect infeasible targets before presentation;
- never display macro grams whose energy exceeds the stated target outside rounding tolerance;
- provide an honest review state rather than silently reducing an essential minimum.

### P1 — wearable energy mode changes when any activity row appears

Visible wearable active energy is ignored in quick mode until at least one activity log exists. Adding even a zero-energy row changes the engine to precise mode and can cause a large target jump unrelated to new physiological evidence.

Required repair:

- choose quick versus precise mode from the availability and quality of wearable/activity evidence, not mere row presence;
- retain the existing no-eat-back and no-double-counting behavior;
- prove adding or deleting a zero-energy row cannot move the target.

### P1 — onboarding completion is not atomic and repair is lossy

Settings, plan rows, profile, and evidence are written in separate operations. A partial failure can leave a committed plan with missing entered body facts. Repair retains the goal but can substitute schema defaults for weight, height, sex, birth date, and activity. Existing standard profiles can also ignore newly entered facts.

Required repair:

- use one authenticated idempotent server transaction;
- retain the complete pending payload until commit;
- merge explicitly entered fields for standard accounts;
- preserve protected bespoke accounts;
- inject a failure after every write boundary and prove retry produces exactly one coherent plan.

### P1 — a fresh subscriber inherits Constantine-specific identity and baselines

The default persona and parts of Avatar history are Constantine-specific. A standard subscriber can therefore receive another person's identity framing and hard-coded starting scores rather than a neutral self identity grounded in their evidence.

Required repair:

- reserve bespoke identities and authored histories for their owners;
- introduce a neutral standard-client baseline;
- derive only the dimensions supported by onboarding or connected evidence;
- label uncertainty rather than presenting unsupported precision.

### P1 — coach-restricted creation can report a false save

The custom-workout builder can dismiss and report success while the underlying session mutation silently returns because training is coach-managed.

Required repair:

- disable the action before submission with a clear lock explanation;
- return a typed failure from the mutation layer;
- dismiss only after confirmed persistence;
- exercise standard, sponsored, coach-managed, and bespoke policies.

### P1 — historical workout completion can write to today

Starting or completing a workout from a historical calendar selection can generate completion/activity facts for the current day instead of the viewed/authored day.

Required repair:

- carry the intended session date through player, receipt, activity, wearable association, and calendar reconciliation;
- prove today, past, timezone boundary, and off-schedule completion behavior.

### P1 — deleting a workout can leave derived energy behind

A workout receipt and its separately generated activity-energy row do not share a durable deletion identity. Removing the workout can leave calories contributing to daily energy and Avatar calculations.

Required repair:

- attach derived activity to the source receipt with a stable owner-scoped identity;
- delete or reconcile only the matching derived row;
- preserve unrelated activity and external HealthKit energy;
- prove no double-counting before and after delete/restore/hide actions.

## Additional integrity findings queued for repair

- Mandatory paywall has no clear close/sign-out route and its purchase control does not complete a purchase flow.
- Declining legal consent can trap the user; the alert's Review action is a no-op despite its promise.
- Custom workouts do not yet provide the full reopen/edit/delete lifecycle implied by the interface.
- Emptying an existing meal persists as a deletion but the label and lack of confirmation make the action ambiguous.
- Notification/nudge read state and identifiers need explicit owner scoping.
- Simple Home exposes training actions that bypass coach restrictions enforced elsewhere.
- Recovery replacement can schedule against rows it deactivates.
- Progress-photo capture options are not consistently preserved and rendered after relaunch.
- Manual-workout copy promises a reusable preset without a route to create one.
- Invalid measured-BMR input can silently clear an existing value.
- An Avatar snapshot with the same day and overall score can ignore changed component scores.
- Native and web weekly calorie calibration use different cadence guards.
- Selected available-session time does not materially constrain generated plan content.
- Goal selection changes some labels and nutrition factors more than the actual exercise prescription, overstating personalization.

## Verified positive behavior so far

- Guided-workout drafts are owner, date, and plan-day scoped.
- Imported HealthKit workout deduplication has explicit owner and identity tests.
- Existing wearable-energy logic avoids directly adding the same external workout calories twice.
- Baseline movement answers visibly affect the supported Avatar capacity dimensions in native calculations.
- DEXA report RMR is currently stored as non-authoritative evidence rather than silently overriding BMR; the misleading copy and lack of a verified-promotion path still require correction.
- The first-run UI requires core consent/body/goal data before plan creation and exposes a return path for accounts without a completed plan.

## Reproduced user-path regression

The focused strawberry flow reached Food Memory, selected **Strawberries, fresh**, opened the circled information control, and rendered only calories plus total fat, carbs, and protein. No Vitamins or Minerals section was present. The lower-level bundle test had passed because it constructed the canonical ID/provider fingerprint directly; the UI fixture used a random ID and `ui_fixture` source, so it never exercised the deployed overlay. The regression now requires a real canonical search result and asserts visible Vitamin C and Iron before it can pass.

## Completion gate

This audit is not complete until every flow in the matrix is classified as passed, repaired, intentionally deferred with an owner-facing roadmap item, or blocked by a named external dependency. Each implemented repair must have a red-green regression, native/web parity where shared, account/date/offline coverage where applicable, and a focused simulator walkthrough. Physical iPhone/Watch installation is intentionally deferred while the owner is asleep.
