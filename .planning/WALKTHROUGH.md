# APEX iOS client-journey walkthrough

Date: 2026-09-02
Simulator lane: `APEX Lane · iPhone 17 Pro` (`6907359A-18D1-46B0-87F1-13CED5CE1C46`)
Scope: native iOS client only. BA-Studio and Finalova devices must not be driven.

## Purpose and acceptance rule

This is the Task 1 acceptance matrix, not a list of screens. A row remains **Pending** until its automated and human evidence lanes are complete. A crash-free screen, a static code observation, or a passing unrelated unit test is not a flow pass.

Every runtime row must bind the following before it can be executed:

- **Persona / owner / date:** the named test identity, active account, and selected local date. `A`, `B`, and `C` are ordinary new subscribers; `D` is A with measured BMR. `Bespoke` is the protected existing account; `Sponsored` is coach-managed. `A→B→A` means two distinct active accounts and a return to the original owner.
- **Precondition → actions → destination:** the exact starting fixture, numbered user actions, and the expected destination after every transition, including Close, Back, Done, Cancel, and denied paths.
- **Mutation → reopen / downstream:** created or changed owner/date-scoped record; a sheet dismiss plus app relaunch and refresh/sync when applicable; the route that reopens it editable; the intended and unintended downstream effects.
- **Negative branch:** invalid, denied, offline, restricted, delayed, malformed, or boundary input and the honest visible recovery state.
- **Artifacts / automated evidence:** screenshots after material transitions in `.planning/walkthrough/<ID>/`, named XCUITest(s), and the result bundle. The current baseline bundle path is `build/apex-client-audit/`; a passing existing smoke method is only partial evidence unless the row says otherwise.
- **Human evidence:** a discoverability script ID or `H—` when it is not one of the four human-rated journeys below. Automation establishes reachability/data effects; the human pass establishes whether the action and return path are discoverable. Neither substitutes for the other.

## Deterministic personas and fixtures

| Key | Account / facts | Required use |
|---|---|---|
| A | New subscriber, male, 38, 178 cm, 70 kg, moderate activity, no measured BMR | recomp and maintenance; ordinary owner/date assertions |
| B | New subscriber, female, 43, 165 cm, 62 kg, moderate activity, body-composition goal | higher-fat macro feasibility and account-B isolation |
| C | New subscriber, male, 45, 180 cm, 95 kg, low activity | fat-loss boundary and adult-safety cases |
| D | A plus explicitly entered DEXA/metabolic-report BMR | provenance, persistence, verified/non-authoritative measured-BMR behavior |
| Bespoke | Existing protected bespoke account | calibration may refine supported stats but must not replace protected plan |
| Sponsored | Coach-owned client account; paired Coach owner | nutrition/training/Avatar access plus locked authoring explanation |
| Empty | No account data and no preview/seed launch argument | true fresh-install zero-state tour |

## Acceptance matrix

All entries are **Pending**. `Smoke:` names current partial UI evidence only; it is not a completion claim.

