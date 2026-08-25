-- Canonical, account-scoped hydration facts and preferences.
-- Existing daily_logs.water_l values remain a read-time legacy fallback; this
-- migration deliberately does not manufacture source or beverage provenance.

create table if not exists public.hydration_events (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_idempotency_key text not null,
  local_date date not null,
  occurred_at timestamptz not null,
  amount_ml integer not null,
  kind text not null,
  palette_token text not null default 'aqua',
  icon_token text not null default 'drop.fill',
  source text not null,
  healthkit_sample_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_idempotency_key),
  constraint hydration_event_amount check (amount_ml > 0 and amount_ml <= 10000),
  constraint hydration_event_kind check (kind in ('water', 'coffee', 'tea', 'juice', 'shake', 'other', 'food', 'external', 'legacy')),
  constraint hydration_event_source check (source in ('iphone', 'watch', 'web', 'food', 'healthkit_external', 'legacy'))
);

create unique index if not exists hydration_events_owner_healthkit_sample
  on public.hydration_events (user_id, healthkit_sample_id)
  where healthkit_sample_id is not null;
create index if not exists hydration_events_owner_day_time
  on public.hydration_events (user_id, local_date, occurred_at desc);

create table if not exists public.hydration_presets (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  amount_ml integer not null,
  kind text not null,
  palette_token text not null default 'aqua',
  icon_token text not null default 'drop.fill',
  sort_order integer not null default 0,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  constraint hydration_preset_name check (length(trim(name)) between 1 and 40),
  constraint hydration_preset_amount check (amount_ml between 10 and 5000),
  constraint hydration_preset_kind check (kind in ('water', 'coffee', 'tea', 'juice', 'shake', 'other')),
  constraint hydration_preset_sort check (sort_order >= 0)
);

create index if not exists hydration_presets_owner_order
  on public.hydration_presets (user_id, enabled desc, sort_order, created_at);

create table if not exists public.hydration_preferences (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  target_ml integer not null default 2750,
  display_unit text not null default 'liters',
  reminders_enabled boolean not null default false,
  reminder_interval_minutes integer not null default 90,
  quiet_hours_start_minutes integer not null default 1290,
  quiet_hours_end_minutes integer not null default 480,
  shows_preset_names boolean not null default true,
  confirmation_haptics boolean not null default true,
  motion_intensity text not null default 'subtle',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id),
  constraint hydration_target_range check (target_ml between 1000 and 6000),
  constraint hydration_display_unit check (display_unit in ('liters', 'gallons')),
  constraint hydration_reminder_interval check (reminder_interval_minutes in (60, 90, 120)),
  constraint hydration_quiet_start check (quiet_hours_start_minutes between 0 and 1439),
  constraint hydration_quiet_end check (quiet_hours_end_minutes between 0 and 1439),
  constraint hydration_motion check (motion_intensity in ('off', 'subtle', 'full'))
);

alter table public.hydration_events enable row level security;
alter table public.hydration_presets enable row level security;
alter table public.hydration_preferences enable row level security;

drop policy if exists "owner_all" on public.hydration_events;
create policy "owner_all" on public.hydration_events
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "owner_all" on public.hydration_presets;
create policy "owner_all" on public.hydration_presets
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "owner_all" on public.hydration_preferences;
create policy "owner_all" on public.hydration_preferences
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke all on table public.hydration_events from public, anon;
revoke all on table public.hydration_presets from public, anon;
revoke all on table public.hydration_preferences from public, anon;
grant select, insert, update, delete on table public.hydration_events to authenticated;
grant select, insert, update, delete on table public.hydration_presets to authenticated;
grant select, insert, update, delete on table public.hydration_preferences to authenticated;
