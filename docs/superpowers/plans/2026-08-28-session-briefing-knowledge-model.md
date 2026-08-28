# Session Briefing Knowledge Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace day-type-only Session Briefing prose with deterministic, movement-specific, evidence-led education that adapts to session position, training history, and persisted caution signals.

**Architecture:** Add a pure `SessionBriefing` knowledge extension that classifies canonical movement metadata and produces localisation lookup keys. `MuscleMapCard` composes dashboard context with the selected session and passes the resulting knowledge to the existing sheet, which renders bounded lesson and caution sections beside the unchanged muscle map.

**Tech Stack:** Swift 6, SwiftUI, XCTest, `.strings` runtime localisation, Node/Vitest repository contracts, Xcode command-line build and test tools.

**Spec:** `docs/superpowers/specs/2026-08-28-session-briefing-knowledge-model-design.md`

## Global Constraints

- Preserve `SessionBriefing.briefing(dayType:exercises:)` and the existing rest-day parity contract.
- Use actual `MovementTiming` and `ExerciseLogging` metadata; only the documented recovery/day-type fallback may infer a family.
- New copy must be authored in all nine offered languages in the same commit.
- Do not add short-form keys because the new sections are vertically scrolling and not width constrained.
- The feature is educational, deterministic, offline, and non-diagnostic.
- Do not claim that acute stretching lengthens muscle, foam rolling breaks fascia, lactate causes next-day soreness, or passive stretching alone prevents injury.
- Complete one atomic roadmap item: tests, implementation, ledger, repair note, commit, both pushes, signed device build, and successful Pages deployment.

---

### Task 1: Lock the knowledge contract with failing tests

**Files:**
- Create: `ios/APEXNative/APEXTests/SessionBriefingKnowledgeTests.swift`
- Modify: `ios/APEXNative/APEXNative.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `MovementTiming.movement(named:)`, `ExerciseLogging.descriptor(for:)`, `DashboardData`, `StrengthProgress.checkins(from:)`.
- Produces: executable expectations for `SessionBriefing.MovementFamily`, `KnowledgeContext`, `Knowledge`, `knowledgeContext(dayType:exerciseNames:date:data:)`, and `knowledge(context:)`.

- [ ] **Step 1: Add a focused test target file**

Create `SessionBriefingKnowledgeTests` with tests that call these exact intended signatures:

```swift
let context = SessionBriefing.KnowledgeContext(
    position: .before,
    movementFamilies: [.mobility],
    movementNames: ["Couch Stretch"],
    painReported: false,
    elevatedJointCheckIn: false,
    hypermobilityReported: false,
    experience: .littleHistory
)
let knowledge = SessionBriefing.knowledge(context: context)
```

Cover:

- `Romanian Deadlift` and `Pull-Up` → `.strengthBodyweight`;
- `Couch Stretch` → `.mobility`;
- `Downward-Facing Dog` → `.yoga` from its canonical `yoga_pose` metadata;
- `Plank`, `Farmer's Carry`, `Stationary Bike`, and `Burpee` → isometric, carry, cardio, and interval respectively;
- rest with no movements → recovery;
- mixed movements preserve first occurrence and remove duplicates;
- a completed same-date session → `.after`, while a different date remains `.before`;
- completed-session counts 0, 6, and 24 choose the three experience bands;
- non-empty induction `pain_areas` sets `painReported`;
- latest joint score at 4 sets `elevatedJointCheckIn`, while 3 does not;
- both structured and scalar hypermobility addon shapes are accepted;
- mobility emits methods, non-muscular-boundary, and neural-warning keys;
- recovery contains the myth-correcting recovery key;
- knowledge caps movement lessons at three;
- unknown movement names do not receive a guessed movement lesson.

- [ ] **Step 2: Register the file in the APEXNativeTests target**

Add one `PBXFileReference`, one `PBXBuildFile`, the file to the `APEXTests` group, and the build file to the test target's `PBXSourcesBuildPhase`, following the identifiers and ordering used by adjacent test files.

- [ ] **Step 3: Run the focused tests and preserve the red result**

Run:

