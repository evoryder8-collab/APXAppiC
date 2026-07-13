-- APEX Orbit private running and Marathon Campaign domain.
-- Additive, idempotent and safe for the existing three accounts.

alter type activity_log_source add value if not exists 'orbit';

create table if not exists orbit_routes (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_idempotency_key text not null,
  name text not null,
  note text not null default '',
  points jsonb not null default '[]'::jsonb,
  distance_m integer not null default 0,
  elevation_gain_m integer,
  surface text not null default 'mixed',
  terrain text not null default 'rolling',
  shape text not null default 'loop',
  navigation_complexity text not null default 'moderate',
  familiarity_pct numeric,
  favourite boolean not null default false,
  rating smallint,
  mission_tags text[] not null default '{}',
  preferred_sections text[] not null default '{}',
  avoided_sections text[] not null default '{}',
  provider text not null default '',
  attribution text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_idempotency_key),
  constraint orbit_route_distance check (distance_m >= 0),
  constraint orbit_route_familiarity check (familiarity_pct is null or familiarity_pct between 0 and 100),
  constraint orbit_route_rating check (rating is null or rating between 1 and 5),
  constraint orbit_route_surface check (surface in ('road', 'path', 'trail', 'mixed')),
  constraint orbit_route_terrain check (terrain in ('flat', 'rolling', 'hilly')),
  constraint orbit_route_shape check (shape in ('loop', 'out_back', 'point_to_point')),
  constraint orbit_route_navigation check (navigation_complexity in ('low', 'moderate', 'high'))
);

-- Repair an interrupted preview without replacing existing route rows.
alter table orbit_routes add column if not exists rating smallint;
do $$ begin
  alter table orbit_routes add constraint orbit_route_rating check (rating is null or rating between 1 and 5);
exception when duplicate_object then null;
end $$;

create table if not exists orbit_shoes (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  brand text not null default '',
  first_use_date date not null,
  preferred_surfaces text[] not null default '{}',
  notes text not null default '',
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists orbit_inductions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  current_step integer not null default 0,
  completed boolean not null default false,
  outcome text,
  outcome_reason text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orbit_induction_step check (current_step >= 0),
  constraint orbit_induction_outcome check (outcome is null or outcome in ('ready', 'foundation', 'more_information', 'professional_review'))
);

create table if not exists orbit_campaigns (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_idempotency_key text not null,
  induction_id uuid not null references orbit_inductions (id) on delete cascade,
  family text not null,
  phase text not null,
  outcome text not null,
  status text not null,
  race_name text not null,
  race_date date not null,
  race_goal text not null,
  started_at timestamptz not null,
  plan_version text not null,
  assignment_reason text not null,
  timeline_warning text not null default '',
  readiness jsonb not null default '[]'::jsonb,
  adaptations jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_idempotency_key),
  constraint orbit_campaign_family check (family in ('foundation_first', 'first_finish', 'first_performance', 'personal_best', 'hybrid')),
  constraint orbit_campaign_phase check (phase in ('foundation', 'aerobic_build', 'durability', 'marathon_specific', 'peak', 'taper', 'race_week', 'post_marathon')),
  constraint orbit_campaign_outcome check (outcome in ('ready', 'foundation', 'more_information', 'professional_review')),
  constraint orbit_campaign_status check (status in ('active', 'paused', 'completed', 'review_required'))
);

create table if not exists orbit_campaign_sessions (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  campaign_id uuid not null references orbit_campaigns (id) on delete cascade,
  date date not null,
  prescribed_date date not null,
  phase text not null,
  original jsonb not null,
  adapted jsonb not null,
  status text not null default 'planned',
  completion_run_id uuid,
  adaptation_reason text not null default '',
  user_override boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (campaign_id, date, id),
  constraint orbit_session_status check (status in ('planned', 'completed', 'missed', 'skipped')),
  constraint orbit_session_phase check (phase in ('foundation', 'aerobic_build', 'durability', 'marathon_specific', 'peak', 'taper', 'race_week', 'post_marathon'))
);

-- Repair a partially applied preview migration without replacing rows.
alter table orbit_campaign_sessions add column if not exists prescribed_date date;
update orbit_campaign_sessions set prescribed_date = date where prescribed_date is null;
alter table orbit_campaign_sessions alter column prescribed_date set not null;

create table if not exists orbit_runs (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  client_idempotency_key text not null,
  local_date date not null,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  mission text not null,
  route_id uuid references orbit_routes (id) on delete set null,
  campaign_session_id uuid references orbit_campaign_sessions (id) on delete set null,
  shoe_id uuid references orbit_shoes (id) on delete set null,
  samples jsonb not null default '[]'::jsonb,
  pauses jsonb not null default '[]'::jsonb,
  manual_laps_m jsonb not null default '[]'::jsonb,
  metrics jsonb not null,
  check_in jsonb not null,
  nutrition_adjustment_applied_at timestamptz,
  status text not null default 'completed',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, client_idempotency_key),
  constraint orbit_run_status check (status in ('completed', 'discarded')),
  constraint orbit_run_mission check (mission in ('recovery', 'easy', 'aerobic_base', 'long_run', 'run_walk', 'progression', 'tempo', 'threshold', 'intervals', 'hills', 'marathon_pace', 'exploration', 'performance_test', 'free_run'))
);

