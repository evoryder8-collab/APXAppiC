# Repair notes — running state

Append to this file after every task. Read it after any compaction to re-orient.
Never re-read source code to remember where you were.

Format: date · task · files changed · commit SHA · tests run · result · next.

---

## Seeded at handoff — 2026-08-22

**Branch:** `codex/main-critical-repair` · **HEAD:** `c1b0e77` · 7 commits ahead of `main`.

**Landed:**
- `9f6c34e` sync hardening — meal-kind normalisation, settings rebound to authenticated user,
  4xx quarantined instead of jamming the offline queue
- `d92a591` meal-edit fix — `clientIdempotencyKey` now computed, differs on reopen, plus
  `replaceMealID`, so edits are no longer swallowed by the RPC short-circuit
- `fb29aee` dayline duplicate time labels removed
- `0306f5a`, `21e9504` docs — beta access and StoreKit plan (`docs/plans/`)
- `130d861` workout receipt preserved, UI coverage
- `c1b0e77` rest-day truth — `SessionBriefing`, `TrainingPlanEngine`, `MuscleMapView`,
  `TrainingProgramView` + parity tests

**Uncommitted, in progress — finish, do not restart:**
- `ios/APEXNative/APEX/Core/Engine/ManualWorkout.swift` — `var rir: Int?` on `SetDraft`, clamped 0–5
- `ios/APEXNative/APEX/Core/Models/APEXModels.swift` — `enum WorkoutSessionMode` with
  `resolve(lastUsed:dayDefault:)`, `sessionMode` mapped to `session_mode`
- `ios/APEXNative/APEXTests/ManualAndInductionTests.swift` — tests for both

**Verified still broken at handoff:**
- RIR fabricated at both capture points: `TrainingProgramView.swift:1424`
  (`rir: skipped ? nil : 2`) and `AppSession.swift:1605` (`rir: 2`)
- `session_mode` referenced in exactly one Swift file (the model). Nothing reads it.
- No `"skip"` string anywhere in `Features/Onboarding`
- `TrainingInductionPanel` gated on `newbie_mode`, so it hides from the advanced users who need it
- Web `21000` (supplements) and `23503` (`food_preferences`) firing in production
- Test meal "Codex server signoff" still in the Breakfast slot of the live account

**Traps — do not rediscover these the hard way:**
- `log_structured_meal` (migration 009) is CREATE-ONLY. It short-circuits on a known
  `client_idempotency_key` and returns before any replace or insert.
- `SyncFailurePolicy` treats all 4xx as permanent except 408/425/429, so a **401 from an expired
  JWT quarantines and discards the write**. 401 should refresh and retry.
- `LazyVStack` has bitten this codebase twice: on the training month grid and on the nutrition page,
  a lazy stack never materialised the cards below the fold, so content was literally unreachable by
  scrolling. Both were fixed by making those stacks eager. Check this before adding a third.
- Cancelled tasks were surfacing `Swift.CancellationError` to users as an alarming error. Cancel
  stale work deliberately, but never show that error.

**Trial: DECIDED, do not re-ask.** No free trial during beta. `Entitlement.trialDays` and the
"7 days free" paywall copy are stale and must be removed. Hard gate immediately after sign-up;
only founding accounts, a redeemed beta code, or a verified StoreKit entitlement pass.

**Entitlement is device-wide today — that is a security defect.** A redeemed code currently unlocks
the device, not the account, so one family member's code can unlock a different account on the same
iPhone. Make it account-scoped and server-authoritative.

**Six audit fixes are stranded on frozen `909cd63`** and are NOT on this branch: realtime filtering,
web supplement dedup, food_preferences repair, `020_restrict_rls_auto_enable.sql`, and two Orbit
items. See the STRANDED WORK table in docs/ROADMAP.md. Port from that commit, do not rewrite.

**Next:** Phase 1.1 — honest RIR.
## 2026-08-22 — Task 1: Recover stranded audit fixes

### Files changed

