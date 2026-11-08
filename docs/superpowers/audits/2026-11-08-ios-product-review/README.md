# FITR MAX iOS product audit

8 November 2026 · build 1.0.0 (403) · source revision `45f58e1`

FITR MAX has several issues worth fixing before expanding paid or coach access. The largest risks are losing ingredients from an existing meal, showing an apparent fitness decline without observations, and enforcing the end of a coach’s access consistently. The audit included the iPhone journeys, Watch controls, account lifecycle, scoring, the public food catalogue, and the backend behind the app.

| Priority | Product finding | What would close it |
| --- | --- | --- |
| Fix first | An older meal can open with only some of its ingredients. Saving a new portion can permanently remove the others. | Load the complete meal before allowing replacement. Exercise an edit past the history limit and a concurrent edit from a second device. |
| Fix first | Opening a finished workout receipt starts a write without the user editing a field. Display rounding can change recorded loads. | Initialise the editor without a write, preserve numeric precision, and assert that simply opening and closing a receipt queues zero changes. |
| Fix first | A standard account that answered “Not tested” received an Overall Fitness score of 50.8. With no further evidence it fell to 39.8 over 31 days. | Keep unobserved domains in “Building your baseline.” Only show a change when dated evidence supports it. |
| Fix first | Coaching access needs an end-to-end revocation check. The owner has the private reproduction covering the iPhone sharing controls and deployed database behavior. | Verify the client’s control over future sharing and the coach’s current eligibility at every read and write. |
| Fix before wider release | A Quick Log can create two receipts on repeated Save, or create a recurring workout from a one-off activity. Simple also omits separately scheduled custom sessions. | Give each draft a stable receipt ID, distinguish performed sessions from prescriptions, and use the same daily schedule in both entry points. |
| Fix before wider release | Hydration and meal timing can earn misleading avatar feedback. Adding a correct brand can also remove a valid food search result. | Share the daily goal, logical meal identity and food-matching rules across the screens using them. |
| Fix before wider release | Someone who signs up with email has no in-app password recovery entry point. The privacy text promises account deletion, but Settings exposes only logout. | Provide recovery from sign-in and an authenticated deletion entry in Settings. |

[Workout, nutrition, scoring and usability evidence](product.md) · [Verification and release checks](verification.md)

The smallest useful repairs follow the records that each screen edits. A performed workout needs one identity even when the user taps twice. A retrieved meal must be complete before an edit can replace it. A score needs an observation date, the goal for that date, and an explicit state for insufficient evidence. These are more valuable changes than reorganising the app’s large session controller by file size alone.
