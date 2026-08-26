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

## 1. WHERE THINGS STAND

**This section deliberately holds no snapshot.** The previous version named a HEAD, a commit count
and three uncommitted files; within a day all three were wrong, and a stale status block is worse
than none because it is read as current.

The live record is **`docs/REPAIR-NOTES.md`**, appended after every task. Read it, then run
`git log --oneline -15`. Between them you will know more than any paragraph here could say.

Completed as of 26 Aug: **Phase 1 sections 1.1 through 1.7**, and **Phase 2 sections 2.1, 2.3 and
2.4**. Those subsections are left in place rather than deleted, so the record shows what was covered
and what the tests guard. Do not redo them; verify against the code if in doubt.

### Recovered work — closed, kept for the record
Six fixes were once written in an abandoned clone and left behind. All six were recovered in Task 1
and verified present: realtime subscription filtering, the web supplement duplicate-batch fix, the
`food_preferences` stale-reference repair, migration `020_restrict_rls_auto_enable.sql`, and the two
Orbit items. Commit `909cd63` on `codex/critical-ios-fixes` in `~/APXAppiC-codex-release` remains
frozen as history and has nothing left to give.

### Traps still live — verified 26 Aug, do not assume these are fixed

**`SyncFailurePolicy` still treats the whole 4xx range as permanent** except 408/425/429.
`OfflineStore.swift:23` reads `if (400..<500).contains(statusCode) { return .permanent }`. So a
**401 from an expired JWT quarantines and discards the write** rather than refreshing the token and
retrying. That is silent data loss, it has been open since the handoff, and it now has a numbered
home at 2.8.

**`log_structured_meal` (migration 009) is still create-only.** It short-circuits on a known
`client_idempotency_key` and returns before any replace or insert. The only `update` inside it
writes computed totals during creation; there is no path that edits an existing meal. `d92a591`
works around this client-side by varying the key on reopen. Do not assume the RPC can update.

**`LazyVStack` has bitten this codebase twice** — the training month grid and the nutrition page,
where a lazy stack never materialised the cards below the fold and content was unreachable by
scrolling. Both were made eager. Check before adding a third.

**Never surface `Swift.CancellationError` to a user.** Cancel stale work deliberately; do not show
that error.

---

### COMMERCIAL RULE — SUPERSEDED 26 Aug

The earlier rule here described a hard paywall at launch with purchasable pricing cards. **That is
no longer the plan.** The app now ships to TestFlight first and does not charge at all in that
phase. See Phase 4.

What survives from it, because it was never about pricing:
- The four founding/bespoke accounts pass permanently and **do not consume beta codes**.
- Entitlement must be **account-scoped and server-authoritative**. The current build stores a
  **device-wide** unlock flag, which would let one account unlock a different account on the same
  iPhone. That is a security defect, not a preference, and it is fixed in 4.4.
- `Entitlement.trialDays` and any paywall copy promising "7 days free" are stale and must be removed.

Everything else about prices, codes on the paywall and the Coach card is settled in Phases 4 and 5.

### Review-effort policy
The Task 5 review loop ran roughly ten rounds and consumed a disproportionate share of the owner's
budget. It found real defects — the fabricated profile defaults were worth every round — but it is
not the right setting for everything.

- **Full independent review**: anything touching persistence, account isolation, entitlements,
  money, or health data.
- **Single-pass review**: UI, copy, layout, labels, animation.

A chip label does not earn a review cycle. Spend the budget where a defect would cost data or money.

---

## EXECUTION ORDER — read this, the numbers are identity, not sequence

Phase numbers are stable identifiers so the cross-references throughout this document keep working.
**They are not the order of work.** The order is:

> **1 → 2 → 3 → 9 (Apple Watch) → 4 (TestFlight) → 5 → 6 → 7 → 8**

