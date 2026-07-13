# Orbit providers and deployment

## Current open provider stack

- Map display: Leaflet with OpenStreetMap raster tiles and visible attribution
- Routing: BRouter `trekking` profile
- Geocoding: Nominatim
- Location: browser Geolocation API

The stack is suitable for a private three-person prototype and requires no paid key. Public community endpoints have fair-use and availability limits. They are not an SLA-backed production routing service. A public commercial release should use a hosted or self-hosted provider with documented capacity, pedestrian routing, surface/elevation coverage and contractual terms.

In production, route and geocoding requests always pass through the authenticated `orbit-geo` gateway, so precise coordinates are not sent directly by the browser to community providers. Direct provider access exists only in local development mode, where Supabase is deliberately unconfigured. If the production gateway is unavailable, Orbit falls back to manual drawing, GPX import and free running instead of silently changing the privacy path.

Orbit never claims route safety. It may describe map-supported properties such as lower navigation complexity, flatter geometry or fewer route changes. Current traffic, lighting, temporary access, weather and personal safety still require user judgement and authoritative local information.

## Supabase deployment

Run the additive migration and deploy the authenticated provider gateway:

```bash
npx supabase link --project-ref rrzcrcjsbkmidlafrhfv
npx supabase db push
npx supabase functions deploy orbit-geo --project-ref rrzcrcjsbkmidlafrhfv
```

Do not deploy `orbit-geo` with `--no-verify-jwt`. The function also calls `auth.getUser()` explicitly, providing defense in depth. Supabase supplies `SUPABASE_URL` and `SUPABASE_ANON_KEY` to Edge Functions.

Then verify:

1. All eight `orbit_*` tables have RLS enabled.
2. Anonymous grants are absent.
3. Constantine, June and Matthew each see only their own runs, routes, campaign, shoes, segments, posters and induction.
4. A route with another user's `user_id` or parent ID is rejected.
5. `orbit-geo` returns 401 without a valid APEX access token.
6. `notify pgrst, 'reload schema'` has refreshed PostgREST before mobile testing.

## Future native adapters

The portable interfaces allow a Swift build to replace:

- Browser Geolocation with Core Location background recording
- Web speech with AVSpeechSynthesizer
- Leaflet with MapKit or another licensed map SDK
- Web wake lock with an iOS workout/background execution strategy
- Browser-only sensor input with HealthKit and supported wearable data

No campaign or performance-analysis rewrite is required for that move.