| ID | Persona / owner / date | Precondition → actions → expected destination | Mutation → reopen / downstream assertion | Negative branch | Artifacts / automated evidence | Human | Status |
|---|---|---|---|---|---|---|---|
| F01 | A; unauthenticated; today | Cold welcome → select each sign-up/sign-in CTA → email-auth form; submit valid route → promised next state; Back → welcome. | Auth/account state survives relaunch; active owner is A before portal mutation. | Invalid email/password, failed callback/network, password recovery, and cancel each show recoverable copy and intended return. | `F01/*`; new `testAuthenticationRoutesAndErrors`; current Smoke: none. | H1 | Pending |
| F01a | A; unauthenticated / subscription-required; today | Mandatory paywall and legal-consent views → Decline, Review, Close, Sign out. | No account/plan mutation on decline; relaunch returns to intentional entry state. | No control may be a no-op or trap; Review must open the promised content. | `F01a/*`; new auth/paywall UI test; Smoke: none. | H1 | Pending |
| F02 | A, B, C; each new owner; today | Welcome → consent → all required baseline/goal answers → starting map → consent finish → intended builder/portal state. Assert Next is disabled until each required answer exists. | Commit profile/evidence under active owner; relaunch and reopen onboarding/builder shows committed selections without fabricated facts. | Decline legal consent exits intentionally; malformed body/date input exposes field-specific recovery. | `F02/*`; extend first-run/induction smoke tests; Smoke: `testFirstRunDistills…`, `testInductionRequires…` (one fixture, partial). | H1 | Pending |
| F02a | A, B, C; active owner; today | Inject failure after every onboarding persistence boundary → retry after dismissal/relaunch. | Exactly one coherent profile + settings + evidence + plan commit; canonical goal reads on native and web boundary; bespoke data remains protected. | Failed write retains full entered payload, never defaults height/weight/sex/date/activity, and never reports false success. | `F02a/*`; new failure-injection UI/integration tests; Smoke: none. | H1 | Pending |
| F03 | A/B/C; active owner; today | Generate fat-loss, recomp, maintenance, lean-bulk variants → plan summary/briefing → portal. | After terminate/relaunch + sync refresh, canonical goal, phase, kcal, P/C/F, duration, sessions, weekdays, owner, and revision match committed fixture. | Rebuild/cancel returns intentionally and does not overwrite protected bespoke plan. | `F03/*`; new plan-variant UI tests; Smoke: induction installs one strength fixture only. | H1 | Pending |
| F04 | A/B/C/D; active owner; today | Render each plan target and independently calculate BMR/TDEE/presets → target explanation. | D displays source/provenance and only uses measured BMR when valid/verified by policy; zero-energy activity add/remove does not change mode/target. | Under-19/unsupported scope fails closed; infeasible macro energy shows review state, never an apparently valid prescription. | `F04/*`; parity/invariant tests plus UI target assertions; Smoke: none. | H— | Pending |
| F05 | A and Bespoke; active owner; today | Portal → Avatar → Nutrition → Fitness Plan → Custom Workouts → Orbit; Simple, Transition, Main selections → each promised screen; Back/Close returns to originating level. | No mutation; relaunch retains selected valid mode only. | Locked destinations explain policy and preserve origin; no dead-end. | `F05/*`; extend `testFivePortalNavigation…`; Smoke: portal navigation/hierarchy partial. | H2 | Pending |
| F06 | A; owner A; today and yesterday | Simple → morning check/weight, food, water add/remove/custom goal, activity, Dayline, full schedule. Repeat on yesterday. | Reopen selected date after relaunch/refresh: only selected owner/date totals, Dayline, schedule, and allowed downstream summaries change. | Invalid water/weight and empty keyboard leave no mutation; undo/delete is clear and idempotent. | `F06/*`; new date-isolation tests; Smoke: morning weight, hydration layout, Simple widget, Dayline fixture partial. | H2 | Pending |
| F07 | A then A→B; today | Nutrition → Food Memory: exact, misspelled, joined word, branded, natural food → details (vitamins/minerals) → serving → log → edit → remove all → explicit empty-meal save → reopen editable. | Reopen meal after relaunch; selected-date owner record/totals/food-water update exactly once. | No-result, failed provider, and offline state are honest; delayed A private search must never render for B. | `F07/*`; extend food/meal UI tests; Smoke: strawberry amount/detail, composer, barcode partial. | H2 | Pending |
| F07a | A→B→A; private food owned by A; today | Start A private-food query → delay public result → switch to B before success, offline error, and cancellation completions. | B sees no A local result/cache/error; return to A can recover only A search state. | Validate owner + account generation after every await. | `F07a/*`; new delayed-search UI/integration test; Smoke: none. | H— | Pending |
| F08 | A; owner A; today | Run versioned corpus: fruit, vegetable, leaf, legume, grain, nut, seed, egg, dairy, meat, fish; capture canonical/alias result and rank. | No durable mutation unless explicitly logged; record provider/source/version. | A true gap is labeled no-result with guidance, never silently counted as alias. | `F08/*`; corpus fixture with expected ID/acceptable alias/max rank; Smoke: none. | H— | Pending |
| F09 | A; owner A; fixtures with 0/1/7/30 observed days | Nutrition intelligence Day → 7 days → Month → coverage/details/water-from-food explanation. | Refresh preserves counts/period and does not duplicate food water. | Sparse evidence states coverage/uncertainty; no diagnosis or deficiency claim. | `F09/*`; extend nutrient-pattern tests; Smoke: month board/detail partial. | H— | Pending |
| F10 | A; owner A; chosen weekday/date | Training → canonical search → configure facts → reorder → save A → explicit reopen/edit → schedule/start/finish → remove; create fresh B workout. | Relaunch: A edits preserve stable identity; B gets fresh ID/rows; remove A leaves B and unrelated workouts intact. | Restricted policy disables before authoring with explanation; no false save/dismiss; replacement requires explicit confirmation. | `F10/*`; new lifecycle test; Smoke: library/search/select only. | H3 | Pending |
| F11 | A; owner A; today, past, future, month boundary | Calendar previous/next month → empty, prescribed, deload, session-mode, briefing, rebuild → day sheet/player. | Selected date governs rows, receipt/activity/wearable association; reopen each date after relaunch. | Historical/tz-boundary/off-schedule completion cannot write today; future empty state is honest. | `F11/*`; extend calendar tests; Smoke: today + one empty day partial. | H3 | Pending |
| F12 | A; owner A; authored today | Start live player → warm-up → pause/resume → skip → record actual facts → rest → review → finish → receipt → Done → reopen receipt. | Receipt contains only entered/skipped facts; no invented reps/sets or duplicate activity/Avatar evidence; reload preserves receipt. | Cancel/back retains or discards draft as labeled and returns intentionally. | `F12/*`; extend player/receipt tests; Smoke: player phases + receipt partial. | H3 | Pending |
| F13 | A; owner A; same-day wearable fixtures at 4:59/5:00/5:01 | Pause player → Already finished → decline/resume → choose same-day wearable candidate → merged receipt. | One linked receipt/source identity and one daily/Avatar energy contribution; candidate order and five-minute eligibility deterministic. | No candidate / cancel restores warm-up without completion; no calorie duplication. | `F13/*`; new wearable-boundary tests; Smoke: no-wearable cancel/complete partial. | H— | Pending |
| F14 | A; owner A; today, historical, future | History → expand native/external → edit/delete native → hide external → date/range controls → export PNG. | Delete reconciles only receipt-derived activity; reopen dates/ranges after relaunch; exported PNG is complete and readable. | Future/no-data/date-isolation state is intentional; external hide never deletes Apple Health original. | `F14/*`; extend receipt/insights tests; Smoke: tray/open/export partial. | H— | Pending |
| F15 | A/D/Bespoke, then A→B(profileless)→A; selected today | Mutate exactly one source at a time: nutrition, hydration, workout, recovery, sleep/readiness, calibration → Avatar. | For each fixture assert changed domain(s), unchanged unsupported domains, source provenance/confidence, generation/signature, deterministic refresh. On switch B publishes honest empty state; late A completion cannot repopulate B. | Unsupported evidence does not invent a score/precision; delete/edit source retracts only matching downstream effect. | `F15/*`; new propagation/account-race tests; Smoke: Avatar presentation only. | H4 | Pending |
| F16 | D and Bespoke; active owner; today | Avatar calibration → each section → body fat/measured BMR/source → save → Close → reopen. | Evidence/source persists after relaunch; only policy-supported visible stats change; Bespoke protected plan remains. | Invalid BMR preserves prior valid value and explains failure; report BMR is not presented as authoritative until verified. | `F16/*`; extend calibration tests; Smoke: draft resume + DEXA save partial. | H4 | Pending |
| F17 | A and Bespoke; owner/date-selected | Each Avatar `Plan it` → guided/external → accept/schedule/customize → calendar → reopen plan. | Calendar creates intended dated rows; replacement only changes intended future rows; Avatar contribution stays bounded/provenanced. | External-video fallback does not invent completion; cancel returns to Avatar; missing custom edit path is a known static blocker. | `F17/*`; new recovery lifecycle tests; Smoke: planner entry only. | H4 | Pending |
| F18 | A→B→A; owner/date-selected | Avatar visual progress → consent/guides → camera capture and library import → compare → remove. | Relaunch: A asset/options/thumbnail render; B sees no A metadata/path/thumbnail; return A can reopen/delete. | Camera/photo deny gives retry/settings route without false capture; removal scope is explicit. | `F18/*`; new permission/ownership tests; Smoke: visual-progress ordering only. | H4 | Pending |
| F19 | A→B→A; owner/date-selected | Orbit home/library/mission → configure → cancel **and** successful run → debrief/history. | Completed run contributes distance/energy once across activity/nutrition/Avatar after refresh; interrupted A draft is visible only to A after return. | Location denial has retry/settings route; B cannot view/continue/cancel/save A draft; home recent-run row must navigate. | `F19/*`; new Orbit lifecycle/account tests; Smoke: home destination only. | H4 | Pending |
| F20 | A, B, long-name A; A→B→A | Settings → language, units, notifications, Health permissions, data/report, paywall, logout/account switch, destructive controls. | Preferences/identity are owner-scoped and persist after relaunch; A→B→A clears/reloads Avatar, food, hydration, Orbit, entitlements, and pending state correctly. | Each destructive action has target/confirmation/cancel/relaunch result; paywall/logout/consent has non-trapping return. | `F20/*`; new settings/account-boundary UI tests; Smoke: Constantine name layout only. | H— | Pending |
| F20a | A→B(profileless)→A; A work in flight | Start upload/invitation/progress mutation and Orbit/search work as A → switch B before completion → return A. | Late success/failure cannot change B UI/persistence/remote path; A state recovers only under A owner/generation. | B gets honest empty/active-owner state, never A avatar/private food/draft/notification. | `F20a/*`; account-generation tests with UI proof; Smoke: none. | H— | Pending |
| F21 | Coach + Sponsored + ordinary A + Bespoke; selected date | Coach client list/profile → author/publish plan/workout → Sponsored client refreshes and sees exact version/date. | Persisted client-visible version is owner/date scoped; ordinary/bespoke policies remain separate. | Sponsored/coach-managed creation controls are disabled before submit with lock explanation; no false save or draft orphan. | `F21/*`; new coach/client round-trip UI tests; Smoke: none. | H— | Pending |
| F22 | A; owner A; today | Offline local mutation → relaunch offline → inspect queued/quarantined work → restore network → retry → terminal status. | One final local/server record with original owner/date; no loss/duplicate; status remains visible in Simple and Advanced. | Distinguish transient retry, auth recovery, permanent quarantine, and cancel; never claim Synced before completion. | `F22/*`; extend sync test; Smoke: failed-sync disclosure partial. | H— | Pending |
| F22a | A; Health permission denied; today | Request/read/write Health → deny → settings/retry route. | Existing account data is preserved; no unauthorized overwrite; successful later grant reconciles once. | Denial is specific and recoverable, not an empty success. | `F22a/*`; new permission test; Smoke: none. | H— | Pending |
| F22b | A; camera/photo permission denied; today | Progress capture/import → deny → retry/settings. | No asset/metadata mutation; later grant yields one A-owned asset. | Clear purpose/recovery copy. | `F22b/*`; paired F18 test; Smoke: none. | H— | Pending |
| F22c | A; location permission denied; today | Orbit run start → deny → retry/settings/cancel. | No draft/route/energy created until authorized; later start has one owner/date-scoped draft. | No trapped run screen or misleading active run. | `F22c/*`; paired F19 test; Smoke: none. | H— | Pending |
| F23 | A and long-name A; VoiceOver; largest accessibility Dynamic Type; smallest supported phone | Visit portal, nutrition/food amount, training/player, Avatar/progress, Orbit, settings in light/dark, increased contrast, Reduce Motion. | No durable mutation; every primary control/value remains labeled, ordered, selected where applicable, reachable/hittable, and in safe viewport. | Record focus order/traits and no clipped critical value; reduced motion does not hide state/route. | `F23/*`; new configuration UI tests + screenshots; Smoke: individual geometry/labels only. | H— | Pending |
| F23a | A; VoiceOver enabled | Execute H1–H4 with VoiceOver → record label, hint, trait, focus order, modal focus and announcement. | No durable mutation beyond each parent flow's own fact. | No unlabeled icon, duplicate focus, inaccessible drag-only action, or focus escape. | `F23a/*`; accessibility audit attachment; Smoke: none. | H— | Pending |
| F23b | A; accessibility Dynamic Type / smallest phone | Run critical values/actions across light/dark/increased contrast. | No durable mutation. | Primary action has at least 44×44 target where applicable and no clipping/overlap. | `F23b/*`; device/config screenshots; Smoke: compact food/hydration checks only. | H— | Pending |
| F24 | Empty; no active owner; no seed/preview; today | Fresh install launch with **no** `-apex-preview`, `-apex-ui-test-first-run`, or fixture argument → visit every available top-level route. | No fixture identity/data leaks after relaunch; each allowed empty state gives one clear next action. | Auth/onboarding-required paths state why and offer return/exit, not blank space or trap. | `F24/*`; new true-unseeded UI tour; current first-run Smoke is explicitly not evidence. | H1 | Pending |