do $$ begin
  alter table orbit_campaign_sessions add constraint orbit_session_completion_run_fk
    foreign key (completion_run_id) references orbit_runs (id) on delete set null;
exception when duplicate_object then null;
end $$;

create table if not exists orbit_segments (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  route_id uuid not null references orbit_routes (id) on delete cascade,
  name text not null,
  start_distance_m integer not null,
  end_distance_m integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint orbit_segment_distance check (start_distance_m >= 0 and end_distance_m > start_distance_m)
);

create table if not exists orbit_posters (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  run_id uuid not null references orbit_runs (id) on delete cascade,
  style text not null,
  privacy_trim_m integer not null default 300,
  include_heart_rate boolean not null default false,
  note text not null default '',
  created_at timestamptz not null default now(),
  constraint orbit_poster_style check (style in ('map', 'constellation', 'elevation', 'minimal')),
  constraint orbit_poster_privacy check (privacy_trim_m >= 0)
);

create index if not exists idx_orbit_routes_user_favourite on orbit_routes (user_id, favourite desc, updated_at desc);
create index if not exists idx_orbit_runs_user_date on orbit_runs (user_id, local_date desc);
create index if not exists idx_orbit_runs_user_route on orbit_runs (user_id, route_id, local_date desc);
create index if not exists idx_orbit_sessions_user_date on orbit_campaign_sessions (user_id, date, status);
create index if not exists idx_orbit_campaigns_user_status on orbit_campaigns (user_id, status, race_date);
create index if not exists idx_orbit_segments_user_route on orbit_segments (user_id, route_id);
create index if not exists idx_orbit_shoes_user_archive on orbit_shoes (user_id, archived, updated_at desc);

-- Composite owner references prevent a valid user from attaching their row to
-- another account's guessed UUID even though RLS would hide that parent row.
create unique index if not exists uq_orbit_routes_id_owner on orbit_routes (id, user_id);
create unique index if not exists uq_orbit_runs_id_owner on orbit_runs (id, user_id);
create unique index if not exists uq_orbit_shoes_id_owner on orbit_shoes (id, user_id);
create unique index if not exists uq_orbit_inductions_id_owner on orbit_inductions (id, user_id);
create unique index if not exists uq_orbit_campaigns_id_owner on orbit_campaigns (id, user_id);
create unique index if not exists uq_orbit_sessions_id_owner on orbit_campaign_sessions (id, user_id);

do $$ begin alter table orbit_campaigns add constraint orbit_campaign_induction_owner_fk foreign key (induction_id, user_id) references orbit_inductions (id, user_id) on delete cascade; exception when duplicate_object then null; end $$;
do $$ begin alter table orbit_campaign_sessions add constraint orbit_session_campaign_owner_fk foreign key (campaign_id, user_id) references orbit_campaigns (id, user_id) on delete cascade; exception when duplicate_object then null; end $$;
do $$ begin alter table orbit_runs add constraint orbit_run_route_owner_fk foreign key (route_id, user_id) references orbit_routes (id, user_id) on delete set null (route_id); exception when duplicate_object then null; end $$;
do $$ begin alter table orbit_runs add constraint orbit_run_session_owner_fk foreign key (campaign_session_id, user_id) references orbit_campaign_sessions (id, user_id) on delete set null (campaign_session_id); exception when duplicate_object then null; end $$;
do $$ begin alter table orbit_runs add constraint orbit_run_shoe_owner_fk foreign key (shoe_id, user_id) references orbit_shoes (id, user_id) on delete set null (shoe_id); exception when duplicate_object then null; end $$;
do $$ begin alter table orbit_campaign_sessions add constraint orbit_session_run_owner_fk foreign key (completion_run_id, user_id) references orbit_runs (id, user_id) on delete set null (completion_run_id); exception when duplicate_object then null; end $$;
do $$ begin alter table orbit_segments add constraint orbit_segment_route_owner_fk foreign key (route_id, user_id) references orbit_routes (id, user_id) on delete cascade; exception when duplicate_object then null; end $$;
do $$ begin alter table orbit_posters add constraint orbit_poster_run_owner_fk foreign key (run_id, user_id) references orbit_runs (id, user_id) on delete cascade; exception when duplicate_object then null; end $$;

alter table orbit_routes enable row level security;
alter table orbit_runs enable row level security;
alter table orbit_segments enable row level security;
alter table orbit_shoes enable row level security;
alter table orbit_posters enable row level security;
alter table orbit_inductions enable row level security;
alter table orbit_campaigns enable row level security;
alter table orbit_campaign_sessions enable row level security;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'orbit_routes', 'orbit_runs', 'orbit_segments', 'orbit_shoes', 'orbit_posters',
    'orbit_inductions', 'orbit_campaigns', 'orbit_campaign_sessions'
  ] loop
    execute format('drop policy if exists owner_all on %I', table_name);
    execute format(
      'create policy owner_all on %I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())',
      table_name
    );
    execute format('revoke all on table %I from anon', table_name);
    execute format('grant select, insert, update, delete on table %I to authenticated', table_name);
  end loop;
end $$;

do $$ begin alter publication supabase_realtime add table orbit_runs; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table orbit_routes; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table orbit_campaigns; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table orbit_campaign_sessions; exception when duplicate_object then null; end $$;

notify pgrst, 'reload schema';