- `ios/APEXNative/APEX/App/AppSession.swift`
- `ios/APEXNative/APEX/Core/Networking/SupabaseService.swift`
- `ios/APEXNative/APEX/Features/Orbit/OrbitIntegrations.swift`
- `ios/APEXNative/APEXTests/OrbitIntegrationsTests.swift`
- `ios/APEXNative/APEXTests/OrbitPrivacyArchiveTests.swift`
- `src/lib/foodSync.ts`
- `src/lib/sync.ts`
- `src/store/AppStore.tsx`
- `src/store/FoodStore.tsx`
- `supabase/migrations/020_restrict_rls_auto_enable.sql`
- `tests/food-sync.test.ts`
- `tests/persistence.test.ts`
- `tests/rls-auto-enable-schema.test.ts`
- `tests/sync.test.ts`

### Commits

- `be739db3036a9caa3dd6e6df7b333a2868f47f25` — port the six sound safeguards from frozen audit commit `909cd63ce7ccfef642094a49639116e2ff3dd876`.
- `0393d4265f0996cef3b8f0886865869258314027` — retain preferences until a narrow server response proves a stale `food_id` reference.

### Tests added and verification

- Realtime subscription coverage verifies every private-table channel carries the authenticated `user_id` filter and shared tables are not subscribed.
- Supplement sync coverage verifies duplicate batch rows collapse by `(user_id, date, supplement_id)` before optimistic state and outbound queueing.
- Food preference coverage verifies incomplete local food snapshots retain preferences, and only the classified foreign-key failure prunes and acknowledges a stale reference.
- Migration coverage verifies `020_restrict_rls_auto_enable.sql` revokes `public`, `anon`, and `authenticated` execute access and grants none back.
- Orbit nutrition coverage verifies meal-draft construction and the no-food guard; production inspection confirms consumed totals and the adjustment timestamp change only after meal persistence succeeds.
- Orbit activity coverage verifies reconciliation replaces only the deterministic Orbit-generated activity row while preserving distinct manual/watch rows.
- Focused web regression run: 26 passed, 0 failed.
- Complete web suite: 425 passed, 0 failed.
- Production web build: passed; only the existing Vite large-chunk advisory.
- Focused native Task 1 run: 9 passed, 0 failed.
- Exact clean committed-tree native unit target: 289 passed, 0 failed, with no exclusions. This includes the three TrainingPlanParity tests that fail only when the protected uncommitted Phase 1.1 session-mode changes are present.
- Scoped re-review: both Important findings addressed; no new Critical or Important breakage.

### Installed build and publication