## Layer 1 — static navigation findings (separate from runtime evidence)

These are source-review findings, not simulator observations. They block or constrain the listed runtime loops until repaired; no flow above is marked passed because of a static finding.

1. **P1 · NO-EDIT-PATH — saved custom workouts cannot reopen in an editable builder.** `TrainingProgramView` routes saved days to read/start-only `WorkoutDayView`; the builder only creates blank workouts. Missing arrow: saved custom day → editable builder → explicit Save changes/Delete. Affects F10 and F17.
2. **P1 · ORPHANS-ENTITY — coach-restricted custom-workout creation discards a draft and opens a lock after rejected save.** The authoring affordance is not capability-gated; save returns without writing but builder reports success/dismisses. Missing arrow: capability check before draft, or confirmed persisted save → Custom Workouts. Affects F10/F21.
3. **P1 · ORPHANS-ENTITY — “Build a workout” silently replaces a saved same-weekday workout.** Save reuses the weekday day ID and deletes its prior exercise rows without an applicable replacement warning. Missing arrow: new fresh day/date, or explicit replace confirmation → intentional update. Affects F10.
4. **P2 · DEAD-END — Orbit Home recent-run rows display a chevron but do not navigate.** Library rows navigate to historical debrief; Home rows are inert. Missing arrow: Orbit Home recent run → historical debrief. Affects F19 and H4.
5. **P2 · NESTED-NAV — historical Orbit debrief is pushed into its own `NavigationStack`.** A Library `NavigationLink` pushes a wrapper whose `RunDebriefView` owns another stack; this can produce a second bar and disrupt parent Back. Affects F19's history/reopen return assertion.

