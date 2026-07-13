# Orbit real-device QA

Automated tests validate deterministic domain and privacy behavior. These checks require real hardware and cannot be proven by a desktop simulator.

## iPhone Safari and installed web app

- Sign into Constantine, June and Matthew separately and confirm private isolation.
- Deny location. Planner still supports manual drawing and GPX; live run explains the missing permission.
- Grant precise location outdoors. Confirm the first stable sample, current position and accuracy state.
- Start, pause, resume, add a manual lap and finish a short run.
- Reload during a run. Confirm `Continue run` restores the same track.
- Lock the phone long enough for Safari to suspend. Confirm Orbit does not claim continuous recording and recovers the partial active run after return.
- Create an impossible GPS spike by moving between indoor/outdoor reception if practical. Confirm the final map and pace do not show an implausible jump.
- Check spoken kilometre splits with mute, Bluetooth and screen-reader states.
- Confirm 44-point minimum touch areas while moving.

## Android Chrome

- Repeat permission denial, approximate location, offline start, reload recovery and finish sync.
- Confirm the screen wake lock is released on finish and cancellation.
- Confirm route tiles and BRouter failure states degrade to draw, GPX and free run.

## Provider and route checks

- Zurich city route, rural path and hilly route.
- Loop, out-and-back and point-to-point requests.
- Save, rename, reverse, duplicate, favourite, note, GPX export and re-import.
- Confirm options are genuinely different and that distance error is visible rather than hidden.
- Confirm no screen labels a route guaranteed safe.

## Campaign checks

- Beginner, regular recreational, experienced marathoner and Hybrid Athlete inductions.
- Resolved old injury versus a current movement-changing symptom.
- Race date too close.
- Championship and travel event movement.
- Hard run adaptation, missed hard session and user override.
- Race week and post-marathon recovery states.

## Poster checks

- Map, Constellation, Elevation and Minimal styles.
- 0, 200 and 1,000 metre privacy trim.
- Ensure exact start and finish are absent from the default export.
- PNG and SVG save failure paths.
