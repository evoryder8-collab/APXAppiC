# APEX — takeover brief

You are continuing development of APEX: a SwiftUI iOS app plus a web fallback, sharing one
Supabase backend. Work through the phases in order. Do not skip ahead.

---

## 0. WORKING METHOD — read this first, it is load-bearing

The previous session failed by looping: a very large brief was re-injected on every
auto-compaction, the agent re-read 1,500-line files to re-orient, context filled again, and
it compacted again. Almost no work landed between compactions. Avoid that as follows.

1. **Keep state on disk, not in context.** Maintain `docs/REPAIR-NOTES.md` in the repo. After
   every task, append: what changed, commit SHA, tests run, result, what is next. After any
   compaction, read that file to re-orient. Never re-read source code to remember where you were.
2. **One task at a time.** Complete and commit a numbered task, with its tests, before starting
   the next. Do not hold two tasks open.
3. **Never re-read a file you have already read this session.** Never print more than ~120 lines
   of a file in one command. Use `grep -n` with targeted patterns instead of `sed -n '1,400p'`.
4. **No status updates without a diff or a test result.** If you have nothing concrete, keep
   working. Do not narrate intent.
5. **Do not restate this brief back.** It is on disk; refer to it.

## 0.1 Workspace and git safety

Use only: `/Users/jaxoncorrey/APXAppiC-codex-main-repair`, branch `codex/main-critical-repair`,
HEAD `c1b0e77`.

Do not touch: `~/dev/apex` (clean main checkout), `~/APXAppiC-codex-release` (frozen, see below),
`~/Desktop/my-video/APXAppiC` (stale, 104 commits behind — abandoned).

No `git reset --hard`, no destructive checkout, no broad deletion. Verify branch, HEAD, remote
and worktree status before relying on anything stated here.

Repo: https://github.com/evoryder8-collab/APXAppiC
Live web: https://evoryder8-collab.github.io/APXAppiC/
Supabase project: `rrzcrcjsbkmidlafrhfv`

**Never take the web app offline while working on iOS.** It is a working fallback with real users.

---

## 1. STATE AS OF HANDOFF

### Landed on `codex/main-critical-repair` (7 commits ahead of `main`)

| commit | what |
|---|---|
| `9f6c34e` | sync hardening: meal-kind normalisation, settings rebound to authenticated user, 4xx quarantined instead of jamming the offline queue |
| `d92a591` | meal-edit fix: `clientIdempotencyKey` is now computed and differs on reopen, plus `replaceMealID`, so edits are no longer swallowed |
| `fb29aee` | dayline duplicate time labels removed |
| `0306f5a`, `21e9504` | docs only: beta access and StoreKit plan |
| `130d861` | workout receipt preserved, UI coverage |
| `c1b0e77` | rest-day truth: `SessionBriefing`, `TrainingPlanEngine`, `MuscleMapView`, `TrainingProgramView` + parity tests |

### Uncommitted, in progress — finish it, do not restart it

- `ios/APEXNative/APEX/Core/Engine/ManualWorkout.swift` — `var rir: Int?` on `SetDraft`, clamped 0–5
- `ios/APEXNative/APEX/Core/Models/APEXModels.swift` — `enum WorkoutSessionMode` with
  `resolve(lastUsed:dayDefault:)`, and `sessionMode` mapped to `session_mode`
- `ios/APEXNative/APEXTests/ManualAndInductionTests.swift` — tests for both

### Frozen reference branch

`909cd63` on `codex/critical-ios-fixes` in `~/APXAppiC-codex-release` holds an earlier repair
attempt: 23 files, +1352/−172, including **web fixes** (`src/lib/foodSync.ts`,
`src/store/AppStore.tsx`, `src/store/FoodStore.tsx`) and a migration
(`020_restrict_rls_auto_enable.sql`). Do not merge blindly, but do not lose it — the web fixes
it contains are for bugs that are **live in production right now** (see Phase 2).

### Context that is expensive to rediscover

- **`log_structured_meal` (migration 009) is CREATE-ONLY.** It short-circuits on a known
  `client_idempotency_key` and returns before any replace or insert. `d92a591` works around this
  client-side. Do not assume the RPC can update anything.
- **`SyncFailurePolicy` treats all of 4xx as permanent** except 408/425/429. A **401 from an
  expired JWT therefore quarantines and discards the write** — silent data loss. 401 should
  refresh the token and retry. Reconsider 403 too.
- A verification meal named **"Codex server signoff"** is sitting in the Breakfast slot of the
  live account and needs deleting.