## Current automated evidence inventory

The `APEXSmokeUITests` source currently contains 30 methods. The final Task 1 rerun completed on `APEX Lane · iPhone 17 Pro` (iOS 26.5) with **30 passed, 0 failed, 0 skipped**. The test action reported 1,165.655 seconds and the result summary reported `Passed`. Evidence is retained at:

- `build/apex-client-audit/APEXUI-baseline.xcresult`
- `build/apex-client-audit/APEXUI-portal-rerun.xcresult`
- `build/apex-client-audit/APEXUI-task1-final.xcresult`

It is **partial evidence only**. It exercises selected preview/fixture paths: required onboarding answers/starting map/return to builder; portal hierarchy; nutrition goal/detail, meal amount, composer, barcode, nutrient patterns and Dayline; morning check/hydration layout; calendar states; custom-workout catalogue selection; live player/receipt basics; Avatar/calibration/recovery entry; settings identity layout; and quarantined-sync disclosure. It does not drive real authentication, A→B→A switching, coach/client publication, location-backed Orbit lifecycle, system permission denial, accessibility configuration, or a no-seed fresh-install launch.

The longest existing smoke flow spent about 251 seconds repeatedly trying to make an already-present but non-hittable element tappable. That is a harness-efficiency finding for later test maintenance, not evidence that the product flow passed or failed. The result bundle likewise identifies one outlier-duration run. No matrix row is promoted from `Pending` on this basis.

