-- APEX schema. Paste this whole file into the Supabase SQL editor and run it.
-- Every table has RLS scoped to auth.uid() because the anon key ships in the
-- client bundle. Seeding happens automatically from the app on first sign-in.

create table if not exists profile (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  sex text not null default 'male',
  weight_kg numeric not null default 70,
  body_fat_pct numeric not null default 23,
  height_cm numeric not null default 178,
  birthdate date not null default '1992-07-25',
  activity_level text not null default 'moderate',
  goal text not null default 'recomp',
  training_time text not null default '19:00',
  baseline_date date not null default current_date,
  updated_at timestamptz not null default now(),
  unique (user_id)
);

create table if not exists settings (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  voice_on boolean not null default true,
  ticks_on boolean not null default true,
  notifications_on boolean not null default false,
  guardian_factor numeric not null default 1.5,
  addons jsonb not null default '{"endurance1":false,"endurance2":false,"endurance3":false}'
);

create table if not exists meals (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  time text not null,
  name text not null,
  foods text not null default '',
  kcal integer not null default 0,
  protein_g integer not null default 0,
  fat_g integer not null default 0,
  carbs_g integer not null default 0,
  full_days_only boolean not null default false,
  sort_order integer not null default 0
);

create table if not exists meal_logs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date date not null,
  meal_id uuid not null references meals (id) on delete cascade,
  checked_at timestamptz not null default now(),
  unique (user_id, date, meal_id)
);

create table if not exists supplements (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  dose text not null default '',
  timing text not null default 'clock',
  clock_time text,
  offset_min integer,
  group_label text not null default '',
  training_days_only boolean not null default false,
  sort_order integer not null default 0
);

create table if not exists supplement_logs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date date not null,
  supplement_id uuid not null references supplements (id) on delete cascade,
  checked_at timestamptz not null default now(),
  unique (user_id, date, supplement_id)
);

create table if not exists programs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  slug text not null,
  name text not null,
  description text not null default '',
  unique (user_id, slug)
);

create table if not exists program_days (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  program_id uuid not null references programs (id) on delete cascade,
  weekday integer not null,
  name text not null,
  day_type text not null,
  est_minutes integer not null default 20,
  warmup_note text not null default '',
  sort_order integer not null default 0
);

create table if not exists exercises (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  program_day_id uuid not null references program_days (id) on delete cascade,
  name text not null,
  sets integer not null default 3,
  rep_min integer not null default 8,
  rep_max integer not null default 12,
  rep_unit text not null default 'reps',
  per_side boolean not null default false,
  rest_sec integer not null default 90,
  tempo_up_s numeric not null default 1,
  tempo_down_s numeric not null default 2,
  tempo_pause_s numeric not null default 0,
  tempo_note text not null default '',
  notes text not null default '',
  increment_kg numeric not null default 0,
  is_lite boolean not null default false,
  optional boolean not null default false,
  sort_order integer not null default 0
);

create table if not exists workout_sessions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date date not null,
  program_day_id uuid not null references program_days (id) on delete cascade,
  is_lite boolean not null default false,
  is_deload boolean not null default false,
  is_event_recovery boolean not null default false,
  completed boolean not null default false,
  quality_score numeric not null default 0,
  started_at timestamptz,
  completed_at timestamptz,
  notes text not null default ''
);

create table if not exists workout_logs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  session_id uuid not null references workout_sessions (id) on delete cascade,
  exercise_id uuid references exercises (id) on delete set null,
  exercise_name text not null default '',
  set_no integer not null default 1,
  weight_kg numeric,
  reps integer,
  rir integer,
  skipped boolean not null default false,
  override_flag boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists daily_logs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date date not null,
  kcal integer,
  protein_g integer,
  fat_g integer,
  carbs_g integer,
  water_l numeric not null default 0,
  unique (user_id, date)
);

create table if not exists events (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  type text not null default 'filming_championship',
  start_date date not null,
  end_date date not null,
  notes text not null default ''
);

create table if not exists rpg_snapshots (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date date not null,
  overall numeric not null,
  health numeric not null,
  joint numeric not null,
  flexibility numeric not null,
  endurance numeric not null,
  strength numeric not null,
  strength_upper numeric not null,
  strength_lower numeric not null,
  unique (user_id, date)
);

create table if not exists deload_marks (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  date date not null,
  unique (user_id, date)
);

-- Row Level Security: each row belongs to its creator, full stop.
do $$
declare t text;
begin
  foreach t in array array[
    'profile','settings','meals','meal_logs','supplements','supplement_logs',
    'programs','program_days','exercises','workout_sessions','workout_logs',
    'daily_logs','events','rpg_snapshots','deload_marks'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "owner_all" on %I', t);
    execute format(
      'create policy "owner_all" on %I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())',
      t
    );
  end loop;
end $$;

-- settings uses user_id as its primary key; the loop above already covered it.

-- Helpful indexes for date-range reads.
create index if not exists idx_sessions_user_date on workout_sessions (user_id, date);
create index if not exists idx_wlogs_session on workout_logs (session_id);
create index if not exists idx_daily_user_date on daily_logs (user_id, date);
create index if not exists idx_snapshots_user_date on rpg_snapshots (user_id, date);
