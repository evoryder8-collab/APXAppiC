# APEX

Personal performance system for Constantin. Nutrition, two training programs with a guided
workout player, a procedural holographic 3D body, an intelligent event taper, and an RPG stat
engine with science-based decay. Bright light-mode glassmorphism, single user, static SPA.

Live: https://evoryder8-collab.github.io/APXAppiC/

## Stack

- Vite + React + TypeScript, `HashRouter` (routes survive refresh on GitHub Pages)
- Tailwind CSS v4, Framer Motion, date-fns
- Supabase (Postgres + Auth + Realtime) as the only backend, optional (see modes below)
- Three.js via React Three Fiber + postprocessing for the hologram (lazy-loaded chunk)

## Two modes

**Local mode (works immediately).** Without Supabase env vars the app runs entirely from
localStorage: it seeds your programs, meals and supplement stack on first open and everything
works offline on that one device. The top-bar dot shows blue.

**Synced mode.** Add the env vars and redeploy: the app gates behind email/password auth, seeds
your Supabase tables on first sign-in, syncs phone and desktop live (Realtime), and queues
writes in localStorage while offline (amber dot), flushing when connectivity returns (green dot).

## Supabase setup (one time, ~5 minutes)

1. Create a free project at supabase.com.
2. Open the SQL editor, paste all of `supabase/migrations/001_schema.sql`, run it. That creates
   every table with Row Level Security scoped to your user (the anon key is safe in the bundle).
3. Authentication → Users → Add user: your email + password (disable public signups if you like,
   the app never signs anyone up).
4. Project Settings → API: copy the URL and anon key into:
   - `.env.local` (copy `.env.example`) for local dev, and
   - GitHub repo → Settings → Secrets and variables → Actions → new secrets
     `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for deploys.
5. Push to `main` (or re-run the deploy workflow). Sign in once; the app seeds all data
   automatically. No seed SQL to paste.

## Local development

```bash
npm install
npm run dev        # http://localhost:5174
npm run build      # typecheck + production build to dist/
```

## Deployment

Pushing to `main` triggers `.github/workflows/deploy.yml`, which builds and publishes to GitHub
Pages (source: GitHub Actions, already enabled). Vite `base` is set to `/APXAppiC/`.

## What's inside

- **Portal**: four breathing glass buttons. Nutrition (amber), Transition Phase (teal),
  Main Phase (violet), Avatar (emerald). Sync dot + settings in the top bar.
- **Nutrition**: BMR via Mifflin-St Jeor and Katch-McArdle, TDEE, goal calories and macro
  targets (protein 2.2 g/kg); meal timeline with minimum-effective-meal fallbacks; the exact
  supplement stack as a checkable timeline where training-relative windows (T-60/T-45/T-15/post)
  reflow from the training time; a 20-second evening log with 7-day sparklines. Water is one
  shared record per date with the calendars. Browser reminders (permission-gated) fire while a
  tab is open; a static site has no push server.
- **Workout sections**: monthly glass calendars (accent fill = done, ice shimmer = deload,
  amber→crimson ramp = event approach), streak counter, tap to plan, hold to mark deload.
  Day sheets show the adjusted plan, Full/Lite toggle (Lite = the planned session, full RPG
  credit, 0-1 RIR), per-exercise recommendation chips, the hologram, water quick-log and START.
- **Taper engine**: -25% sets at day -4/-3, -50% at -2/-1, heavy pulling and spinal loading
  swapped for thoracic work in the final 72 h, no legs in the 7 days before a filming
  championship, recovery micro-sessions during events (they keep the streak and feed Joint
  Health), two rebound days after. Return-from-layoff (3+ weeks) auto-applies a deload week.
- **Guided player**: warmup → sets → rests → logs as one timeline. Rep cadence from each
  exercise's tempo with voice + ticks (both toggleable), breathing rest ring with skip/+30 s,
  checkpoint scrubber to jump anywhere, state survives backgrounding, 2-tap logging with
  prefilled weight/reps, session summary with streak and stat deltas.
- **Smart progression**: top of rep range on all sets at target RIR recommends +2.5 kg
  (compounds/backpack) or +1 kg (isolations). The Overload Guardian flags jumps beyond ~1.5x
  your typical increment (tunable in Settings) with the tendon-adaptation reasoning, offers the
  safe load, and logs overrides (they ding Joint Health).
- **Avatar**: level HUD, hexagonal radar, six animated stat bars with Upper/Lower strength
  sub-bars (lower seeded at 42 vs upper 60; leg XP boosted 1.25x until convergence), per-stat
  30/90-day history, an expandable baseline-reasoning panel, and "What your body needs" cards.
  Stats replay deterministically every app load (idempotent catch-up) with physiology-based
  half-lives: endurance ~12 days, flexibility ~8.5, strength ~31, plus a tiny continuous age drag.
- **Export**: Markdown report (download or clipboard) of any date range, formatted for pasting
  into an AI for program assessment.

## Tuning the hologram

All body proportions live in one constants object:
`src/components/hologram/proportions.ts` (`BODY`). Shoulder width, limb lengths and radii,
muscle-region placement and the day-type highlight map are plain numbers there.
