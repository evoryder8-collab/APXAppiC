# Avatar Baseline Calibration — Implementation Plan

**Goal:** Add a compact Avatar `Edit` entry point that opens a resumable, evidence-honest baseline calibration for standard and bespoke accounts without changing programme authority.

## Task 1 — Lock the calibration contract in red tests

- Add one shared native/web fixture for the extended four-domain questionnaire.
- Require at least two observable anchors per domain, preserve `not tested`, widen uncertainty when answers disagree, emit low-confidence band-only evidence, and never emit an Overall score.
- Add account-isolation, stable-idempotency, malformed-answer, and bespoke-authority regressions.
- Add UI/source contracts for the 44-point `Edit` control directly above Stats, the `Calibrate my baseline` accessibility label, adaptive presentation, progress restoration, and authored localization.

## Task 2 — Implement the cross-platform calibration model

- Add deterministic native/web evaluation for three observable anchors in each of cardiorespiratory fitness, upper strength, lower strength, and region-specific mobility.
- Keep the output broad and low confidence; retain every answer, evidence range, provenance, model version, and measured time.
- Add validated manual-entry builders for recent body-fat, resting-energy, VO2-max, resting-heart-rate, and waist results. User-entered values remain low confidence even when the user names an external source.
- Persist only account-scoped drafts and make completed writes replay-safe through the existing evidence ledger/outbox.

## Task 3 — Build the native adaptive sheet

- Place the compact `Edit` button immediately above the Avatar Stats card with a minimum 44-point target and accessibility label `Calibrate my baseline`.
- Present an adaptive, dismissible sheet with a short route chooser: sharpen with questions, connect Apple Health, or add a recent result.
- Make the questionnaire resumable across dismissal/relaunch, offer `Not tested` without penalty, explain safety/stop conditions, and show a band-only review before saving.
- Use the existing HealthKit authorization/import path and keep denial non-blocking.
- State explicitly that calibration refines evidence only and cannot replace a bespoke programme or nutrition protocol.

## Task 4 — Build web parity and localization

- Add the same entry point, questionnaire, recent-result path, account-scoped draft restoration, authority copy, and evidence behavior on the web Avatar.
- Explain that Apple Health connection is completed in the iPhone app while preserving the other routes.
- Author all new full and compact strings in every offered language; verify Dynamic Type, VoiceOver, keyboard/focus, Reduce Motion, and no truncation.

## Task 5 — Verify and release

- Run focused parity, evidence, UI, localization, account-retention, full web, native unit, and native UI suites.
- Build/sign/install the exact product on `iConstantine Main`; use only `APEX Lane · iPhone 17 Pro` for Simulator checks and retry the paired APEX Watch companion without touching other lanes.
- Append `REPAIR-NOTES`, commit this task alone, push both required refs, wait for GitHub Pages, and confirm the live URL.