Phase 9 moves ahead of TestFlight on the owner's decision, 26 Aug: the testers are friends who own
Apple Watches, and a companion that only tracks water invites the same question from every one of
them. See the sequencing note at the head of Phase 9 for what may be deferred within it.

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
332 typed movement definitions, 96 of them selectable exist. Do not show barbell-rep inputs for everything. Strength: sets/reps/load/RIR.
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

### 2.8 401 must refresh and retry, not quarantine
`SyncFailurePolicy.classify` treats every 4xx except 408/425/429 as permanent, so an expired JWT
causes the write to be quarantined and dropped. Token expiry after the app sits backgrounded is the
most ordinary 401 there is and it heals completely on a refresh.

Fix: 401 refreshes the session and retries with bounded backoff. Reconsider 403 as well —
post-4.4 it should not occur, but discarding user data on one is the wrong failure direction.

Related: a quarantined write is currently **silent**. `quarantine()` records the failure and removes
the operation with nothing surfaced. The queue no longer jams, which was the fix, but the discarded
write still vanishes without telling anyone — and the original complaint that started all of this
was a meal disappearing. A quarantined write needs to be visible.

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

## PHASE 4 — TestFlight release

**Runs after Phase 9, not before it.** See the execution order above.

**Decided 26 Aug: the app ships to TestFlight, not the App Store, and it does not charge yet.**
The previous Phase 4 (StoreKit and paywall) and Phase 5 (App Store submission) are replaced by
this. Monetisation is deferred to Phase 5 below and does not gate anything here.

The reasoning is that bugs get found by people using the app, not by more rounds of internal
review, and nobody should be charged for a build still finding its shape.

### 4.1 What TestFlight actually needs
Far less than an App Store submission. **No StoreKit, no paywall, no screenshots, no listing copy,
no App Review** for internal testers.

- An App Store Connect record for `ch.apexperformance.APEX`.
- A **Release** archive, not Debug, signed for distribution.
- The export-compliance answer. The app uses HTTPS only, so it is almost certainly exempt, but the
  question must be answered or the build will not process.
- `PrivacyInfo.xcprivacy` — **already present** at `ios/APEXNative/APEX/PrivacyInfo.xcprivacy`.
- Build number incremented on every upload. Version stays `1.0.0`; the build number is what
  distinguishes uploads.

The Paid Applications agreement is **not** required. That gates selling, and nothing here sells.

### 4.2 Internal versus external
- **Internal** — up to 100 people, added as users in App Store Connect, **no Beta App Review**,
  builds live within about an hour of processing. This is the near-term target.
- **External** — up to 10,000 via a public link, needs a light Beta App Review and a "what to test"
  note plus a contact email. Worth enabling once the internal group stops finding basics.

### 4.3 Access during TestFlight
Testers get the build; there is no purchase to make. So during this phase:
- **No paywall, no price display.** A price with nothing behind it is pointless here and becomes an
  App Store rejection later if it survives into submission.
- Entitlement still resolves server-side and still grants everyone, per 4.4. Build the gate now
  even though it says yes to everybody.
- The Coach card stays out entirely rather than greyed. There is nothing to preview yet.

### 4.4 Ship the gate, granting everyone — this is the load-bearing part
If this build has no entitlement concept, then the version that introduces charging has to add
gating to clients whose installed binaries contain no gate, and everyone who does not update keeps
full access forever. They will not choose to install the update that removes their access.

So: every account carries a server-side entitlement row with a state and an `expires_at`. During
TestFlight it resolves to granted with a stated date. The app checks it on launch and on foreground,
caches it for offline, reconciles when online. Flipping to paid later becomes a **server change**,
and old clients ask the same question and get a different answer.

Two supporting pieces, both cheap now and impossible to retrofit:
- **A server-side minimum-version check.** You cannot add one later to clients that lack it.
- **`created_at` on every profile**, which is the grandfathering list when charging begins.

### 4.5 Feedback path
TestFlight has a built-in feedback channel and captures screenshots plus device state. Put a visible
in-app route to it as well. A tester who cannot report a bug in ten seconds does not report it.