- **RIR is fabricated at both capture points**: `TrainingProgramView.swift:1424`
  (`rir: skipped ? nil : 2`) and `AppSession.swift:1605` (`rir: 2`).
- **`session_mode` appears in exactly one Swift file** (the model, uncommitted). Nothing reads it.
- **`Features/Onboarding` contains no "skip" string anywhere.**

### COMMERCIAL RULE — DECIDED, DO NOT RE-ASK

The owner settled this directly: **during beta there is no free trial at all.** Ignore
`Entitlement.trialDays` and any paywall copy that still promises "7 days free" — both are stale and
must be removed.

The gate is hard and immediate after sign-up:
- The four founding/bespoke accounts pass permanently and **do not consume beta codes**.
- The five beta codes belong to five entirely new family accounts, one redemption each.
- Everyone else sees the three-slide intro deck ending at the paywall, and cannot reach a single
  protected APEX screen without a verified StoreKit entitlement or a redeemed code. Not even one
  frame of the portal.
- Entitlement is account-scoped and server-authoritative. The current build stores a **device-wide**
  unlock flag, which would let one redeemed family account unlock a different account on the same
  iPhone. That is a security defect, not a preference.
- The Coach card stays visible, greyed out, labelled "Coming soon", excluded from StoreKit.

---

## STRANDED WORK — READ BEFORE STARTING ANYTHING

Codex repaired a set of audit findings in `~/APXAppiC-codex-release`, then abandoned that clone and
rebuilt only **part** of that work on the current branch. I diffed both. These fixes exist **only**
on the frozen commit `909cd63` and are **not** on `codex/main-critical-repair`:

| finding | status on the active branch |
|---|---|
| Realtime subscribed to the whole public schema | **still unfiltered** — `SupabaseService.swift:306` is still `postgresChange(AnyAction.self, schema: "public")` |
| Web supplement `21000` duplicate batch | **not fixed** — no dedup in `src/store/AppStore.tsx` |
| `food_preferences` `23503` stale references | **not fixed** |
| `020_restrict_rls_auto_enable.sql` | **missing** — the grant was hardened directly in the production DB via MCP, so prod is fixed but the migration file is absent; a fresh environment would not get it |
| Orbit nutrition recorded as consumed | **unverified** — verify against the current code before assuming |
| Orbit run import deleting unrelated activity | **unverified** — an `overlapping` guard exists but is also present on `main`, so it predates the repair |

`9f6c34e` touched only five files (`AppSession`, `APEXModels`, `OfflineStore`, `MealComposerView`,
`MealComposerTests`). Everything else from the first repair attempt was left behind.

**Do not re-implement these from scratch.** Read `909cd63` in `~/APXAppiC-codex-release` first and
port what is sound, with tests.

## LAUNCH SCOPE AND WORKING POLICY — decided 22 Aug

**Order is unchanged: finish the work, then launch paid.** A free or code-only beta was
considered and rejected. Phases run in their existing numbered order; do not pull Phase 4 or 5
forward, and do not ship an interim free release.

### Launch scope, decided
- **Two products only**: Premium monthly and Premium yearly. Do not create Coach products —
  a subscription with no platform behind it is a 3.1.2 rejection risk. The Coach card stays
  visible, greyed, "Coming soon", excluded from StoreKit.
- Pricing cards are purchasable at launch. The five beta codes bypass the paywall for family
  accounts, per 4.2.
- **Defer App Store Server Notifications V2 to 1.1.** For launch, `Transaction.currentEntitlements`
  checked on launch and on foreground, mirrored to Supabase, is sufficient. Do not build the
  JWS-verifying Edge Function now; it processes renewals that will not exist for a month.

### Owner-side, runs in parallel and blocks nothing you build
The Paid Applications agreement (App Store Connect → Business) must be Active before IAP products
can be created. That is the owner's task. **The StoreKit client code does not depend on it** — only
sandbox testing does. When you reach Phase 4, build and unit-test against a local `.storekit`
configuration file so the two never block each other.

### Review-effort policy, effective now
This matters more than it looks. The Task 5 review loop ran roughly ten rounds and consumed a
disproportionate share of the owner's weekly budget. It found real defects — the fabricated profile
defaults were worth every round — but it is not the right setting for everything, and at that burn
rate "finish everything first" is not affordable.

- **Full independent review**: anything touching persistence, account isolation, entitlements,
  money, or health data.
- **Single-pass review**: UI, copy, layout, labels, animation.

