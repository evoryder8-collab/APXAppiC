# Dayline parity and account-experience sandbox

Approved in conversation September 8: native Dayline should retain real web-style cables connecting meal cards to their actual time; refine the premium dark rail and restrained colour/depth without inventing metabolic precision. Preserve meal opening, dragging, deletion, date/timezone semantics and accessibility.

Simple order is Finished Workouts → Wearable Activity → Workout Insights. Insights starts as a narrow expandable bar. Apply equivalent web/native behaviour; reuse authored titles. Expansion is transient UI state, not account data.

Settings Developer Mode offers My account (actual current bespoke identity), Individual subscriber, Coach and Invited client. The latter three are interactive isolated sandboxes, not entitlement impersonation. Individual begins with new-user onboarding and plan building; coach has sample clients/authoring; client sees an assigned plan and real restrictions. Return restores the actual account unchanged. Clearly indicate preview mode and allow return from every sandbox route. No sandbox network mutation, production sync/cache/outbox, Apple Health, Watch, location, notification or purchase effects. Never make production RLS or entitlements trust a local role selector.

Temporary developer controls are restricted to the development owner rather than ordinary subscribers. Sample state is separate from account state. New UI strings need authored native nine-locale copy and web supported-locale copy. No new dependencies, no destructive operations, no other simulator lane. Necessary focused tests only; commit/push/Pages per delivered part. Build/install final signed app over existing data.