The source/unit suite may be cited as supporting computation, owner-scoping, sync, food-privacy, calendar, or hydration evidence, but never as user-flow or discoverability proof without the corresponding runtime case above.

## Layer 3 — human discoverability scripts

Run these after the associated automated case reaches its expected state. Rate every numbered action `1` (not discoverable) to `5` (immediately obvious), mark whether the return destination matched expectation, and record a hesitation note. A script with no rating/note remains pending.

### H1 — first account: consent, onboarding, and return

1. From Welcome, choose the correct path for a new account. Was sign-up versus sign-in clear? `1–5`
2. Complete consent and required baseline/goal answers. Did you understand what was required and why Next was unavailable? `1–5`
3. Review the starting map and finish/skip optional portions. Did the result and next action make sense? `1–5`
4. Return to an incomplete plan/account and find the route back to the builder. Did you land where expected? `Y/N`

Hesitation note: ____________________

### H2 — daily nutrition: find, log, edit, and remove food

1. From the daily screen, find how to add food to the intended meal. `1–5`
2. Search, open nutrition detail, set a serving, and log it. Were amount and nutrient-detail actions understandable? `1–5`
3. Reopen the meal, edit and remove food, then save an empty meal. Was the deletion meaning and confirmation clear? `1–5`
4. Return to the day. Did totals and date feel like the expected destination? `Y/N`

