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
