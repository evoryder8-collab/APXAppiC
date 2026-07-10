-- Daily Activity Estimator
-- Additive and safe to run repeatedly against an existing APEX project.

do $$ begin
  create type activity_input_style as enum ('count', 'duration', 'distance', 'steps', 'watch_kcal');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type activity_log_source as enum ('manual', 'workout_module', 'event_prefill');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type daily_activity_mode as enum ('quick', 'precise');
exception when duplicate_object then null;
end $$;

-- Shared catalog. It deliberately has no user_id and normal authenticated
-- clients receive SELECT only. Admin/service-role edits remain possible.
create table if not exists activity_types (
  id text primary key,
  category text not null,
  name text not null,
  icon text not null default 'walk',
  met numeric not null default 1.2,
  input_style activity_input_style not null default 'duration',
  default_duration_min integer,
  is_training_linked boolean not null default false,
  notes text not null default '',
  distance_factor numeric,
  supports_watch boolean not null default false
);

create table if not exists activity_logs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date date not null,
  type_id text not null references activity_types (id),
  quantity numeric not null default 1,
  duration_min integer,
  distance_km numeric,
  watch_kcal numeric,
  computed_kcal numeric not null default 0,
  source activity_log_source not null default 'manual',
  reconciled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table daily_logs add column if not exists estimated_tdee integer;
alter table daily_logs add column if not exists computed_pal numeric;
alter table daily_logs add column if not exists activity_mode daily_activity_mode not null default 'quick';
alter table daily_logs add column if not exists weight_kg numeric;

-- Explicit backfill for projects where activity_mode may have first been
-- added as nullable during a partial migration.
update daily_logs set activity_mode = 'quick' where activity_mode is null;
alter table daily_logs alter column activity_mode set default 'quick';
alter table daily_logs alter column activity_mode set not null;

alter table profile add column if not exists calibration_k numeric not null default 1.0;
alter table profile add column if not exists calibration_history jsonb not null default '[]'::jsonb;

do $$ begin
  alter table profile add constraint profile_calibration_k_range
    check (calibration_k >= 0.85 and calibration_k <= 1.15);
exception when duplicate_object then null;
end $$;

insert into activity_types
  (id, category, name, icon, met, input_style, default_duration_min, is_training_linked, notes, distance_factor, supports_watch)
values
  ('massage-session', 'therapy', 'Massage session given', 'hands', 4.0, 'count', 60, false, 'Choose the number of sessions and 30, 60, or 90 minutes each.', null, false),
  ('deep-tissue-massage', 'therapy', 'Sports or deep-tissue massage', 'hands', 4.5, 'count', 60, false, 'Heavier hands-on work with more sustained force.', null, false),
  ('gimbal-filming', 'camera', 'Handheld or gimbal filming', 'camera', 3.2, 'duration', 240, false, 'Moving while filming with handheld or stabilized camera equipment.', null, false),
  ('tripod-shoot', 'camera', 'Static or tripod shoot', 'tripod', 2.3, 'duration', 120, false, 'Standing for a shoot with limited movement.', null, false),
  ('active-photo-shoot', 'camera', 'Active photo shoot', 'camera', 3.0, 'duration', 120, false, 'Repositioning, crouching, and moving around the set.', null, false),
  ('event-rig-carry', 'camera', 'Event day rig carry', 'case', 3.5, 'duration', 120, false, 'Bags, rig handling, and moving between venues.', null, false),
  ('desk-editing', 'work', 'Desk or editing work', 'desk', 1.2, 'duration', 240, false, 'Covered by the floor. Log it if useful for context, but it adds no calories.', null, false),
  ('standing-job', 'work', 'Standing job', 'stand', 2.2, 'duration', 240, false, 'Retail, teaching, reception, or another mostly standing shift.', null, false),
  ('nurse-server-shift', 'work', 'Nurse or server shift', 'walk', 3.3, 'duration', 480, false, 'A shift with frequent walking and limited sitting.', null, false),
  ('manual-labor', 'work', 'Manual labor or construction', 'hammer', 4.5, 'duration', 240, false, 'Sustained lifting, carrying, digging, or construction work.', null, false),
  ('active-childcare', 'work', 'Active childcare or park play', 'play', 3.0, 'duration', 60, false, 'Playing, carrying, chasing, and moving with children.', null, false),
  ('supermarket-trip', 'life', 'Supermarket trip', 'cart', 3.0, 'count', 25, false, 'Walking the store and carrying groceries. Count 25 minutes per trip.', null, false),
  ('household-cleaning', 'life', 'Household cleaning', 'home', 3.0, 'count', 30, false, 'Count in 30-minute blocks.', null, false),
  ('casual-walk', 'life', 'Dog walk or casual walk', 'walk', 3.0, 'duration', 30, false, 'Use time when distance is not known.', null, true),
  ('walking-distance', 'life', 'Walking distance', 'route', 3.0, 'distance', null, false, 'Uses 0.5 kcal per kilogram per kilometre.', 0.5, true),
  ('travel-day', 'life', 'Travel day on feet', 'case', 2.5, 'duration', 120, false, 'Airport walking, queues, and luggage handling.', null, false),
  ('incidental-steps', 'life', 'Steps not already covered by the blocks above.', 'steps', 1.2, 'steps', null, false, 'Use only steps that are not part of a logged run, walk, shift, or filming block.', null, false),
  ('apex-strength', 'training', 'APEX home strength session', 'strength', 5.0, 'duration', 20, true, 'Short home strength session, usually 15 to 20 minutes.', null, true),
  ('full-gym', 'training', 'Full gym session', 'strength', 6.0, 'duration', 60, true, 'A complete 45 to 60-minute resistance session.', null, true),
  ('focus-hiit', 'training', 'FocusT25 or HIIT', 'bolt', 8.5, 'duration', 25, true, 'High-intensity interval work.', null, true),
  ('mobility', 'training', 'Mobility or stretch session', 'mobility', 2.5, 'duration', 30, true, 'Focused mobility, stretching, or corrective work.', null, false),
  ('jog-run', 'training', 'Jog or run', 'run', 7.0, 'distance', null, true, 'Uses 1 kcal per kilogram per kilometre, independent of pace.', 1.0, true),
  ('watch-kcal', 'device', 'My watch says', 'watch', 1.2, 'watch_kcal', null, false, 'APEX counts 80% because wrist estimates often run high.', null, false)
on conflict (id) do nothing;

alter table activity_types enable row level security;
alter table activity_logs enable row level security;

drop policy if exists "authenticated_read" on activity_types;
create policy "authenticated_read" on activity_types
  for select to authenticated using (true);

drop policy if exists "owner_all" on activity_logs;
create policy "owner_all" on activity_logs
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke all on table activity_types from anon, authenticated;
grant select on table activity_types to authenticated;
revoke all on table activity_logs from anon;
grant select, insert, update, delete on table activity_logs to authenticated;

do $$ begin
  alter publication supabase_realtime add table activity_logs;
exception when duplicate_object then null;
end $$;

create index if not exists idx_activity_logs_user_date on activity_logs (user_id, date);
create index if not exists idx_activity_logs_user_type on activity_logs (user_id, type_id, date desc);

notify pgrst, 'reload schema';
