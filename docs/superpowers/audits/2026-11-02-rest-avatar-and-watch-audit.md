# Guided rest, Avatar attribution and Watch gallery audit

Scope: June's web/iOS rest comparison, completed Quick Log contribution to Avatar, overlapping history dates, and the missing Watch complication listing reported on 2 November 2026. Source baseline: `8aef6dd` / TestFlight 400. This audit uses isolated fixtures; it does not create real Apple Health workouts or alter either bespoke programme.

## Findings and corrections

### Authored rests were consistent; execution was not

The current June V8.4 prescription and shared web/native timeline use the same rest values:

| Example | Rest after the completed set |
| --- | --- |
| Monday hip thrust, Bulgarian split squat, Romanian deadlift | 120 seconds |
| Morning hip thrust and Friday unilateral work | 105 seconds |
| Push-ups, rows and curls | 90 seconds |
| Lighter assistance work | 45–60 seconds, according to the exercise |

Light/deload changes the prescribed set count, not these authored rests. The native live player had not consumed the timeline's left/right stages: a unilateral set could move straight to rest after its first side. It also began counting while the introduction was still being spoken. The corrected live sequence is left side, the authored changeover, right side, then rest. A completed set records the lower per-side count, matching web; it does not sum both sides. June's Bulgarian split squat changeover is 27 seconds and Friday reverse lunge changeover is 12 seconds. The web voice no longer falsely calls every changeover three seconds.

Optional persisted side state keeps old drafts readable. Pause/background handling and speech tokens prevent old callbacks or suspended execution from completing an unperformed side.

### Quick Log facts were saved but lost on the path to Avatar

Manual/custom receipts store `movement_id` and set facts while `exercise_id` is normally absent. Native mapping discarded those facts and did not recognise the `custom` day type; web accepted the type but had no scoring branch for it. Thus ordinary custom squats, presses and runs produced the same capacity-lane result as no workout. The save/recompute trigger itself worked.

Both clients now resolve the saved catalogue ID and performed facts. Known primary muscles route resistance work to upper/lower lanes; mobility and cardio use their own catalogue categories. Custom credit is bounded to one contribution per domain/day and does not stack onto an already credited planned workout in that domain. Linked wearable records remain excluded from duplicate scoring. Unknown IDs and unperformed, skipped, incomplete, foreign or future work cannot invent credit. Existing editing/deletion replays remain intact.

Representative one-day synthetic replay, with all other inputs held fixed:

| Added custom activity | Before → after in its affected lane |
| --- | --- |
| Squat | Lower strength 41.8 → 44.0 |
| Push-up | Upper strength 59.7 → 60.9 |
| Running | Endurance 44.2 → 46.9 |
| Mobility | Flexibility 39.1 → 41.8 |

These are **game-index outputs**, not measured changes in physiological ability. Completed/performed guards also close a separate defect where an unfinished set could trigger a progressive-overload gain or an override penalty. Unknown exercise categories no longer default to upper-body overload credit.

### What the visible engine actually computes

The current visible model remains version 1. Native `AppSession.data` changes replay `FitnessBrainEngine`, update the owned snapshots locally, and persist the latest deterministic snapshot when permitted. The web uses the corresponding `computeEngine`. Backdated input is replayed on its assigned calendar day.

| Input | Current version-1 effect |
| --- | --- |
| Completed classified training | Game-index strength, endurance or flexibility credit; mobility/recovery can affect the joint lane |
| Completed heavier programme exercise | Bounded per-exercise overload events for the known upper/lower category |
| Protein/energy against a publishable target | Strength-day game multipliers and Health-lane consistency credit |
| Logged drinking water | Health-lane credit at the legacy fixed threshold; a T25-specific endurance modifier |
| Saved recovery/sleep score | Health-lane support; it is not a direct strength measurement |
| Finalised meal rhythm | Consistency context and game modifiers; open days do not receive a closed-day verdict |
| Owned calibration evidence | Updates only its corresponding provisional capacity lane |
| VO₂ evidence | Legacy endurance anchor; its linear scale is not a validated age/sex percentile |

