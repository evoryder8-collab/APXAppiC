# Coach Platform Foundation — Design

Date: 2026-09-01
Status: approved by the owner for implementation

## Outcome

APEX gains a real coach workspace without turning a client account into a remotely controlled profile. A coach can invite a person, publish a versioned training plan, and review only the areas that person explicitly shares. A sponsored client can follow the published programme without buying an individual subscription, while nutrition, workout completion, Avatar history, export, and all previously owned records remain the client's.

This is a production foundation, not a Coach pricing launch. Commercial Coach products, public sales copy, and seat billing remain disabled until the roadmap's commercial release gate is separately authorised.

## Trust boundaries

- A database coach profile, not a device flag or subscription string, grants coach tools.
- Invitations are token based, expire, and must be accepted by the signed-in invitee whose email matches the invitation.
- Consent scopes are explicit. Visual-progress photos start disabled and require a separate opt-in.
- Coaches never receive direct write access to client-owned profile, logs, photos, nutrition, hydration, supplements, or workout history.
- Coach plans are immutable versions. Editing a published plan creates a new version; old receipts keep their original programme-day references.
- A client activates a published version. The activation RPC materialises a new active `coach` programme into that client's owner-scoped rows and retires, rather than deletes, the prior coach-authored days.
- Ending a relationship preserves the plan, acknowledgements, client data, and history. The relationship enters a transparent read-only grace state before its seat is released.
- Every invitation, consent, plan publication, activation, acknowledgement, and relationship transition is written to an append-only audit ledger.

## Server model

`coach_profiles`
: Server-owned coach identity, operational status, and seat limit. The owner account receives a development coach profile so the platform can be exercised without exposing Coach pricing.

`coach_invitations`
: Coach, normalized invitee email, SHA-256 token digest, requested scopes, expiry, and lifecycle. The raw token is returned only once by the creation RPC.

`coach_relationships`
: Coach/client pair, consented scopes, relationship status, sponsored-seat state, consent timestamp, grace boundary, and end timestamp.

`coach_plan_versions`
: Immutable draft or published plan version with bounded typed JSON, checklist, review date, author, and version number.

`coach_plan_acknowledgements`
: Client receipt that a specific published version was reviewed and, separately, activated.

`coach_plan_installations`
: Maps a client-owned `coach` programme to the exact immutable version installed in it.

`coach_audit_log`
: Append-only event facts with actor, relationship, event type, and bounded metadata.

All tables have RLS enabled and deny generic cross-account access. Narrow security-definer RPCs apply authentication, relationship, email, scope, seat, expected-revision, payload-size, and ownership checks.

## Plan contract

A plan has a title, objective, optional coach note, review date, six completion pillars, and one to seven session templates. Each session has a stable template id, weekday, name, guided/tracked mode, estimated minutes, warm-up note, and ordered exercises. Each exercise references the typed APEX movement library and includes sets, work target/unit, rest, tempo, optional/per-side flags, equipment note, and grouping identifiers where relevant.

Unknown top-level fields, oversized payloads, duplicate template ids, invalid weekdays, unsupported units, out-of-range prescriptions, empty plans, and movements absent from the published catalogue are rejected before publication. Drafts may be incomplete; publication may not.

## Client capabilities

While an active sponsored relationship exists, the client can:

- use their coach programme, player, logging, receipts, Nutrition, Avatar, recovery, hydration, supplements, settings, and export;
- see who sponsors access, the scopes they granted, the current plan version, review date, and whether a newer plan awaits activation;
- revoke optional scopes and end the relationship;
- keep all owned data after the relationship ends.

The client cannot create custom workouts, rebuild a coach-owned plan, edit its prescribed targets, access the coach roster, or impersonate another account. Those controls are absent and route guards enforce the same policy.

## Coach experience

The workspace opens on a calm roster with search, relationship/seat state, current plan version, review date, acknowledgement state, and attention reasons. A coach can:

- create an expiring invitation and copy its one-time link;
- open a consent-scoped client overview;
- build a programme using the APEX movement library;
- save a draft, publish a new immutable version, and see client acknowledgement/activation;
- end the relationship without deleting client history.

Nutrition, recovery, hydration, measurements, notes, and visual-progress review remain scope gated. This foundation exposes a bounded overview and plan workflow; richer reporting builds on the same permission ledger rather than creating a second access system.

## Failure and offline behaviour

- Coach mutations fail closed while offline and never enter the client's general offline owner-write queue.
- A previously activated client plan remains usable offline because it lives in the client's existing dashboard cache.
- Invitation, roster, consent, and unpublished draft state clearly report that a connection is required.
- A failed refresh cannot leak the prior account's coach context; account switching clears it before network work begins.

## Verification

- Pure web and Swift contracts cover policy, plan validation, version/activation semantics, attention calculation, and account switching.
- SQL validation proves RLS isolation, matching-email consent, seat limits, scope defaults, publication validation, activation ownership, history retention, and append-only audit behaviour.
- Web and native UI coverage proves coach-only entry, invitation feedback, client plan visibility, route locks, no-photo-by-default, and no truncation at supported text sizes.
- The native build and UI flow use only the dedicated `APEX Lane` simulator. Physical iPhone and Watch installation remains deferred while the owner sleeps.