### 4.6 What still applies from the old Phase 5
These were written for an App Store submission and remain correct work, just not blocking here:

**Technical hygiene** — Release configuration, version and build numbering, signing, icons, launch
experience, privacy manifest, required-reason APIs, HealthKit entitlements, location, motion, camera,
photo library, notifications, background modes, account deletion, data export, offline behaviour,
crash handling. No development endpoints, embedded credentials, embedded beta codes, private APIs,
placeholder buttons, or unfinished screens presented as complete.

**Accessibility** — done already: Dynamic Type via `UIFontMetrics` across every call site, `AnyLayout`
reflow at accessibility sizes, Reduce Motion honoured. **Not yet checked: Bold Text, Increase
Contrast, and VoiceOver labels on icon-only buttons.** Also audit touch-target size, charts, 3D-body
alternatives, calendar navigation, the workout player in motion, and error messages.

**Health and fitness boundaries** — APEX gives fitness, education and performance guidance. It must
not claim to diagnose, medically clear anyone for exercise, replace a doctor or physiotherapist,
guarantee injury prevention, interpret medication compatibility, guarantee a race result, or
guarantee route safety. Label estimates honestly and keep calculations transparent.

---

## PHASE 5 — Monetisation and public release

**Not now.** This begins only after TestFlight has run long enough that the internal group stops
finding basics. Nothing in Phase 4 depends on any of it.

### 5.1 StoreKit 2
Two products only: Premium monthly and Premium yearly. **No Coach products** — a subscription with
no platform behind it is a 3.1.2 rejection risk. Purchase, pending, cancellation, failure,
verification, restore, current entitlements, revocation, expiration, upgrade and downgrade, family
sharing per product configuration, backend entitlement sync, sandbox testing, and a local
`.storekit` configuration so the client can be built and unit-tested before App Store Connect is
ready. **Do not hardcode prices** — use `Product.displayPrice` and derive any saving from real
StoreKit values.

**Defer App Store Server Notifications V2 to a point release.** `Transaction.currentEntitlements`
checked on launch and foreground, mirrored to Supabase, covers launch. Do not build the
JWS-verifying Edge Function for renewals that will not exist for a month.

### 5.2 Beta codes and multiplatform access
Apple's own **Subscription Offer Codes** are the sanctioned way to give family free access to a paid
subscription — configure a free-period offer, generate one-time codes, redeem through
`AppStore.presentOfferCodeRedeemSheet(in:)`. Apple enforces single use and there is no 3.1.1
exposure, because the whole thing runs through their system. The redeemed offer then appears in
`Transaction.currentEntitlements` like any other subscription, so one code path serves both a paying
customer and a family member.

The existing hashed Supabase codes move **off the iOS paywall** and stay useful for web sign-ups,
where Apple's rules do not apply, and later for coach-granted client seats in Phase 6. A redeem field
sitting beside in-app prices is the part that reads as bypassing IAP.

Guideline **3.1.3(b) Multiplatform Services** permits a user to sign in and access entitlement
acquired on the web, provided the same thing is also purchasable in-app. Do not steer users to the
web from inside the app.

### 5.3 Legal, required before submission
Terms of Use link, Privacy Policy link, auto-renewing subscription disclosure, duration, billing and
renewal behaviour, how to cancel, Restore Purchases, correct localised pricing. The legal URLs must
resolve publicly without authentication.

### 5.4 Listing screenshots — the owner's specific direction
Three to four compositions, each a **real APEX screenshot half-revealed** behind a generated subject,
poster-like and seamless rather than a screenshot beside an image:
- **Nutrition** — the interface partly covered by food items.
- **Orbit** — partly covered by a runner in a running stance, route detail still legible.
- **Live workout** — partly covered by a fitness model mid-exercise, matching the session shown.
- **Avatar** — a refined holographic or human-performance motif.