A chip label does not earn a review cycle. Spend the budget where a defect would cost data or money.

---

## PHASE 1 — Native workout repair

### 1.1 Honest RIR
Finish the uncommitted work. RIR optional; absent stores `nil`; the guided player asks at a
sensible moment; `ManualWorkoutLoggerView` gains an RIR control; tracked mode exposes it directly.
`ProgressionEngine` currently reads
`atTargetRIR: bucket.reps.allSatisfy { $0.rir == nil || $0.rir! <= 2 }`, which is always true
while every set is written as 2. Give missing RIR a conservative, documented fallback rather than
treating it as target met. Exports must never print RIR 2 unless the user recorded 2.
Tests: encode/decode, migration of existing rows, progression, history, export.

### 1.2 Port `session_mode`
`supabase/migrations/019_session_mode.sql` defines `guided | tracked` on `program_days` and its
comment specifies the behaviour precisely. Wire it natively: per-day mode choice, remember the
last choice as a default without corrupting the prescribed day, both modes writing identical
canonical history. Web already implements this (`src/pages/TrackedSession.tsx`,
`src/lib/sessionShape.ts`) — port the real algorithm, do not approximate.

### 1.3 Workout calendar correctness
Tapping calendar days under the 3D figure reportedly shows every day as Rest. `c1b0e77` fixed
rest-day *rendering*; verify whether the calendar *query* is still wrong (date, timezone, program
slug, ownership, fallback). Days must distinguish: scheduled, rest, deload, completed, partially
completed, missed, manually logged, custom, no prescription. **A day with no prescription shows an
honest empty state, never a fake rest day.**

### 1.4 Skippable induction with a working plan B
Add a visible Skip to the six-question workout induction. Skipping must not fabricate height,
weight, ability, pain or equipment, and must leave a route back. `TrainingInductionPanel` is
currently gated on `settings.addons["newbie_mode"] && (slug == "transition" || slug == "main")`,
which hides it from exactly the advanced users who skipped. Gate it on "no generated plan exists".

### 1.5 Exercise-kind-aware logging
244 typed movements exist. Do not show barbell-rep inputs for everything. Strength: sets/reps/load/RIR.
Bodyweight: sets/reps/assist or added load/RIR. Isometric: duration, optional load. Carry:
distance or duration + load. Cardio: duration/distance/pace. Mobility: duration or completion.
Intervals: work/recovery. Circuits: rounds and time.

### 1.6 Supersets
The generator emits them; the native timeline flattens them into sequential exercises. Represent
them as linked work: grouping, round structure, rest after the intended pairing, clear labelling,
correct history writing.

### 1.7 Zero-rest and timer correctness
A prescribed zero-second rest must not become a default rest through nil-coalescing. Cover zero
rest, custom rest, movement-specific rest, warm-up timing, backgrounding, interrupted-session
recovery, completion.

### 1.8 Custom workouts runnable
`2950099` made custom workouts real follow-along sessions **on web only**. On iOS the Custom page
is a dead list (`slug != "custom"` guards the path that launches the player). A custom workout must
be creatable, orderable, configurable (sets/reps/time/distance/rest/supersets), runnable guided or
tracked, and must feed history, progression and Avatar signals without duplication.

### 1.9 Live metabolic dayline
`fb29aee` removed the duplicate time labels. Remaining: drag-to-reschedule with the configured
increment, timezone-correct snapping, accurate current-time indication, distinct planned/completed
states, refresh after edits. Restore the meal-to-training guidance from the web implementation
(post-meal window, compromise window, suitable window; based on meal energy, macro composition,
size and configured workout; no false medical certainty). **Read the web algorithm; do not
approximate it from screenshots.**

---

## PHASE 2 — Live production bugs and iOS/web parity

### 2.1 Web bugs firing in production right now
Confirmed in Supabase logs, ongoing: **`21000`** (supplement `ON CONFLICT DO UPDATE` affecting the
same row twice — `src/store/AppStore.tsx` dedupes local state but sends the original array) and
**`23503`** on `food_preferences` (references food IDs no longer in `foods` —
`src/store/FoodStore.tsx`). Fixes exist on frozen `909cd63`. Land them properly with tests.

### 2.2 Imported activity UUID error — UNVERIFIED, inherited claim
The previous brief said values like `orbit-d4c3a069-...` were being written into UUID columns.
**I could not reproduce this.** The only `orbit-` prefixed strings in Swift are export filenames,
a poster path, a draft file path, and `planVersion = "orbit-campaign-1.0.0"` — none of which is a
UUID column. Run activity writes use `clientIdempotencyKey: "ios-run-<uuid>"`, and
`client_idempotency_key` is a text column, so that is legitimate. Confirm against production logs
before spending time here; it may already be fixed or may have been misdiagnosed. If it is real,
use real UUIDs and keep the source namespace in a source column.

