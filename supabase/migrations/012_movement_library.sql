-- The movement library: canonical exercises the plan generator selects from.
--
-- The existing `exercises` table holds programme rows, one per exercise per
-- programme day, with instructions fused into the name: "Pull-Ups (different
-- grip than Wed)", "Bulgarian Split Squat (backpack)". That is correct for an
-- authored programme and useless for a generator, which needs to ask things
-- like "a hip-dominant movement, loadable with dumbbells, that can be failed
-- safely without a spotter, in under four minutes including setup".
--
-- So this table holds the movement, and only the movement. Programme rows keep
-- their own names, sets, reps and notes and reference a movement by id.

create table if not exists public.movement_library (
  id text primary key,
  name text not null,
  -- What the movement is for. The generator fills a session by pattern first
  -- and only then chooses a specific movement inside it.
  pattern text not null check (pattern in (
    'hip_hinge','squat','lunge','horizontal_push','vertical_push',
    'horizontal_pull','vertical_pull','carry','core_anti_extension',
    'core_anti_rotation','core_flexion','isolation_upper','isolation_lower',
    'calf','conditioning','plyometric','mobility','skill','yoga_pose'
  )),
  -- A movement can belong to several worlds at once: a pistol squat is both
  -- calisthenics and a squat pattern, a kettlebell swing is both conditioning
  -- and a hinge. The generator filters by discipline when a user asks for a
  -- style, and ignores it when they only asked for a result.
  disciplines text[] not null default '{strength}',
  primary_muscles text[] not null default '{}',
  secondary_muscles text[] not null default '{}',
  -- Every item must be available for the movement to be selectable.
  equipment text[] not null default '{}',
  -- 1 trivial to 5 requires real coaching.
  skill smallint not null check (skill between 1 and 5),
  -- How much balance or bracing limits the load rather than the target muscle.
  stability_demand smallint not null check (stability_demand between 1 and 5),
  -- Can a set be taken to failure alone, without dumping a bar on yourself.
  can_fail_safely boolean not null,
  needs_spotter boolean not null default false,
  needs_safeties boolean not null default false,
  unilateral boolean not null default false,
  -- Setup time in seconds, which the honest session-duration maths needs.
  setup_seconds smallint not null default 30,
  rep_unit text not null default 'reps',
  rep_low smallint,
  rep_high smallint,
  loadable boolean not null default true,
  min_increment_kg numeric,
  -- Systemic cost, 1 trivial to 5 leaves you on the floor. Used to avoid
  -- stacking two brutal movements in one short session.
  fatigue_cost smallint not null check (fatigue_cost between 1 and 5),
  -- Movement restrictions this exercise runs into, so a body-map answer
  -- excludes patterns rather than whole regions.
  contraindications text[] not null default '{}',
  -- Ordered fallbacks, best first, used when equipment or symptoms rule it out.
  substitutions text[] not null default '{}',
  -- Suitable for 16 to 18 under the adolescent rails.
  youth_safe boolean not null default true,
  glute_emphasis boolean not null default false,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists movement_library_pattern_idx on public.movement_library (pattern);
create index if not exists movement_library_equipment_idx on public.movement_library using gin (equipment);
create index if not exists movement_library_discipline_idx on public.movement_library using gin (disciplines);

-- Maps the programme names already in use onto canonical movements, so
-- existing history and the generator speak about the same thing.
create table if not exists public.movement_aliases (
  alias text primary key,
  movement_id text not null references public.movement_library(id) on delete cascade
);

alter table public.exercises
  add column if not exists movement_id text references public.movement_library(id);

alter table public.movement_library enable row level security;
alter table public.movement_aliases enable row level security;

-- The library is shared reference data: readable by any signed-in user,
-- writable by nobody through the API.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'movement_library' and policyname = 'movement_library_read') then
    create policy movement_library_read on public.movement_library
      for select to authenticated using (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'movement_aliases' and policyname = 'movement_aliases_read') then
    create policy movement_aliases_read on public.movement_aliases
      for select to authenticated using (true);
  end if;
end $$;

grant select on public.movement_library to authenticated;
grant select on public.movement_aliases to authenticated;

notify pgrst, 'reload schema';
