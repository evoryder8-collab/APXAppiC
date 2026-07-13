# Orbit data and privacy

Orbit is private to authenticated APEX users. It has no public profile, follower graph, public feed, public route, public segment or leaderboard.

## Data model

- `orbit_routes`: route geometry, private labels and preferences
- `orbit_runs`: private GPS samples, pauses, metrics and reflection
- `orbit_segments`: private route intervals
- `orbit_shoes`: factual pair history and notes
- `orbit_posters`: poster recipe and privacy trim, not a public URL
- `orbit_inductions`: readiness answers
- `orbit_campaigns`: family, phase, transparent readiness and adaptation history
- `orbit_campaign_sessions`: original and adapted prescriptions

Every row contains `user_id`. RLS allows all operations only where `user_id = auth.uid()`. Anonymous grants are explicitly revoked. Composite owner foreign keys prevent a signed-in account from attaching its own row to a guessed identifier belonging to another user.

The local IndexedDB stores are also indexed by `user_id`, and the store rejects a cross-account write before persistence. Signing into another APEX profile loads only that profile's records and active run.

## Offline behavior

Routes, run progress, shoes, segments, induction and campaigns write locally first. Supabase operations enter a persistent user-scoped outbox. A completed run, active-run removal and outbox write are one IndexedDB transaction. Network loss cannot turn one finish tap into duplicate runs because remote rows use deterministic idempotency keys.

## Location privacy

Exact GPS history remains private. Route posters trim 200 metres from both the start and finish by default; the user may choose another distance. The generated image contains only the trimmed geometry. A precise home location is never exposed by default.

The geographic Edge Function validates the Supabase user before proxying a route or geocode request. Provider queries necessarily disclose requested coordinates or search text to the configured routing/geocoding provider; they do not include the APEX profile, health history or campaign answers.

## Export and deletion

Orbit Home can export the current user's complete Orbit domain as JSON. Permanent deletion removes that user's remote Orbit rows plus local stores and queued operations. Existing APEX nutrition, training, profile and Avatar records are outside that delete action.
