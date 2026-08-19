-- Restructures the movement library after review.
--
-- The first version made four structural mistakes. It stored one `pattern` per
-- movement, so a thruster counted as a squat and its overhead press vanished
-- from the volume maths. It fused cardio machines with cardio prescriptions, so
-- "Stationary Bike, Zone 2" was one row and a user who owned a rower lost the
-- zone 2 session entirely -- the same fusion this project already removed from
-- the `exercises` table. It hid logical ORs inside equipment strings, so
-- `cable_stack_or_bands` matched neither a cable stack nor a band. And it set a
-- youth flag by hand on every row, which produced 274 opinions rather than one
-- rule: the front squat was barred and the back squat was not.
--
-- This migration is additive. Existing columns keep their meaning and nothing is
-- dropped, so the web app continues to read the table exactly as it does today.

-- A thruster is a squat and a vertical push. Counting it as one of them
-- undercounts the other, which is how a "balanced" week quietly stops being one.
alter table public.movement_library
  add column if not exists secondary_patterns text[] not null default '{}',
  -- Muscles that hold the position without producing the movement. Credited at
  -- zero toward volume, but they are why a movement fatigues where it does.
  add column if not exists stabilizer_muscles text[] not null default '{}',
  -- What kind of thing this is, which decides how it can be prescribed at all.
  add column if not exists entity_type text not null default 'resistance_dynamic',
  add column if not exists prescription_schema text not null default 'sets_reps_load',
  -- Requirements the array type could not express: groups where any one item does.
  add column if not exists equipment_any_of jsonb not null default '[]'::jsonb,
  -- Failing alone is conditional. A back squat in a rack with the safeties set
  -- is not the same proposition as one in open space.
  add column if not exists fail_safe_conditions text[] not null default '{}',
  add column if not exists technical_complexity smallint,
  add column if not exists is_ballistic boolean not null default false,
  add column if not exists impact_level text not null default 'none',
  add column if not exists is_overhead boolean not null default false,
  add column if not exists is_axial_load boolean not null default false,
  add column if not exists requires_bail_skill boolean not null default false,
  add column if not exists prerequisites text[] not null default '{}',
  -- Same movement, different kit. Replaces the duplicate rows that made the
  -- substitution graph offer the reverse pec deck as an alternative to the
  -- machine rear delt fly, which is the same machine.
  add column if not exists family text,
  add column if not exists variant text,
  add column if not exists implementations jsonb not null default '[]'::jsonb,
  -- Ordered steps, for the sequences that were previously a single vague row.
  add column if not exists sequence_steps text[] not null default '{}',
  -- Eligibility derived from the properties above, never hand-set.
  add column if not exists youth_auto_assignable boolean not null default true,
  add column if not exists adult_auto_assignable boolean not null default true,
  add column if not exists coached_only boolean not null default false,
  -- Under-18s are never given maximal singles, whatever the movement.
  add column if not exists youth_rep_floor smallint,
  add column if not exists space_requirement text not null default 'minimal',
  -- Nothing is auto-assigned by the generator until it has been reviewed.
  add column if not exists review_status text not null default 'draft';

alter table public.movement_library
  drop constraint if exists movement_library_pattern_check;

-- Balance is a trainable capability with its own dose response, and it was
-- missing entirely. Anti-lateral-flexion is the fourth core category, and the
-- side plank was filed under anti-rotation for want of it.
alter table public.movement_library
  add constraint movement_library_pattern_check check (pattern in (
    'hip_hinge','squat','lunge','horizontal_push','vertical_push',
    'horizontal_pull','vertical_pull','carry','balance',
    'core_anti_extension','core_anti_rotation','core_anti_lateral_flexion',
    'core_flexion','isolation_upper','isolation_lower','calf','conditioning',
    'plyometric','mobility','skill','yoga_pose'
  ));

alter table public.movement_library
  add constraint movement_library_entity_type_check check (entity_type in (
    'resistance_dynamic','resistance_isometric','plyometric','power_throw',
    'conditioning_complex','skill_drill','mobility_drill','yoga_pose',
    'movement_sequence','breathing_recovery','balance_drill','cardio_modality'
  )),
  add constraint movement_library_impact_check
    check (impact_level in ('none','low','moderate','high')),
  add constraint movement_library_review_check
    check (review_status in ('draft','internally_reviewed','expert_reviewed'));

-- Cardio is a modality and a prescription, not one fused record. Nine
-- modalities times seven prescriptions would have been 63 rows nobody maintains,
-- and a user with a rower but no bike would still lose the zone 2 session.
create table if not exists public.cardio_modalities (
  id text primary key,
  name text not null,
  equipment text[] not null default '{}',
  impact_level text not null default 'none'
    check (impact_level in ('none','low','moderate','high')),
  skill smallint not null default 1,
  -- How the work divides, so a rowing session is not stacked onto a heavy pull day.
  upper_share numeric not null default 0,
  lower_share numeric not null default 1,
  -- Which intensity bands this modality can actually deliver. Outdoor cycling
  -- cannot hold a true interval through traffic lights.
  supports_zones text[] not null default '{}',
  warmup_seconds smallint not null default 180,
  contraindications text[] not null default '{}',
  outdoor boolean not null default false,
  measures text[] not null default '{}',
  -- Concurrent-training interference with lower-body hypertrophy: cycling is the
  -- low-interference choice, running the high one.
  leg_interference numeric not null default 1.0,
  notes text not null default ''
);

create table if not exists public.cardio_prescriptions (
  id text primary key,
  name text not null,
  zone text not null check (zone in ('z1','z2','tempo','threshold','vo2','sprint')),
  structure text not null check (structure in ('steady','intervals','variable','transition')),
  duration_low smallint not null,
  duration_high smallint not null,
  unit text not null default 'minutes',
  work_seconds smallint,
  rest_seconds smallint,
  rounds_low smallint,
  rounds_high smallint,
  rpe smallint,
  skill smallint not null default 1,
  fatigue_cost smallint not null default 2,
  -- A ceiling per week that no training goal overrides.
  weekly_cap smallint,
  -- Aerobic base required before this is prescribed at all.
  prereq_base_weeks smallint not null default 0,
  adaptations text[] not null default '{}',
  notes text not null default ''
);

-- Programme names already in use, resolved to the pair they always meant.
create table if not exists public.cardio_aliases (
  alias text primary key,
  modality_id text not null references public.cardio_modalities(id) on delete cascade,
  prescription_id text not null references public.cardio_prescriptions(id) on delete cascade
);

create index if not exists movement_library_entity_idx
  on public.movement_library (entity_type);
create index if not exists movement_library_family_idx
  on public.movement_library (family);
create index if not exists movement_library_secondary_pattern_idx
  on public.movement_library using gin (secondary_patterns);

alter table public.cardio_modalities enable row level security;
alter table public.cardio_prescriptions enable row level security;
alter table public.cardio_aliases enable row level security;

do $$
declare t text;
begin
  foreach t in array array['cardio_modalities','cardio_prescriptions','cardio_aliases'] loop
    if not exists (select 1 from pg_policies where tablename = t and policyname = t || '_read') then
      execute format(
        'create policy %I on public.%I for select to authenticated using (true)',
        t || '_read', t);
    end if;
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

notify pgrst, 'reload schema';