```bash
xcodebuildmcp simulator test \
  --project-path ios/APEXNative/APEXNative.xcodeproj \
  --scheme APEX \
  --simulator-name 'iPhone 17 Pro' \
  --use-latest-os \
  --extra-args '-only-testing:APEXTests/SessionBriefingKnowledgeTests' \
  --prefer-xcodebuild
```

Expected: compilation fails because the new `SessionBriefing` knowledge types do not exist. Keep the failure output as the TDD red evidence.

### Task 2: Implement movement classification and adaptive context

**Files:**
- Create: `ios/APEXNative/APEX/Core/Engine/SessionBriefingKnowledge.swift`
- Modify: `ios/APEXNative/APEXNative.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: the interfaces named in Task 1.
- Produces:

```swift
extension SessionBriefing {
    enum MovementFamily: String, CaseIterable {
        case strengthBodyweight, mobility, yoga, isometric
        case carry, cardio, interval, recovery
    }
    enum SessionPosition { case before, after }
    enum ExperienceBand { case littleHistory, developingHistory, establishedHistory }
    struct KnowledgeContext: Equatable { /* spec fields */ }
    struct Knowledge: Equatable {
        let lessonKeys: [String]
        let contextNoteKey: String?
        let cautionKeys: [String]
    }
    static func knowledgeContext(
        dayType: String,
        exerciseNames: [String],
        date: String?,
        data: DashboardData
    ) -> KnowledgeContext
    static func knowledgeContext(
        dayType: String,
        exerciseNames: [String],
        date: String?,
        completedSessionDates: [String],
        completedSessionCount: Int,
        addons: [String: JSONValue]?
    ) -> KnowledgeContext
    static func knowledge(context: KnowledgeContext) -> Knowledge
}
```

- [ ] **Step 1: Add the typed values and catalogue classifier**

Resolve each exercise with `MovementTiming.movement(named:)`. Check `movement.entityType == "yoga_pose"` first. Otherwise switch on `ExerciseLogging.descriptor(for: movement).kind`, folding strength/bodyweight and interval/circuit exactly as specified. Keep only first occurrences.

- [ ] **Step 2: Add compatibility fallback and history calculation**

Use recovery only when the day type is rest/recovery and no family resolved. For other unresolved cached plans, recognise only existing day-type tokens (`mobility`, `yoga`, `cardio`, `interval`, `conditioning`, `rest`, `recovery`); otherwise leave the families empty. Derive position from a completed same-date session and derive history from completed session counts at 6 and 24.

- [ ] **Step 3: Extract persisted caution signals without inventing them**

Read `training_induction.pain_areas`, latest `joint_checkins`, and the two hypermobility addon shapes from the design. Treat malformed or missing values as absent. Do not infer hypermobility from range of motion or exercise selection.

- [ ] **Step 4: Produce bounded lesson, note, and caution keys**

Use these exact English lookup keys:

```text
Strength and bodyweight work improve when the same positions stay repeatable. Load, leverage, range and tempo can all progress the exercise; a grinding rep is not required for every useful set.
Mobility work can change what range feels available now, often through tolerance and stiffness. Range that lasts also needs repeated exposure and strength near the edge you can control.
Static holds, dynamic repetitions, PNF and loaded end-range work are different tools. For a prescribed static stretch, roughly 30–60 seconds is a useful working range; dynamic work fits the warm-up better.
A pinch or hard joint block is not a cue to pull harder. Bone shape, the joint and its capsule can limit a position as well as muscle tolerance.
Yoga here is practice, not a contest for the deepest pose. Use steady breathing and a position you can control.
An isometric builds strength most strongly around the angle and task you hold. End the hold when the position or normal breathing gives way.
A carry links grip, trunk control and gait under load. Reduce the load if you have to lean or shorten your steps to keep moving.
Steady cardio is its own aerobic session, not a failed interval workout. Keep the prescribed effort sustainable instead of turning every session into a time trial.
Recovery makes hard intervals repeatable. Start at a pace that lets the later work bouts still look like the first ones.
Easy recovery work may change short-term range or soreness, but it does not break fascia, flush away next-day soreness or erase training stress. Finish fresher than you started.
With only a small amount of logged history, make repeatable technique the baseline today. Leave room to learn what normal effort feels like.
Your recent sessions are the useful comparison. Match their clean repetitions or steady pace before you add difficulty.
You have enough history to compare this session with your own pattern. Use that pattern, not somebody else’s standard, to judge today’s work.
This session is already complete. Use the briefing to understand what you trained; it is not a prompt to add bonus work.
You reported pain or irritation during setup. Pain is not a mobility target: reduce or stop a movement that reproduces it, and get qualified help if it persists or worsens.
Your latest joint check-in was elevated. Keep the affected area away from sharp or worsening pain and adjust the session instead of testing the symptom.
More range is not the goal when you already have it. Stay short of a passive end position and train control there.
A broad muscle pull can be part of a stretch; tingling, burning, numbness or an electric line is not a cue to push farther. Back off and seek assessment if it persists.
Pregnancy, glaucoma, fragile bones and some other conditions can require yoga modifications, especially for heat, long supine holds, inversions or forceful breath work. Use qualified guidance when any of these applies.
```

Cap family lessons at three, append mobility boundary material only for a mobility family, de-duplicate cautions, and order them hypermobility → pain → joint → movement-specific boundary.

- [ ] **Step 5: Register the source and run the focused tests**

Add the source reference and build phase entry to the app target. Run the Task 1 command. Expected: all focused tests pass.

### Task 3: Render knowledge in the existing briefing flow

**Files:**
- Modify: `ios/APEXNative/APEX/Features/Training/MuscleMapCard.swift`
- Modify: `ios/APEXNative/APEX/Features/Training/SessionBriefingSheet.swift`
- Modify: `ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift`
- Modify: `ios/APEXNative/APEX/Features/Training/WorkoutDaySheet.swift`

**Interfaces:**
- Consumes: `SessionBriefing.knowledgeContext(...)` and `SessionBriefing.knowledge(context:)`.
- Produces: `MuscleMapCard(dayType:exerciseNames:sessionDate:)` and `SessionBriefingSheet(briefing:knowledge:)`.

- [ ] **Step 1: Compose context in `MuscleMapCard`**

Add `@Environment(AppSession.self)`, add `sessionDate: String? = nil`, and build the knowledge value only when the sheet opens:

```swift
let context = SessionBriefing.knowledgeContext(
    dayType: dayType,
    exerciseNames: exerciseNames,
    date: sessionDate,
    data: session.data
)
SessionBriefingSheet(
    briefing: SessionBriefing.briefing(dayType: dayType, exercises: exerciseNames),
    knowledge: SessionBriefing.knowledge(context: context)
)
```

- [ ] **Step 2: Pass the selected ISO day at all three call sites**

Use the program-day/calendar date already present in `TrainingProgramView` and `WorkoutDaySheet`. Do not derive the selected day from `Date.now` inside the card.

- [ ] **Step 3: Extend the sheet without replacing the muscle map**

Add a custom initializer whose `knowledge` defaults to an empty value for compatibility. Below the existing muscle explanation, render:

- heading `"What this session trains"` and each `lessonKey` in its own readable block;
- heading `"For this session"` and `contextNoteKey` when present;
- heading `"Worth knowing"` and each caution when present;
- the existing focus section last.

Resolve every key with `language.text`, use semantic text styles, and preserve vertical scrolling, Dynamic Type, and VoiceOver reading order.

- [ ] **Step 4: Build the app target**

Run an unsigned simulator build. Expected: `BUILD SUCCEEDED`, with no Swift concurrency or unreachable-code warnings introduced by this change.

### Task 4: Author and validate all nine runtime-localised voices

**Files:**
- Modify: `ios/APEXNative/APEX/Resources/de.lproj/Localizable.strings`
- Modify: `ios/APEXNative/APEX/Resources/de-CH.lproj/Localizable.strings`
- Modify: `ios/APEXNative/APEX/Resources/es.lproj/Localizable.strings`
- Modify: `ios/APEXNative/APEX/Resources/it.lproj/Localizable.strings`
- Modify: `ios/APEXNative/APEX/Resources/pt.lproj/Localizable.strings`
- Modify: `ios/APEXNative/APEX/Resources/ro.lproj/Localizable.strings`
- Modify: `ios/APEXNative/APEX/Resources/th.lproj/Localizable.strings`
- Modify: `ios/APEXNative/APEX/Resources/ja.lproj/Localizable.strings`
- Create: `tests/session-briefing-copy-contract.test.ts`

**Interfaces:**
- Consumes: the 19 exact lookup keys in Task 2 plus headings `What this session trains`, `For this session`, and `Worth knowing`.
- Produces: English source values in Swift, translated locale values for all 22 keys in the eight non-English tables, and a focused source/copy contract.

- [ ] **Step 1: Add the English source values**

Keep each lookup key as its own English value in `SessionBriefingKnowledge.swift` or the sheet headings. English is the source language and has no `Localizable.strings` table in this project.

- [ ] **Step 2: Author each locale from meaning**

Write all 22 values independently in the established local coaching register. Do not preserve English clause order when the target language would phrase the coaching differently. Keep `30–60` and the four warning sensations semantically intact; they are safety content.

- [ ] **Step 3: Add a structural and calibration contract**

The Node test file must parse the eight translated tables and assert:

- every source key exists exactly once in every locale;
- no locale value equals its English value except legitimate technical tokens such as `PNF`;
- German/Swiss German do not use the Romanian mechanical phrase family;
- Romanian uses `lucrează`/natural equivalents and rejects `funcționează` for the muscle-work line;
- no locale introduces the prohibited claims `break fascia`, `lactate causes soreness`, or `stretching prevents injury` as affirmative statements;
- no value is blank and every file parses.

Name the test so its output says structural coverage and calibration, never prose-quality certification.

- [ ] **Step 4: Validate property lists and localisation contracts**

Run `plutil -lint` for each edited `.strings` file, the focused `node:test` contract, the existing runtime-localisation source contracts, and the native localisation test suite. Expected: all pass.

### Task 5: Add the movement-science ledger and close the roadmap item

**Files:**
- Create: `docs/training/MOVEMENT_SCIENCE_LEDGER.md`
- Modify: `docs/REPAIR-NOTES.md`

**Interfaces:**
- Consumes: every scientific statement shipped by Tasks 2–4.
- Produces: an auditable evidence entry for each statement and an append-only completion record.

- [ ] **Step 1: Write the ledger in the Orbit evidence format**

Create sections for stretching mechanisms/dose, resistance and end-range strength, proximity to failure, isometric specificity, interval/cardio adaptation, foam rolling/recovery myths, neural/joint boundaries, injury prevention, and yoga contraindication boundaries. For each include APEX application, population, linked primary source or systematic review, confidence, and limitation. Use the PubMed/ACOG sources captured in the design session and date the review `2026-08-28`.

- [ ] **Step 2: Run focused and full verification**

Run, in order:

1. `SessionBriefingKnowledgeTests`;
2. focused native localisation tests;
3. full native unit suite;
4. all repository/web tests;
5. production web build;
6. `plutil -lint` on all edited localisation files;
7. `git diff --check`.

Record exact pass counts and build results in `docs/REPAIR-NOTES.md`. Do not turn structural localisation counts into a prose-quality claim.

- [ ] **Step 3: Perform independent review and visual/device verification**

Review the final diff for scientific overclaiming, context leakage, accessibility, and localisation omissions. Build the next signed Release number, verify its deep code signature, install it on the connected iPhone, launch it when the device is unlocked, and also launch the source-matching app in Simulator so the sheet can be inspected even if physical launch is temporarily locked.

- [ ] **Step 4: Commit and publish one atomic roadmap item**

Stage only the 1.10 files and commit with:

```text
feat: teach movement-specific session briefings
```

Push the commit to `origin/codex/main-critical-repair` and `origin/main`. Monitor the resulting GitHub Pages workflow to a successful conclusion and confirm the live URL returns HTTP 200.

- [ ] **Step 5: Re-read the roadmap before selecting the next numbered task**

Only after deployment succeeds, re-read `docs/ROADMAP.md` section 0 and select the next unclosed item in the mandated phase order.