### 2.3 Supabase hardening (from the audit)
- `beta_codes` has RLS but no policy (inaccessible rather than exposed — still needs a policy).
- `rls_auto_enable()` is executable by `anon` despite being `SECURITY DEFINER`; revoke that grant.
- Leaked-password protection is disabled.
- Foreign keys lack supporting indexes; many RLS policies re-evaluate `auth.uid()` per row.
- Query limits silently drop older records out of in-memory history and analysis. Verified in
  `SupabaseService.swift`: workout_sessions 180, workout_logs 2000, deload_marks 180,
  activity_logs 360, daily_logs 90, logged_meals 360, logged_food_entries 1000. Paginate or bound
  the analysis window explicitly rather than truncating silently.

### 2.4 Realtime and reload cost
Verified: `SupabaseService.swift:306` calls `channel.postgresChange(AnyAction.self, schema: "public")`
with no table filter and no user filter, so every change anywhere in the public schema wakes the
client. The reload it triggers is exactly 34 concurrent `async let` queries. This is a credible
cause of battery drain, network traffic and sluggishness. Filter the subscription to the tables and
user that matter, and debounce or scope the reload.

### 2.5 Parity matrix
Build and execute a matrix comparing real behaviour — not screenshots — across: auth and identity,
languages, Simple/Advanced modes, date navigation and calendar (copy/clear/paste day, new IDs on
copy, timezone), Nutrition at a Glance and the target modal, the Daily Activity Estimator (Quick
and Precise modes kept separate, no double counting), meal composer and Food Memory, hydration,
supplements, recovery and wearables, Avatar, Orbit, Settings. Compare behaviour, calculations,
DB reads and writes, ownership, offline behaviour, error behaviour, localisation, date handling.

### 2.6 Cross-platform contract tests
The two clients must not invent different enum strings for one concept. Create fixtures proving
Swift and TypeScript encode and decode canonical Supabase payloads identically.

### 2.7 Translations
Chrome is complete in all 8 languages. **~2,269 content strings remain** for German, Swiss German,
Italian, Spanish, Japanese and Portuguese (food quantities, export headings, marathon copy, engine
content). `ios/APEXNative/Tools/audit-translation-coverage.mjs` measures coverage; six guards in
`APEXTests/LocalisationCoverageTests.swift` catch invented keys, mixed scripts, stranded English,
lowercased shouted labels, mismatched format arguments, and languages offered before completion.
**No em dashes in UI copy. No language offered until finished.**

---

## PHASE 3 — Verification and delivery

Run Swift unit tests, Swift Testing/XCTest suites, integration tests, and the web suite and build.
Add a regression test for every repaired bug. Note: four UI smoke tests were failing at handoff —
identify whether they are genuine navigation regressions or brittle tests (one is known to search
for non-unique text when a unique accessibility identifier already exists).

