# APEX

Personal performance system for Constantin. Nutrition, training programs, a guided workout player, a holographic 3D body, and an RPG stat engine, all in one bright glassmorphism SPA.

## Stack

- Vite + React + TypeScript, static SPA with `HashRouter` (survives refresh on GitHub Pages)
- Tailwind CSS v4, Framer Motion, date-fns
- Supabase (Postgres + Auth + Realtime) as the only backend, from phase 2
- Three.js via React Three Fiber for the hologram body, from phase 5

## Local development

```bash
npm install
npm run dev        # http://localhost:5174
npm run build      # typecheck + production build to dist/
```

## Environment variables

Copy `.env.example` to `.env.local` and fill in (needed from phase 2):

| Variable | Description |
| --- | --- |
| `VITE_SUPABASE_URL` | Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | Supabase anon public key (safe in the bundle, RLS protects all data) |

## Supabase setup (phase 2)

1. Create a free project at supabase.com.
2. Paste the migration SQL from `supabase/migrations/` into the SQL editor and run it.
3. Create the single user account under Authentication, email + password.
4. Put the project URL and anon key into `.env.local`, and into the repo's GitHub Actions secrets (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`) for deploys.

## Deployment

Pushing to `main` triggers `.github/workflows/deploy.yml`, which builds the app and publishes `dist/` to GitHub Pages. One-time setup: repo Settings, Pages, set Source to "GitHub Actions". The app is served at `https://evoryder8-collab.github.io/APXAppiC/` (the Vite `base` is already configured for that path).

## Build phases

1. Scaffold, design system, 4-button portal (done)
2. Supabase schema, auth, offline queue
3. Nutrition incl. daily log
4. Workout calendars, logging, events and taper
5. Hologram body
6. Guided workout player
7. RPG engine and recommendations
8. Smart progression, Overload Guardian, export, polish
