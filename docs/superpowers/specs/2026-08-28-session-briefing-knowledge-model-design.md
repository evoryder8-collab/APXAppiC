# Session Briefing Knowledge Model Design

**Roadmap item:** 1.10 — Session briefings that teach something true
**Date:** 2026-08-28
**Status:** Approved for implementation by the owner's standing instruction to continue the roadmap autonomously

## Problem

The current briefing selects one English paragraph from a day-type switch. It can name the muscles involved, but it does not explain the actual movement methods in the prescription, distinguish what changes before versus after a session, or respond to the user's training history and caution signals. The mobility branch also compresses several different tools into generic flexibility language.

The replacement must teach one bounded, sourced idea at the moment it is useful. It must not diagnose, prescribe treatment, imply that discomfort is always muscular, or repeat common recovery and stretching myths.

## Goals

- Derive briefing content from the movements prescribed for the selected session.
- Model these families explicitly: strength/bodyweight, mobility/stretching, yoga, isometric, carry, cardio, interval, and recovery.
- Change the coaching frame for a planned session versus a completed session.
- Respond conservatively to reported pain, an elevated joint check-in, and an optional hypermobility marker.
- Adjust the coaching emphasis when APEX has little, developing, or established workout history.
- Show movement-science lessons and cautions in the existing Session Briefing sheet without hiding the muscle map.
- Author every new line independently in all nine offered languages: English, German, Swiss German, Spanish, Italian, Portuguese, Romanian, Thai, and Japanese.
- Record each scientific claim, confidence level, population boundary, and limitation in a movement-science ledger.

## Non-goals

- This item does not add a hypermobility questionnaire; roadmap item 7.1 owns that input surface. It consumes an optional persisted marker when present and exposes a typed context input for that future surface.
- It does not diagnose nerve, joint, muscle, pregnancy, eye, or bone conditions.
- It does not rewrite exercise prescriptions or replace a clinician or qualified coach.
- It does not reopen the already-completed Romanian corpus repair or mechanically rewrite simple labels.
- It does not add remote AI generation. The briefing remains deterministic and available offline.

## Chosen Architecture

Add a pure knowledge layer beside `SessionBriefing.swift`, leaving the existing muscle grouping and legacy `Briefing` value intact. The new layer builds a typed context from session data, classifies the actual exercise names through the canonical `MovementTiming` and `ExerciseLogging` catalogues, and returns a presentation containing the existing briefing plus ordered lessons, a contextual note, and zero or more cautions.

`MuscleMapCard` is the composition boundary. It already owns the exercise names and opens the sheet; it will additionally read `AppSession`, accept the selected date, build the context, and pass one complete presentation into `SessionBriefingSheet`. This keeps persistence knowledge out of the sheet and keeps the science engine independently testable.

## Data Model

The new API lives under `SessionBriefing`:

```swift
enum MovementFamily: String, CaseIterable {
    case strengthBodyweight, mobility, yoga, isometric
    case carry, cardio, interval, recovery
}

enum SessionPosition { case before, after }
enum ExperienceBand { case littleHistory, developingHistory, establishedHistory }

struct KnowledgeContext: Equatable {
    let position: SessionPosition
    let movementFamilies: [MovementFamily]
    let movementNames: [String]
    let painReported: Bool
    let elevatedJointCheckIn: Bool
    let hypermobilityReported: Bool
    let experience: ExperienceBand
}

struct Lesson: Identifiable, Equatable {
    let id: String
    let heading: String
    let body: String
}

struct Presentation {
    let briefing: Briefing
    let lessons: [Lesson]
    let contextNote: String?
    let cautions: [String]
}
```

All strings in `Lesson`, `contextNote`, and `cautions` are English lookup keys, not already-localised text. `SessionBriefingSheet` resolves them through `APEXLanguage.text` at render time, matching the existing runtime-localisation contract.

## Context Extraction

`knowledgeContext(dayType:exerciseNames:date:data:)` is deterministic:

1. Resolve each name with `MovementTiming.movement(named:)`.
2. Preserve yoga before consulting logging because yoga poses intentionally have no logging descriptor.
3. Map `ExerciseLogging.descriptor(for:).kind` as follows:
   - `.strength` and `.bodyweight` → `.strengthBodyweight`
   - `.mobility` → `.mobility`
   - `.isometric` → `.isometric`
   - `.carry` → `.carry`
   - `.cardio` → `.cardio`
   - `.interval` and `.circuit` → `.interval`
4. De-duplicate families while retaining the prescription's first-occurrence order. If no movement resolves, use `.recovery` for rest/recovery day types; otherwise retain a conservative day-type fallback solely so older cached plans are not blank.
5. Set `.after` only when a completed `WorkoutSession` has the selected date; all other cases are `.before`.
6. Read pain from `settings.addons["training_induction"].pain_areas` and treat a non-empty array as reported pain.
7. Read joint check-ins through `StrengthProgress.checkins(from:)`. The most recent check-in is elevated when any region is at least 4/10. This flag changes language; it is not a diagnosis or clearance decision.
8. Read optional hypermobility markers from `settings.addons["hypermobility_baseline"].reported` or the legacy-compatible scalar `settings.addons["hypermobility_reported"]`. Missing data means false, never an inference from exercise performance.
9. Count completed workout sessions: 0–5 is little history, 6–23 is developing history, and 24 or more is established history. These bands only tune how specific the comparison cue can be; they never label the user's ability.