Physical iPhone is the authoritative device (`A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6`, "iConstantine
Main"). Build, sign, install and launch the exact tested binary from the repair clone. Verify the
bundle identifier is `ch.apexperformance.APEX` and that the launched process is APEX before reading
any screenshot. Record the installed commit SHA.

Server-side verification, not UI verification: new meal without `23514`; settings update without
`42501`; edited meal content visible in the database; future-date meals save; day copy without child
ID collision; offline queue drains after a poisoned entry; imported activity carries valid UUIDs;
account isolation intact.

Then commit, push, and confirm GitHub Pages deploys and the live site still signs in and round-trips
one shared record.

---

## PHASE 4 — Beta access, onboarding deck, StoreKit, paywall

Design work already exists — read these before writing anything new, and extend rather than
duplicate them:
- `docs/plans/2026-08-21-beta-access-storekit-design.md`
- `docs/plans/2026-08-21-beta-access-storekit-implementation.md`

**Get the trial decision from the owner first (section 1, DECISION REQUIRED).**

### 4.1 Entitlement gate
Server-backed and authoritative. Must not be bypassable by reinstalling, clearing local storage,
editing defaults, deep links, the web client, restoring a stale cache, or switching accounts. Cache
for resilience; reconcile securely.

### 4.2 Beta codes
Five codes exist, stored hashed in `beta_codes` with `redeem_beta_code(p_code_hash text)`
(security definer, returns `ok | already_redeemed | not_signed_in | invalid_or_used`), a unique
partial index on `claimed_by`, and `profile.beta_code_redeemed`. **Do not put plaintext codes in
Swift or JS.** The four bespoke accounts are grandfathered server-side and do not consume codes.
Tests: valid unused, invalid, already used, concurrent redemption, same account retrying,
whitespace/case variants, network interruption, RLS isolation.

### 4.3 Premium onboarding deck
Roughly three manually swiped slides, then the paywall as the final card. Cinematic, calm, fast.
Suggested: (1) one connected performance system — nutrition, hydration, supplements, recovery,
training and Avatar signals communicating; (2) training intelligence — adaptive programming,
guided or tracked, progressive overload, exercise-specific logging, recovery-aware scheduling;
(3) APEX Orbit — route intelligence, run missions, marathon preparation.

Use GPT Image 2 for the slide artwork (via the session's image-generation MCP tooling), for
supporting imagery only. **Never ask an image model to invent readable app UI** — use genuine APEX
screenshots or native recreations for any product claim. Keep all copy as native SwiftUI text for
localisation and accessibility; do not bake English into rasters. Respect Reduce Motion, allow
manual swiping, show progress, do not auto-advance aggressively.

### 4.4 StoreKit 2
Real subscriptions for Premium monthly and annual. Purchase, pending, cancellation, failure,
verification, restore, current entitlements, revocation, expiration, upgrade/downgrade, family
sharing per product config, backend entitlement sync, App Store Server Notifications where
practical, sandbox testing, a StoreKit configuration file for local tests.
**Do not hardcode CHF prices** — the paywall currently does. Use `Product.displayPrice` and derive
the savings percentage from actual StoreKit prices. Do not invent product IDs; configure or inspect
the real App Store Connect products.

### 4.5 Coach card
Visible as a future tier but greyed out, labelled "Coming soon", non-purchasable, excluded from
StoreKit actions. Do not sell an unfinished tier.

### 4.6 Legal (App Store blocker)
The paywall currently has none of this. Add: Terms of Use link, Privacy Policy link, auto-renewing
subscription disclosure, duration, billing and renewal behaviour, how to cancel, Restore Purchases,
correct localised pricing. The legal URLs must resolve publicly without authentication.

### 4.7 Web entitlement parity
The web fallback reads the same entitlement state. An entitled subscriber can use it after sign-in;
a non-entitled account must not bypass the native paywall via GitHub Pages. No fake Apple purchase
flow in the browser — an honest entitlement message instead.

---

## PHASE 5 — App Store readiness

### 5.1 Technical
Release configuration, version/build numbering, signing, bundle ID, icons, launch experience,
StoreKit products, privacy manifest, required-reason APIs, HealthKit entitlements, location,
motion, camera, photo library, notifications, background modes, account deletion, data export,
offline behaviour, crash handling. No development endpoints, embedded test credentials, embedded
beta codes, private APIs, placeholder buttons, or unfinished screens presented as complete.

### 5.2 Accessibility
Already done: Dynamic Type via `UIFontMetrics` across all 874 call sites, `AnyLayout` reflow at
accessibility sizes, Reduce Motion honoured on the animations that never stopped.
**Not yet checked: Bold Text, Increase Contrast, and VoiceOver labels on icon-only buttons.**
Also audit touch-target size, charts, 3D-body alternatives, calendar navigation, the workout player
in motion, the paywall, the onboarding slides, and error messages.

### 5.3 Health and fitness boundaries
APEX gives fitness, education and performance guidance. It must not claim to diagnose, medically
clear anyone for exercise, replace a doctor or physiotherapist, guarantee injury prevention,
interpret medication compatibility, guarantee a race result, or guarantee route safety. Label
estimates honestly and keep calculations transparent.

### 5.4 Listing screenshots — the owner's specific direction
Three to four compositions, each a **real APEX screenshot half-revealed** behind a generated subject,
poster-like and seamless rather than a screenshot pasted next to an image:
- **Nutrition** — the interface partly covered by food items.
- **Orbit** — partly covered by a runner's body in a running stance, route detail still legible.
- **Live workout** — partly covered by a fitness model mid-exercise, matching the session shown.
- **Avatar / connected system** — a refined holographic or human-performance motif.

Use GPT Image 2 for the generated subjects. **Never let an image model invent app UI** — every pixel
of interface must be a genuine capture. **Do not include the paywall**; the listing states in-app
purchases on its own. No private user data, no exact home-route locations. Produce the current
required device sizes, keep sources editable, verify every export visually.

### 5.5 Listing copy
Write it to sit comfortably beside world-class fitness apps: natural English, confident, unfussy
grammar, no translated-sounding phrasing. It is the first impression a stranger forms of the product.
App name, subtitle, promotional text, full description, keywords, What's New template, support URL,
privacy URL, marketing URL, App Review notes, subscription explanation, health and location
explanation, demo account instructions, and short forms for localisation. Position APEX on the fact
that it connects nutrition, training, activity, recovery, hydration, supplements, running and
long-term body development into one private system. No "best app" claims, no medical claims.

### 5.6 Release path
Critical repairs → launch-critical parity → accessibility and privacy audits → StoreKit local and
sandbox testing → beta-code testing → archive → App Store Connect/TestFlight → controlled TestFlight
pass → resolve blockers → final metadata → submit only what is genuinely complete, Coach still
"Coming soon".

---

## PHASE 6 — Coach-to-client platform

Begins only after the individual Premium product is launched and stable. Coach sales stay disabled
until this is production-ready.

### 6.1 Commercial model
Coach-sponsored client access: the coach subscription includes a defined number of active client
seats; a client accepts an invitation and explicitly consents; while attached to an active paid seat
the client uses the client-facing features needed to follow their plan without buying an individual
subscription. If the relationship ends, the client keeps their data and export rights, with a
transparent grace/read-only state before an individual subscription is required. **Never delete a
client's history because a coach removed a seat.** Verify the final model against current App Store
rules before launch.

### 6.2 Server-side entities
User role, subscription tier, coach profile, coach-client relationship, invitation, consent status,
seat assignment, permission scopes, plan ownership, assignment history, client acknowledgement,
coach action audit log. **Not a client-side role flag.** A coach must never see another coach's
clients.

### 6.3 Permission scopes
The client controls what the coach sees: nutrition logs, workout logs, activity, hydration,
supplements, Avatar stats, advanced measurements, notes, recovery, visual progress. **Private
progress photographs stay invisible to a coach unless the client grants explicit, revocable
permission.**

### 6.4 Coach workspace
Calm and professional, not a wall of widgets: today's priorities, client roster, attention-needed
list, recently completed plans, missing plan pillars, upcoming reviews, client status summaries,
search, filters, templates, reports.

### 6.5 Per-client plan checklist
Nutrition ✅ / Workouts ✅ / Supplements ✅ / Hydration ✅ / Schedule ✅ / Review date ✅. The coach marks
a section complete; the client gets a concise notification when a section is ready or materially
changed.

### 6.6 Nutrition programming
Review the client's goal and profile; set or propose calories and macros; build reusable predefined
food lists; assign meals and templates; set meal timing; configure adaptive versus fixed foods; set
hydration; add notes; preview exact calorie and macro effects; schedule start and end; preserve
version history. **Never silently rewrite a client's historical logged meals.**

### 6.7 Workout programming
Build sessions from the typed movement library; assign weekdays; set guided/tracked defaults;
configure sets, reps, duration, distance, load guidance, tempo, rest and RIR targets; build
supersets and circuits; warm-up and cooldown; loop a week; rotate sessions every N weeks; insert
deloads such as every eighth week; alternate A/B weeks; minimum-effective versions; respect
equipment and calendar restrictions; version and publish; preview the client experience; see
prescribed versus completed.

### 6.8 Supplements, hydration, communication
Assign supplements and timing without diagnosing or prescribing medication; client acknowledgement
and completion tracking; water target accounting for food-derived water. Notifications limited to
what is useful: plan updated, review requested, session completed, check-in submitted, material
target changed. No manipulative engagement mechanics.

---

## PHASE 7 — Avatar baselines, advanced measurements, reporting

### 7.1 Baseline questionnaire
Stop initialising every new user at 50/100. After entitlement is established, add a concise
**separate** baseline questionnaire (distinct from workout induction, which stays skippable).
Anchored self-assessment, not vague sliders: upper-body strength, lower-body strength, endurance,
flexibility/mobility, joint comfort or load tolerance, training consistency, general activity.
Each 1–10 point needs a plain-language anchor (typical untrained adult / recreationally active /
consistently trained / advanced / outlier athlete). Neither flattering nor punishing.
Translate answers into conservative initial 0–100 estimates carrying source = user-reported
baseline, date, confidence and an explanation. Real logged evidence gradually replaces the estimate.

### 7.2 Advanced Avatar view
Optional view for manually entered or imported measurements: body weight, body fat, lean mass,
skeletal muscle mass, visceral-fat rating, bone density, bone mass, waist, measured BMR, resting
heart rate, VO2max. Every measurement stores value, unit, date, source, method, optional note, and
whether it was measured, device-estimated or user-entered (DEXA, smart scale, Apple Health, lab
test, manual measurement, user estimate). **Never present a smart-scale estimate as equivalent to
DEXA.** Store as append-only observations, not one overwritten profile value, so history is real.

### 7.3 Reports and export
Three modes: **Avatar Only**, **Workouts Only**, **Complete**. Include date range, source,
prescribed versus completed, strength progression, RIR where genuinely recorded, volume,
consistency, nutrition adherence, hydration, recovery, advanced measurements, coach notes where
permitted, and an honest data-confidence and missing-data disclosure. Export to polished PDF and a
structured data format. Graphs should be lab-grade and genuinely enjoyable to read — real data,
units, labelled source changes, no smoothing that misrepresents, no false precision, accessible.

---

### 7.4 One ledger, not two systems
Do not store an Avatar stat as a number that different subsystems overwrite. Store **observations**
and derive the stat. Every observation carries value, date, source, method and confidence:

| source | method | feeds |
|---|---|---|
| baseline questionnaire | user-estimated, low confidence, decays | seeds every stat instead of a flat 50 |
| logged training | measured | e1RM per lift, volume, consistency |
| HealthKit | device-estimated | VO2max, HR recovery |
| DEXA / manual entry | measured, high confidence | body composition, bone density, measured BMR |

Resolution rule, identical to the energy rule in 7.5: **measured outranks estimated, recent outranks
old, confidence decays.** The questionnaire seeds the avatar on day one and fades on its own as real
evidence accumulates, so there is never a reconciliation step between manual input and logged work.

The decay rate is a **heuristic, not a finding**. There is no literature that fixes it. Expose it as
a tunable and label it as an assumption wherever it affects a displayed number.

### 7.5 Expenditure: intervals with provenance, resolved once
Energy is currently at risk of being counted twice (Orbit adds suggested nutrition to consumed
totals; imported runs delete unrelated activity). The fix is structural, not a policy choice between
"count it" and "decorate with it".

Every expenditure record carries interval (start/end), value, source and method. The daily total is
**resolved, not summed**: overlapping intervals collapse, and within an overlap the precedence is
measured > device-estimated > APEX MET estimate > plan assumption. A session card showing
"412 kcal · Apple Watch" and the day's total including 412 once are then the same record seen twice,
not two rows.

Flexibility: a per-account expenditure source setting (Automatic / Wearable only / APEX estimates /
Manual), settable by a coach per client, with a per-client scaling factor built on the existing
`calibrationK` on the profile (`calibration_k`, used at `AppSession.swift:2632`). Coaches distrust
Watch calories for lifting and they are right to; HR under load does not track oxygen cost the way
steady-state cardio does.

Always **show the resolution**: "2,840 kcal today — Watch active energy across 3 workouts, APEX
estimate for 1 unmatched session." A number whose source is visible gets believed.

### 7.6 HealthKit session enrichment
Permissions and plumbing already exist: the app requests `heartRate`, `activeEnergyBurned`,
`appleExerciseTime`, `stepCount`, `restingHeartRate`, HRV, `vo2Max`, `bodyMass` and `workoutType`,
and reads `HKWorkout` duration/distance/energy in `HealthKitManager.swift`. What is missing is
attaching any of it to a training session — `WorkoutSession` has no heart-rate field.

- Use `HKWorkout.statistics(for:)` (iOS 16+) rather than separate sample queries. This app already
  fires too many queries.
- **Store the `HKWorkout.uuid` on the session.** This makes correlation idempotent and retires the
  date + source + duration dedup heuristic that currently mistakes two similar runs for duplicates.
- Write sessions back with `HKWorkoutBuilder` so APEX closes the user's rings and appears in Fitness.
  Different entitlement (share, not read) and the same double-count discipline.
- Honest empty states: heart rate exists for a lifting session **only if an Apple Watch recorded it**.
  Phone-only users must not see a broken or fabricated panel.

### 7.7 Strength by muscle group, on the body itself
The navigation surface already exists: the 3D figure. Make it the strength dashboard rather than
building a separate screen.

- **Tint by trend, not absolute score.** Absolute strength painted on a body reads as judgement
  ("your chest is weak"); trend reads as information ("hamstrings stalled for six weeks").
- **No data must look absent, not zero.** Unlit, not dark red. Same honesty rule as RIR.
- **Weight attribution by movement role.** `movement_library.role` already carries
  `primary | accessory` (migration 016). Primary lifts drive a group's trend; accessories contribute
  at reduced weight. State the attribution in the tooltip so it is inspectable rather than magic.
- Tapping a region opens that group's lifts with their individual e1RM trends. The composite must
  **expand into its inputs** — a coach needs to see that the overhead press stalled while the bench
  moved, and a single "upper body 68" hides exactly that.
- The actionable output is stall detection: "hamstrings: no e1RM gain in 6 weeks across 3 lifts."
- Caveat to respect in the UI: e1RM formulas (Epley, Brzycki) degrade badly above roughly 8 reps.
  Show a confidence band rather than a point estimate when the source sets were high-rep.
- HR recovery between sets is **heavily confounded** by rest duration, caffeine, temperature, sleep
  and proximity to failure. Only compare rest-interval-matched sets within one person and one
  exercise, or do not show the comparison at all.
- Let a coach **switch the gamified layer off entirely for a client** and work from raw data. Some
  will, and being able to is what makes the rest credible.

### 7.8 Branded PDF export
Three report modes (Avatar Only / Workouts Only / Complete) exported as a print-quality PDF a coach
is proud to send.

Rendering: no third-party dependency. Draw into a `UIGraphicsPDFRenderer` context so **text stays
vector and selectable** and charts are vector paths, not screenshots of the app. `ImageRenderer` is
already used for the Orbit route poster but rasterises; that is wrong for print. Default to **A4**
(the users are Swiss), offer Letter. Pagination must be deterministic — a report that reflows
differently on each export looks amateur.

Branding model. A logo belongs to an **organisation**, and a coach may or may not have one:
- New `organisation` entity (gym or studio): name, logo, optional accent colour.
- Coach carries an optional `organisation_id` and an optional personal logo.
- Resolution order per report: explicit per-report override > organisation logo > coach's own logo >
  APEX default. Resolve at render time from current membership, so a coach who leaves a gym stops
  emitting that gym's mark on new reports.
- Storage follows the existing per-owner bucket pattern from migration 005, scoped to the
  organisation rather than to `auth.uid()`.
- Accept PNG and SVG, require a transparent background, cap the file size, and render at print DPI.
  A 200px PNG on an A4 header looks cheap and undoes the point of the exercise.

**Decision for the owner:** co-brand or full white-label? Keeping a small "Powered by APEX" mark
preserves a marketing surface every time a coach sends a client a report; removing it sells better
to gyms that want the document to look entirely their own. This is a business call, not a technical
one — ask rather than choose.

Every report carries the provenance work above: date range, source per figure, method, and an honest
missing-data disclosure. That is what makes it a document a sports-science coach will sign their name
to.


## VOICE AND TRAINING-SCIENCE ITEMS

### Follow-along voice (active, not deferred)
Replace the current follow-along coach audio with ElevenLabs voices to raise the quality of the
live session. Use the ElevenLabs MCP tooling in the session. Keep cue text as localisable strings
so the same script can be voiced per language rather than baked into English audio, and make sure
a missing or still-generating voice falls back to the existing audio instead of a silent session.

### Hamstring eccentric tempo — decision for the owner, not a bug
`src/lib/liftingTempo.ts` defines a tempo class `hamstring_eccentric`: a 4 second lowering,
1 second pause, 1 second lift, marked evidence `strong`, on the reasoning that eccentric hamstring
work carries the strongest injury-reduction evidence of any single exercise and the lengthening is
where the adaptation happens. 18 movements in `src/data/movements.ts` currently carry
`tempoClass: 'hamstring_eccentric'`.

The open question is whether to extend that class to the remaining movements that qualify for it
but are not tagged. Doing so lengthens every affected set, which adds meaningful time per training
week. **Re-derive the exact affected row count and the added minutes before proposing it** — an
earlier estimate exists but has not been re-checked against the current library. This is a training
prescription decision, so put the numbers in front of the owner rather than applying it.

---

## DEFINITION OF DONE

A phase is not complete because code exists. For each completed task report: files changed, commit
SHA, tests added, tests run, results, Supabase schema or log verification, iPhone build
configuration, the installed commit SHA, web build result, GitHub Pages deployment result where
relevant, remaining limitations, and any external configuration still required in App Store Connect,
Supabase or Apple Developer.

Do not claim anything is complete without that evidence.
