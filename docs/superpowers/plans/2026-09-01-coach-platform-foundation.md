# Coach Platform Foundation — Implementation Plan

Date: 2026-09-01

## 1. Executable contracts

- Add pure TypeScript and Swift coach-domain models.
- Add failing tests for permission resolution, explicit photo consent, plan validation, client locks, roster attention, immutable versions, and account-bound context reset.
- Add SQL source contracts for required RLS/RPC protections.

## 2. Server authority

- Add migration `045_coach_platform_foundation.sql` with the seven coach tables, active/coach-version fields on programme rows, indexes, constraints, triggers, RLS, and audit protections.
- Add authenticated RPCs for context, roster, invitation creation/acceptance, scoped overview, draft/publish, acknowledgement, activation, scope revocation, and relationship ending.
- Seed only the owner UUID as a development coach; create no client relationship and expose no price.
- Apply the migration and run adversarial SQL validation before wiring production UI.

## 3. Web coach and client surfaces

- Add an account-bound coach client/hook and route guards.
- Add `/coach` roster, invitation, client overview, movement-backed plan editor, draft/publish, and relationship controls.
- Add `/coach/invite/:token` consent flow and `/coach-plan` client plan/activation view.
- Show coach entry only from server context; show sponsored plan state to clients.
- Hide and guard custom-plan creation/rebuild controls for sponsored clients while retaining all owner logs and general wellness surfaces.
- Add authored English, Romanian, and Thai copy.

## 4. Native coach and client surfaces

- Add Codable coach models and Supabase RPC methods.
- Clear coach state at every account boundary and refresh it with the dashboard.
- Add coach workspace, invitation, scoped roster detail, movement-backed plan editor, publish feedback, client plan preview, acknowledgement, and activation.
- Add `coach` programme navigation and sponsored-client policy locks.
- Add authored strings and compact controls for every native language.

## 5. Integrated verification and delivery

- Run focused red/green tests, full web tests/build, focused then full native unit tests, native UI flow tests, and an unsigned watchOS build to ensure the deferred complication fix remains buildable.
- Run web localisation and native localisation coverage.
- Append exact evidence and the physical-device deferral to `docs/REPAIR-NOTES.md`.
- Commit the coach foundation separately, push the repair branch and `main`, confirm GitHub Pages, and verify the live URL.
- Do not install or launch on the physical iPhone or Watch until the owner explicitly says they are awake.