Hesitation note: ____________________

### H3 — training: create, edit, schedule, and start a custom workout

1. Find the action to build a workout and select/configure/reorder exercises. `1–5`
2. Save it, then find how to reopen it for editing. `1–5`
3. Schedule/start it and finish with actual set facts. Did the receipt and Done route match expectation? `Y/N`
4. If authoring is locked, did you understand why before losing work? `1–5` or `N/A`

Hesitation note: ____________________

### H4 — Avatar, recovery, visual progress, and Orbit

1. On Avatar, find visual progress and understand capture/import/privacy choices. `1–5`
2. Find `Plan it`, choose recovery, and understand whether it schedules a session or opens external guidance. `1–5`
3. Find Orbit history and a mission/run action. Did the chevron/history affordance do what you expected? `Y/N`
4. Return from recovery/progress/debrief. Was the destination expected? `Y/N`

Hesitation note: ____________________

## Evidence discipline and disposition

- Capture each important transition in `.planning/walkthrough/<ID>/`; keep result bundles under `build/apex-client-audit/`.
- Keep **static** navigation/code observations separate from **runtime** screenshots/assertions and separate again from **human** discoverability ratings.
- For every persisted entity, prove Create → Read → explicit Update/reopen → Delete/retention as applicable. `Done`, `Back`, `Close`, and cancellation must each assert their destination.
- A row may become `Passed`, `Repaired`, `Deferred` (with owner-facing roadmap reference), or `Blocked` (named external dependency) only after both lanes have evidence. Until then it remains `Pending`.

## Existing cross-client finding

- **P0 · static/shared-calculator reproduction:** native onboarding can persist the valid default goal `general`, while shared web `goalPresetsForPlan` has no `general` branch and returns `undefined`; web Home/Nutrition consumers then call `.find` on the missing preset array. This is a persisted-schema failure for a new general-fitness subscriber, not an iOS-screen crash. F02a/F03/F04 must prove canonical writer/reader normalization and legacy tolerance before closure.
