# Linked wearable workout evidence

## Goal

Treat an APEX follow-along session and its independently recorded wearable workout as two views of one effort. The APEX receipt remains authoritative for performed exercise facts; the HealthKit receipt remains read-only evidence for time, energy, distance, and source-device facts.

## Association contract

- A link is account-owned and stored on the existing imported activity row through `apex_workout_session_id`.
- Automatic association considers only visible, external HealthKit workouts that are not already linked and are not APEX-authored HealthKit mirrors.
- The wearable workout must belong to the same owner and local day, start no more than five minutes before the APEX session, overlap the APEX start, and start no later than APEX completion.
- Exactly one eligible candidate links automatically. Multiple eligible workouts require the user to choose; APEX does not guess between them.
- A later HealthKit refresh preserves a manual or automatic external link. APEX-authored mirrors remain deduplicated by their APEX bundle identifier and metadata/session identity.
- An imported workout may link to only one APEX receipt. A receipt exposes at most one selected wearable effort.
- Deleting an APEX receipt never deletes Apple Health data. The imported receipt remains account-owned and may return as a standalone external workout after unlinking or session deletion.

## Finished-workout presentation

A linked external workout is nested visibly inside its APEX Finished Workouts card rather than emitted as a second standalone card. The expanded APEX receipt keeps its editable exercise facts and adds a read-only wearable evidence panel with the localized workout name, source, date/time, duration, and only the energy or distance values that exist. Wearable calories are descriptive and never added to HealthKit active energy again.

## “Already finished?” recovery flow

The guided player offers a small lower-trailing `Already finished?` action throughout an unfinished session.

1. Opening it pauses cadence and timers while remembering whether the player was already paused.
2. The sheet asks whether the user already completed the workout outside the follow-along flow.
3. `No, keep training` closes the sheet and restores the prior pause state.
4. `Yes, choose wearable activity` shows visible external workouts from the selected workout day, newest first. A refresh action requests the event-driven HealthKit import path; it does not poll.
5. Choosing a workout shows its available receipt facts and an explicit completion action.
6. Completion stores only exercise sets the user actually recorded so far, links the selected wearable receipt, marks the planned session complete, and opens the normal finished receipt. It never invents reps, sets, load, RIR, distance, energy, or heart-rate values.
7. `Finished without a wearable` is available for a user who completed externally but did not record a device workout. It keeps only facts already recorded in APEX.

HealthKit denial, an empty candidate list, missing metrics, account switching, and offline state leave the live session intact and recoverable.

## Cross-platform behavior

Native owns HealthKit import. Web consumes the same account-scoped imported rows and must group linked evidence identically in Finished Workouts. The web player offers the recovery flow against already synchronized same-day rows; it does not claim to initiate a browser HealthKit refresh.

## Later insight/export increment

The next separate increment aggregates finished receipts over day, week, year, or a bounded custom interval. Exercise facts come only from APEX logs, while wearable metrics come only from linked or standalone imported receipts with HealthKit energy kept non-additive. A rounded PNG card will label exact 1-, 5-, and 10-year spans as anniversaries without changing the underlying totals.