The weighted overall formula is 25% mean strength, 20% endurance, 15% flexibility, 20% joint and 20% Health, bounded to 0–100. Replay also includes the legacy decay, streak and headroom rules. Arithmetic parity verifies implementation consistency, **not scientific validation of these coefficients**.

The visible disclosure remains “Legacy game scores. Not medical measurements.” Version 2 separates capacity, readiness, adherence and adaptation support, but remains in shadow validation under the existing claim ledger. This hotfix does not silently activate it. Remaining model limitations include unlogged-day decay, fixed hydration threshold, same-day nutrition game multipliers, generic HealthKit strength credit without muscle-specific evidence, and absence of validated physiological capacity estimates from reps/load/RIR. Those require the planned evidence-model rollout; this audit must not be described as proving universal or clinical accuracy.

### History chart

The native chart treated `YYYY-MM-DD` strings as categories and printed every category. It now plots real dates with sparse localized day/month ticks and collision avoidance. All daily data points remain. The tooltip no longer claims every date represents a complete picture; all nine native languages have the corrected explanation. A gated 90-day fixture supports visual verification without touching account history.

### Watch complication gallery

The exact build-400 archive contains the Watch app, WidgetKit extension, intent metadata, four display choices and all four accessory families. The deployment target is watchOS 10; June's Series 10 on current watchOS meets it. No packaging omission was found. The report is that the app opens but its complication is absent from both Watch and iPhone selectors; the precise cause on her device is not yet proven.

Gallery snapshots previously awaited HealthKit queries and could write reconciliation state. Preview snapshot/timeline paths now return sample data immediately without Health access or sidecar writes, following Apple's [preview guidance](https://developer.apple.com/documentation/widgetkit/appintenttimelineprovider/snapshot(for:in:)). The Watch app invalidates configuration recommendations once per installed build, independently of Health permission, to refresh cached choices without a log-triggered reload loop. Existing complication kind, bundle IDs, App Group and hydration state remain stable. The requested visible Watch and complication name is **FITR MAX Watch**; iPhone remains **FITR MAX**.

## Verification record

- Initial engine boundary/calibration/nutrition/claim checks: 29 passed.
- Focused changed web paths, wearable linkage and player timeline/runtime checks: 32 passed.
- Production web build passed.
- Native full string tables parse; corrected chart copy is covered. The existing localization audit now handles the space in the canonical checkout path. It reports 24 unrelated gaps rather than a file-URL error; those are not claimed resolved here.
- Native integrated tests, visual checks and release evidence are recorded with the delivery entry in `docs/REPAIR-NOTES.md`.

## Subsequent focused findings

- Watch discovery is now reproduced in the simulator: WidgetKit crashes before timeline generation with `Formatted text for AppIntentRecommendation is not supported`. The recommendation description interpolated the display mode. Four literal, distinct mode labels remove that trap; the corrected extension successfully precaches placeholders for all four accessory families. This supersedes treating discovery only as a preview/cache hypothesis. June's physical Watch still requires the released update to confirm her outcome.
- A missing guided set can leave final Save disabled without feedback. Forward progress navigation can omit a set, while reviewing the last set enters the completion screen. In the supplied full Glutes A screenshot, 11 records and the white 2·3 pill identify the unresolved third Bulgarian split-squat set in the 12-set prescription. Recovery must explicitly collect or skip that set and retain all existing records. Completed-but-unsaved drafts must be restorable.
- Planned attempts with only skipped/empty work or explicit zero quality must not earn training or overload credit. Historical receipts with no set detail remain compatible; lack of old detail is not evidence that no work occurred. Known mobility completion is valid without inventing a duration.
- Multiple daily prescriptions now remain separate on Simple: their completion and draft identity include owner, date and exact programme-day ID. A morning receipt cannot mark the official session or cardio complete.
