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

## 2026-08-23 — Task 8 / user-reported nutrition repair: keyboard exit, meal water, and removal undo

- **Status:** complete — implementation, behavioral red/green proof, full regression suites, visual review, exact-SHA iPhone installation, normal main merge, Pages deployment, HTTP smoke check, and authenticated shared-record round trip all verified.
- **Implementation commit:** `64c20325c2dac21e467ccbbf3ff19323b4a0eb10` (`fix: make meal editing recoverable`).
- **Files changed:** 12 files, 312 insertions, 3 deletions across `FoodAmountSheet.swift`, `MealComposerView.swift`, all eight native localization files, `MealComposerTests.swift`, and `APEXSmokeUITests.swift`.
- **Behavior delivered:** the decimal quantity keyboard now has a localized Done action that dismisses it without losing the entered amount, after which Add Food remains tappable; both compact and expanded meal rows show their portion-adjusted water; the meal header shows a water total that equals the sum of the individually displayed rounded row values; either layout's X uses one deletion path; an immediate banner names the removed item and restores that exact item at its original position; the one-item heading now reads `1 food`.
- **Red/green evidence:** hydration and undo unit tests first failed to compile because their production helpers did not exist; the keyboard UI test first failed because there was no dismiss control; the meal UI test first failed because compact and expanded removal had no shared undo behavior; the singular-count assertion first failed on `1 foods`; and the sub-millilitre case first exposed a visible rounding disagreement (`0.6 + 0.6` rows versus the total). Each case passed only after the corresponding production behavior was implemented. A transient UI-test tap overlapped the sticky Save bar; the accessibility hierarchy identified the overlap, and the test now scrolls the row clear before tapping the real X without weakening its assertions.
- **Tests added:** three unit behaviors cover actual-portion hydration math, displayed-total rounding, and exact-position undo; one new XCUITest covers decimal-keyboard dismissal followed by adding the food; the meal-composer XCUITest now covers water in both layouts plus remove/undo restoration in compact and expanded modes and the singular item count.
- **Final test output:** web `npm test` — 472 passed, 0 failed in 3308.5 ms; production `npm run build` — TypeScript and Vite passed, 1,169 modules transformed, existing chunk-size advisory only; full native scheme including UI — 396 passed, 0 failed, 0 skipped in 611.6s; all eight native localization property lists passed `plutil -lint`; `git diff --check` — clean.
- **Native result bundle:** `~/Library/Developer/XcodeBuildMCP/workspaces/APXAppiC-codex-main-repair-5a1504548845/result-bundles/test_sim_2026-08-23T15-45-26-548Z_pid10130_1c849a08.xcresult`.
- **Visual review:** simulator captures verified the decimal-keyboard Done toolbar, cyan droplet water badges and total in compact and expanded layouts, and an unclipped undo banner above the persistent Save action. The review caught and drove the singular-count and displayed-rounding corrections before commit.
- **Physical device:** exact implementation SHA `64c20325c2dac21e467ccbbf3ff19323b4a0eb10` was clean-built and signed from `/tmp/apex-task8-device-64c2032/Build/Products/Debug-iphoneos/APEX.app`; after one transient CoreDevice connection reset, it installed as `ch.apexperformance.APEX` on connected `iConstantine Main` (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`), launched successfully, and was confirmed running as PID `8351`.
- **Publication:** normal two-parent main merge `d76a8388651d75223203b7397958900575eca0c9` was pushed to `origin/main`, and its tree exactly matched the verified feature tree. Pages workflow run `32650274256` completed the production schema gate, build, and deploy successfully; `https://evoryder8-collab.github.io/APXAppiC/` returned HTTP 200.
- **Authenticated shared-record smoke:** on the deployed site, the account-scoped interface-mode setting began `advanced`, synced to `simple`, remained `simple` after a full reload, was restored to `advanced`, and remained `advanced` after a second reload with status `Synced`. The round trip left the original account value intact.

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

## 2026-08-24 — Task 9: stage the owner exercise CSV for review

- Scope: preserved `exercise_extra_encyclopedia_with_sport_tags.csv` as source evidence, staged every row in an RLS-protected service-only review queue, applied only verified tags to exact canonical matches, and kept unmatched rows out of selection and automatic programming.
- Implementation commit: `36cda64e6387430c52c577429d12c41e3ac397ad` (`feat: stage owner movement import for review`).
- Files changed:
  - `data/imports/exercise_extra_encyclopedia_with_sport_tags.csv`
  - `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`
  - `src/data/movements.ts`
  - `supabase/migrations/015_movement_library_seed.sql`
  - `supabase/migrations/023_movement_import_review_queue.sql`
  - `tests/exercise-import-review.test.ts`
  - `tools/exercise-import-review.mjs`
  - `tools/movement-library.py`
- Import audit: 219 source rows / 219 normalized unique names; 10 exact canonical matches; 209 pending review; no fuzzy matches. Categories: 176 Strength, 12 Mobility, 13 Conditioning, 5 Plyometric, 13 Skill. Sport tags: 79 populated, 140 blank.
- Applied canonical changes: `kettlebell_clean` gained `kettlebell_sport`; `bear_crawl` gained `crossfit`. The other eight exact matches already had all verified tags. `Archer Pull-up` remains pending rather than being conflated with `Archer Push-up`.
- Source integrity: downloaded CRLF file SHA-256 `8ae1056ec3787059a70623de7d2d56572e7760c3da97a7b505495d684d779e1d`; repository LF-normalized SHA-256 `a7c3efb73ca84bcb597a5edc1955672bf2bd0ecd8f08625a87954bc231c17cd0`; the test reconstructs CRLF and verifies the original byte hash.
- Tests added: eight focused behavioral/import tests covering CSV parsing and row identity, exact/unmatched classification, exact tag application, no fuzzy admission, migration shape/security, generated-file parity, malformed optional cells, and original-byte hash recovery.
- Red/green verification: the first production migration attempt exposed a `verified_tags`/`verified` CTE-name defect and rolled back atomically. A new regression assertion made the focused suite fail 7/8 with that defect; after the one-token generator/generated-SQL fix it passed 8/8.
- Test output:
  - Focused import: 8 passed, 0 failed (`74.89 ms`).
  - Movement/security focused set: 27 passed, 0 failed.
  - Complete web suite: 480 passed, 0 failed (`4939.95 ms`).
  - Web production build: passed, 1,169 modules transformed; only the existing chunk-size advisory remained.
  - Native unit suite: 387 passed, 0 failed (`2.090 s`), result `/tmp/apex-task9-unit-tests-final.xcresult`.
  - Native UI: all 9 cases have green final-code evidence (7 unaffected cases in the complete run plus 2/2 corrected nutrition interaction cases in `63.994 s`), result `/tmp/apex-task9-food-ui-rerun3.xcresult`.
  - All three generators reproduced their committed outputs byte-for-byte; `git diff --check` passed.
- Production migration: Supabase version `20260823234438`, name `movement_import_review_queue`. Verified 219 total / 10 exact / 209 pending / 219 distinct names and source rows 2...220. RLS is enabled, policy count is zero, `anon` and `authenticated` cannot select, and `service_role` can select. The advisor's `rls_enabled_no_policy` INFO is intentional for this service-only queue.
- Production tag verification: `bear_crawl` is exactly `calisthenics,hiit,conditioning,crossfit`; `kettlebell_clean` is exactly `crossfit,strength,kettlebell_sport`.
- Live shared-record round trip: on Constantine's authenticated Pages session, `settings.addons.uiMode` was changed `simple → advanced`, confirmed by direct Supabase read, restored `advanced → simple`, confirmed by direct Supabase read, then reloaded; the page rendered `simple` pressed and `Synced`. No account data was left changed.
- GitHub publication: feature commit pushed to `origin/codex/main-critical-repair`; normal main merge `e7e826e8f43656a230498b48c7b7f23b94743f77` pushed to `origin/main`.
- Pages: run `32674788172` completed successfully for `e7e826e8f43656a230498b48c7b7f23b94743f77`; both build and deploy jobs passed. Live cache-busted URL returned HTTP 200 with 1,248 bytes: `https://evoryder8-collab.github.io/APXAppiC/?task9=e7e826e8f43656a230498b48c7b7f23b94743f77`.
- Physical iPhone: built, installed, launched, and process-verified `ch.apexperformance.APEX` from exact implementation SHA `36cda64e6387430c52c577429d12c41e3ac397ad` on `iConstantine Main` (iPhone 15 Pro Max, device `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`); install UUID `625EBB09-7EBF-4327-A9DC-EC413D86FA9E`; launch PID `1336`.

## 2026-08-24 — Task 10: expose the canonical workout catalogue

- Scope: replaced the workout studio's independent 96-row legacy mirror with the canonical 317 typed movements plus 15 cardio modalities, removed the native/web/manual result caps, and kept the 209 unreviewed owner-CSV rows out of selection until their safety and progression facts are verified.
- Implementation commit: `3fd697d5146acd3b7448e32bc934102e534d713d` (`fix: expose the canonical workout catalogue`).
- Files changed: 12 files across the shared catalogue and web builder/logger, native catalogue resource/decoder/builder/logger/save boundary, web/native catalogue tests, and the native builder flow test.
- Catalogue truth: 332 selectable unique IDs on web and native, with exact ID-set parity. Requested overlapping filters contain HYROX 8, CrossFit 16, Olympic Weightlifting 3, Powerlifting 3, Kettlebell Sport 1, Strongman 2, and Mobility & prehab 42. The filters are views over the same canonical rows, not duplicate exercises.
- Behavior delivered: Build a Workout now displays the full count and lazily renders every result; manual logging no longer stops at 60; web no longer stops at 14/24; multi-category sport/equipment filters share the same items; saves persist the exact canonical movement ID and authored load increment; steps and rounds display their real units; legacy localized aliases and reviewed hologram metadata remain attached without creating duplicate catalogue rows.
- Red/green evidence: the new web parity checks first failed at 96 versus 332 and a missing HYROX filter; the native suite first produced 12 catalogue/filter failures; the UI flow reached `332 movements` but failed when the newly searchable Power Snatch result had no stable selectable identity. After implementation, the same assertions passed. The full web run then caught lost Human Flag forearm metadata; the focused hologram test passed after reviewed legacy display metadata was merged into the canonical row.
- Tests added or strengthened: full canonical count/unique-ID/set parity; exact requested filter contents and counts; static guards against reintroducing the three picker caps; canonical cardio identity and tempo coverage; native decoding/category/load/unit parity; and one XCUITest that opens Build a Workout, asserts 332, searches Power Snatch, selects it, and verifies it appears in the workout.
- Final test output: web `npm test` — 483 passed, 0 failed in 5475.1 ms; production `npm run build` — TypeScript and Vite passed, 1,169 modules transformed, existing chunk-size advisory only; native unit suite — 388 passed, 0 failed in 2.225 s; focused web catalogue/hologram/tempo — 16 passed, 0 failed; focused native builder — 13 passed, 0 failed; driven native builder UI — 1 passed, 0 failed in 24.897 s; `git diff --check` — clean.
- Native evidence: unit result `/tmp/apex-catalog-final-native-0276ea8.xcresult`; UI result `/tmp/apex-catalog-ui-green2-0276ea8.xcresult`. Two retained UI attachments show `332 movements` with the new sport chips and Power Snatch inside `IN THIS WORKOUT`.
- Review: the rejection pass verified no duplicate canonical IDs, no uncategorized row, no hidden result cap, exact movement identity through both save paths, exact requested filter counts, and lazy native rendering. No known Critical or Important finding remained.
- Publication: normal two-parent main merge `301ab82ec2b100e52b24e69e9d9bbbb22f97bd55` was pushed to `origin/main`. Pages workflow run `32677943977` completed successfully (build 26 s, deploy 10 s); `https://evoryder8-collab.github.io/APXAppiC/?catalog=301ab82` returned HTTP 200 with 1,248 bytes.
- Authenticated shared-record smoke: the deployed Constantine session changed `settings.addons.uiMode` from `advanced` to `simple`, reached `Synced`, and a direct Supabase read returned `simple`; the client then restored `advanced`, reached `Synced`, and Supabase returned `advanced`. No account data was left changed.
- Physical iPhone: exact shipped merge SHA `301ab82ec2b100e52b24e69e9d9bbbb22f97bd55` clean-built and signed with `** BUILD SUCCEEDED **`, installed as `ch.apexperformance.APEX` on paired `iConstantine Main` (iPhone 15 Pro Max, device `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`), launched successfully, and was process-verified as PID `1798`; installation database UUID `ED0A22D6-5D24-4C8D-9A52-88AEA200DEF2`.

### Task 11 — Enrich the owner exercise CSV and publish the complete selectable catalogue

- Scope: imported and fully enriched all `209` previously withheld owner-CSV movements rather than exposing incomplete rows; retained the `10` exact canonical matches already present; added `8` researched steel-mace movements tagged for Street workout; regenerated the shared TypeScript and native catalogues; preserved official HYROX station order; and generated `docs/APEX-CURRENT-EXERCISE-CATALOG.csv` as the user-facing catalogue export.
- Catalogue result: `549` user-selectable entries (`534` movements plus `15` cardio modalities). Per-kind totals are strength `242`, bodyweight `132`, isometric `17`, carry `24`, mobility `90`, interval `28`, circuit `1`, and cardio `15`; the parts sum to `549`.
- HYROX order verified in code, tests, and the deployed UI: Ski Erg; Sled Push; Sled Pull; Burpee Broad Jump; Rowing Machine; Farmer's Carry; Sandbag Lunge; Wall Ball.
- Steel-mace additions: 360, 10-to-2, Uppercut, Offset Press, Offset Squat, Rotational Lunge, Single-Arm Swing, and Overhead Carry. All eight resolve under the Street workout filter.
- Research/provenance: added `data/research/exercise-enrichment-sources.json` with `21` evidence sources and `docs/research/APEX-EXERCISE-ENRICHMENT-REPORT-SOURCE.md`; high-consequence movements remain coach-gated, and the catalogue records timing, safety, measurement, progression, aliases, tags, and provenance instead of inventing unsupported facts.
- Database: added and applied `supabase/migrations/024_movement_catalog_enrichment.sql` as migration `20260824023336_movement_catalog_enrichment`. Live validation returned movement count `534`, owner-enriched count `209`, mace count `8`, sourced count `217`, review-queue count `219`, approved exact count `219`, and pending count `0`. The review queue remains service-only under RLS; the advisor's no-policy informational finding is intentional.
- Tests added: `tests/exercise-catalog-export.test.ts`, `tests/movement-enrichment-migration.test.ts`, and `tests/movement-enrichment.test.ts`; expanded native catalogue/timing parity coverage and generator exactness coverage.
- Red/green evidence: the focused native catalogue tests initially failed `8` assertions because `movement-timing.json` still carried `332` rows while `exercise-catalog.json` carried `549`; regeneration produced `549` timing rows and `190` aliases, after which the focused native run passed `30/30`. The first database migration attempt failed atomically on an inferred `text` argument to `array_to_string`; the explicit `text[]` cast was added and the migration-focused suite passed `10/10` before the migration was applied.
- Final verification: web suite `495/495` passed in `4866.7855 ms`; full native `APEXTests` suite `388/388` passed with `0` failures in about `2.209 s` (`build/catalog-enrichment-simulator/Logs/Test/Test-APEX-2026.08.24_04-30-43-+0200.xcresult`); `npm run build` completed successfully over `1170` modules; `git diff --check` was clean; the generated CSV has `549` data rows and `38` columns with no spreadsheet formula errors.
- Git: implementation commit `1e32f4f0bc75bbdf15e8efd0ec74a05b97d73379`; normal two-parent main merge `9bbe5faf35da97c32376cbe1a8d73bb6efe59db7`. The merge tree exactly matches the implementation tree (`1f06c4af100fba4176ec67d6ea5d5975b158dd13`).
- GitHub Pages: Actions run `32683622562` succeeded for merge SHA `9bbe5faf35da97c32376cbe1a8d73bb6efe59db7`; `https://evoryder8-collab.github.io/APXAppiC/?catalog=9bbe5faf` returned HTTP `200` (`1248` bytes). The live builder showed `549 movements`, the exact eight-station HYROX order, and the expanded catalogue including steel-mace entries.
- Authenticated shared-record round trip: on the deployed site, session mode was changed from `advanced` to `simple`, reached `Synced`, survived a full navigation/reload, then was restored to `advanced`, reached `Synced`, and again survived a full navigation/reload; no account data was left changed.
- Physical iPhone: exact shipped merge SHA `9bbe5faf35da97c32376cbe1a8d73bb6efe59db7` built successfully for the paired physical-device destination (`xcodebuild` exit `0`), signed as `ch.apexperformance.APEX`, and bundled `549` rows in both `exercise-catalog.json` and `movement-timing.json`. It installed on `iConstantine Main` (device `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`) at installation URL UUID `87267AEA-8499-461B-8A64-754C5349D486`, database UUID `ED0A22D6-5D24-4C8D-9A52-88AEA200DEF2`, launched successfully, and was process-verified as PID `2230`.

### Task 12 — Make plan building explicit, polished, and recovery-aware

- Scope: redesigned the native Build a Plan flow as a four-step card-based wizard; replaced the goal dropdown with descriptive outcome cards; explicitly labelled training frequency as days per week; made `2...7` selectable; added an informed but non-blocking advisory for six and seven days; and put Weighted Vest and Weighted Backpack first in the Home equipment choices.
- Recovery behavior: six-day plans distribute capped hard work across upper, lower, mobility, and capacity sessions; seven-day plans reserve one low-load recovery session. Hard-set metadata is capped at two for high-frequency plans, and existing contraindication safety caps still take precedence after selection.
- Cross-client parity: the web and native clients use the same frequency range, advisory substance, equipment IDs, movement substitutions, weekly-load metadata, and plan-generation rules. The native wizard exposes stable accessibility identities and selected values for goals, venues, frequencies, equipment, pain choices, and advisory actions.
- Tests added or strengthened: web and native behavioral coverage for exact six/seven-day counts, weekday distribution, recovery placement, hard-set caps, weighted-vest/backpack ordering and movement effects, goal-card/day-label source contracts, advisory content, and a driven physical-interface flow that selects seven days, accepts the advisory, selects weighted vest, and installs the resulting safety-adjusted plan.
- Red/green and interface evidence: the UI test exposed and drove fixes for section identifiers masking child controls, the off-screen seven-day control, missing selected accessibility values, and advisory-dismissal timing. Its final screenshot is `/tmp/apex-task12-passing-ui/09AC9174-21C6-4409-8E67-1FF11060E120.png`.
- Final local verification: focused web `18/18` passed; complete web `498/498` passed in `5939.66425 ms`; production web build passed with `1170` modules; complete native `APEXTests` `392/392` passed with zero failures in `2.262 s`; focused physical-device native behavior `3/3` passed; driven native UI `1/1` passed in `30.067 s`; and `git diff --check` was clean. Native result bundles are `build/task12-tests/Logs/Test/Test-APEX-2026.08.24_07-30-00-+0200.xcresult` and `build/task12-tests/Logs/Test/Test-APEX-2026.08.24_07-28-54-+0200.xcresult`.
- Evidence basis: resistance-training frequency and volume are managed as separate variables; strenuous sessions can require more than 24 hours of recovery; and sleep, hydration, and adequate protein support recovery. The advisory deliberately warns without claiming that seven days is safe for every user.
- Publication and exact-device evidence are recorded in the follow-up entry after the implementation commit is merged and deployed.
- Git: implementation commit `c52da23c31c754a348db37d8d1de604d50544a29`; normal two-parent main merge `718643f4ed22056b04df95a9dae83719f87ec64e`. The merge tree exactly matches the tested implementation tree (`c35fb904e57c05be05059ea7dd369d539975e8ca`).
- GitHub Pages: Actions run `32694056427` succeeded for merge SHA `718643f4ed22056b04df95a9dae83719f87ec64e` (build `23 s`, deploy `8 s`); `https://evoryder8-collab.github.io/APXAppiC/?task12=718643f4ed22056b04df95a9dae83719f87ec64e` returned HTTP `200` with `1248` bytes.
- Authenticated shared-record round trip: the deployed Constantine session changed `settings.addons.uiMode` from `simple` to `advanced`, rendered the detailed interface with `Synced`, and a direct Supabase read returned `advanced`; it was restored to `simple`, rendered the simple interface with `Synced`, and a second direct read returned `simple`. No account data was left changed.
- Physical iPhone: exact shipped merge SHA `718643f4ed22056b04df95a9dae83719f87ec64e` built and signed successfully with `xcodebuild` exit `0`, installed as `ch.apexperformance.APEX` on paired `iConstantine Main` (iPhone 15 Pro Max, device `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`) at installation URL UUID `EA843891-24E2-489A-B707-E2C74F0785B0`, and launched successfully with process-verified PID `2814`.

### User integrity repair — barcode camera lifecycle (2026-08-24)

- Root cause: the found-food card was an overlay over a still-mounted `AVCaptureSession`; capture stopped only when the scanner view disappeared, so resolving a barcode left the camera running behind the result.
- Fix: modelled the scanner lifecycle explicitly, stopped capture on the dedicated session queue immediately after a code leaves the scanning phase, dismantled the camera view outside scanning, and allowed restart only when returning to scanning.
- Regression test: `testBarcodeCameraStopsAsSoonAsCaptureLeavesScanning` covers scanning, lookup, found-food, message, and portion-selection phases. It first failed because the lifecycle resolver did not exist, then passed after the session wiring was implemented.
- Verification: focused regression `1/1` passed; complete `FoodPortionParityTests` `7/7` passed with zero failures in `18.8 s`; `git diff --check` passed.
- Git: implementation commit `7a6d9bf2` (`fix: stop barcode camera after capture`). Publication and exact-device evidence will be recorded after the complete user integrity batch is merged, deployed, and installed.

### User integrity repair — measured food amount defaults (2026-08-24)

- Root cause: the barcode route still presented a legacy portion sheet whose initializer preferred any declared serving over the nutrition-basis unit. That sheet also displayed a bare `Serving` label even when its calculation depended on an unseen gram equivalent.
- Fix: fresh foods now open at `100 g` or `100 ml` in both clients; remembered/history and explicit user preferences still take precedence. Serving and piece are selectable only with a positive measured equivalent and render as labels such as `Serving (30 g)`. Barcode confirmation now uses the same amount configurator as the meal composer, while the remaining legacy logging route delegates default and unit-label decisions to the shared portion math.
- Regression tests: native default-selection coverage now includes fresh pieces, fresh declared servings, remembered servings, invalid equivalents, and literal equivalent labels; web coverage mirrors fresh and remembered behavior. The existing driven UI flow still proves the decimal keyboard can be dismissed and the chosen food can be added.
- Red/green evidence: native first returned `1 piece` and `1 serving` instead of `100 g` (four assertion failures); web first returned `1 serving` instead of `100 g`; the new unit-label test first failed because no shared label function existed. Final native `FoodPortionParityTests` passed `8/8`, web food tests passed `37/37`, and the driven amount-entry UI passed `1/1` in `32.8 s`; `git diff --check` passed.
- Git: implementation commit `cc7fd9e3` (`fix: default food amounts to measured weight`). Publication and exact-device evidence will be recorded after the complete user integrity batch is merged, deployed, and installed.

### User integrity repair — goal-aware macro targets (2026-08-24)

- Root cause: native `EnergyEngine` pinned protein to `2.2 g/kg` and fat to `0.7 g/kg` for every goal, then put every calorie change into carbohydrate. Its old regression test explicitly asserted that recomp and bulk protein/fat were equal.
- Fix: native targets now use the same activity- and goal-aware macro policy already shipped and tested on web: protein remains within the athlete-oriented range, fat uses the greater of a bodyweight floor and a goal-specific energy share, and carbohydrate is derived from the remaining energy. Recomp, maintain, and bulk therefore recalculate all targets as one coherent set.
- Literal parity fixture at 70 kg/moderate activity: recomp at 2,200 kcal = `147 P / 61 F / 266 C`; maintain at 2,400 = `133 / 73 / 303`; bulk at 2,600 = `126 / 81 / 342`. Each reconstructs its target within two calories using `4/9/4` energy factors.
- Evidence check: ISSN identifies `1.4–2.0 g/kg/day` as sufficient for most exercising people, with higher needs possible in energy restriction; EFSA places adult fat within a broad `20–35%` energy reference range. APEX's outputs remain personalised estimates rather than medical prescriptions.
- Red/green and verification: the replacement native suite first failed because no shared policy existed and the old implementation held protein/fat constant. Final `EnergyEngineTests` passed `8/8`; web activity parity passed `12/12`; `git diff --check` passed.
- Git: implementation commit `c5ad789d` (`fix: recalculate nutrition macros by goal`). Publication and exact-device evidence will be recorded after the complete user integrity batch is merged, deployed, and installed.

## 2026-08-24 — Food water provenance and honest disclosure

- Finding: the catalogue's water values were not uniformly fact-checked. The bundled catalogue contains 1,511 foods with water values, but only 31 are reference-backed; 1,457 are macro-difference estimates and 23 are name-based estimates.
- Retailer audit (bundled): Migros 216 estimated / 0 exact, Aldi 215 / 0, Lidl 215 / 0, REWE 224 / 0, Coop 0, Denner 0.
- Retailer audit (live): Migros 12 estimated / 0 exact, Aldi 3 estimated + 1 missing, Lidl 3 estimated + 1 missing, REWE 1 estimated + 1 missing, Coop 1 estimated, Denner 0.
- Regulatory/source finding: EU Regulation 1169/2011 does not require water in the mandatory nutrition declaration, and Open Food Facts is community-contributed data subject to quality controls. A retailer label or provider result therefore cannot be treated as a measured water assay by default.
- Repair:
  - added a controlled water provenance vocabulary: `measured`, `provider_reported`, `reference`, `name`, `difference`, `legacy`, `user_entered`, and `unknown`;
  - persisted provenance/source IDs through Food, structured meal requests, immutable logged-food snapshots, and Open Food Facts normalization;
  - marked every non-measured value as estimated in native item, portion, meal-total, and accessibility output;
  - classified seed-derived water values explicitly instead of presenting them as exact;
  - added and remotely applied `025_food_water_provenance.sql`, including conservative legacy backfill and snapshot trigger propagation.
- Live migration verification: 148 foods total; 124 legacy values, 4 traceable reference values, and 20 unknown/missing. New provenance columns and constraints exist on `foods` and `logged_food_entries`.
- Implementation commit: `b41df74b` (`fix: disclose food water provenance`).
- Files changed:
  - `src/lib/hydration.ts`, `src/lib/food.ts`, `src/data/foodSeeds.ts`, `src/store/FoodStore.tsx`, `src/components/food/MealComposer.tsx`, `shared/openFoodFacts.ts`
  - `ios/APEXNative/APEX/Core/Engine/FoodHydration.swift`, `MealMemory.swift`, `APEXModels.swift`, `AppSession.swift`, `FoodAmountSheet.swift`, `MealComposerView.swift`
  - `tests/hydration.test.ts`, `FoodHydrationTests.swift`, `MealComposerTests.swift`
  - `supabase/migrations/025_food_water_provenance.sql`
- Tests added:
  - web disclosure/provenance tests for measured, estimated, and unknown values;
  - native disclosure/provenance tests and mixed-provenance meal-total behavior.
- Test output:
  - web food/hydration/sync suites: 68/68 passed;
  - native FoodHydration + MealComposer suites: 21/21 passed in 44.0 s;
  - production web build: succeeded, 1,170 modules transformed in 633 ms;
  - `git diff --check`: clean.
- Sources:
  - https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32011R1169
  - https://openfoodfacts.github.io/documentation/docs/
  - https://openfoodfacts.github.io/documentation/docs/Product-Opener/api/tutorials/how-to-create-data-quality-controls-in-your-app/

## 2026-08-24 — Watch companion signing and runtime verification

- Scope: verification-only; the existing Watch target did not require a source change.
- Watch runtime verification:
  - XcodeBuildMCP built, installed, and launched `APEXWatch` on Apple Watch Series 11 (46 mm), watchOS 26.5;
  - bundle `ch.apexperformance.APEX.watchkitapp` launched as PID 10404;
  - runtime accessibility snapshot contained 66 elements and reached the Health authorization flow;
  - simulator build completed in 262.3 s with no compile/signing error.
- Embedded extension verification:
  - strict deep signature verification passed for the Watch simulator bundle;
  - `APEXWatchWidgets.appex` is present with bundle ID `ch.apexperformance.APEX.watchkitapp.widgets`.
- Physical signing verification at HEAD `2175ab79`:
  - XcodeBuildMCP built, installed, and launched `ch.apexperformance.APEX` on connected iPhone `iConstantine Main` as PID 3286 in 138.4 s;
  - strict deep signature verification passed for the physical `APEX.app` bundle;
  - iOS app, embedded Watch app, and embedded Watch widget all carry Apple Development signature `Constantin Barbu (YYWFU4Y9QV)`, team `UG979XDY72`;
  - verified bundle IDs: `ch.apexperformance.APEX`, `ch.apexperformance.APEX.watchkitapp`, and `ch.apexperformance.APEX.watchkitapp.widgets`.
- Hardware limit stated explicitly: no physical Apple Watch is connected to this Mac. Executable behavior was therefore verified on the Watch simulator, while the exact device provisioning/signature chain was verified inside the build installed on the physical iPhone.
- Files changed: `docs/REPAIR-NOTES.md` only.
- Tests added: none; this task is a build, launch, and signature-verification gate.

## 2026-08-24 — Movement catalogue fact audit

- Implementation commit: `26633ea7` (`fix: audit movement catalogue facts`).
- Files changed: `src/lib/eventCampaign.ts`, `src/data/exerciseCatalog.ts`, `src/data/movements.ts`, `tools/export-exercise-catalog.mts`, `docs/APEX-CURRENT-EXERCISE-CATALOG.csv`, `ios/APEXNative/APEX/Resources/exercise-catalog.json`, `ios/APEXNative/APEX/Resources/movement-timing.json`, `tests/exercise-catalog.test.ts`, `tests/exercise-catalog-export.test.ts`, `tests/movement-library.test.ts`, and `ios/APEXNative/APEXTests/CustomWorkoutBuilderTests.swift`.
- Canonical count remains 549 unique rows: 534 selectable movement entities plus 15 separately modelled cardio modalities. Entity types and the lowercase controlled discipline vocabulary were already explicit and valid.
- Accepted audit findings: HYROX station 6 now resolves to the kettlebell farmer's walk; `equipmentAnyOf` is visible instead of incorrectly projecting resistance movements as Bodyweight; the audit CSV now exports canonical primary, secondary, and stabilizer anatomy; high-consequence barbell movements and an erroneous snatch-grip RDL record received evidence-bounded safety corrections.
- Rejected unsupported findings: the ten allegedly missing muscle mappings were already present in the canonical source; cardio modalities intentionally do not pretend to have resistance-only tempo or spotter facts; provenance and aliases remain unknown where no source supports a backfill; controlled floor-returned pulls were not blanket-labelled unsafe.
- Tests added: alternative-equipment projection, canonical anatomy export, official HYROX station identity/order, barbell failure-mode distinctions, anchored-landmine bail behaviour, and native HYROX parity.
- Red proof: the new web assertions failed five times against the old HYROX/equipment/safety behaviour; the canonical-anatomy assertion then failed with an empty exported muscle value; the native parity test failed on the old generic farmer's-carry ID.
- Green proof: targeted web catalogue suite 71/71; full web suite 502/502 in 5.83 s; native `CustomWorkoutBuilderTests` 30/30 in 13.6 s; production web build succeeded (1,170 modules transformed in 0.70 s); `git diff --check` passed.
- Evidence used: official HYROX race/rules material for station order and kettlebells; ACE exercise guidance for Pallof resistance requirements; NSCA strength-and-conditioning safety guidance for rack safeties, platforms, and high-consequence barbell failure handling.

## 2026-08-24 — Native release-gate UI hardening

- Implementation commit: `02f39027` (`test: harden catalogue and meal UI flows`).
- Files changed: `ios/APEXNative/APEX/Features/Nutrition/MealComposerView.swift` and `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`.
- Red proof: the first complete native run finished 404/406 with a stale 332-row catalogue assertion and a reproducible meal-composer navigation failure; the latter also failed alone at the same assertion.
- Fix: the catalogue UI test now asserts the verified 549-row headline and waits for selected results to leave through their animation; the meal-name field has a stable semantic identifier, and the preset workflow taps the uniquely identified Breakfast title rather than an overlapping combined Dayline frame.
- Behaviour retained: selection must persist in the authored workout, and the meal test must open the Breakfast composer, expose its food picker, preserve water facts, exercise preset selection, removal/undo, and selection mode.
- Green proof: isolated meal-composer flow 1/1 in 45.0 s; workout-builder flow passed in the focused run; complete native suite 406/406, 0 failed, 0 skipped in 681.0 s using the official XcodeBuildMCP runner.

## 2026-08-24 — Integrity batch production integration

- Feature branch published at `1f864a19971d`; normal merge commit `e39b7637aedc` has parents `5a0ac19da67b` (`origin/main`) and `1f864a19971d` (the tested repair branch). The merge tree was verified byte-identical to the tested feature tree before push.
- GitHub Pages workflow `32704767164` succeeded from `main`: build 22 s, deploy 10 s. `https://evoryder8-collab.github.io/APXAppiC/` loaded as APEX in the browser and independently returned HTTP 200.
- Production shared-record proof: inserted food probe `e39b7637-aedc-424c-8807-c7475c419dc8`, independently read it back with `owner_user_id = null` and `is_shared = true`, deleted that exact probe, then confirmed `remaining = 0`.
- Physical device proof for merge SHA `e39b7637aedc`: official XcodeBuildMCP device build succeeded in 186.1 s, installed on `iConstantine Main` (iOS 27.0), and launched as PID 3620.
- Signature proof: the iPhone app (`ch.apexperformance.APEX`), embedded Watch app (`ch.apexperformance.APEX.watchkitapp`), and Watch widget (`ch.apexperformance.APEX.watchkitapp.widgets`) all passed strict deep verification and carry Apple Development signer Constantin Barbu (`YYWFU4Y9QV`), team `UG979XDY72`.

## 2026-08-24 — Account-scoped bespoke plan restoration

- Root cause: a generic `settings.addons.training_induction` payload was present on both bespoke accounts. June's incomplete induction window rejected every main-plan date; Constantine's induction deferred the bespoke main phase and pointed at generated day IDs. The authored plans remained mostly intact beneath that routing state.
- Production repair: `supabase/maintenance/20260824_restore_bespoke_training_plans.sql` restores only the two intended owners inside one guarded transaction. It removes their induction override, preserves their original seven historical day IDs, archives obsolete definitions still referenced by history, removes only unlogged duplicates, and installs June Glute Training V8 plus Constantin Training V8.3 from the supplied PDFs. No default or seed plan for ordinary users is changed.
- Production verification: June resolves 7 days and 23 full rows at protocol 80; Constantine resolves 7 days and 28 full rows at protocol 83; both resolve a runnable current-day workout. Ownership mismatches are zero and all three owner-RLS policies remain present.
- Preservation proof: the two accounts' 150 workout logs retained MD5 `77d5bfed480d490e5a1be7914e80c6c6`; their 25 sessions retained MD5 `0600211b3e3bfe726b2b5ecd6dd1eb8a`. Other-account programs, days, and exercises retained counts/hashes `5/e7795c174bd569a2264876ad2f2474e8`, `48/7be0c19df7a97b86cb02aa2d2bf62ea8`, and `228/d1f2681ec62ab9c5396779db2708d3e8` respectively.
- Client parity repair: web and native now render the account's protocol revision (`V8`, `V8.1`, `V8.3`) instead of hard-coding `V8.1`. Friday's Focus T25 full-prescription guidance is no longer mislabeled as light-only. The shared plan-parity fixture was regenerated for both clients.
- Red proof: the web and native badge tests both failed against the hard-coded `V8.1`; the Friday guidance tests failed against the old `Light option only` note.
- Green proof: focused web plan tests 7/7; complete web suite 504/504 in 5.0 s; complete native `APEXTests` 398/398 in 14.8 s with the official XcodeBuildMCP runner; production web build succeeded with 1,170 modules transformed; `git diff --check` passed.

## 2026-08-24 — Bespoke workout projection in Simple mode

- Root cause: the native Simple home hard-coded the transition programme even for June and Constantine, while the web client selected their main programme without first proving it had an active runnable prescription. The Advanced Main Phase therefore showed the restored PDF plan while the Simple training surface could still project a different workout.
- Fix: one shared policy per client now prefers a usable bespoke main phase for June and Constantine, falls back to a usable transition phase, and preserves transition-first behaviour for ordinary accounts. The native training square, its quick panel, no-day route, and full-schedule route all consume that resolved programme. The square also exposes the resolved workout name as its accessibility value.
- Tests added: web policy coverage for both bespoke personas and ordinary-account fallbacks; native policy parity; a seeded Constantine integration assertion resolving `Upper strength`; and an end-to-end Simple-mode Training-square assertion that the widget projects `Upper strength` rather than `Full-body foundation`.
- Red proof: the web and native policy tests initially failed because no resolver existed; the seeded native assertion failed against the old transition-only behaviour. The first UI attempts also exposed an offline-fixture sync alert and an oversized Dayline traversal, after which the final test was narrowed to the reported Training square itself.
- Green proof: focused Simple-mode UI flow 1/1 in 36.5 s; complete web suite 505/505 in 4.86 s; complete native `APEXTests` 400/400 in 134.3 s; production web build succeeded with 1,170 modules transformed; `git diff --check` passed.

## 2026-08-24 — Physical Apple Watch Ultra 3 recovery

- Device identity: `Constantin’s Apple Watch` is an Apple Watch Ultra 3 (`Watch7,12`) running watchOS 27.0 (`24R5325h`), hardware UDID `00008310-001C23162680E01E`. It is paired to Xcode, connected through its developer tunnel, and has Developer Mode enabled.
- Toolchain repair: the existing Xcode 26.6 installation did not support watchOS 27. The cached Apple Xcode 27 beta 3 archive was expanded side-by-side to `/Users/jaxoncorrey/Downloads/Xcode-beta.app`; the system-wide Xcode selection was not changed.
- Signing repair: Xcode created Watch provisioning profile `69426bb7-fdc2-49dc-a9e6-26c0ba4bf150` for `ch.apexperformance.APEX.watchkitapp`. Its `ProvisionedDevices` list contains both the Ultra 3 UDID and iPhone UDID `00008130-001618C60843401C`.
- Build and signature proof: the `APEXWatch` physical-device build succeeded against the Ultra 3 destination. Xcode's embedded-binary validation passed, and both the standalone Watch bundle and containing iPhone bundle passed `codesign --verify --deep --strict`.
- Physical Watch proof: `APEX Water` installed at database sequence 987 and launched successfully on the Ultra 3. A subsequent process query showed the Watch app running as PID 511 and `APEXWatchWidgets.appex` running as PID 503.
- Matching iPhone proof: the containing `ch.apexperformance.APEX` build installed at database sequence 5508 and launched successfully on `iConstantine Main`.
- Source SHA installed on both devices: `09048c9adeff9ab6b0b6f11ab728b1994f32f234`.
- Files changed: `docs/REPAIR-NOTES.md` only. Tests added: none; this closes the physical provisioning, build, signature, installation, and launch gate for the already-tested bespoke-plan source commit.

## 2026-08-24 — Native barcode scanner usability

- Implementation commits: `4d9a90785` (`fix: make barcode scanning immediately usable`) and `31b6c7907` (`fix: defer denied camera state update`).
- Files changed: `ios/APEXNative/APEX/Features/Nutrition/BarcodeScannerView.swift`, `ios/APEXNative/APEX/Features/Nutrition/MealComposerView.swift`, `ios/APEXNative/APEXTests/FoodPortionParityTests.swift`, and `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`.
- Fix: scanned-food macro facts now render as bold monospaced text on an opaque near-black capsule whose production colour values are guarded at WCAG AAA contrast. The meal discovery card now has independent search and barcode controls: the text region opens Food Memory and the 58 × 54 point orange target opens the scanner directly.
- Additional runtime repair: a previously denied camera permission called back synchronously from `UIViewControllerRepresentable.viewDidLoad`, producing `Modifying state during view update`. The permission binding write is now deferred to the next main-queue turn.
- Tests added: a production-palette contrast-ratio assertion and an end-to-end meal-composer test that taps `meal-barcode-scanner-open`, reaches `SCAN FOOD BARCODE`, and proves the Food Memory navigation bar never appeared.
- Red proof: the contrast test failed to compile against the old UI because no guaranteed scanner-result palette existed. The old discovery card also exposed no independent barcode target, so the UI test's required control did not exist.
- Green proof: contrast test 1/1; final focused scanner UI flow 1/1 with zero runtime warnings; complete native unit suite 401/401; web suite 505/505 in 4.87 s; production web build succeeded with 1,170 modules transformed; `git diff --check` passed.
- Physical-device proof: Xcode 27 physical build succeeded, the final iPhone bundle passed strict deep signature verification, and source SHA `31b6c7907` installed at database sequence 5524 and launched on `iConstantine Main` as PID 7124.
- Next: restore the animated water-filled body silhouette to the Apple Watch hydration surface as its own tested task.

## 2026-08-24 — Animated Apple Watch hydration silhouette

- Implementation commit: `3050eb8c1` (`feat: animate hydration silhouette on watch`).
- Files changed: `ios/APEXNative/APEXNative.xcodeproj/project.pbxproj`, `ios/APEXNative/APEX/Core/Engine/WatchHydrationFillState.swift`, `ios/APEXNative/APEXTests/HydrationGaugeTests.swift`, `ios/APEXNative/APEXWatch/WatchHydrationStore.swift`, and `ios/APEXNative/APEXWatch/WatchHydrationView.swift`.
- Fix: the Watch hydration surface now uses a custom human silhouette filled by an animated cyan-blue-violet water wave at the account's true hydration percentage. Empty and full states do not show phantom water or air; Reduce Motion freezes the wave; litres, percentage, target, a mini progress bar, and 44-point `+250`, `+300`, and `+500` controls remain readable on the Ultra display. The whole hydration card exposes a combined VoiceOver label and value.
- Shared model: `WatchHydrationFillState` is compiled into both native targets and owns progress clamping, proportional waterline placement, and bounded wave geometry, keeping UI rendering separate from hydration math.
- Tests added: four `WatchHydrationFillStateTests` cover empty/target clamping, proportional quarter/half/three-quarter waterlines, exact endpoint fill behaviour, and the invariant that every animated wave sample remains in `[0, 1]`.
- Red proof: the new focused test target failed to compile while `WatchHydrationFillState` was absent. Green proof: focused tests 4/4; complete native suite 405/405 with zero failed or skipped; complete web suite 505/505 in 4.93 s; production web build succeeded with 1,170 modules transformed; final Watch Ultra 3 simulator build succeeded under Xcode 27; `git diff --check` passed.
- Visual and animation proof: a final Ultra 3 render at 1.65/2.75 L showed the 60% waterline around the upper abdomen with all three quick-add controls fully visible. A 13.688-second, 165-frame capture ran at approximately 12 fps; silhouette-only frames six seconds apart produced different hashes, proving that the clipped water surface moves rather than remaining a static gradient.
- Signing proof: the physical Xcode 27 Watch build succeeded, and both `APEX Water.app` and the containing `APEX.app` passed strict deep signature verification.
- Physical Watch proof: source SHA `3050eb8c1` installed on Apple Watch Ultra 3 at database sequence 989 and launched successfully; the Watch app is running as PID 601 and `APEXWatchWidgets.appex` as PID 591.
- Matching iPhone proof: the same source SHA installed on `iConstantine Main` at database sequence 5540 and launched successfully as PID 7277.
- Next: resume the roadmap at the next numbered task only after this evidence commit is pushed and Pages succeeds.

## 2026-08-24 — Account-scoped HealthKit hydration unification

- Implementation commit: this commit (`fix: unify hydration through HealthKit`).
- Files changed: `ios/APEXNative/APEX/App/AppSession.swift`, `ios/APEXNative/APEX/Core/Engine/FoodHydration.swift`, `ios/APEXNative/APEX/Core/Engine/WatchHydrationFillState.swift`, `ios/APEXNative/APEX/Features/Health/HealthKitManager.swift`, `ios/APEXNative/APEX/Features/Settings/SettingsView.swift`, `ios/APEXNative/APEX/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`, `ios/APEXNative/APEXNative.xcodeproj/project.pbxproj`, `ios/APEXNative/APEXTests/FoodHydrationTests.swift`, `ios/APEXNative/APEXTests/HydrationGaugeTests.swift`, `ios/APEXNative/APEXTests/WaterWatermarkTests.swift`, `ios/APEXNative/APEXWatch/WatchHydrationStore.swift`, `ios/APEXNative/APEXWatch/WatchHydrationView.swift`, and `ios/APEXNative/APEXWatchWidgets/APEXWaterComplication.swift`.
- HealthKit model: all dietary-water samples remain visible in the unified HealthKit total, while APEX imports only Watch-authored and external-app samples into its manual-water ledger. APEX iPhone mirrors and account/day food-water samples are classified and excluded from that import, preventing feedback loops and double counting. Food hydration is published as one stable, replaceable sample per account and day, so edits and deletions reconcile rather than accumulate.
- Watch recovery: write authorization is checked against the dietary-water type instead of assuming that a successful read request permits writes. Denied access now names the exact Health settings route; reconnect retries undetermined access. Custom amounts, timestamped source-aware history, deletion of APEX Watch entries, a proper Watch app icon, and percent/litres/US-gallons complication variants are included.
- Tests added: source-classified hydration import, reversible external edits/deletions, stable account/day food sample identity, Watch-only deletion policy, and complication display derivation. The existing watermark suite now exercises the production reconciliation policy rather than a private duplicate.
- Red proof: the focused suite failed to compile before `HydrationReconciliation` and `WatchHydrationDisplayMode` existed. Green proof: focused hydration suites 24/24; complete native suite 411/411, 0 failed and 0 skipped; complete web suite 505/505; iOS and Watch Ultra 3 simulator builds succeeded; production web build succeeded; `git diff --check` passed.
- UI proof: the Watch Ultra 3 simulator exposed five first-screen targets (`+250`, `+300`, `+500`, `Custom`, and `History`) beneath the animated silhouette. The built Watch bundle declares `AppIcon` as its primary icon.

## 2026-08-25 — Canonical Watch hydration finish and battery gate

- Implementation commit: this commit (`fix: finish watch hydration experience`).
- Files changed: `ios/APEXNative/APEX/Core/Engine/FoodHydration.swift`, `ios/APEXNative/APEX/Core/Engine/WatchHydrationFillState.swift`, `ios/APEXNative/APEX/Resources/Assets.xcassets/HydrationMaleSilhouette.imageset/Contents.json`, `ios/APEXNative/APEX/Resources/Assets.xcassets/HydrationMaleSilhouette.imageset/HydrationMaleSilhouette.svg`, `ios/APEXNative/APEXTests/FoodHydrationTests.swift`, `ios/APEXNative/APEXTests/HydrationGaugeTests.swift`, `ios/APEXNative/APEXWatch/WatchHydrationStore.swift`, `ios/APEXNative/APEXWatch/WatchHydrationView.swift`, `tests/watch-hydration-silhouette.test.ts`, and `tools/prepare_hydration_assets.mjs`.
- Visual repair: the approximate Watch-only body drawing is gone. The scalable Watch image is mechanically exported from the exact detailed male SVG path used by the iPhone hydration surface, and a parity test compares the two path geometries and viewBox. The figure now carries a restrained radial breathing glow and floating motion. The primary amount is one unbroken value such as `1.38 L`; the redundant `TODAY` label is absent.
- Battery and sync policy: the water animation runs at eight frames per second only while the Watch scene is active, the display is not in reduced-luminance always-on mode, and Reduce Motion is off. It pauses otherwise. There is no timer, WatchConnectivity polling, or HealthKit background-delivery request. Opening/foregrounding the Watch app refreshes once, and the existing idempotent weak HealthKit observer refreshes only after a real dietary-water change.
- History repair: an APEX Watch row is fully tappable, supports trailing swipe actions, and presents a destructive `Remove water entry?` confirmation with Remove and Cancel before deleting the HealthKit sample. External, food, and ordinary iPhone samples remain read-only. The simulator exposed a HealthKit edge case where Watch writes can be attributed to the parent APEX bundle; deletion authorship now requires either the Watch bundle or the parent bundle plus APEX's Watch-specific sync-identifier prefix, so third-party prefix spoofing remains rejected.
- Tests added: exact phone/Watch silhouette parity; event-driven battery constraints; tap/swipe deletion structure; single-line litre presentation without a day label; foreground/always-on/Reduce Motion animation policy; and parent-source Watch authorship with negative food and third-party cases.
- Red proof: the asset test failed because no canonical Watch SVG existed; native tests failed to compile without `primaryAmount` and `WatchHydrationAnimationPolicy`; battery and deletion contracts both failed against the old view; the driven Ultra 3 flow then exposed a locked Watch-created row and the authorship test failed to compile without sync-identifier handling.
- Green proof: focused silhouette/battery/deletion contracts 3/3; focused Watch presentation tests 7/7; focused HealthKit authorship test 1/1; complete native `APEXTests` 413/413, 0 failed and 0 skipped; complete web suite 508/508; production web build succeeded with 1,170 modules transformed; final Apple Watch Ultra 3 simulator build succeeded; `git diff --check` passed.
- Driven UI proof: on the Watch Ultra 3 simulator, the main card rendered the detailed canonical silhouette and `0.00 L` on one line. Adding 250 mL produced an `APEX Watch` History row; tapping it rendered the Remove/Cancel confirmation, and confirming removal left History empty.

## 2026-08-25 — Smooth continuous Watch hydration motion

- Implementation commit: this commit (`fix: smooth watch hydration motion`).
- Files changed: `ios/APEXNative/APEXWatch/WatchHydrationView.swift`, `tests/watch-hydration-silhouette.test.ts`, and `docs/REPAIR-NOTES.md`.
- Root cause: the prior battery gate manually limited the active `TimelineView` to eight frames per second, so the silhouette advanced in visible 125 ms blocks. Its animation phase also reset at an arbitrary ten-second boundary that was not aligned with the breathing or floating periods, producing a discontinuous jump.
- Fix: active motion now uses SwiftUI's system display-paced animation schedule and a monotonic continuous phase. The existing battery controls remain intact: the schedule pauses whenever the Watch scene is inactive, the display enters reduced-luminance always-on mode, or Reduce Motion is enabled; it still has no timer, polling loop, WatchConnectivity loop, or HealthKit background-delivery request.
- Test added: `Watch hydration motion uses a smooth continuous animation clock` rejects both a manually throttled animation interval and phase remainder/reset logic, while requiring the event-driven paused schedule.
- Red proof: the new contract failed against the shipped eight-fps/resetting clock (`3 passed, 1 failed`). Green proof: focused Watch hydration contracts 4/4; complete web suite 509/509; complete native `APEXTests` 413/413, 0 failed and 0 skipped; Apple Watch Ultra 3 simulator build succeeded; production web build succeeded with 1,170 modules transformed.

## 2026-08-25 — Watch hydration controls, settings, and reminders

- Design commit: `67dd3283f` (`docs: specify unified hydration system`).
- Implementation: this commit (`feat: make Watch hydration configurable`).
- Files changed: `ios/APEXNative/APEX/Core/Engine/WatchHydrationPreferences.swift`, `ios/APEXNative/APEX/Core/Engine/WatchHydrationReminderPolicy.swift`, `ios/APEXNative/APEXWatch/APEXWaterWatchApp.swift`, `ios/APEXNative/APEXWatch/WatchHydrationStore.swift`, `ios/APEXNative/APEXWatch/WatchHydrationView.swift`, `ios/APEXNative/APEXTests/HydrationGaugeTests.swift`, `ios/APEXNative/APEXNative.xcodeproj/project.pbxproj`, and `tests/watch-hydration-silhouette.test.ts`.
- Watch layout: replaced the scrollable title/dead space with a compact top-toolbar `APEX HYDRATION` settings control aligned with the system time; enlarged the amount, percentage, target, presets, Custom, and History controls while keeping every primary action visible on the Apple Watch Ultra 3 first screen.
- Motion and power: one shared `TimelineView` drives continuous float, breathing glow, and progress gleam; it pauses while inactive, under Always-On reduced luminance, with Reduce Motion, or when motion is disabled. No polling loop or permanent phone connection was introduced.
- Settings: added an accessible gear screen with a validated exact 1.0–6.0 L target, litre/gallon display, reminder toggle and interval, quiet hours, preset-name visibility, haptics, and off/subtle/full motion controls.
- Reminders: notification permission is requested only after the user explicitly enables reminders. Scheduling is event-driven after a real hydration refresh or settings change, observes quiet hours, goal completion, pace deficit, and a maximum of three attempts per day, and avoids misleading numeric claims.
- Tests added: four preference tests, three reminder-policy tests, and two source contracts for the pinned settings entry and event-driven scheduler; the toolbar accessibility label is also contract-tested.
- Red proof: preference and reminder tests first failed to compile because the models did not exist; UI contracts first failed because the settings route, pinned title, scheduler, and accessibility label were absent. Visual review rejected the first large-navigation-title version because it clipped primary actions on the Ultra 3.
- Green proof: focused native tests 7/7; focused Watch source contracts 6/6; complete native unit target 420/420; complete web suite 511/511; production web build 1,170 modules; exact-source `APEXWatch` Watch Ultra 3 simulator build succeeded in 5.1 seconds; `plutil -lint` and `git diff --check` clean.
- Broader UI smoke: the two preceding UI cases passed, then the unrelated portal navigation case entered its pre-existing 60-swipe search loop; it was stopped after the complete 420-test unit target had passed rather than treating the stale navigation loop as hydration evidence.
- Visual proof: Watch Ultra 3 simulator inspection confirmed the full first-screen control set, and the settings screen showed complete labels without truncation.
- Current boundary: Watch preferences and reminders remain local in this slice. Account-scoped hydration events, custom beverage presets/composition, companion sync, complication variants, and HealthKit partial-failure recovery are the next committed slices from the approved design.

## 2026-08-25 — HealthKit partial-read resilience

- Implementation: this commit (`fix: preserve partial HealthKit refreshes`).
- Files changed: `ios/APEXNative/APEX/Features/Health/HealthKitManager.swift` and `ios/APEXNative/APEXTests/HealthImportParityTests.swift`.
- Root cause: `readToday()` launched independent HealthKit queries with `async let` but awaited their throwing values as one aggregate; one denied, protected, or temporarily failing metric therefore made `silentRefresh()` discard every valid metric and left the portal looking disconnected.
- Fix: introduced one typed `HealthTodayQueryPlan` used by production and tests. Each fixed query remains structured and concurrent, ordinary per-metric errors become unavailable fields, and readable steps, energy, exercise, sleep, water, vitals, and workouts survive independently.
- Truthfulness: a fully failed read is rejected instead of being reported as a successful sync; ten successful empty reads remain an honest empty snapshot with nil optionals; workout-only, VO2-max-only, resting-HR-only, and HRV-only snapshots now count as importable signal.
- Cancellation: `CancellationError` is rethrown, cancellation is checked before and after each HealthKit operation and after aggregation, and a cancelled lifecycle refresh cannot publish a partial snapshot or start monitoring.
- Tests added: five production-boundary cases covering one denied metric beside valid activity, denied water beside sleep/workouts, total query failure, successful empty queries with every optional remaining nil, and deterministic cancellation propagation.
- Red proof: the first focused run failed with 23 missing-type compiler errors before the partial-read model existed. Independent review then rejected the first green implementation because it swallowed cancellation, collapsed total failure into empty success, and tested helper construction rather than production orchestration.
- Green proof: corrected focused suite 5/5; complete native unit target 425/425; complete web suite 511/511; production web build 1,170 modules; `git diff --check` clean.
- Review: required health-data review round one found three Important issues and no Critical issues; round two confirmed all three resolved, found no new Critical or Important issues, and returned `Ready to merge: Yes`.
- Existing launch behavior remains intentional: bootstrap and every foreground activation call the silent HealthKit refresh without prompting. This task repairs the failure isolation that made those calls appear disconnected; it introduces no polling.
- Next: account-scoped hydration events, beverage presets/composition, and companion sync.

## 2026-08-25 — Unified hydration, configurable Watch companion, and workout handoff

- Implementation commit: `564150048d79cef8954e88eff3d1823b5bc8192a` (`feat: unify hydration across phone and watch`).
- Changed: account-scoped hydration event/preset/preference ledgers across TypeScript, Supabase, iPhone, and Watch; colored beverage composition and editable presets; Watch settings, reminders, history deletion, exact targets, complication modes, and low-power event-driven sync; anchored HealthKit reconciliation; durable WatchConnectivity mutations and disconnect handling; matching Watch workout handoff for strength, mobility, conditioning, running, cycling, and walking sessions.
- Database: applied `026_hydration_ledger.sql` to production. Authenticated own-row insert/read succeeded, foreign-owner insert was rejected by RLS, and verification rows were removed (`0` remaining).
- Tests added: legacy hydration migration/cutoff behavior, HealthKit empty-read and explicit deletion behavior, stale Watch event/preference rejection, and workout-type handoff mapping. Existing web/native hydration, account, HealthKit, and workout flows were expanded to exercise the new contracts.
- Verification: `npm test` — `517/517` passed; `npm run build` — succeeded (`1,170` modules); `APEXTests` — `438/438` passed; affected workout UI flows — `2/2` passed; targeted hydration/HealthKit/account suite — `42/42` passed; Watch simulator build succeeded; `plutil -lint` passed for Watch/app/widget entitlements and plist; `codesign --verify --deep --strict` passed for both physical-device artifacts; `git diff --check` passed.
- Physical install: exact implementation SHA installed and launched on iConstantine Main (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, PID `992`) and Constantin's Apple Watch Ultra 3 (`F6BE2986-A704-5C82-BC2B-6D02E09CBD04`, PID `1322`). Watch inventory confirmed `APEX Water` bundle `ch.apexperformance.APEX.watchkitapp`, version `1.0.0`.
- Publication: pushed the implementation SHA to `main`, `codex/main-critical-repair`, and `codex/main-integration-20260824`. GitHub Pages run `32825393700` completed successfully and `https://evoryder8-collab.github.io/APXAppiC/` returned HTTP `200` with an implementation-SHA cache buster.
- Next: make barcode-scanned foods participate in account-scoped Food Memory recency on native and web, as a separate tested task.

## 2026-08-25 — Barcode foods participate in Food Memory recency

- Implementation commit: `b59589bf2f2ef7c7015489bf00f16deb568acd8d` (`fix: remember barcode foods in Food Memory`).
- Files changed: `AppSession.swift`, `MealMemory.swift`, `FoodLoggingViews.swift`, `MealMemoryParityTests.swift`, and `nutrition-experience.test.ts`.
- Changed: native barcode lookup now retains the resolved food in the active account's offline catalogue; direct and composed meal saves create/update exact-portion `food_preferences`; standalone Food Memory is reconstructed from immutable account-owned meal snapshots before catalogue backfill; recent sorting now uses `last_used_at` before lifetime usage. The existing web immutable-history implementation was retained and locked with a scanned-UUID regression test.
- Tests added: a native missing-catalogue scanned-food reconstruction case with cross-account exclusion, a native exact confirmed-amount preference case, and a web case proving yesterday's scanned UUID remains recent outside the loaded catalogue page.
- Red proof: the new native suite failed to compile because `MealMemory.recentFoods` and `MealMemory.usagePreferenceUpdates` did not exist; the web regression passed immediately, verifying that web already had the correct snapshot fallback rather than requiring duplicate logic.
- Test output: focused native `6/6` passed; focused web `1/1` passed; complete native `APEXTests` `440/440` passed; complete web `npm test` `518/518` passed; `npm run build` succeeded with `1,170` modules; `git diff --check` passed.
- Physical install: XcodeBuildMCP built, installed, and launched exact SHA `b59589bf2f2ef7c7015489bf00f16deb568acd8d` on iConstantine Main (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, PID `1074`). Device inventory confirmed `ch.apexperformance.APEX` version `1.0.0`, and `codesign --verify --deep --strict` passed.
- Next: push/publish this completed fix, then re-read the living roadmap changes and resume the next numbered Phase 1 task.

## 2026-08-25 — Task 1.7 exact workout timing and interruption recovery

- Implementation commit: `5483e9e3f574b88fb93de4a5807beb9555247426` (`fix: preserve authored workout timing`).
- Files changed: `ios/APEXNative/APEX/Core/Engine/MovementTiming.swift`, `ios/APEXNative/APEX/Core/Engine/PlayerTimeline.swift`, `ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift`, `ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift`, `ios/APEXNative/APEX/Features/Training/WorkoutDaySheet.swift`, `ios/APEXNative/APEXTests/PlayerTimelineTests.swift`, `src/lib/sessionShape.ts`, and `tests/player-timeline.test.ts`.
- Timing repair: explicit zero recovery no longer becomes the old 15- or 60-second default; ordinary custom rest stays exact; a transition retains only real next-movement setup time; positive rest after a high-fatigue movement retains the established 90-second safety floor. Native warm-up clocks now use the adjusted plan's authored duration instead of a hard-coded 180 seconds on every launch surface.
- Recovery and completion: foreground timers use wall-clock deltas; passive warm-up/rest clocks reconcile time spent backgrounded; an interrupted active set pauses rather than fabricating work. Guided drafts persist every meaningful transition and at a bounded five-second cadence, are keyed by account/day/date/full-or-lite mode and exercise revision, resume after process interruption, remain available after a failed save, and are removed only after successful completion or an explicit Delete action.
- Tests added: zero and custom rest resolution, movement setup and high-fatigue behavior, authored warm-up duration/absence, passive countdown expiry, manually paused countdown preservation, interrupted active-set pausing, account-scoped draft round-trip, foreign-account rejection, and completion-time draft clearing. Web parity locks zero/custom transition behavior.
- Red proof: native initially failed with 15 missing timer/draft APIs; after those existed, the behavioral test still failed `60 != 15` for zero recovery. Web independently failed `60 != 15`. The full web pass then exposed the pre-existing high-fatigue safety contract, and the implementation was narrowed to preserve it.
- Test output: focused native `14/14`; focused web timer/session `26/26`; complete native `APEXTests` `444/444`; complete web `npm test` `519/519`; affected guided-player UI flows `2/2`; `npm run build` succeeded with `1,170` modules; `git diff --check` passed.
- Physical install: XcodeBuildMCP with Xcode 27 beta built, signed, installed, and launched exact SHA `5483e9e3f574b88fb93de4a5807beb9555247426` on iConstantine Main (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, PID `1377`). The artifact passed `codesign --verify --deep --strict`; bundle `ch.apexperformance.APEX`, version `1.0.0`.
- Publication: pushed the implementation SHA to `main`, `codex/main-critical-repair`, and `codex/main-integration-20260824`. GitHub Pages run `32830865902` completed successfully, and the cache-busted live URL returned HTTP `200`.
- Next: re-read the living roadmap and begin Phase 1 Task 1.8, custom workouts runnable, as a separate tested commit.

## 2026-08-25 — Watch hydration uses exact beverage proportions without floating

- Implementation commit: `b29b5b14d77f2b0a492d66a5e1af98a642713066` (`fix: render honest hydration composition`).
- Files changed: `ios/APEXNative/APEX/Core/Engine/WatchHydrationFillState.swift`, `ios/APEXNative/APEXWatch/WatchHydrationView.swift`, `ios/APEXNative/APEXTests/HydrationGaugeTests.swift`, and `tests/watch-hydration-silhouette.test.ts`.
- Changed: removed the silhouette's sinusoidal vertical offset while retaining the low-power breathing glow, waterline, and horizontal gleam. One shared millilitre-weighted layout now drives both the silhouette and progress line; boundaries are centred on exact cumulative beverage shares and use at most a `0.4%` transition span. Silhouette stops map only into the currently filled vertical interval, so `900 mL` water plus `100 mL` coffee resolves to an exact `90%`/`10%` split rather than equal color bands.
- Tests added: exact `900/100` boundary and maximum-transition assertions, partial-fill coordinate mapping, a no-vertical-float source contract, and a contract proving the silhouette and gleam consume the same proportional stop layout.
- Red proof: native initially failed because `HydrationCompositionLayout` did not exist; the Watch contract independently failed on `floatOffset` and `.offset(y:)`. Both became green only after the production layout and rendering paths changed.
- Test output: focused native hydration `16/16`; focused Watch contracts `8/8`; complete native `APEXTests` `446/446`; complete web `npm test` `520/520`; `npm run build` succeeded with `1,170` modules; Watch Ultra 3 simulator build/install/launch succeeded; `git diff --check` passed. An accidental all-target run was stopped after its unrelated UI journey had passed `448` tests and repeatedly searched for `Daily log`; it reported zero failures but is not used as completion evidence.
- Physical installs: XcodeBuildMCP with Xcode 27 beta built, signed, installed, and launched exact SHA `b29b5b14d77f2b0a492d66a5e1af98a642713066` on iConstantine Main (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, bundle `ch.apexperformance.APEX`, PID `1530`) and Apple Watch Ultra 3 (`F6BE2986-A704-5C82-BC2B-6D02E09CBD04`, bundle `ch.apexperformance.APEX.watchkitapp`, PID `1519`).
- Publication: pushed the implementation SHA to `main`, `codex/main-critical-repair`, and `codex/main-integration-20260824`. GitHub Pages run `32833272852` completed successfully (build `20s`, deploy `10s`), and `https://evoryder8-collab.github.io/APXAppiC/?hydration=b29b5b14d` returned HTTP `200`.
- Next: address the requested Simple Mode cleanup and truthful burned/activity summary as a separate red/green commit before Task 1.8.

## 2026-08-25 — Pre-1.8 Simple Mode health-summary cleanup

- Removed the redundant Simple Mode greeting and manual Today’s Checklist in both clients. Daily completion now lives in the Nutrition at a glance header.
- Replaced the meal-count side metric with resolved active calories burned on Simple Mode and Nutrition. A positive whole-day wearable value is authoritative; APEX estimates are used only when that value is absent, so measured and estimated expenditure are never summed.
- The collapsed native Wearable Activity card now exposes steps, active kcal, and exercise minutes whenever a dated wearable record exists.
- Files changed: `ios/APEXNative/APEX/Features/Nutrition/EnergyEngine.swift`, `ios/APEXNative/APEX/Features/Nutrition/NutritionParityViews.swift`, `ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift`, Romanian/Thai native strings, `ios/APEXNative/APEXTests/EnergyEngineTests.swift`, `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`, `src/lib/activity.ts`, `src/lib/translations.ts`, `src/components/food/ActualFoodTracker.tsx`, `src/components/food/NutritionGlance.tsx`, `src/pages/SimpleHome.tsx`, `src/pages/Nutrition.tsx`, `tests/activity.test.ts`, and `tests/simple-home-cleanup.test.ts`.
- Red/green evidence: the new resolver tests initially failed because no wearable-precedence API existed; four new source contracts initially failed for the still-present greeting/checklist, external completion ring, Meals metric, and hidden collapsed wearable facts.
- Tests: focused native 14/14; focused web 32/32; native Simple Mode UI flow 1/1; full native unit suite 447/447; full web suite 526/526; `npm run build` passed with 1,170 modules; `git diff --check` passed.
- Implementation commit: `ea581847bd57516b15fd522f9b63f6dabd023426` (`fix: simplify daily health summary`).
- Physical iPhone: signed Debug build from exact implementation SHA `ea581847b` installed and launched on `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, PID 1793.
- GitHub: implementation pushed to `main`, `codex/main-critical-repair`, and `codex/main-integration-20260824`.
- Pages: run `32836678958` succeeded; `https://evoryder8-collab.github.io/APXAppiC/?simple=ea581847b` and the hash route both returned HTTP 200.
- Next: resolve the requested sleep-score provenance mismatch as its own tested pre-1.8 task.

## 2026-08-25 — Pre-1.8 honest sleep-score provenance

- Root cause: native APEX converted imported sleep duration with `hours / 8 * 100` and presented the result as Apple’s Sleep Score. That made roughly 4.2 hours appear as 52 even when the Sleep app’s composite score was 57.
- Removed the duration-to-score conversion. HealthKit sleep duration remains a separately labelled measured fact; APEX shows no invented readiness band until an explicit vendor score exists. An entered Watch score is preserved verbatim and blank fields can no longer save a fabricated zero.
- The expanded editor now explains the public API boundary, labels the field `Watch Sleep Score`, wraps its explanatory copy instead of truncating it, and keeps Romanian/Thai parity. Web copy states the same provenance boundary.
- Apple verification: the installed iOS/watchOS beta SDK headers contain no public HealthKit sleep-score symbol. Apple’s public HealthKit data-type documentation exposes sleep-analysis stages, while Apple Support documents Sleep Score as a separate composite of duration, consistency, and interruptions.
- Files changed: `ios/APEXNative/APEX/Core/Engine/RecoveryAssessment.swift`, `ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift`, Romanian/Thai native strings, `ios/APEXNative/APEXTests/MealTimingAndRecoveryTests.swift`, and `src/components/RecoveryCheckinCard.tsx`.
- Red/green evidence: `testSleepDurationNeverMasqueradesAsAppleSleepScore` failed with an invented 90 from 7.2 hours before the fix; it now passes. `testRecordedAppleSleepScoreIsNeverRecomputedFromDuration` proves an explicit 57 remains 57 alongside a 4.16-hour duration.
- Tests: focused recovery/localization 20/20; focused web protocol 7/7; full native unit suite 447/447; full web suite 526/526; `npm run build` passed with 1,170 modules; `git diff --check` passed.
- Implementation commit: `2f8818a40659ae73a6c86c992b07e3c3c7a0c893` (`fix: keep sleep duration separate from score`).
- Physical iPhone: signed Debug build from exact implementation SHA `2f8818a40` installed and launched on `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, PID 1903.
- GitHub: implementation pushed to `main`, `codex/main-critical-repair`, and `codex/main-integration-20260824`.
- Pages: run `32837962231` succeeded; `https://evoryder8-collab.github.io/APXAppiC/?sleep=2f8818a40` returned HTTP 200.
- Next: add an explicit plan-duration question to both plan builders as its own tested pre-1.8 task.

## 2026-08-25 — Pre-1.8 generated plan duration is explicit and finite

- Added a dedicated duration question to both web and native plan builders, including first-run native onboarding. Choices are 4, 8, or 12 weeks and 6 months (stored as 26 weeks); old plans without the field restore as 12 weeks.
- Generation now persists `plan_weeks`, `transition_weeks`, and an exclusive `end_date`. Four-, eight-, and twelve-week plans remain bounded foundations; the six-month choice uses the established twelve-week foundation followed by a main phase through week 26. Calendar and Simple Mode stop projecting workouts at the end date, and Simple Mode selects the correct active phase during a six-month plan.
- Files changed: `src/lib/types.ts`, `src/lib/trainingInduction.ts`, `src/components/workout/TrainingInductionPanel.tsx`, `src/pages/SimpleHome.tsx`, `tests/training-induction.test.ts`, `ios/APEXNative/APEX/Core/Engine/TrainingInduction.swift`, `TrainingPlanEngine.swift`, native onboarding/return-builder/Simple Mode/program views, Romanian/Thai strings, native generation/calendar tests, and the return-builder UI flow.
- Red/green evidence: the new web test failed `undefined !== 4` because the selected duration was discarded; native failed to compile because `TrainingInduction.Input` had no `planWeeks`. Both now prove 4-week expiry at day 28 and 6-month expiry at week 26, including main-phase activation only inside its real window.
- Tests: focused web 19/19; focused native duration/calendar/UI/localization 14/14; native return-builder UI flow 1/1; full native unit suite 449/449; full web suite 527/527; `npm run build` passed with 1,170 modules; `git diff --check` passed.
- Implementation commit: `22e2ccdd74d485d3c7b95d6f07400870836418f3` (`feat: bound generated plans to chosen duration`).
- Physical iPhone: signed Debug build from that exact implementation SHA, including the validated embedded Watch app, installed and launched on `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, PID 1996.
- GitHub/Pages: implementation pushed to `main`; Pages run `32840299271` succeeded, and `https://evoryder8-collab.github.io/APXAppiC/?plan-duration=22e2ccdd74d485d3c7b95d6f07400870836418f3` returned HTTP 200.
- Next: implement the approved scientifically grounded baseline and activity-aware hydration target as a separate red/green task before Task 1.8.

## 2026-08-25 — Pre-1.8 hydration targets adapt without pretending to measure sweat

- Added an account-scoped `automatic`/`custom` hydration target mode shared by web, iPhone, Watch, and complications. Existing non-default targets remain exact custom choices; only the legacy app default (`2.75 L`) migrates to automatic.
- Automatic mode is explicitly presented as an APEX total-water estimate, not a diagnosis. The body-size estimate is bounded by the EFSA/National Academies sex-specific adult total-water references. Planned and recorded training use the larger value rather than being summed. After 15:00, active calories or steps may select only a small capped wearable buffer; neither is converted into claimed sweat loss. Drinks and food water remain separately attributable while their sum answers the total-water target.
- Exact custom targets remain exact and never drift with plans, workouts, calories, or steps. Fitness goal affects hydration only through the actual generated session duration, avoiding an extra untraceable goal multiplier. Simple Mode and Nutrition now feed the same scheduled-session fact into the policy.
- Migration `027_adaptive_hydration_target.sql` was applied by itself to the linked Supabase project. Readback verified `target_mode text NOT NULL DEFAULT 'automatic'`, the `hydration_target_mode` check constraint, and preservation of the one existing preference as `custom`; no older local migration was pushed.
- Files changed: hydration policy/ledger/store code on web; Simple Mode and Nutrition target presentation; native session, ledger, Simple Mode, Watch store/settings, and Romanian/Thai copy; migration 027; and web/native hydration regression suites.
- Red/green evidence: the initial policy tests failed because the target resolver/migration did not exist; the later steps-only regression independently failed `0 !== 100` before the HealthKit steps fallback was implemented. Both clients now cover body bounds, plan/recorded deduplication, late calorie and steps signals, capped adjustments, legacy mode inference, old Watch-cache decoding, and exact custom overrides.
- Tests: focused web hydration `23/23`; complete web `npm test` `535/535`; focused native hydration/preferences `12/12`; complete post-change native unit/integration `457/457`; the all-target run passed `468/468` (`456` unit/integration plus `12` UI smoke) before the final steps-only policy case, whose post-change native compilation and focused/full unit runs are green. `npm run build` passed with `1,170` modules and `git diff --check` passed.
- Implementation commit: `fa9750672114b0a4bd7589d3f4f5a2702914a836` (`feat: adapt hydration targets to body and activity`).
- Physical installs: deep signature verification passed for the iPhone and embedded Watch apps. That exact SHA was installed and launched on iConstantine Main (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, bundle `ch.apexperformance.APEX`) and directly installed and launched on Constantin's physical Apple Watch Ultra 3 (`F6BE2986-A704-5C82-BC2B-6D02E09CBD04`, bundle `ch.apexperformance.APEX.watchkitapp`).
- GitHub/Pages: implementation fast-forwarded to `main`, `codex/main-critical-repair`, and `codex/main-integration-20260824`. Pages run `32859727143` succeeded (build `25s`, deploy `11s`); `https://evoryder8-collab.github.io/APXAppiC/?hydration=fa9750672114b0a4bd7589d3f4f5a2702914a836` returned HTTP `200`.
- Next: create the approved post-generation plan briefing slides as their own tested pre-1.8 task, then resume Task 1.8.

## 2026-08-25 — Pre-1.8 generated-plan briefing is complete

- Added a five-card briefing after a generated plan installs: exact plan duration/structure, safety, personalized hydration, sleep, and evidence-qualified supplement guidance. Both clients support swipe navigation, a one-time reduced-motion-aware first-card nudge, dismissal into the installed plan, and reopening through `Plan Guide`.
- The safety artwork was replaced at the user's request with a bold cel-shaded graphic-novel key-art illustration; the other four approved illustrations were left unchanged. The source image was generated with transparency, resized to `888 × 900`, and installed in matching web and native asset paths.
- Kept guidance honest: no invented medical guarantees, no universal salt prescription, no profile-weight fabrication, and no unsupported supplement claims. Hydration uses the shared `HydrationTargetPolicy`; the six-month briefing reflects the real 26-week plan and transition.
- Files changed: `src/lib/planBriefing.ts`, the web induction panel and test; native `TrainingInduction.swift`, induction/program views, unit/UI tests; five web briefing images; and five matching native image sets.
- Red/green evidence: web initially failed because the briefing module did not exist; native initially failed because no `planBriefing` API existed. The expanded UI test then exposed two real lifecycle defects (the deck was suppressed without a profile and the panel disappeared after commit), plus a dismissal identifier mismatch; all were repaired in production code. The replacement test also caught and removed an em-dash copy regression.
- Tests: complete web `npm test` `541/541`; `npm run build` passed with `1,171` modules; native `TrainingInductionTests` `53/53`; focused physical-iPhone tests `2/2`; full install/briefing/reopen UI journey `1/1`; `git diff --check` passed. The final screenshot was visually inspected with an opaque, non-truncated deck and the new safety artwork.
- Implementation commit: `665ea022055a073cc01e68aa0eb9bd5ae0e18ecb` (`feat: brief generated training plans`).
- Physical iPhone: a fresh signed build from that exact SHA passed `codesign --verify --deep --strict`, validated its embedded APEX Water watch app, installed on `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, and launched as `ch.apexperformance.APEX`.
- Next: publish and verify this task, then re-read the living roadmap before Task 1.8. Task 1.8 has not started.

## 2026-08-25 — Pre-1.8 generated-plan installation collision repair

- Root cause: the four-day-or-higher Home/Outdoors `Upper B` template copied a second position-1 exercise into the same `upper-pair`. The generated batch therefore violated the live `exercises_work_group_position_unique` index before the post-generation briefing could open.
- Corrected the shared structure in both generators: the intended push/row pair remains linked at positions 1 and 2, while the additional press is explicitly standalone. The database constraint remains unchanged and continues to reject genuinely ambiguous groups.
- Files changed: `src/lib/trainingInduction.ts`, `tests/training-induction.test.ts`, `ios/APEXNative/APEX/Core/Engine/TrainingInduction.swift`, and `ios/APEXNative/APEXTests/ManualAndInductionTests.swift`.
- Tests added: both clients now generate every Home, Gym, and Outdoors plan at every supported 2–7-day frequency and assert uniqueness of `(program day, full-or-lite mode, work group, position)`.
- Red proof: web reproduced `home/4` with only `8` unique keys from `10` grouped rows; native reproduced the same collision for Home and Outdoors at 4, 5, 6, and 7 days. The unchanged tests pass only after the copied press loses its stale grouping metadata.
- Test output: focused web `1/1`; focused native `1/1`; complete web `542/542`; native induction `54/54`; complete native unit suite `460/460`; `npm run build` passed with `1,171` modules; `git diff --check` passed.
- Implementation commit: `6043a487fcaafaa2583d92aa108e4a0c838c9d88` (`fix: keep generated work groups unique`).
- Physical iPhone: a fresh signed build from that exact SHA passed `codesign --verify --deep --strict`, validated the embedded APEX Water watch app, installed on `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, and launched as `ch.apexperformance.APEX`.
- Retry behavior: the pre-existing interrupted-save tests prove the builder remains available after an exercise-batch failure; resubmission safely upserts the already-created program/day rows before saving the corrected exercise batch.
- Next: publish and verify this repair, then re-read the living roadmap before Task 1.8. Task 1.8 has not started.

## 2026-08-25 — Pre-1.8 plan briefing opens the daily Simple Mode surface

- Changed the final `Open my plan` action on both clients to select the account-scoped Simple Mode setting and return to the root daily surface. The X remains dismissal-only, so closing the guide keeps the user on Main Phase and does not change their selected interface mode.
- Native mode changes now update root navigation synchronously before a full-screen briefing is dismissed, while server persistence remains owner-verified and account-generation guarded in the background. This prevents the old Advanced root from flashing back into place.
- Files changed: `src/components/workout/TrainingInductionPanel.tsx`, `src/lib/simpleMode.ts`, `tests/simple-mode.test.ts`, native `AppSession.swift`, `PortalUIMode.swift`, `TrainingInductionPanel.swift`, and `APEXSmokeUITests.swift`.
- Tests added/strengthened: web proves the destination is `/`, `uiMode` becomes `simple`, and unrelated add-ons survive. Native UI first dismisses with X and verifies the generated plan metadata remains intact, then reopens the briefing and proves the CTA selects Simple, deselects Advanced, exposes the Simple-only training surface, and does not reopen the builder.
- Red/green evidence: the web test initially failed because `planBriefingExit` did not exist. The native UI test then caught the deferred root update by landing on Advanced; after the synchronous local mutation it passed. Final output: web `543/543`; native unit suite `460/460`; native install/briefing/dismiss/reopen/open journey `1/1` in `41.685s`; production web build passed with `1,171` modules; `git diff --check` passed.
- Implementation commit: `20120a160c0abe8379e2d58f2fc0e6ee5ec01140` (`fix: open installed plans in simple mode`).
- Physical iPhone: a fresh signed build from that exact SHA passed `codesign --verify --deep --strict`, validated the embedded `APEX Water` watch app and `APEXWatchWidgets` complication, installed on `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, and launched as `ch.apexperformance.APEX`.
- Next: publish and verify this repair, then re-read the living roadmap before Task 1.8. Task 1.8 has not started.
## 2026-08-25 — Pre-1.8 native hydration refinement

- Files changed: `ios/APEXNative/APEX/Features/Portal/HydrationFigureWebView.swift`, `PortalShellView.swift`, `SimpleHomeView.swift`, both bundled hydration SVG/HTML resources, `HydrationGaugeTests.swift`, and `APEXSmokeUITests.swift`.
- Implementation commit: `031fd567e9be760107f412b25f3aeead90476e9c` (`fix: refine native hydration entry`).
- Tests added:
  - `WatchHydrationFillStateTests.testFigureBridgeCarriesWeightedStopsAcrossTheVisibleFill` proves explicit 900 mL water / 100 mL coffee boundaries survive the Swift-to-WebKit bridge and remain confined to the visible fill.
  - `APEXSmokeUITests.testWaterQuickAddDismissesAnEmptyNumericKeyboardAndKeepsSettingsAtTheBottom` opens the real sheet, focuses an empty numeric input, dismisses it without logging, verifies bottom-only settings placement, and captures the refined UI.
- Test output:
  - Native unit suite: `461 tests, 0 failures`, `** TEST SUCCEEDED **`.
  - Focused hydration suite: `10 tests, 0 failures`.
  - Hydration UI flow: passed in `22.907 seconds`, `** TEST SUCCEEDED **`.
  - `git diff --check`: clean.
- Device evidence: exact SHA `031fd567e9be760107f412b25f3aeead90476e9c` built with `** BUILD SUCCEEDED **`, passed `codesign --verify --deep --strict`, installed to connected iPhone `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, and launched as `ch.apexperformance.APEX`. The embedded `APEX Water.app` and `APEXWatchWidgets.appex` were signed in the same build.

## 2026-08-25 — Pre-1.8 repair: honest workout history and tracked entry

- Implementation commit: `9243d9e59eb9de5434029d10d5d1fdafcd96f626` (`fix: restore honest workout history`).
- Completed Simple Mode training cards now open the latest completed receipt for the exact selected date and programme day instead of offering to start the workout again.
- Strength history now groups regenerated exercise rows by canonical movement, emits one chart point per completed session, and reports the real session count. The web and native engines share the same regenerated parity fixture.
- Workout receipts now preserve distinct strength insights while rendering repeated first-baseline copy only once on both clients.
- Tracked numeric fields keep keystrokes local, commit after a 300 ms pause or focus loss, and reuse cached exercise descriptors and work-group labels instead of rebuilding them for every row on every keypress.
- Tests added:
  - `SimpleHomeLogicTests.testCompletedTrainingOpensTheLatestReceiptForThatExactDayAndPrescription`
  - `StrengthProgressParityTests.testTrackedHistoryKeepsOnePointPerSessionAcrossRegeneratedExerciseRows`
  - `WorkoutReceiptTests.testStrengthSignalDeduplicatesIdenticalBaselineCopy`
  - `ExerciseLoggingTests.testNumericFactDraftSeparatesCommittedValuesFromIncompleteTyping`
  - matching TypeScript regenerated-row and receipt-deduplication tests in `tests/strength-progress.test.ts`
- Red checks captured the prior failures: missing completed-session resolver; two one-session Front Lunge series; missing receipt deduplication helper; missing numeric draft resolver.
- Verification:
  - web focused strength suite: 8/8 passed
  - web full suite: 545/545 passed in 4.75 s
  - production web build: TypeScript passed; Vite transformed 1,171 modules
  - native focused history/home suite: 15/15 passed
  - native full suite: 465/465 passed, 0 failed, 0 skipped
  - `git diff --check`: clean
- Physical-device evidence for exact commit `9243d9e59eb9de5434029d10d5d1fdafcd96f626`:
  - iPhone build succeeded; deep strict code-sign verification passed; installed and launched as `ch.apexperformance.APEX`
  - embedded `APEX Water.app` and `APEXWatchWidgets.appex` strict signatures passed
  - installed and launched directly on connected physical Apple Watch Ultra 3 as `ch.apexperformance.APEX.watchkitapp`

## 2026-08-25 — Honest morning health facts and one calendar path

- Scope: completed the pre-1.8 Morning Check repair without deriving or claiming access to Apple's proprietary Sleep Score. HealthKit continues to provide measured sleep duration/stages; APEX now accepts the score explicitly when the user wants it, and a morning weigh-in can be saved independently without creating a fake score. The lower duplicate Nutrition calendar button was removed; the persistent top date navigator remains.
- Apple API verification: the iOS 27 HealthKit SDK contains no Sleep Score symbol, and Apple DTS states that there is no API for third-party access to the score (`https://developer.apple.com/forums/thread/800403`). Apple's own description documents the 0–100 display and its duration/consistency/interruption components but does not expose a HealthKit score type (`https://support.apple.com/en-euro/guide/watch/apded441a669/26/watchos/26`).
- Files changed:
  - `ios/APEXNative/APEX/App/AppSession.swift`
  - `ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift`
  - `ios/APEXNative/APEX/Features/Portal/PortalUIMode.swift`
  - `ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift`
  - `ios/APEXNative/APEXTests/SimpleHomeLogicTests.swift`
  - `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`
- Implementation commit: `2b0f8391714b9f9224efddd4bcbb83474db51dde` (`fix: make morning health facts honest`).
- Tests added:
  - `testMorningCheckAcceptsWeightWithoutFabricatingAnAppleSleepScore`
  - `testMorningWeightPreservesExistingDailyNutritionFacts`
  - `testMorningCheckAcceptsWeightWithoutForcingASleepScore`
- Red proof: the focused test build failed with four `Cannot find 'MorningCheckLogic' in scope` errors before implementation.
- Test output after implementation:
  - focused native logic: 8 tests, 0 failures;
  - full native unit suite: 467 tests, 0 failures;
  - driven XCUITest flow: 1 test, 0 failures in 18.310 seconds, including keyboard dismissal and weight-only save;
  - full web suite: 545 tests, 545 passed, 0 failed in 4.889 seconds;
  - production web build: TypeScript clean, 1,171 modules transformed;
  - `git diff --check`: clean.
- Physical delivery from the exact implementation SHA:
  - device build: `** BUILD SUCCEEDED **`;
  - strict signatures valid for `ch.apexperformance.APEX`, `ch.apexperformance.APEX.watchkitapp`, and `ch.apexperformance.APEX.watchkitapp.widgets`, Team ID `UG979XDY72`;
  - iPhone 15 Pro Max: app installed and launched from `2b0f8391714b9f9224efddd4bcbb83474db51dde`;
  - physical Apple Watch Ultra 3: Watch app installed directly and launched from the same build.
- GitHub: the implementation SHA was atomically pushed to `main`, `codex/main-critical-repair`, and `codex/main-integration-20260824`.
- GitHub Pages: run `32898667184` succeeded (build 23 seconds, deploy 35 seconds); `https://evoryder8-collab.github.io/APXAppiC/?morning-health=2b0f8391714b9f9224efddd4bcbb83474db51dde` returned HTTP 200.

## 2026-08-25 — Practical food discovery and honest meal guidance

- Scope: completed the pre-1.8 nutrition repair. Food Memory now has one reachable bottom search control on native, generic meal guidance is structured into five-item carbohydrate/protein/fat groups (and five quick snack picks), wearable-to-manual activity switching explains the consequence plainly, and common kebab spellings resolve to one evidence-labelled Swiss reference food instead of fabricated retailer or restaurant variants. Existing account-authored meal guides remain untouched.
- Evidence source: Swiss Food Composition Database v7.1, food ID 1572 (`https://naehrwertdaten.ch/de/downloads/`). The reference row records 121 kcal, 7.6 g protein, 14.6 g carbohydrate, 3.4 g fat, and 73.6 g water per 100 g; the UI states that restaurant recipes and sauces vary.
- Files changed:
  - `src/lib/mealGuide.ts`
  - `src/components/food/MealComposer.tsx`
  - `src/data/foodCatalogExpansion.ts`
  - `src/data/foodSeeds.ts`
  - `src/lib/food.ts`
  - `src/pages/Nutrition.tsx`
  - `supabase/migrations/028_swiss_kebab_reference.sql`
  - `ios/APEXNative/APEX/Core/Engine/MealProtocolGuide.swift`
  - `ios/APEXNative/APEX/Features/Nutrition/FoodLoggingViews.swift`
  - `ios/APEXNative/APEX/Features/Nutrition/MealComposerView.swift`
  - `ios/APEXNative/APEX/Features/Nutrition/NutritionParityViews.swift`
  - `tests/food.test.ts`
  - `tests/meal-guide.test.ts`
  - `tests/nutrition-experience.test.ts`
  - `tests/swiss-food-migration.test.ts`
  - `ios/APEXNative/APEXTests/MealProtocolGuideTests.swift`
  - `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`
- Implementation commit: `03fcbdf7acb60e72456cbe652600188c532a9a52` (`fix: make nutrition discovery practical`).
- Tests added: Swiss kebab aliases/provenance/nutrition, generic grouped meal guidance and bespoke-account preservation, migration contract, native grouped-guide parity, and a native Food Memory UI assertion that the bottom field exists while the dead navigation magnifier does not.
- Red proof: three focused web contracts failed before implementation (missing Swiss food, missing grouped-guide module, and missing activity/search UX); the focused native build failed because `MealProtocolGuide.sections` did not exist.
- Test output after implementation:
  - focused web nutrition suite: 69 tests, 69 passed, 0 failed in 2.652 seconds;
  - focused native meal-guide suite: 15 tests, 0 failures in 0.013 seconds;
  - migration contract: 1 test, 1 passed;
  - driven Food Memory XCUITest flow: 1 test, 0 failures in 25.244 seconds;
  - full native unit suite: 468 tests, 0 failures in 2.086 seconds;
  - full web suite: 550 tests, 550 passed, 0 failed in 4.679 seconds;
  - production web build: TypeScript clean, 1,172 modules transformed;
  - `git diff --check`: clean.
- Database delivery: migration 028 was applied idempotently to linked Supabase project `rrzcrcjsbkmidlafrhfv`; the live row was queried back with the exact fixed ID, provider, macros, water basis, and source ID.
- Physical delivery from the exact implementation SHA:
  - device build: `** BUILD SUCCEEDED **`;
  - strict signatures valid for `ch.apexperformance.APEX` and `ch.apexperformance.APEX.watchkitapp`;
  - connected iPhone: app installed and launched from `03fcbdf7acb60e72456cbe652600188c532a9a52`;
  - connected physical Apple Watch Ultra 3: Watch app installed directly and launched from the same build.
- GitHub: the implementation SHA was pushed to `main`, `codex/main-critical-repair`, and `codex/main-integration-20260824`.
- GitHub Pages: run `32901347444` succeeded; `https://evoryder8-collab.github.io/APXAppiC/?sha=03fcbdf7a` returned HTTP 200.

## 2026-08-26 — Generated-plan briefing refinement (before roadmap 1.8)

- Implementation commit: `961dac0ab904996f7bd79140c84cf2d424a271ba` (`fix: refine generated plan briefing`).
- Files changed:
  - `src/lib/planBriefing.ts`
  - `src/components/workout/TrainingInductionPanel.tsx`
  - `tests/plan-briefing.test.ts`
  - `public/plan-briefing/plan-briefing-safety.png`
  - `ios/APEXNative/APEX/Core/Engine/TrainingInduction.swift`
  - `ios/APEXNative/APEX/Features/Training/TrainingInductionPanel.swift`
  - `ios/APEXNative/APEX/Resources/Assets.xcassets/plan-briefing-safety.imageset/plan-briefing-safety.png`
  - `ios/APEXNative/APEXTests/ManualAndInductionTests.swift`
  - `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`
- Result:
  - Replaced dense, repetitive briefing copy with five scannable cards and semantic per-tip icons in both clients.
  - `Open my plan` appears only on the final card; earlier cards advance with `Next tip`; the final route remains Simple Mode.
  - Safety copy distinguishes ordinary effort, stop rules, emergency symptoms and Swiss emergency number 144.
  - Hydration remains driven by the shared personalized target policy; supplement copy remains food-first and qualified.
  - Evidence links now use the Swiss Heart Foundation, Swiss FSVO, Swiss Society for Sleep Research and Swiss Sports Nutrition Society.
  - Replaced the old safety character with a transparent 1254×1254 painterly open-world-game-key-art illustration; native and web files share SHA-256 `2c800f7dc38112a6cb8ba27649459be2987333985f5f82d7d8581726ff5bcf20`.
- Red proof:
  - Web briefing suite: 2 passed / 6 failed before the new copy, model, source links, asset and UI contracts existed.
  - Native focused build failed to compile while tests referenced the not-yet-implemented per-tip icon and evidence model.
  - The first green attempt was 7/8 and correctly rejected safety copy that omitted an explicit stop instruction; native then executed 3 focused tests and correctly rejected copy that omitted the word `emergency`.
- Green verification:
  - Focused web briefing tests: 8/8 passed.
  - Focused native briefing tests: 3/3 passed, 0 skipped.
  - Native end-to-end induction/briefing/Simple Mode flow: 1/1 passed in 44.243 seconds.
  - Full web suite: 552/552 passed in 4.731 seconds.
  - Full native unit suite: 469/469 passed, 0 skipped.
  - Production web build: TypeScript clean; Vite transformed 1,172 modules; `git diff --check` clean.
- Physical deployment for exact implementation SHA `961dac0ab904996f7bd79140c84cf2d424a271ba`:
  - Apple Development build succeeded for `iphoneos` and `watchos`; strict signatures passed for APEX, APEX Water and APEXWatchWidgets.
  - Installed and launched `ch.apexperformance.APEX` on physical iPhone 15 Pro Max `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`.
  - Installed and launched `ch.apexperformance.APEX.watchkitapp` on physical Apple Watch Ultra 3 `F6BE2986-A704-5C82-BC2B-6D02E09CBD04`.
- Publication:
  - Pushed the implementation SHA to `main`, `codex/main-critical-repair` and `codex/main-integration-20260824`.
  - GitHub Pages run `32904688560` succeeded.
  - `https://evoryder8-collab.github.io/APXAppiC/` returned HTTP 200; the live safety asset returned HTTP 200 and matched the committed SHA-256 exactly.

## 2026-08-26 — Restore the owner-approved plan safety artwork

- Implementation commit: `ac8a46347` (`fix: restore approved plan safety artwork`).
- Files changed: the matching web and native `plan-briefing-safety.png` assets and `tests/plan-briefing.test.ts`.
- Result: restored the exact earlier 888×900 transparent illustration in both clients and converted the asset test into an owner-approval lock on SHA-256 `b28b785dafb6d58d8e1abd72b8d7cafb9c13dd671b8bc83e876984832ea79b83`.
- Red proof: focused briefing suite ran 7/8; the asset contract rejected the replacement SHA `2c800f7dc38112a6cb8ba27649459be2987333985f5f82d7d8581726ff5bcf20`.
- Green proof: focused briefing suite ran 8/8 in 44.546 ms; web/native assets are byte-identical and retain RGBA transparency; `git diff --check` passed.
- Physical-device and publication evidence: aggregate source SHA `96c6b82f18` built successfully for a signed physical device, passed deep signature verification, installed and launched on `iConstantine Main` (iOS 27.0), and its signed companion installed and launched on `Constantin’s Apple Watch` (watchOS 27.0). Pages run `32937833636` built and deployed successfully; the live site returned HTTP 200 and served this approved asset at exact SHA-256 `b28b785dafb6d58d8e1abd72b8d7cafb9c13dd671b8bc83e876984832ea79b83`.

## 2026-08-26 — Past-day hydration reductions cannot increase water

- Implementation commit: `f64063174a` (`fix: make hydration reductions monotonic`).
- Files changed: `ios/APEXNative/APEX/App/AppSession.swift`, `Core/Engine/HydrationLedger.swift`, and `APEXTests/FoodHydrationTests.swift`.
- Root cause: partial reduction deleted the current event through the full delete path and then logged its retained amount as a new event. Between those operations, the now-empty ledger fell back to the stale `DailyLog.waterL`; past-day legacy materialization could treat that old aggregate as fresh water and then add the retained amount, producing the reported upward jump. Concurrent remove taps could interleave across the same suspension points.
- Fix: reductions now calculate one deterministic final ledger, stage its exact legacy mirror before the first persistence suspension, update partial events in place, and serialize rapid adjustment taps in their original order. HealthKit mirrors are replaced only after the local total is already monotonic.
- Tests added:
  - `testPastDayReductionsNeverResurrectTheLegacyAggregate` applies −250, −500 and −300 successively and proves every result is non-increasing through exact zero.
  - `testRapidHydrationAdjustmentsRunInTapOrderWithoutOverlap` proves a delayed first tap finishes before the next mutation starts.
- Red proof: focused native build failed with missing `HydrationLedger.reductionPlan` and `HydrationMutationQueue`, demonstrating the old implementation had neither atomic reduction nor serialization.
- Green proof: focused hydration suite 27/27; complete native unit suite 471/471, 0 failed, 0 skipped; `git diff --check` passed.
- Physical-device and publication evidence: aggregate source SHA `96c6b82f18` built successfully for a signed physical device, passed deep signature verification, installed and launched on `iConstantine Main` (iOS 27.0), and its signed companion installed and launched on `Constantin’s Apple Watch` (watchOS 27.0). Pages run `32937833636` built and deployed successfully; the live site returned HTTP 200.

## 2026-08-26 — Calendar keeps the real current day visible

- Implementation commit: `25439159a4` (`fix: keep today visible in calendars`).
- Files changed: `ios/APEXNative/APEX/Core/Engine/FocusT25.swift`, `Features/Nutrition/NutritionParityViews.swift`, `APEXTests/TrainingCalendarDayTests.swift`, `src/lib/activeDate.ts`, `src/pages/SimpleHome.tsx`, `src/components/NutritionLogCalendar.tsx`, and `tests/active-date.test.ts`.
- Fix: selection and current-day state are now independent. Native and web calendars keep a conventional circular marker around the real current date while another day is selected, and expose the date through VoiceOver/`aria-current="date"` rather than relying on colour alone.
- Red proof: focused web failed because `calendarDayState` did not exist; focused native failed because `APEXDateMath.calendarDayState` did not exist.
- Green proof: active-date web contract 4/4; native current-day regression 1/1; native calendar suite 12/12; complete web suite 553/553; production TypeScript/Vite build succeeded with 1,172 modules; `git diff --check` passed.
- Before this task, the unchanged signed companion from aggregate app SHA `96c6b82f18` was reinstalled and launched successfully on the connected `Constantin’s Apple Watch` (watchOS 27.0, process 460), as explicitly requested. The calendar implementation will be included in the next aggregate physical-device build.

## 2026-08-26 — Weighted bodyweight work contributes honest loaded volume

- Implementation commit: `ea4eb548ae` (`fix: count weighted bodyweight volume`).
- Files changed: `ios/APEXNative/APEX/Core/Engine/WorkoutReceipt.swift`, `ios/APEXNative/APEXTests/WorkoutReceiptTests.swift`, `src/lib/exerciseLogging.ts`, and `tests/exercise-logging.test.ts`.
- Root cause: both receipt implementations admitted only movements resolved as `strength`, so every `bodyweight` movement was discarded before its signed external load was examined. A weighted push-up with `+7 kg` therefore contributed zero even though its measured reps and load were present.
- Fix: loaded volume now accepts strength and bodyweight rows, counts only the positive side of the shared signed-load axis, and continues to treat negative assistance as zero.
- Tests added: the shared regression scenario combines a `50 kg × 10` bench press, `−20 kg` assisted pull-up, and `+7 kg × 10` weighted push-up and requires an exact `570 kg` total in both clients.
- Red proof: web focused suite failed with `500 !== 570`; native focused suite failed with `500 != 570`, demonstrating that the old readers dropped the weighted push-up.
- Green proof: web exercise-logging suite 15/15; native WorkoutReceipt suite 9/9; complete web suite 552/552; complete native logic suite 471/471. The aggregate native run passed 484/485 before one unrelated Water Quick Add UI snapshot timed out; that exact UI test immediately passed 1/1 in isolation. `git diff --check` passed.
- Physical-device and publication evidence: aggregate source SHA `96c6b82f18` built successfully for a signed physical device, passed deep signature verification, installed and launched on `iConstantine Main` (iOS 27.0), and its signed companion installed and launched on `Constantin’s Apple Watch` (watchOS 27.0). Pages run `32937833636` built and deployed successfully; the live site returned HTTP 200.

## 2026-08-26 — Generated plans govern nutrition targets and briefing

- Implementation commit: `aeeee2b954` (`feat: adapt nutrition targets to generated plans`).
- Files changed: shared web and native nutrition policy/target engines, plan briefing and induction views, every target consumer, a reusable three-choice goal picker in each client, and focused web/native regression tests.
- Result: the existing three persisted goal slots are interpreted lazily from the installed plan's questionnaire goal and duration, with distinct, plain-language choices for general fitness, muscle gain, fat loss, strength and endurance. Every choice exposes its energy effect, purpose and caution. The generated-plan briefing now opens by explaining why the plan and its three energy choices fit the assessment. The existing BMR safety floor remains authoritative; no crash-diet target or data migration was introduced.
- Red proof: the new web contract initially failed because the plan-context policy exports did not exist and the briefing lacked its plan-rationale card; native focused tests failed because `NutritionGoalPolicy`, plan-aware presets and a recommended slot did not exist.
- Green proof: focused web nutrition/activity/briefing tests 24/24; focused native `EnergyEngineTests` and `ManualAndInductionTests` passed with `xcodebuild` exit 0; complete web suite 556/556; production TypeScript/Vite build succeeded with 1,173 modules; `git diff --check` passed.
- Physical proof for exact source SHA `aeeee2b954`: the signed iPhone/embedded-Watch build succeeded; both app bundles passed `codesign --verify --deep --strict`; APEX installed at database sequence 5768 and launched on `iConstantine Main`. Direct Watch installation remains an open delivery gate because CoreDevice's paired-watch local-network tunnel timed out on three attempts; the signed companion is embedded in the installed iPhone app, but this entry does not claim a direct Watch install.

## 2026-08-26 — Finished Quick Log and Tracked workouts remain accessible

- Implementation commit: `3edd1fe01c` (`fix: keep finished workouts accessible`).
- Files changed: the shared web history resolver and history cards; web Simple Mode and phase pages; native receipt/history engine, Simple Mode and phase pages; native receipt persistence/editor; focused web and native regressions.
- Root cause: completed sessions were treated as a transient end-of-workout screen. Native Simple Mode additionally resolved only the one session whose `program_day_id` matched the currently generated day, so Quick Logs and tracked work from a replaced plan became unreachable even though their rows still existed.
- Fix: every completed owner session is now resolved by its recorded calendar date, independent of the active plan revision. Quick and Tracked sessions appear as compact faded receipt cards directly below the four Simple Mode tiles and on phase pages, expand into honest metrics, and open the full receipt. Quick Logs can reopen their workout structure; native receipt facts and skipped state can be corrected in place without changing the durable set id or inventing an unrated RIR.
- Tests added:
  - Web verifies owner/date/completion filtering, newest-first ordering, Quick Log title recovery, legacy generated-day survival, and placement on both required surfaces.
  - Native verifies the same history behavior and proves a corrected weighted set retains its row/session identity, updates loaded volume, and preserves `nil` RIR.
- Red proof: web failed because `completedWorkoutHistoryForDate` did not exist; native failed because `WorkoutReceipt.history`, `editInput`, and `correctedLog` did not exist.
- Green proof: focused web history 2/2; focused native receipt 11/11; complete web suite 558/558; complete native unit suite 476/476; TypeScript/Vite production build transformed 1,175 modules; `git diff --check` passed.
- Physical-device proof for exact source SHA `3edd1fe01c`: Apple Development build succeeded and strict signatures passed for APEX, APEX Water, and APEXWatchWidgets. APEX installed at database sequence 5776 and launched on `iConstantine Main`. Xcode's physical watchOS build-and-run installed and launched `ch.apexperformance.APEX.watchkitapp` on `Constantin’s Apple Watch` (Apple Watch Ultra 3, watchOS 27.0) as process 666.

## 2026-08-26 — Water Quick Add responds immediately and stays legible

- Implementation commit: `015432998d` (`fix: make custom hydration entry immediate`).
- Files changed: `ios/APEXNative/APEX/App/AppSession.swift`, `Features/Portal/HydrationFigureWebView.swift`, `Features/Portal/SimpleHomeView.swift`, `APEXTests/HydrationGaugeTests.swift`, and `APEXUITests/APEXSmokeUITests.swift`.
- Root cause: the transparent UIKit-backed hydration figure could overflow its compressed geometry and retain an invisible hit region over the custom amount control. Only the narrow text glyph focused the number field, while the disabled Add action faded its entire cyan-and-white control to near-zero contrast.
- Fix: the decorative gauge is explicitly noninteractive in SwiftUI and UIKit, its geometry can no longer overflow its allocation, the complete 52-point custom amount row focuses the field, and disabled Add now uses a deliberate dark-on-neutral palette with an outline instead of whole-control opacity.
- Tests added: a hydration source contract prevents the gauge from regaining hit testing, requires whole-row focus, and rejects the illegible opacity implementation. The existing Water Quick Add UI test now opens the sheet deterministically in Debug, requires the number keyboard within one second (under two seconds end-to-end including XCUITest tap serialization), verifies empty Add remains disabled, dismisses an empty keyboard, and confirms Settings remains at the bottom.
- Red proof: the focused hydration regression failed all three new source assertions before implementation. The tightened UI test then exposed a stale dashboard scroll assumption after finished-session cards changed page length; its isolated flow subsequently reached and enforced the actual keyboard timing requirement.
- Green proof: Water Quick Add UI 1/1; hydration gauge suite 8/8; complete native unit suite 477/477; `git diff --check` passed.
- Physical-device proof for exact source SHA `015432998d`: the signed iOS build installed and launched `ch.apexperformance.APEX` on `iConstantine Main` as process 3104. The signed watchOS build installed and launched `ch.apexperformance.APEX.watchkitapp` on the connected Apple Watch Ultra 3 as process 820.

## 2026-08-26 — Finished workout receipts are complete and removable

- Implementation commit: `5b76225c7c` (`fix: make finished workout receipts manageable`).
- Files changed: the shared web completed-history resolver and cards; native receipt engine, history UI and session deletion boundary; focused web and native regressions.
- Root cause: finished-session cards hid their set facts behind another screen, exposed two overlapping edit actions, and had no deliberate way to remove an accidental Quick Log or Tracked session. A naive delete could also have crossed account ownership or left child set rows behind.
- Fix: expanded cards now show the complete performed set receipt inline and expose one unambiguous `Edit receipt` action. Collapsed cards reveal a red delete action with a left swipe; expanded cards expose a red corner X. Both require confirmation. Deletion is resolved against the signed-in owner and removes only that completed session and its owned set rows. No date/source heuristic is used to delete an activity row because the durable session correlation required by Roadmap 7.6 does not exist yet.
- Tests added: web and native owner-bound deletion-plan tests include a foreign child row and prove it cannot be targeted; web and native UI-contract tests require inline facts, swipe/X deletion, confirmation and one edit action while rejecting the former duplicate labels.
- Red proof: the web regression failed because `completedWorkoutDeletionPlan` did not exist; native failed because `WorkoutReceipt.DeletionPlan` and its resolver did not exist. The UI contracts also failed against the former two-button cards.
- Green proof: focused web completed-history suite 4/4; focused native receipt suite 13/13; complete web suite 560/560; complete native unit suite 479/479; TypeScript/Vite production build transformed 1,175 modules; `git diff --check` passed.
- Physical-device proof for exact source SHA `5b76225c7c27f6fc53986dbe25ba428ae6edd4a9`: the signed iOS build installed and launched `ch.apexperformance.APEX` on `iConstantine Main` as process 3412. The signed watchOS build installed `ch.apexperformance.APEX.watchkitapp` on the connected Apple Watch Ultra 3; an independent CoreDevice app inventory confirmed the installed bundle and version. watchOS did not return from the automatic launch request, so this entry does not claim a Watch process id.

## 2026-08-26 — Hydration colors stack by the time they were logged

- Implementation commit: `3cc56a0d3c` (`fix: stack hydration colors by recency`).
- Files changed: native hydration ledger ordering, shared iPhone/Watch composition-stop layout, and focused ledger/gauge regressions.
- Root cause: composition bands were always sorted by a fixed liquid-kind list, so coffee could remain at the silhouette's feet even when it was the latest drink. The color boundary also still used the previous 0.4% transition width.
- Fix: amounts remain aggregated by liquid type, but bands are ordered by each type's most recent factual event, newest first, which maps the newest liquid to the top of both the iPhone silhouette and Watch fill. Equal-time facts retain a deterministic kind fallback. Boundary smoothing increases by exactly 15% from 0.0040 to 0.0046 while its midpoint and millilitre-weighted areas stay unchanged.
- Tests added: the ledger regression requires a 09:00 100 ml coffee above an 08:00 900 ml water band; the layout regression requires the same 90/10 midpoint with the precisely widened transition.
- Red proof: the new ledger test returned `[water 900, coffee 100]` instead of `[coffee 100, water 900]`; the new smoothing contract targeted a wider boundary than the old layout produced.
- Green proof: focused native hydration suites 36/36; `git diff --check` passed. The immediately preceding complete gates remain green at web 560/560, native 479/479 and a successful production web build.
- Physical-device proof for exact source SHA `3cc56a0d3c5e18b439a8c653a9f24a4b1b4eda70`: the signed watchOS build installed and launched `ch.apexperformance.APEX.watchkitapp` on the connected Apple Watch Ultra 3 as process 860. The signed iOS build installed `ch.apexperformance.APEX`; CoreDevice independently confirmed version 1.0.0 in the iPhone app inventory. Auto-launch alone was denied because the iPhone was locked, so this entry does not claim an iPhone process id.

## 2026-08-26 — Removed meal items have a five-second Undo window

- Implementation commit: `f9fd70f702` (`fix: expire meal undo after five seconds`).
- Files changed: the shared web Meal Composer and new timed-undo domain helper/test; native Meal Composer undo buffer/UI and focused regressions.
- Root cause: native kept the last removed food undoable indefinitely, while web removed food immediately with no recovery action. Neither behavior communicated a bounded safety window.
- Fix: Compact and Expanded removals in every shared web/native Meal Composer now create the same five-second buffer, restore the exact item and list position, show a live `Undo · 5s` through `Undo · 1s` countdown, and remove the action automatically at expiry. A newer removal replaces the older buffer, and an expiry-boundary tap fails closed rather than restoring stale state.
- Tests added: web domain coverage proves exact-index restoration before 5,000 ms and rejection at 5,000 ms, plus a source contract for the shared countdown UI; native behavior proves the same five-second boundary and visible count, plus a lifecycle contract requiring the periodic view and token-owned expiry task.
- Red proof: web failed because `mealUndo.ts` did not exist; native failed to compile because `MealComposerUndoBuffer` had no deadline, remaining-seconds API or time-aware restore.
- Green proof: focused web undo suite 2/2; focused native Meal Composer suite 15/15; complete web suite 562/562; TypeScript/Vite production build transformed 1,176 modules; `git diff --check` passed. The preceding complete native gate remains green at 479/479, with the subsequent changed-area hydration and Meal Composer suites green at 36/36 and 15/15.
- Physical-device proof for exact source SHA `f9fd70f7020dea72c052d8bcd3f8710f338103af`: the signed iOS build installed and launched `ch.apexperformance.APEX` on `iConstantine Main` as process 1780. The signed watchOS artifact installed at CoreDevice database sequence 1168 and launched `ch.apexperformance.APEX.watchkitapp` on the connected Apple Watch Ultra 3.

## 2026-08-26 — First-run plan creation and induction repair

- Implementation commit: `e6eb97ee3cb53cec9b566d2b08eb98ab3cac7898`
- Files changed:
  - `ios/APEXNative/APEX/Core/Engine/TrainingInduction.swift`
  - `ios/APEXNative/APEX/Core/Networking/SupabaseService.swift`
  - `ios/APEXNative/APEX/Features/Onboarding/InductionView.swift`
  - `ios/APEXNative/APEX/Features/Training/TrainingInductionPanel.swift`
  - `ios/APEXNative/APEX/Resources/{de-CH,de,es,it,ja,pt,ro,th}.lproj/Localizable.strings`
  - `ios/APEXNative/APEXTests/ManualAndInductionTests.swift`
  - `src/components/workout/TrainingInductionPanel.tsx`
  - `src/lib/planBriefing.ts`
  - `tests/plan-briefing.test.ts`
- Result: first-run profile creation now supplies the schema-required deterministic profile `id`, uses the authenticated account UUID for `id` and `user_id`, and does not start a beta trial. The native induction offers 2–7 days, presents the shared high-frequency recovery advisory for 6/7 days, adds a native vector cue above every question, gives health concerns an explicit `None` reset, and labels the exit `Skip Questionnaire`. Native and web briefing energy presets now persist real goal changes; emergency copy no longer hard-codes Switzerland's 144 number. No existing briefing image asset was changed.
- Tests added/extended:
  - `testFirstRunProfileInsertOwnsAStablePrimaryKeyWithoutStartingATrial`
  - `testFirstRunQuestionnaireOffersEveryApprovedDayAndAnExplicitNoConcernsChoice`
  - briefing safety and actionable energy-choice regressions on native and web
- Verification:
  - `npm test`: 562 passed, 0 failed.
  - `xcodebuild ... -only-testing:APEXTests`: 485 passed, 0 failed; `TEST SUCCEEDED`.
  - Focused onboarding UI flow: 1 passed, 0 failed (skip, 7-day warning, plan installation, briefing, and Simple Mode landing).
  - `npm run build`: passed; 1,176 modules transformed.
  - `git diff --check`: passed.
  - Signed generic iOS build from `e6eb97ee3c`: `BUILD SUCCEEDED`; embedded `APEX Water.app` validation passed.
- Physical installs from the exact implementation SHA:
  - iPhone 15 Pro Max `iConstantine Main`: `ch.apexperformance.APEX` installed and launched successfully.
  - Apple Watch Ultra 3 `Constantin's Apple Watch`: `ch.apexperformance.APEX.watchkitapp` installed successfully and confirmed by device app inventory. Command-line foreground launch timed out while enabling the beta developer disk image, so no launch-success claim is made for that step.

## 2026-08-26 — Committed plans recover their account profile

- Implementation commit: `31c4646e027b793283863c66f5fe7940d1a1a6ec` (`fix: recover profiles for committed plans`).
- Files changed: native debug fixture, session refresh, induction ownership resolver, Supabase profile boundary, induction panel, native unit/UI regressions, shared web induction resolver/store, and web regressions.
- Root cause: an authenticated account could commit a plan without a matching `profile` row. Native and web then treated the missing profile as an empty app state, so Simple Mode and Nutrition rendered no useful content even though the owner already had an installed plan. The onboarding close action also shared a root accessibility identifier, which made the end-to-end check vulnerable to tapping the wrong element.
- Fix: only a committed training induction owned by the authenticated account may recover its missing profile. Native creates the deterministic account-owned profile through the server boundary and waits for the recovered account before opening Simple Mode; web performs the same owner-gated recovery during hydration. A settings-only questionnaire skip stays profileless. The recovered profile uses the authenticated UUID for both `id` and `user_id`, the current seed, `APEX Athlete` as its display name, and the committed plan goal. No trial is started. The briefing close control now has its own accessibility identifier, and the UI fixture remains offline after recovery.
- Tests added/extended: native ownership and request-payload regressions; web committed-owner recovery, foreign-plan rejection, and profileless-skip regressions; a native end-to-end UI flow that begins without a profile, installs a plan, opens Simple Mode, verifies Nutrition at a glance and the scheduled training tile, then opens the populated Nutrition page.
- Red proof: the original end-to-end flow reached blank Simple and Nutrition states after plan installation. The first repair run then exposed a real lazy-layout assumption and an irrelevant network alert in the offline fixture; both were made deterministic without weakening the profile-recovery assertions.
- Green proof: focused end-to-end UI flow 1/1 in 46.731 seconds; complete native suite 486/486 in 2.099 seconds; complete web suite 563/563 in 4,999.456 ms; TypeScript/Vite production build transformed 1,176 modules in 496 ms; `git diff --check` passed.
- Result bundles: `build/profile-recovery-ui-green/Logs/Test/Test-APEX-2026.08.26_19-09-31-+0200.xcresult` (UI) and `build/profile-recovery-ui-green/Logs/Test/Test-APEX-2026.08.26_19-10-51-+0200.xcresult` (native unit suite).
- Physical-device proof for exact source SHA `31c4646e02`: the Apple Development build installed and launched `ch.apexperformance.APEX` on `iConstantine Main`; CoreDevice inventory independently confirmed version 1.0.0. Its embedded `APEX Water.app` installed on `Constantin’s Apple Watch`, and independent Watch inventory confirmed `ch.apexperformance.APEX.watchkitapp` version 1.0.0. The direct Watch foreground launch request timed out while CoreDevice initialized, so this entry does not claim a Watch process id.

## 2026-08-26 — Beta access is account-owned and server-authoritative

- Implementation commit: `1d0b5f857c9270a59206a9a88c7cc4c40bfeaae9` (`fix: make beta access account scoped`).
- Files changed: entitlement model/store, authenticated session resolution, account profile decoding, paywall/settings/top-bar/auth/onboarding copy, unfinished-language visibility, eight localization catalogues, entitlement regressions, and migration `029_account_scoped_beta_entitlements.sql`.
- Root cause: the beta unlock was a device-wide `UserDefaults` flag with a client-embedded developer-code hash, while ordinary accounts silently received temporary access and onboarding/paywall resources still promised seven or fourteen free days. A reinstall, another device, or an account switch could therefore disagree with the server about access.
- Fix: a profile's server-owned `beta_code_redeemed` value is now the beta authority. Founding and active subscription facts remain server-owned alternatives; every other account resolves to locked. Beta redemption sends only `p_code_hash` to the existing one-use RPC, then reloads the dashboard and refuses to close the gate until the refreshed account profile confirms access. The device flag, embedded code hash, automatic temporary-access clock, countdown UI, and all user-facing free-period copy were removed. Historical `trial_started_at` remains decode-compatible but cannot unlock the app.
- Server guard: production applied the byte-identical repository SQL as migration `20260826202500_account_scoped_beta_entitlements.sql`. It adds/defaults `profile.beta_code_redeemed`, rejects direct anon/authenticated writes through an invoker trigger, restricts `redeem_beta_code(text)` execution to authenticated callers, and reloads PostgREST. Isolated dry-run listed only that migration; the applied migration hash was `be3b0e2422a7c89bd8d2c7e22e6b93fa191d17a4275328fe21f7da288ec8fff1`. Production probes returned HTTP 200 for the profile column and HTTP 401 for anonymous `redeem_beta_code(p_code_hash)`.
- Tests added/extended: ordinary account stays locked; claimed beta profile unlocks; historical temporary-access data cannot unlock; profileless account cannot inherit prior access; account generation guards remain intact; StoreKit/founding behavior remains intact; source contract rejects device flags, embedded hashes, clock writes, free-period copy, and RPC parameter drift; every localized catalogue is scanned.
- Red proof: `build/entitlement-red/Logs/Test/Test-APEX-2026.08.26_20-07-46-+0200.xcresult` failed to compile because the required `.locked`/`.beta` states and `betaCodeRedeemed` profile fact did not yet exist and the removed device/trial API still did.
- Green proof: focused entitlement suite 13/13; complete native suite 488/488 in 2.200 seconds; complete web suite 563/563 in 4,221.943 ms; TypeScript/Vite production build transformed 1,176 modules; all eight localization files passed `plutil`; stale free-period scan and `git diff --check` passed. Final native result bundle: `build/entitlement-green/Logs/Test/Test-APEX-2026.08.26_20-28-25-+0200.xcresult`.
- Physical-device proof for exact source SHA `1d0b5f857c`: the signed iOS build succeeded, both iPhone and embedded Watch bundles passed `codesign --verify --deep --strict`, and APEX installed on `iConstantine Main` at database sequence 5840 and launched as PID 2660. The same signed `ch.apexperformance.APEX.watchkitapp` installed directly on the connected physical Apple Watch Ultra 3 at database sequence 1192 and launched as PID 1469.

## 2026-08-26 — Exact Sportyfeel Clear Whey record and concise provenance

- Implementation commit: `e2d044d8d10b8deef79744c3d28553b1c4c86dfa` (`fix: add exact Sportyfeel clear whey`).
- Files changed: the shared food expansion/seeding/search pipeline, web and native portion provenance copy plus eight native localizations, focused web/native regressions, and migration `030_sportyfeel_clear_whey.sql`.
- Product result: Sportyfeel Clear Whey, peach iced tea (`4335619267756`) is an exact searchable/barcode-resolvable product with the verified package facts `347 kcal`, `84 g protein`, `2.4 g carbohydrate`, and `0.1 g fat` per 100 g and a 25 g serving. The displayed Open Food Facts caveat is now simply `Check the package label.`; no UI calls a result an “Open Food Facts community record”.
- Server result: production applied the isolated migration as `20260826210000_sportyfeel_clear_whey.sql`; a post-apply REST probe returned exactly one row with the canonical UUID, EAN, macros, serving, provider-verified confidence, and difference-method water value. The pre-apply probe returned no matching row, and the dry run listed only this migration.
- Tests added/extended: exact catalogue/offline/barcode/search/macros/serving/confidence/water coverage; concise-provenance rejection of the former phrase; idempotent, non-destructive SQL contract with exact EAN/macros; native portion-source parity.
- Red proof: web failed for the missing EAN and former provenance phrase, the database contract failed because the migration did not exist, and native failed because the old source copy was still returned.
- Green proof: focused web/database suites 3/3; focused native suite 1/1; complete web suite 566/566; complete native suite 488/488; TypeScript/Vite production build passed; all eight localization files passed `plutil`; `git diff --check` passed. Native result bundles: `build/food-red/FocusedGreen.xcresult` and `build/food-red/FullGreen.xcresult`.
- Physical-device proof for exact source SHA `e2d044d8d10b8deef79744c3d28553b1c4c86dfa`: the signed device build succeeded and strict signature verification passed for APEX and its embedded Watch app. APEX installed on `iConstantine Main` at database sequence 5848 and launched. `ch.apexperformance.APEX.watchkitapp` installed directly on the connected physical Apple Watch Ultra 3 at database sequence 1200 and launched.

## 2026-08-26 — Activity picker starts with broadly useful work and life groups

- Implementation commit: `6af666fa1e713dc32901ce2f6c8d16fd716ec1c4` (`fix: lead activity picker with general needs`).
- Files changed: shared web activity category presentation and picker default; native Add Activity grouping/presentation; focused web and native regressions.
- Result: both clients now present `Work: general`, `Errands & life`, `Work: camera`, `Work: hands-on therapy`, `Training`, then `Device import`. The web picker opens on General Work instead of Camera, and native grouping consumes the same explicit priority rather than database row order.
- Tests added: cross-client category order and visible-label assertions. Red proof: web returned therapy/camera/work/life, while native could not compile because the required shared presentation contract did not exist.
- Green proof: focused web 1/1; focused native 1/1; complete web suite 567/567; complete native suite 489/489; TypeScript/Vite production build passed; `git diff --check` passed. Native result bundle: `build/activity-order-red/Logs/Test/Test-APEX-2026.08.26_21-19-29-+0200.xcresult`.
- Physical-device proof for exact source SHA `6af666fa1e713dc32901ce2f6c8d16fd716ec1c4`: the signed build and strict signature checks passed. APEX installed and launched on `iConstantine Main` at database sequence 5856. The embedded `ch.apexperformance.APEX.watchkitapp` installed and launched on the connected physical Apple Watch Ultra 3 at database sequence 1208.

## 2026-08-26 — Nutrition ring reports the real calorie excess

- Implementation commit: `b7c8c00238d8829f662689e8f16a72ec271a7324` (`fix: report calorie excess honestly`).
- Files changed: shared web calorie-balance resolver and Nutrition at a glance presentation; native calorie-balance contract and Nutrition card; Romanian/Thai web translations; eight native localizations; focused web and native regressions.
- Result: an over-target day now says `Exceeding by` and displays the actual excess in red (for example, 2,119 eaten against 1,685 shows 434), while under-target days retain the existing `Remaining` behavior.
- Tests added: two web and two native behavior tests covering both over-target and under-target days. Red proof: both suites failed because the calorie-balance contracts did not exist; green proof: focused web 2/2 and native 2/2.
- Full verification: complete web suite 569/569; complete native suite 491/491; TypeScript/Vite production build passed; all eight edited `.strings` files passed `plutil -lint`; `git diff --check` passed. Native result bundle: `build/activity-order-red/Logs/Test/Test-APEX-2026.08.26_21-27-37-+0200.xcresult`.
- Physical-device proof for exact source SHA `b7c8c00238d8829f662689e8f16a72ec271a7324`: signed iPhone and embedded Watch builds succeeded and both passed strict signature verification. APEX installed and launched on `iConstantine Main` at database sequence 5864. `ch.apexperformance.APEX.watchkitapp` installed and launched on the connected physical Apple Watch Ultra 3 at database sequence 1216.

## 2026-08-26 — Apple Fitness activity totals are authoritative and refreshes cannot erase good wearable data

- Fixed the 204 kcal in Apple Fitness versus 22 kcal in APEX discrepancy at both failure points: native HealthKit now reads the current-day Activity Summary Move value as the authoritative active-energy total (falling back to cumulative active-energy samples only when Activity Summary is unavailable), and a partial HealthKit refresh now merges into the same-day wearable record instead of replacing unread metrics with zero.
- Existing installs request the newly added Activity Summary read access only when HealthKit reports that an authorization extension is required. Steps, active energy, and exercise minutes remain independently optional so one unavailable metric cannot erase the other two.
- Added four native regression tests covering the exact 204-versus-22 precedence case, Activity Summary precedence over an overlapping 231 kcal raw sample, preservation of prior 204 kcal/31 minutes during a steps-only refresh, and complete replacement when all three metrics are present. The tightened precedence test was proven red against the former max-value behavior before the resolver was corrected.
- Verification: focused HealthKit regression suite `4/4` passed; native unit suite `495/495` passed in `5.002 s`; web suite `569/569` passed; production web build passed (`1177` modules transformed). A full native scheme run passed `497` tests and exposed `12` existing UI smoke failures because the account-scoped premium paywall covered otherwise-present portal controls; the exported UI hierarchy showed `Premium access or a beta code is required`, so those failures are unrelated to this four-file HealthKit change.
- Commit `0e4c74974d` built successfully for the connected physical devices. Both signed bundles passed strict code-sign verification. The exact build installed and launched on `iConstantine Main` as sequence `5872`, and the Watch companion installed and launched directly on `Constantin’s Apple Watch` as sequence `1224`.

## 2026-08-26 — Nutrition has one meal surface and date-owned workout receipts

- Implementation commit: `fa8ec260d657bbebd429d176e3b7cba7a06783c0` (`fix: keep one nutrition meal surface`).
- Files changed: web Nutrition composition, shared Today’s Activities, the actual-food tracker, native Nutrition composition, and two focused regression suites.
- Result: the live metabolic dayline is now the only meal list/editor on web and native. The duplicate `Meals` card and separate `Meal timeline / Portions adapt...` disclosure are no longer rendered, while the dayline retains meal creation, review, editing, and deletion. Nutrition’s `Today’s Activities` now reuses the same selected-date completed-workout receipt component as Simple Mode and phase pages, so quick and tracked sessions appear consistently without a second history implementation.
- Tests added/updated: a cross-client single-meal-surface contract, a cross-client selected-date workout-receipt integration contract, and the meal swipe/delete regression was redirected to the surviving dayline rather than deleted.
- Red proof: the two new tests initially failed because the duplicate meal surfaces were still present and Today’s Activities did not render completed receipts. Green proof: focused suite 21/21; complete web suite 571/571 in 3,975 ms; complete native suite 495/495 in 2.148 seconds; TypeScript/Vite production build passed with 1,177 modules; `git diff --check` passed.
- Physical-device proof for exact source SHA `fa8ec260d6`: the Apple Development build succeeded, Xcode validated the embedded Watch binary, and both bundles passed strict signature verification. APEX installed and launched on `iConstantine Main` at database sequence `5880`. `ch.apexperformance.APEX.watchkitapp` installed and launched on the connected physical Apple Watch Ultra 3 at database sequence `1232`.

## 2026-08-27 — Supplement stack editing is shared and overflow-safe

- Implementation commit: `d3a432c43fb4d3f50eb80914bc397e5ff414d091` (`fix: unify supplement stack editing`).
- Files changed: the shared web supplement catalogue/types/editor, Simple Mode and Nutrition integrations, the native supplement catalogue and shared editor integrations, web/native regressions, and migration `031_archive_supplements.sql`.
- Result: Simple Mode and Nutrition now use one supplement-stack editor per client with the same add, search, evidence/info, dose, check-off, and archive behavior. Long supplement names and guidance wrap inside their cards instead of crossing the screen edge. Archive is reversible at the data boundary and preserves historical logs. Both catalogues lead with Whey Protein and Creatine Monohydrate, show a separator, then present the remaining supplements alphabetically.
- Server result: production applied migration 031. A post-apply SQL inspection returned `archived | boolean | NO | false`, confirming the non-null `profile_supplements.archived` column and default.
- Tests added: shared-surface/parity and catalogue-order regressions on web; catalogue priority and alphabetical-tail regressions on native. Red proof: web failed because the ordered catalogue contract did not exist, and native returned `five_htp`/`agmatine` before the required research-led pair. Green proof: focused web 3/3; complete web suite 574/574 in 4.02 seconds; complete native suite 496/496; TypeScript/Vite production build passed with 1,179 modules; `git diff --check` passed. Native result bundle: `build/codex-supplement-stack/Logs/Test/Test-APEX-2026.08.26_23-28-20-+0200.xcresult`.
- Physical-device proof for exact source SHA `d3a432c43f`: signed Release build 356 succeeded and both APEX and the embedded Watch app passed strict code-sign verification. APEX installed and launched on `iConstantine Main` at database sequence `5888`. `ch.apexperformance.APEX.watchkitapp` installed and launched on the connected physical Apple Watch Ultra 3 at database sequence `1240`.

## 2026-08-27 — Finished-workout deletion is hidden until requested

- Implementation commit: `4ac3c5b0d43efa939f1d1585f72d89552b33e32d` (`fix: hide workout deletion until swipe`).
- Files changed: `src/lib/completedWorkoutHistory.ts`, `src/components/workout/CompletedWorkoutHistoryCards.tsx`, `tests/completed-workout-history.test.ts`, `ios/APEXNative/APEX/Core/Engine/WorkoutReceipt.swift`, `ios/APEXNative/APEX/Features/Training/WorkoutReceiptSheet.swift`, `ios/APEXNative/APEXTests/WorkoutReceiptTests.swift`, `ios/APEXNative/APEXUITests/APEXSmokeUITests.swift`, `ios/APEXNative/APEX/App/APEXDebugFixture.swift`, and `ios/APEXNative/APEX/App/AppSession.swift`.
- Behavior: collapsed receipts contain no destructive tray at rest; only a negative left-swipe offset renders it. Expanded receipts retain the compact confirmed-delete corner action.
- Test fixture: the UI fixture now resolves a profile-backed beta entitlement through `EntitlementStore`; it does not bypass the server-authoritative entitlement model.
- Red proof: focused web/native tests first failed because the reveal predicate did not exist; native result bundle `build/finished-workout-tray-red/Red.xcresult`. The prior permanent-tray implementation fails the new zero-offset assertions.
- Focused green: web completed-workout history `6/6`; native `WorkoutReceiptTests` `14/14` (`build/finished-workout-tray-red/Green.xcresult`).
- Rendered UI green: `testFinishedWorkoutDeletionIsHiddenAtRestAndMovesIntoExpandedCard` `1/1` in 13.369 seconds (`build/finished-workout-tray-red/UI5.xcresult`).
- Full green: web `575/575` in 4019.4915 ms; native `497/497` in 2.137 seconds (`build/finished-workout-tray-red/Full.xcresult`); `npm run build` passed; `git diff --check` passed.
- Physical release: build `357`, source SHA `4ac3c5b0d43efa939f1d1585f72d89552b33e32d`; strict deep signature verification passed for both bundles.
- Installed and launched on physical iPhone 15 Pro Max `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, database sequence `5896`.
- Installed and launched on physical Apple Watch Ultra 3 `F6BE2986-A704-5C82-BC2B-6D02E09CBD04`, database sequence `1248`.

## Compact meal serving-unit layout repair — 2026-08-27

- Implementation commit: `db06034d99fd7a52e8a4c2b60ffa2880873282e8` (`fix: keep meal units on one line`).
- Replaced the undersized compact-row system picker with the same constrained, single-line serving-unit menu used by expanded rows. The compact control now reserves a 72 x 40 pt frame for `g`, `ml`, and `serving`, so millilitres cannot wrap into `m` / `l` or stretch and displace the food row.
- Added a realistic 200 ml high-protein-milk UI fixture so the rendered compact meal row exercises the exact failure shown on-device.
- Tests added:
  - `MealComposerTests.testCompactUnitControlReservesOneLineForMillilitresAndServingLabels`
  - `APEXSmokeUITests.testCompactMealMillilitreUnitStaysOnOneLineInsideItsCard`
- Red proof: the focused layout test failed before implementation because `MealComposerCompactLayout` did not exist (`build/meal-unit-layout-red/Logs/Test/Test-APEX-2026.08.27_01-00-09-+0200.xcresult`, exit 65).
- Green proof: focused unit test 1/1 passed (`build/meal-unit-layout-red/Logs/Test/Test-APEX-2026.08.27_01-02-27-+0200.xcresult`); rendered UI test 1/1 passed in 14.089 seconds (`build/meal-unit-layout-red/Logs/Test/Test-APEX-2026.08.27_01-08-56-+0200.xcresult`).
- Full verification: native 498/498 passed with 0 failures (`build/meal-unit-layout-full/Logs/Test/Test-APEX-2026.08.27_01-09-44-+0200.xcresult`); web 575/575 passed with 0 failures; `npm run build` passed; `git diff --check` passed.
- Release build: APEX 1.0.0 (358), built from exact implementation SHA `db06034d99fd7a52e8a4c2b60ffa2880873282e8`; strict deep code-sign verification passed for both the iPhone app and embedded Watch app.
- Installed and launched on physical iPhone `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, database sequence `5904`.
- Installed and launched on physical Apple Watch Ultra 3 `F6BE2986-A704-5C82-BC2B-6D02E09CBD04`, database sequence `1256`.

## 2026-08-27 — First-run consent and honest nutrition baseline

- Implementation commit: `fe85132f9cef6324569e2d890c5f8763586fd34d` (`fix: require honest first-run nutrition baseline`).
- Rebuilt first-run setup around three mandatory facts before any Skip action exists: explicit current Terms/Privacy and sensitive-health-data consent, a validated body baseline (sex used by the metabolic equation, weight, height, exact birth date), and the user's goal. The remaining training questions can then be skipped without inventing a workout programme.
- A baseline-only completion now creates the server profile with the captured body facts, persists versioned legal acceptance and goal metadata, derives calorie/macro targets in both native and web clients, and leaves a clear plan-builder route instead of a blank portal or fabricated plan. Interrupted profile creation returns to setup rather than stranding the account.
- Added an accessible nine-step native setup with Swiss-oriented privacy copy, local Terms/Privacy explanations, keyboard Previous/Next/Done controls, native vector illustrations, and stable accessibility identifiers. Existing web sessions consume the same server-shaped baseline marker for cross-client parity.
- Tests added or strengthened:
  - `TrainingInductionTests.testSkippingOnlyAfterMandatoryBaselineCreatesNutritionFactsWithoutAWorkoutPlan`
  - baseline-only profile recovery and portal-routing assertions
  - `nutrition-plan-presets.test.ts` baseline-only target parity assertion
  - `APEXSmokeUITests.testInductionRequiresConsentBodyAndGoalBeforeSkipAndNoPlanAccountCanReturnToTheBuilder`
  - single-flight submission guard now independently protects Back, Continue, and the conditionally visible Skip action.
- Red proof: the focused native test failed to compile before implementation because `BodyBaseline`, `DataConsent`, and `baselineOnly` did not exist (`build/onboarding-baseline-red/Logs/Test/Test-APEX-2026.08.27_01-33-07-+0200.xcresult`, exit 65).
- Green proof: focused native 1/1 passed (`build/onboarding-baseline-red/Logs/Test/Test-APEX-2026.08.27_01-42-54-+0200.xcresult`); end-to-end first-run UI flow 1/1 passed in 56.842 seconds (`build/onboarding-baseline-ui/Logs/Test/Test-APEX-2026.08.27_02-00-01-+0200.xcresult`).
- Full verification: native 499/499 passed with 0 failures (`build/onboarding-baseline-full/Logs/Test/Test-APEX-2026.08.27_02-17-53-+0200.xcresult`); web 576/576 passed with 0 failures; `npm run build` passed; `git diff --check` passed.
- Release build: APEX 1.0.0 (359), built and codesigned from exact implementation SHA `fe85132f9cef6324569e2d890c5f8763586fd34d`.
- Installed and launched on physical iPhone `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, database sequence `5912`.
- Installed and launched on physical Apple Watch Ultra 3 `F6BE2986-A704-5C82-BC2B-6D02E09CBD04`, database sequence `1264`.

## 2026-08-27 — Overlapping meal comfort windows

- Implementation commit: `5bd5253391ba7cad45eb8a30cfe4acede569e427` (`fix: merge overlapping meal comfort windows`).
- Replaced the latest-meal-wins rendering in both native and web Daylines with a shared interval resolver. Every meal contributes settling and transition intervals; overlapping intervals resolve by severity, adjacent equal bands coalesce, and a later snack may extend but can never shorten an active larger-meal context.
- The native headline now selects the still-active context with the furthest honest ready time, while both rails render the complete resolved interval sequence. This also handles a later substantial meal re-entering a settling phase instead of assuming the day can only progress monotonically.
- Tests added:
  - `MealTimingEngineTests.testALaterLightSnackCannotEraseAnActiveLongerLunchComfortWindow`
  - `MealTimingEngineTests.testNativeDaylineRendersMergedBandsInsteadOfOnlyTheLatestMeal`
  - web `a later light snack cannot erase an active longer lunch comfort window` behavioral and renderer-integration assertion.
- Red proof: web failed because `mergeMealComfortBands` did not exist; native failed because `ComfortAnchor` and the merge resolver did not exist (`build/meal-window-merge-red/Logs/Test/Test-APEX-2026.08.27_02-40-45-+0200.xcresult`, exit 65).
- Green proof: web meal timing 20/20 passed; native focused regression 1/1 passed (`build/meal-window-merge-red/Logs/Test/Test-APEX-2026.08.27_02-43-15-+0200.xcresult`); native meal timing 11/11 passed (`build/meal-window-merge-red/Logs/Test/Test-APEX-2026.08.27_02-53-13-+0200.xcresult`).
- Full verification: native 501/501 passed with 0 failures (`build/meal-window-merge-red/Logs/Test/Test-APEX-2026.08.27_02-56-03-+0200.xcresult`); web 577/577 passed with 0 failures; `npm run build` passed; `git diff --check` passed.
- Release build: APEX 1.0.0 (360), built and codesigned from exact implementation SHA `5bd5253391ba7cad45eb8a30cfe4acede569e427`.
- Installed and launched on physical iPhone `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, database sequence `5920`.
- Installed and launched on physical Apple Watch Ultra 3 `F6BE2986-A704-5C82-BC2B-6D02E09CBD04`, database sequence `1272`.
- Next: add and verify the photographed Sportyfeel whey record and remove redundant Open Food Facts provenance copy from the portion sheet.

## 2026-08-27 — Phase 1.8 custom workouts are fully runnable

- Implementation commit: `1c00c4ba3ca944af2434cff1e3287e8a4f4ad5e8` (`feat: make custom workouts fully runnable`).
- Web and native builders now preserve a user-authored movement order, expose honest set/target/rest controls for repetitions, seconds, minutes, metres, steps, and rounds, and persist adjacent linked movements through the existing generic work-group membership fields. The same round model handles pairs and longer circuits without introducing a second superset representation.
- Guided and tracked sessions consume the stored units rather than treating every target as repetitions. Distance work stores distance instead of fabricating duration; manual-cadence step and round targets retain their measured count; grouped work runs through the existing round-major player timeline and the shared completion path.
- Builder ergonomics now use 44-point reorder/remove/link controls, A1/A2 group labels, and dismiss the software keyboard after selection on both clients so the prescription remains reachable.
- Tests added or expanded:
  - web `custom-workout-builder.test.ts`: unit labels, lossless reorder, generic adjacent grouping, and safe removal at a linked boundary;
  - native `CustomWorkoutBuilderTests`: lossless reorder, deterministic work-group positions, persisted order/prescription/group membership, honest distance facts, and manual-cadence round counts;
  - native UI smoke flow: all 549 catalogue movements remain exposed, Power Snatch can be selected, and selection dismisses the keyboard.
- Red proof: the replacement UI assertion failed against the old keyboard behavior (`build/custom-workout-ui-red/Logs/Test/Test-APEX-2026.08.27_03-55-27-+0200.xcresult`, exit 65); the Wrist Roller regression failed while manual-cadence rounds were being dropped (`build/custom-workout-round-red/Logs/Test/Test-APEX-2026.08.27_04-11-23-+0200.xcresult`, exit 65). Both passed after their scoped fixes (`build/custom-workout-ui-green/Logs/Test/Test-APEX-2026.08.27_03-59-58-+0200.xcresult`, 1/1; `build/custom-workout-round-green/Logs/Test/Test-APEX-2026.08.27_04-15-11-+0200.xcresult`, 1/1).
- Full verification: native 506/506 passed with 0 failures (`build/custom-workout-full-tests-final/Logs/Test/Test-APEX-2026.08.27_04-18-08-+0200.xcresult`); web 581/581 passed with 0 failures; `npm run build` passed; `git diff --check` passed.
- Release build: APEX 1.0.0 (361), built and strictly signature-verified for both iPhone and embedded Watch app from exact implementation SHA `1c00c4ba3ca944af2434cff1e3287e8a4f4ad5e8`.
- Installed on physical iPhone `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, database sequence `5928`; automatic CLI launch was denied because the phone was locked, not because of an install failure.
- Installed and launched on physical Apple Watch Ultra 3 `F6BE2986-A704-5C82-BC2B-6D02E09CBD04`, database sequence `1280`.
- Next: reread the living roadmap and begin the next numbered Phase 1 task only after this task is pushed and Pages is green.

## 2026-08-27 - Task 1.9: live metabolic Dayline parity

- Implementation commit: `eacd9a0d28d44b072219d44058be0474717b5a73` (`feat: complete live metabolic dayline parity`).
- Native now resolves factual meal and completed-workout timestamps against the account timezone and the logical 03:00-02:59 day, including the next-calendar-day portion before 03:00. The full Dayline refreshes every 30 seconds while visible, keeps planned and recorded states distinct, merges overlapping meal comfort windows, and lets completed workout times be corrected on the same configured snap increment.
- Scheduled meal drags now persist through the shared account-scoped `meal_blocks` settings on native, Simple web, and Advanced web without dropping custom blocks or preset assignments. Actual meal drags continue to change factual finish time rather than schedule.
- Native now renders factual completed workouts on the rail and the web-derived recovery context with a broad two-hour 20-40 g protein opportunity, timing score, and an explicit non-cliff explanation in detailed mode. Guidance remains contextual and does not claim medical certainty.
- Tests added or expanded:
  - native `MealTimingEngineTests`: selected-date validation, configured snapping, exact zoned instant construction, pre-03:00 logical-day behavior, completed workout timing, and source integration;
  - web `meal-blocks.test.ts`: canonical and custom rescheduling while preserving assignments;
  - native UI smoke flow: user-visible recovery guidance and completed workout both appear in Nutrition.
- Red proof: the new native timing tests initially failed because the Dayline resolver/snap/workout APIs did not exist; the web test initially failed because `rescheduleMealBlock` did not exist. Self-review then reproduced the overnight bug with three failing assertions (`Test-APEX-2026.08.27_05-18-25-+0200.xcresult`, exit 65) before the logical-day fix; the same 16-test target then passed with 0 failures (`Test-APEX-2026.08.27_05-19-10-+0200.xcresult`).
- Full verification: native 511/511 passed with 0 failures (`Test-APEX-2026.08.27_05-19-46-+0200.xcresult`); web 582/582 passed with 0 failures; the focused native UI flow passed 1/1 in 8.733 seconds (`Test-APEX-2026.08.27_05-20-05-+0200.xcresult`); `npm run build` and `git diff --check` passed.
- Release build: APEX 1.0.0 (362), built and strictly signature-verified for both iPhone and embedded Watch app from exact implementation SHA `eacd9a0d28d44b072219d44058be0474717b5a73`.
- Installed on physical iPhone `A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, database sequence `5936`; automatic CLI launch was denied because the phone was locked, not because of an install failure.
- Installed and launched on physical Apple Watch Ultra 3 `F6BE2986-A704-5C82-BC2B-6D02E09CBD04`, database sequence `1288`.
- Next: push this task to both remote refs, verify the main-backed Pages deployment and live 200 response, then reread the living roadmap before the next numbered task.
