# Workout insights and export design

## Outcome

APEX shows an account-owned, fact-only workout summary for a day, rolling week, rolling year, or unrestricted custom interval. The same totals render into a premium rounded PNG card that can be shared or saved.

## Truth model

- A completed APEX session counts as one workout.
- A linked external HealthKit workout is evidence inside that APEX workout, not a second workout.
- An unlinked visible external workout counts once on its own.
- Sets/efforts and reps come only from non-skipped APEX workout logs.
- Recorded load volume is `positive recorded kg × recorded reps`; missing load or reps never becomes zero-valued evidence.
- Duration prefers linked wearable duration; otherwise it uses valid APEX start/completion timestamps. Standalone external duration is counted once.
- Active energy comes only from external HealthKit workout rows that actually contain it. It is never added to an APEX estimate or to linked evidence twice.
- Distance prefers linked wearable distance; APEX logged distance is used only for sessions without linked wearable evidence.
- Hidden imports, APEX-authored HealthKit mirrors, foreign owners, invalid timestamps, and facts outside the selected range are excluded.

## Ranges and anniversaries

Day is one ISO date. Week is the inclusive trailing seven days. Year is the inclusive trailing calendar year. Custom accepts any ordered dates and is bounded only by the account's available history.

An export gains the highest eligible `1 YEAR`, `5 YEARS`, or `10 YEARS` anniversary treatment only when both the selected range and the account's actual workout evidence span that many calendar years. A long empty selection never earns an anniversary.

## Presentation

The in-app card leads with workouts, active days, and recorded time, followed by the facts that exist: active energy, reps, sets/efforts, recorded load volume, and distance. Missing optional facts use an em dash rather than a fabricated zero.

Native uses SwiftUI `ImageRenderer`; web draws the same content into a high-resolution Canvas. Both exports use a 4:5 rounded card, restrained aurora gradients, readable units, the exact range, and an anniversary crest when eligible.