- Built, installed, and launched `0393d4265f0996cef3b8f0886865869258314027` on connected iPhone `iConstantine Main` (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`), bundle `ch.apexperformance.APEX`, process ID `1068`; device build reported 0 errors.
- GitHub branch publication: `origin/codex/main-critical-repair` points to `0393d4265f0996cef3b8f0886865869258314027` before this notes-only commit.
- GitHub Pages workflow run `32562027911` built and deployed that exact SHA successfully.
- Live URL: `https://evoryder8-collab.github.io/APXAppiC/` (HTTP 200 verified; deployed content timestamp `2026-08-22T08:21:10Z`).
- The Pages environment was temporarily permitted to deploy this repair branch, then restored to its original `main`-only custom branch policy.

### Preserved work / next task

- Restored the three pre-existing Phase 1.1 RIR/session-mode files byte-for-byte after exact-tree verification. Their diff SHA-256 remains `ad9cc28c07cc338f79ae34fb94df240154e774f9d16e6a3b2133ae87123373a5`.
- Next: Phase 1.1, honest RIR; finish the existing work in `ManualWorkout.swift`, `APEXModels.swift`, and `ManualAndInductionTests.swift` without restarting it.

## 2026-08-22 — Task 2 / Phase 1.1: honest RIR

Status: implementation and verification complete.

Implementation commits:

- `54b93a44dc8aff56ce497e72bb14ab146b9b2143` — record only explicitly reported workout effort in native manual/guided logging and web guided logging; make progression require every performed top-range set to report RIR >= 2.
- `024de5b0b85a328da5d5d28564e0bea25f826c5f` — independent-review correction that preserves web guided RIR per set instead of copying one report across the exercise.

Files changed:

- `ios/APEXNative/APEX/Core/AppSession.swift`
- `ios/APEXNative/APEX/Core/Models/ManualWorkout.swift`
- `ios/APEXNative/APEX/Core/Engine/ProgressionEngine.swift`
- `ios/APEXNative/APEX/Features/Training/ManualWorkoutLoggerView.swift`
- `ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift`
- `ios/APEXNative/APEXTests/ManualAndInductionTests.swift`
- `ios/APEXNative/APEXTests/ProgressionEngineTests.swift`
- `src/lib/progression.ts`
- `src/lib/workoutSession.ts`
- `src/pages/Player.tsx`
- `tests/follow-along-session.test.ts`
- `tests/player-runtime.test.ts`
- `tests/strength-progress.test.ts`

Tests added or strengthened:

- Native contracts prove RIR begins unreported, survives manual load/edit/save as an optional value, can be cleared, and only explicit RIR >= 2 permits progression after all performed top-range sets.
- Web contracts prove guided RIR begins unreported, can be cleared, serializes per set, preserves `[2, null]`, and treats the missing report as progression-blocking.
- Independent review found one Critical scalar-to-all-sets persistence defect; the fix was re-reviewed with all findings addressed and no new Critical/Important breakage.

Final exact-HEAD verification at `024de5b0b85a328da5d5d28564e0bea25f826c5f`:

- Focused web RIR/session/progression: 29 passed, 0 failed.
- Full web suite: 428 passed, 0 failed.
- Production web build: passed (`tsc --noEmit` plus Vite).
- Full native APEXTests: 296 passed, 0 failed, 0 skipped in 118.5 seconds.
- Native result bundle: `~/Library/Developer/XcodeBuildMCP/workspaces/APXAppiC-codex-main-repair-5a1504548845/result-bundles/test_sim_2026-08-22T08-58-31-018Z_pid45079_90be1e49.xcresult`.

Connected-iPhone evidence:

- Built, installed, and launched clean implementation SHA `024de5b0b85a328da5d5d28564e0bea25f826c5f` on `iConstantine Main` (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`).
- Bundle `ch.apexperformance.APEX`, launch PID `1251`, device build completed in 116.4 seconds from `/tmp/apex-task2-024de5b-device-derived`.

Protected next-task state:

- The two pre-existing Task 3 session-mode hunks were restored after the exact build: 17 model lines and 15 test lines. Their added-line payload hash matches the safety stash (`7fc10597542dd76e1bb0b7ba1e4c97c0ecd687d732afbb75d1f2eebd244422f8`).
- The unrelated historical stash `8e81a00288844b3b18151541419699e1e7c0821f` remains untouched.

## 2026-08-22 — Task 3 / Phase 1.2: equal guided and tracked session modes

Status: implementation, review, exact verification, and connected-iPhone install complete.

Implementation commits:

- `f0672d5ca664ed7898f5ca10f515347331e5d4c0` — preserve the in-progress native mode model/test, decode legacy days safely, add equal guided/tracked starts, a native planned-session tracker, remembered account-scoped device choice, and authored custom-day defaults.
- `600cfba307475e6e32056207947db5ab2ad00111` — make tracked facts explicit: nil actuals until entry, load/work controls, finish gating, timed units, compact RIR, and defensive skipped-log normalization.
- `eac679f` — add practical direct numeric entry and faithful equal/ranged prescription labels.
- `e04383a61b16cf6d66de4bb699d8627de4d6ae3b` — preserve authored MAX and CHECK modes without fabricated reps or RIR. This is the exact implementation SHA installed on the iPhone.

Files changed:

- `ios/APEXNative/APEX/App/AppSession.swift`
- `ios/APEXNative/APEX/Core/Models/APEXModels.swift`
- `ios/APEXNative/APEX/Features/Training/CustomWorkoutBuilder.swift`
- `ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift`
- `ios/APEXNative/APEX/Features/Training/WorkoutDaySheet.swift`
- `ios/APEXNative/APEXTests/ManualAndInductionTests.swift`

Behavior delivered:

- Both native planned-session start surfaces visibly offer guided and tracked modes; the remembered valid choice overrides the authored day default, invalid/missing values fall back safely, and choosing a mode never rewrites plan data.
- Guided opens the existing paced player. Tracked opens a planned-set list, not the unplanned manual logger, and both finish through `AppSession.completeWorkout(day:setInputs:lite:startedAt:)`.
- Custom days persist `session_mode`; legacy rows without it decode as guided.
- Tracked work records distinct optional per-set load, actual reps/seconds/minutes, explicit skips, and optional rep-based RIR. Nothing is recorded as performed until the person reports it.
- Skipped logs defensively clear weight, work, and RIR at the shared persistence boundary.
- MAX requires actual counted work, permits applicable load, and exposes no RIR. CHECK requires an explicit Completed/Skipped choice and persists no invented measurement.
- Direct number/decimal entry supports clearing back to nil and decimal commas; plan copy preserves exact or ranged authored targets.

Tests added:

- 13 native tests cover precedence, legacy decode/round-trip, both routes, custom defaults, explicit per-set facts, load entry, parsing/clearing, skip normalization, timed units, prescription ranges, MAX, and CHECK readiness/persistence.
- Existing web parity proves session mode is not inferred from induction answers, both modes write identical history, and last choice wins.

Final exact-HEAD output at `e04383a61b16cf6d66de4bb699d8627de4d6ae3b`:

- Focused native: 12 passed, 0 failed, 0 skipped.
- Full native APEXTests: 309 passed, 0 failed, 0 skipped.
- Focused web session-mode parity: 17 passed, 0 failed.
- Full web suite: 428 passed, 0 failed.
- Production web build: passed (`tsc --noEmit` plus Vite; existing chunk-size advisory only).
- Independent spec/code reviews: clean, with 0 Critical/Important findings open after three fix rounds.
- Native result bundle: `~/Library/Developer/XcodeBuildMCP/workspaces/APXAppiC-codex-main-repair-5a1504548845/result-bundles/test_sim_2026-08-22T09-54-02-215Z_pid45079_52ab40c9.xcresult`.

Connected-iPhone evidence:

- Built and installed exact clean SHA `e04383a61b16cf6d66de4bb699d8627de4d6ae3b` from `/tmp/apex-task3-e04383a-device-derived` on `iConstantine Main` (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`).
- Bundle `ch.apexperformance.APEX`; direct launch of the installed bundle succeeded as PID `1607` after the initially locked phone accepted a retry.

Concurrent unrelated work:

- Commit `73b244d04c500ee92551d8be6f72a2398d6cc122` appeared mid-task with 106 unrelated roadmap lines. It was preserved at local pointer `codex/preserve-reporting-layer-73b244d` and excluded from this task branch without reset or content loss.
- Historical stash `8e81a00288844b3b18151541419699e1e7c0821f` remains untouched.

## 2026-08-22 — Task 4 / Phase 1.3: honest workout-calendar states

Status: implementation, rejection review, exact verification, and connected-iPhone install complete. GitHub publication and Pages verification follow this local checkpoint.

Implementation commit:

- `46e7ea6824d65dce9a128793f93eaffed920bcb7` — resolve calendar days from authored and recorded facts instead of treating a missing programme day as Rest.

Files changed:

- `ios/APEXNative/APEX/Core/Engine/TrainingCalendarDay.swift`
- `ios/APEXNative/APEX/Core/Engine/TrainingPlanEngine.swift`
- `ios/APEXNative/APEX/Features/Training/TrainingCalendarView.swift`
- `ios/APEXNative/APEX/Features/Training/WorkoutDaySheet.swift`
- `ios/APEXNative/APEXTests/TrainingCalendarDayTests.swift`
- `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`
- `ios/APEXNative/APEXNative.xcodeproj/project.pbxproj`

Behavior delivered:

- Calendar dates now resolve account-scoped, slug-scoped and deterministic scheduled, Rest, deload, completed, partially completed, missed, manually logged, custom-workout, and no-prescription states.
- Missing, stale, malformed or out-of-window programme data says `No workout prescribed`; only an authored Rest day or a valid sparse induction gap says Rest.
- Partial means a real start or workout log exists. An untouched incomplete row remains scheduled.
- Recorded sessions retain their own authored `programDayID` when completed off schedule; the date's prescription is only a fallback.
- Programmes, days, exercises, events, sessions, logs, deload marks, water and imported-activity indicators are scoped to the active account before display.
- The calendar uses readable `PLAN`/`MISS`/`NONE` state codes, distinct symbols, non-color accessibility labels, deterministic duplicate-weekday ordering, and a state legend.
- The day sheet no longer falls back from nil to Rest. Honest no-prescription and Rest explanations are visually distinct, recorded partial/manual/custom sessions reopen their actual receipt, and repeated empty-state headings were removed after device-scale screenshot review.

Tests added:

- Nine native resolver tests cover all nine states, untouched-versus-started partials, completed deload metadata, manual/custom records, valid sparse induction Rest, malformed induction boundaries, account/slug isolation, deterministic duplicate weekdays, and off-schedule recorded-day identity.
- One XCUITest scrolls to the native calendar, verifies today's cell announces Scheduled, verifies tomorrow announces No prescription, opens the date, proves the honest explanation is present and `Rest day` is absent, and captures both calendar and sheet frames.
- Red/green evidence: missing resolver initially failed to compile; malformed induction boundary failed before boundary validation; off-schedule identity failed before recorded-day-first resolution. Each focused regression passed after its scoped fix.

Final verification for implementation SHA `46e7ea6824d65dce9a128793f93eaffed920bcb7`:

- Full native `APEXTests`: 318 passed, 0 failed, 0 skipped on iPhone 17 Pro simulator, iOS 26.5.
- Native result bundle: `/tmp/apex-task4-derived-data-20260822/codex-task4-full/Logs/Test/Test-APEX-2026.08.22_13-43-44-+0200.xcresult`.
- Focused native calendar XCUITest: 1 passed, 0 failed, 0 skipped.
- UI result bundle: `/tmp/apex-task4-derived-data-20260822/codex-task4-ui/Logs/Test/Test-APEX-2026.08.22_13-44-11-+0200.xcresult`.
- Full web suite: 428 passed, 0 failed, 0 skipped.
- Production web build: passed (`tsc --noEmit` plus Vite; 1,166 modules transformed; existing chunk-size advisory only).
- `git diff --check`: clean before commit.

Connected-iPhone evidence:

- Clean SHA `46e7ea6824d65dce9a128793f93eaffed920bcb7` built and signed from `/tmp/apex-task4-46e7ea6-device-derived`; `** BUILD SUCCEEDED **`.
- Installed bundle `ch.apexperformance.APEX` on paired `iConstantine Main` (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`), physical iPhone 15 Pro Max.
- Installed container `CCFCF256-EBE7-4A4D-835C-5DBCEE91B88F`; direct launch succeeded and the device process table confirmed PID `2129`.

GitHub publication evidence:

- Repair branch through notes SHA `7437f9262d4a149eb5f5e8051397393971a56d02` pushed to `origin/codex/main-critical-repair`.
- Normal two-parent main merge `02f4b69956b70893234a89e45ed22475348002c4` pushed to `origin/main`; its tree exactly matched the verified repair branch.
- Pages workflow run `32571440488` completed both build and deploy jobs successfully for that exact main SHA.
- Pages remains workflow-backed from `main`; `https://evoryder8-collab.github.io/APXAppiC/` returned HTTP 200 after deployment.

## 2026-08-23 — Task 5 / Phase 1.4: skippable induction with a working plan B

- **Status:** complete — implementation, rejection review, tests, exact-SHA iPhone installation, GitHub publication, Pages deployment, HTTP smoke check, and authenticated shared-record round trip all verified.
- **Implementation commit:** `711490608dbfc6bbfd8e4a511a2f132069461b3b` (`feat: make induction skippable and recoverable`).
- **Scope:** 42 files changed, 3,673 insertions, 359 deletions. Native changes cover `AppSession`, induction/plan/progression engines, Supabase ownership and sync, onboarding, Simple Home, settings, training surfaces, and their unit/UI tests. Web changes cover induction/plan generation, persistence/seed repair/sync, account ownership, workout surfaces, and their tests. Shared cross-client revision fixture: `tests/fixtures/training-induction-revision.json`.
- **Behavior verified:** induction can be skipped without fabricating a profile, facts, or plan; the server-backed account marker survives hydration and restore; no-plan accounts can return to the builder with persisted 2–5-session, location, equipment, and pain answers; generated plans install as a versioned overlay without destroying authored/history rows; revised progression stays within the same account; native/web profileless plan completion uses a verified account owner; grouped web sync preserves transaction and same-record ordering; stale native installs/restores cannot cross an account switch; legacy Constantine metadata is migrated only when explicit; incomplete generated plans never expose runnable days.
- **Tests added:** 40 native unit regressions, 16 web regressions, two focused XCUITests, and one shared native/web UUID revision fixture.
- **Test output:** `npm test` — 444 passed, 0 failed; `npm run build` — TypeScript and Vite build passed (1,166 modules; existing chunk-size advisory only); `APEXTests` — 358 passed, 0 failed, 0 skipped; focused `APEXUITests` — 2 passed, 0 failed (`testInductionOffersSkipAndNoPlanAccountCanReturnToTheBuilder`, `testIncompleteGeneratedPlanCannotExposeARunnableDay`); `git diff --check` — clean.
- **Result bundles:** `~/Library/Developer/XcodeBuildMCP/workspaces/APXAppiC-codex-main-repair-5a1504548845/result-bundles/test_sim_2026-08-23T06-06-38-182Z_pid45079_aff7947b.xcresult` (unit) and `~/Library/Developer/XcodeBuildMCP/workspaces/APXAppiC-codex-main-repair-5a1504548845/result-bundles/test_sim_2026-08-23T06-07-11-281Z_pid45079_f2d64874.xcresult` (UI).
- **Review:** final rejection review reported no Critical or Important findings; reviewer independently confirmed the TypeScript compile and all 444 web tests.
- **Physical device:** exact `711490608dbfc6bbfd8e4a511a2f132069461b3b` built and signed successfully from `/tmp/apex-task5-7114906-device-derived/Build/Products/Debug-iphoneos/APEX.app`, then installed on connected `iConstantine Main` (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`) as `ch.apexperformance.APEX`; installation database sequence `5316`. Automatic launch was attempted and was rejected only because iOS reported the device locked.
- **Publication:** repair branch and `origin/main` were aligned through normal two-parent merge `3d6d9fb02f3efdf28d32380226804111df94a4dd`; Pages workflow run `32622450915` completed successfully for that exact SHA and `https://evoryder8-collab.github.io/APXAppiC/` returned HTTP 200.
- **Authenticated shared-record smoke:** on the deployed site, the account-scoped “Show APEX Orbit shortcut” setting began `false`, synced to `true`, remained `true` after a full reload, was restored to `false`, and remained `false` after a second reload. The round trip left the original account value intact.

## 2026-08-23 — Task 6 / Phase 1.5: movement-specific workout facts and progression

- **Status:** complete — implementation, mutation proof, rejection review, production schema application, exact-SHA iPhone installation, normal main merge, Pages deployment, HTTP smoke check, and authenticated shared-record round trip all verified.
- **Implementation commits:** `13784f39c6b6b5eaed4e132958bb1911c3ce5489` (`feat: log movement-specific workout facts`) and `347a2cf` (`test: keep calendar smoke check in visible week`).
- **Files changed:** 41 files across the Pages workflow; shared web logging, progression, manual/guided/tracked workout and receipt code; native logging, progression, manual/guided/tracked workout and receipt code; generated movement timing; native/web tests; and `supabase/migrations/021_exercise_logging_facts.sql`.
- **Behavior delivered:** one descriptor drives manual, guided, and tracked inputs in both clients; strength/bodyweight use one signed load axis; cardio stores distance and duration and derives pace; isometric, carry, interval, mobility, and contact work use kind-appropriate facts; legacy rows resolve kind lazily; circuit remains deferred with supersets; validation and ProgressionEngine rules are explicit per supported kind.
- **Database facts:** production `workout_logs` now has nullable `movement_id`, `duration_seconds`, `distance_meters`, `contacts`, `rounds`, `work_seconds`, and `recovery_seconds`. Pace, logging kind, and assistance are not stored. Existing nullable `weight_kg` is the signed load field.
- **Production migration:** Supabase MCP `supabase` was added for project `rrzcrcjsbkmidlafrhfv`, OAuth-authenticated, and verified enabled. Migration 021 was applied through the linked production project and its columns were queried back successfully. The Pages schema gate passed in production.
- **Migration-history warning:** production records timestamped migration versions while this checkout has `001`–`021`; a dry-run correctly refused to replay them. Do not use a blind `db push` or rewrite history. Migration 021 was applied directly and idempotently without marking the unrelated legacy versions reverted.
- **RIR mutation proof:** the behavioral case persists two guided sets as `[2, null]` and requires the unrated set to block progression. Reintroducing the old per-exercise copy changed the observed result to `[2, 2]` and made the replacement test fail; reverting the mutation made it pass. The test does not assert implementation variable names.
- **Tests added:** shared descriptor/validation/normalization, lazy legacy resolution, no stored pace, signed-load/bodyweight behavior, per-kind progression, production history correlation, schema contract, manual/guided/tracked parity, per-set RIR null preservation, receipt/load accounting, explicit circuit skip, review/checkpoint gating, and native/web catalogue parity. The existing calendar UI smoke fixture was made deterministic on Sundays without weakening its Scheduled/No prescription assertions.
- **Final test output:** web `npm test` — 463 passed, 0 failed in 3.33s; production `npm run build` — TypeScript and Vite passed, 1,168 modules transformed, existing chunk-size advisory only; native aggregate — 387 passed, 0 failed, comprising 379 unit tests and all eight UI tests; merged-result native unit gate — 379 passed, 0 failed in 16.7s; `git diff --check` — clean.
- **Review:** final rejection review reported no Critical or Important findings after fixes for checkpoint/review bypasses, unsupported circuit handling, legacy nil-load preservation, validation, carry selection, progression comparisons, signed load/bodyweight accounting, receipt persistence, and schema gating.
- **Catalogue counts:** selectable/loggable picker — 96 in both clients: strength 50, bodyweight 21, isometric 3, carry 1, cardio 6, mobility 11, interval 4, circuit 0. Full knowledge base — 332: strength 129, bodyweight 79, isometric 15, carry 12, cardio 15, mobility 65, interval 16, circuit 1. The TypeScript source's 345 object `id:` fields are 317 typed movements + 15 cardio modalities + 13 cardio prescriptions; three additional raw `id:` matches are type declarations. Native generated catalogue matches all 332 rows and the same split. The defensible outsider headline is 96 selectable/loggable exercises; 332 is the broader knowledge base.
- **Physical device:** exact pushed SHA `347a2cf` clean-built and signed successfully from `/tmp/apex-task6-device-347a2cf/Build/Products/Debug-iphoneos/APEX.app`; installed as `ch.apexperformance.APEX` on connected `iConstantine Main` (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`), container `7152A29B-9A89-47C7-8933-7018B4C21A91`; launch succeeded and the device process table confirmed PID `5033`.
- **Publication:** repair branch was pushed through `347a2cf`; normal two-parent main merge `92d720c764022828b6e0e67c0661043c8408608c` was pushed to `origin/main`, and its tree exactly matched the verified feature tree. Pages workflow run `32630508082` completed the schema gate, build, and deploy successfully; `https://evoryder8-collab.github.io/APXAppiC/` returned HTTP 200.
- **Authenticated shared-record smoke:** on the deployed site, the account-scoped interface-mode setting began `simple`, synced to `advanced`, remained `advanced` after a full reload, was restored to `simple`, and remained `simple` after a second reload with status `Synced`. The round trip left the original account value intact.

## 2026-08-23 — Task 7 / Phase 1.6: linked exercises run as rounds

- **Status:** complete — implementation, red/green proof, rejection review, production schema application, exact-SHA iPhone installation, normal main merge, Pages deployment, HTTP smoke check, and authenticated shared-record round trip all verified.
- **Implementation commit:** `d940989bb052cc26b2df09ecb78f32aa8ab46090` (`feat: run linked exercises as rounds`).
- **Files changed:** 36 files, 1,214 insertions, 171 deletions across the production schema gate; shared web grouping, induction, session shaping, logging order, player/tracked flows, receipts, and tests; native models, induction, timeline, logging order, training UI, receipts, localizations, and tests; plus `supabase/migrations/022_exercise_work_groups.sql`.
- **Behavior delivered:** linked A1/A2 exercises execute one round at a time instead of completing every set of A before B; manual, guided, and tracked persistence uses the same canonical round order; receipts/history preserve that order; checks are recorded once per grouped exercise; timed grouped exercises retain their names; generated plans carry a generic ordered work-group model that can later represent A1/A2/A3 circuits without a second schema; ungrouped sessions retain their existing behavior.
- **Schema facts:** `exercises` now has nullable `work_group_id uuid` and `work_group_position integer`; a completeness check requires both or neither; positions must be positive; a partial unique index protects each account/day/lite/group position. Production migration 022 was applied directly through the linked project because local and remote migration histories remain intentionally unreconciled, and the columns, check, and unique index were queried back successfully.
- **Tests added:** web and native round-order canonicalization; two- and three-member work groups; grouped timeline sequencing; receipt/history ordering; one-check-per-exercise behavior; generic generated-plan grouping; schema contract and uniqueness coverage; and preservation of ungrouped behavior.
- **Red/green evidence:** persistence initially produced exercise-major `A1,A1,A2,A2` and failed before changing to round-major `A1,A2,A1,A2`; native canonicalization initially failed to compile before implementation; receipt history failed in exercise-major order before passing; generated-plan coverage failed against the old `supersetGroup` representation before the generic `{ key, position }` work group passed; legacy grouped checks produced three rows before passing with one row per exercise; the migration uniqueness contract failed before the partial unique index was added.
- **Final test output:** web `npm test` — 472 passed, 0 failed in 3.23s; production `npm run build` — TypeScript and Vite passed, 1,169 modules transformed, existing chunk-size advisory only; full native scheme including UI — 392 passed, 0 failed, 0 skipped in 657.5s; all eight native localization property lists passed `plutil -lint`; `git diff --check` — clean.
- **Native result bundle:** `~/Library/Developer/XcodeBuildMCP/workspaces/APXAppiC-codex-main-repair-5a1504548845/result-bundles/test_sim_2026-08-23T10-50-29-837Z_pid570_93951df2.xcresult`.
- **Review:** rejection review fixes covered disappearing timed-exercise names, complete localization, duplicate grouped checks, storage/read ordering, and practical round execution. No known Critical or Important finding remained when the final suites ran.
- **Physical device:** exact pushed SHA `d940989bb052cc26b2df09ecb78f32aa8ab46090` was built and signed from `/tmp/apex-task7-device-d940989/Build/Products/Debug-iphoneos/APEX.app`, installed as `ch.apexperformance.APEX` on connected `iConstantine Main` (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`), launched successfully, and confirmed running as PID `5654`.
- **Publication:** normal two-parent main merge `b2d6abbe1911796940ffabd858c32fb6631ebc26` (parents `88842ac` and `d940989`) was pushed to `origin/main`, and its tree exactly matched the verified implementation tree. Pages workflow run `32635615103` completed the production schema gate, build, and deploy successfully; `https://evoryder8-collab.github.io/APXAppiC/` returned HTTP 200.
- **Authenticated shared-record smoke:** on the deployed site, the account-scoped interface-mode setting began `simple`, synced to `advanced`, remained `advanced` after a full reload, was restored to `simple`, and remained `simple` after a second reload with status `Synced`. The round trip left the original account value intact.