Use GPT Image 2 for the generated subjects. **Never let an image model invent app UI** — every pixel
of interface must be a genuine capture. **Do not include the paywall.** No private user data, no
exact home-route locations. Current required device sizes, sources kept editable, every export
verified visually.

### 5.5 Listing copy
Natural English, confident, unfussy grammar, no translated-sounding phrasing, sitting comfortably
beside world-class fitness apps. App name, subtitle, promotional text, description, keywords, What's
New template, support and privacy URLs, App Review notes, subscription explanation, health and
location explanation, demo account instructions, and short forms for localisation. No "best app"
claims, no medical claims.

### 5.6 App Review account
An app that shows nothing until sign-in is rejected under 2.1, or 4.2 for minimum functionality, if
the reviewer cannot see what it does. Provide a working account with entitlement already granted in
the App Review notes.

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


## PHASE 8 — Supplement scheduling

Post-launch. The supplement widget currently shows one flat list. This turns it into a schedule the
user builds themselves, with the app filling in sensible defaults it can always be overruled on.

### 8.1 User-defined blocks
Separator rows inside the supplement list, each carrying a name, an anchor and an order. The user
creates, renames, reorders and deletes them freely, and can add blocks that appear on no standard
list because their schedule needs them.

Starting set, all editable: Morning – empty stomach · Morning – with breakfast · Mid-morning ·
Before lunch · With lunch · Pre-workout · Intra-workout · Post-workout · With dinner ·
With your largest meal · Before sleep · Situational.

**The user's structure wins.** If someone renames "Before sleep" to "Night stack" or deletes it, the
app maps to what actually exists rather than recreating its own version.

### 8.2 Two kinds of anchor — this is the part that matters
The list above mixes two different things, and treating them the same is why most supplement
trackers feel stupid.

- **Absolute**: a clock time the user sets.
- **Relative**: an offset from an event that moves — "30 minutes before the session", "with lunch".

APEX already knows both anchors. The dayline knows when meals land, Settings holds the default
training time, and the plan knows which days have sessions. A relative block therefore **resolves to
a real time each day on its own**. Someone training at 07:00 on Monday and 19:00 on Thursday gets a
correct pre-workout time both days without touching anything.

A relative anchor with nothing to resolve against — a pre-workout block on a rest day — hides for
that day rather than firing at a guessed time.

### 8.3 Reminders, per block, opt-in
Each block carries its own reminder switch, default off. A reminder fires at the **resolved** time,
not a stored one, and **suppresses itself if the block is already ticked off**. Nobody gets nagged
for something they have done.

### 8.4 Compound-aware default placement — suggestion, never a lock
125 compounds already carry dosing, timing and interaction data. Use it. When a supplement is added
it arrives with a block already selected, and moving it is one tap.

- Magnesium glycinate proposes the night block.
- Iron proposes a fasted block, and **warns if it shares a block with calcium or coffee**.
- Fat-soluble vitamins propose the largest meal, because that meal is not the same one for everyone.
- Caffeine refuses to schedule itself inside the user's sleep window.
- Creatine says timing does not matter and to put it wherever it will be remembered.

An override is permanent. A supplement the user moved does not get re-suggested next time.

### 8.5 Mechanics
- Empty blocks hide entirely. No header with nothing under it.
- Interaction warnings are per block, shown where the conflict is, and never block saving.
- Blocks and their assignments are per account and sync like everything else.

### 8.6 Shared with the coach platform
6.8 already has a coach assigning supplements and timing to a client. That must use **this same block
model**, so a coach-authored schedule arrives as real blocks the client can see and reason about,
rather than a second parallel representation. Whether a client may edit a coach-assigned block is a
permission question that belongs with the other scopes in 6.3.


## PHASE 9 — Apple Watch

**This runs before Phase 4 (TestFlight), not last.** The number is an identifier, not a position.