## Movement Knowledge Models

Each family contributes at most one primary lesson so a mixed session remains readable. The first prescribed family is primary, followed by distinct secondary families. Recovery is used alone.

| Family | Truth taught | Coaching consequence |
| --- | --- | --- |
| Strength/bodyweight | Productive work does not require grinding every set to momentary failure; leverage, range, tempo, and external load are all forms of progression. | Preserve repeatable positions and stop when the prescribed reserve or technique limit is reached. |
| Mobility/stretching | Acute range often reflects stretch tolerance and stiffness changes; static, dynamic, PNF, and loaded end-range work are different tools. Persistent usable range also needs strength and repeated exposure. | Warm the pattern, use roughly 30–60 seconds for a prescribed static hold, and do not force a pinch, hard block, tingling, burning, numbness, or electric sensation. |
| Yoga | Yoga is skilled practice, not a contest for maximal range. Some poses and breath practices need genuine condition-specific modification. | Use controlled breath and stable positions; surface a non-diagnostic caution for pregnancy, glaucoma, fragile bones, and prescribed inversions or forceful breath-holds. |
| Isometric | Strength adaptation is strongest around the trained joint angle and task. | Own the intended angle and end the hold when position or breathing can no longer be maintained. |
| Carry | Carries integrate grip, trunk control, and gait under load. | Keep steps and torso organised; load is too high when the user leans or shortens the gait to survive it. |
| Cardio | Controlled continuous work is a distinct aerobic stimulus, not a failed interval session. | Hold the prescribed sustainable effort instead of turning every session into a time trial. |
| Interval | Recovery periods are part of the dose and permit repeatable hard work. | Choose an opening pace that keeps later bouts recognisably consistent. |
| Recovery | Easy movement or foam rolling can affect short-term range and perceived soreness, but does not break fascia, flush lactate, erase training stress, or guarantee injury prevention. | Finish fresher than the user started and do not convert recovery into another hard session. |

The mobility model also emits a separate boundary lesson: a joint can be limited by articular geometry, capsule, prior injury, or neural sensitivity as well as muscular stretch tolerance. The copy tells the user to back off from non-muscular warning sensations and seek assessment if they persist; it never tells them which tissue is responsible.

## Adaptive Ordering

The sheet displays content in this order:

1. Existing title, intent, and muscle map.
2. “What this session trains” with one lesson for each actual family, capped at three.
3. One position/history note:
   - before + little history: prioritise repeatable technique and a conservative baseline;
   - before + developing history: compare against recent repeatable work;
   - before + established history: use the user's own history, not a generic standard;
   - after: explain what was trained and discourage bonus work prompted by the briefing.
4. Cautions, ordered hypermobility → reported pain → elevated joint check-in → movement-specific neural/yoga boundary. Duplicate cautions are removed.
5. Existing practical focus text as a compact close.

## Localisation and Voice

- English lookup keys express meaning plainly and avoid slogans, puns, and parallel English aphorisms.
- Every language receives authored gym/coach copy from the intended meaning, not translated syntax.
- German and Swiss German may share a line only when it is genuinely idiomatic in both; Swiss orthography uses `ss`, not `ß`.
- Portuguese uses the repository's existing European Portuguese register.
- Thai and Japanese use natural coaching register rather than literal anatomical prose.
- Romanian follows the already-repaired native register (`mușchii lucrează`, not machine-language constructions).
- The sheet is vertically scrollable and not width constrained, so no `LocalizableShort.strings` additions are required.
- Tests assert key presence, format-token parity, and a focused set of prohibited mechanical phrases. They do not claim prose quality from key coverage.

## Evidence and Safety Contract

Create `docs/training/MOVEMENT_SCIENCE_LEDGER.md` using the Orbit ledger's pattern: claim, APEX application, intended population, primary evidence, confidence, and limitation. The ledger must cover every user-visible physiological statement and explicitly record these exclusions:

- acute stretching is not described as permanently lengthening muscle;
- foam rolling is not described as breaking fascia;
- lactate is not described as the cause of next-day soreness;
- passive stretching alone is not described as preventing injury;
- proximity to failure is presented with uncertainty, not as one mandatory threshold;
- neural and joint warning language is triage education, not tissue diagnosis;
- yoga cautions direct modification or professional guidance rather than banning movement for everyone.

## Failure and Compatibility Behaviour

- Unknown exercise names retain the current muscle/day briefing and receive only the conservative history note; they never receive a guessed physiological lesson.
- Cached dashboards without the newer addon keys decode and render as before.
- Existing callers of `SessionBriefing.briefing(dayType:exercises:)` continue to work.
- Existing rest-day parity remains valid.
- If no lesson exists, the sheet omits the knowledge section rather than displaying an empty card.

## Verification

- Unit tests cover every family mapping, yoga precedence, mixed-session ordering, recovery fallback, before/after position, all three history bands, pain, joint, hypermobility, unknown movement, myth exclusions, and presentation caps.
- Localisation tests cover every new key in all nine locales and preserve substitution tokens.
- Focused Session Briefing tests run red before implementation and green after it.
- Full native tests, repository/web tests, production web build, `plutil` validation, signed Release build, physical-device install/launch, GitHub push, and successful GitHub Pages deployment remain required before closing 1.10.
