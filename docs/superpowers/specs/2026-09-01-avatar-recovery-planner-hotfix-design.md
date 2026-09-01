# Avatar recovery planner hotfix design

## Outcome

Avatar advice for Joint Health Balance and Body Flexibility opens a real, additive planning flow instead of dropping the user on a generic phase page. The flow proposes four weeks with two short sessions per week, previews the actual dates, and lets the user choose either an APEX-guided routine or a self-directed mobility/recovery video or routine.

## Evidence boundary

- The default dose is two short sessions each week for four weeks. It sits at the conservative end of ACSM flexibility guidance of at least two to three weekly sessions.
- Guided stretches use a comfortable, pain-free range and ordinary mobility movements already in the reviewed APEX catalogue. Static holds stay in the 10–30 second range and accumulate across repetitions rather than using one exhausting exposure.
- The planner supports general movement and range of motion. It does not diagnose, treat an injury, promise pain relief, or claim that stretching prevents injury.
- Scheduling creates no Avatar credit. Only a genuinely completed mobility workout enters the existing account-owned workout ledger, where the current engine already gives bounded Flexibility and Joint Health evidence once.

## Scheduling and retention

- Eight exact calendar dates are selected across four consecutive seven-day blocks, favouring days with the lowest existing training load and keeping the two weekly sessions separated when possible.
- Recovery rows are additive children of the account's active Transition or Main programme. Exact-date rows never repeat on the same weekday in other weeks and bypass generated-plan day-ID filters only on their own scheduled date.
- Installing a replacement deactivates only future, uncompleted recovery rows for the same account and target. Historical sessions, the authored programme, bespoke day IDs, and all other targets remain untouched.
- Coach-sponsored clients without individual plan-authoring access are directed to ask their coach rather than silently altering a coach plan.

## Surfaces

- Native and web Avatar use the same two choices, schedule semantics, exercise prescriptions, and safety language.
- Private Visual Progress sits immediately below the portrait and before the Performance Body/Body Index region.
- The food amount sheet places a 44-point circled information control beside the food title. It opens the already-built evidence detail sheet for typed and scanned foods.
- The broader Zürich-city Swiss German rewrite is recorded as deferred roadmap work; this hotfix authors its own new Swiss German strings consistently but does not claim to have reviewed the full corpus.