Sequencing within the phase, if it needs shortening: **9.1, 9.2, 9.4 and 9.5 are what a tester
notices in the first five minutes** — the workout player with its two-stage haptics, complications,
and supplement ticking. 9.3 (Avatar) and 9.6 to 9.7 follow. **9.8, the live run, should not hold
TestFlight up** — it is the largest single item here and the least likely to be missed by someone
who has not yet trained with the app.

The Watch already carries the hydration companion. This extends it to the surfaces that genuinely
belong on a wrist. The filter throughout: **something you do while moving, one-handed, in under five
seconds — or that you want without unlocking anything.** Everything failing that test stays on the
phone.

### 9.1 The follow-along workout player — the reason this phase exists
During a session the phone is on the floor, in a bag, or across the gym. The watch is on the wrist
already.

- **Haptic rest timer**, so nobody watches a screen between sets.
- **Set logging on the wrist** — load and reps by the Digital Crown, RIR by tap, using the same
  descriptor-driven field model as the phone so a carry asks for distance and an isometric for time.
- **Continuous heart rate for the session**, which is what feeds 7.6.

Technically this requires an `HKWorkoutSession`. Without one, watchOS suspends the app between sets
and both the timer and the heart rate stop. That session also closes the user's rings, which is worth
having on its own.

**Watch the double count.** A watch workout session and a phone-logged session must resolve to one
expenditure record under the 7.5 precedence rule, never two.

### 9.2 The pre-warning haptic — owner's specification
A single buzz at the end of rest is too late; the user is still sitting down. So the timer fires
**twice**: a distinct pre-warning while rest is still running, then the end-of-rest cue.

- Configurable: **30, 25, 20, 15 or 10 seconds** before rest ends, plus off.
- The two cues must be **haptically distinguishable** — a lighter single tap for the warning, a
  firmer double for the end — so they are told apart without looking.
- Suppress the pre-warning when the configured lead is longer than the rest itself. A ten second rest
  with a thirty second warning must not fire immediately, and must not fire both cues at once.
- Honour Reduce Motion and the system haptic setting, and keep working when the wrist is down.

### 9.3 Avatar on the wrist — owner's specification
Not a port of the phone page. A concise version that opens with the **user's avatar portrait**,
because seeing yourself on your own watch is the moment this reads as a premium product rather than
a utility.

Carries: the portrait, strength progress, the joint check-in slides, and the headline trend
direction per stat.

Everything not suited to the screen states so plainly and stops:
- The photo comparison engine shows **"Available on iPhone"**.
- Denser sections show **"More on iPhone"** rather than a cramped rendering of themselves.

A watch screen that says honestly what it cannot do reads as considered. One that tries to show a
radar chart at 40mm reads as broken.

### 9.4 Complications — the cheapest permanent value here
A watch-face slot is real estate won once and never paid for again. Offer several so people pick
what they care about: calories remaining, water progress, next session with its time, or readiness.
Respect the complication refresh budget rather than fighting it.

### 9.5 Supplement blocks
Pairs directly with Phase 8. A block reminder fires on the wrist and dismisses **as taken** with one
tap. The use case is standing in the kitchen at 07:15 with the phone in the bedroom.

### 9.6 Morning readiness and the joint check-in
One question, answered on waking without finding a phone. Skipped check-ins are why readiness-aware
scheduling has nothing to work with, and the friction being removed is precisely "get the phone out
at 6am".

### 9.7 Planned meals
Tick a **planned** meal as eaten, or repeat a Food Memory favourite. **Not** the meal composer —
food search on a 40mm screen is a bad idea and should not be attempted.

### 9.8 Live run — high value, expensive, sequence it last
Nobody carries a phone for a 10k, so serious running needs this eventually. It means GPS on the
watch, workout sessions, background location, and standing directly beside Apple's own Workout app.
After the strength player, not before.

### 9.9 Explicitly not on the watch
The full Avatar page and any chart, the meal composer, plan browsing, the calendar, settings.
Dense reading on a small screen is where watch apps go to be uninstalled.


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
