-- Store only observations made during a set. The client resolves the movement
-- kind from movement_id (or the authored name for legacy rows) when reading.
-- weight_kg is deliberately signed: negative is supported load, zero is
-- bodyweight, and positive is added or external load.

alter table public.workout_logs
  add column if not exists movement_id text,
  add column if not exists duration_seconds integer,
  add column if not exists distance_meters numeric,
  add column if not exists contacts integer,
  add column if not exists rounds integer,
  add column if not exists work_seconds integer,
  add column if not exists recovery_seconds integer;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'workout_logs_duration_seconds_nonnegative') then
    alter table public.workout_logs add constraint workout_logs_duration_seconds_nonnegative
      check (duration_seconds is null or duration_seconds >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'workout_logs_distance_meters_nonnegative') then
    alter table public.workout_logs add constraint workout_logs_distance_meters_nonnegative
      check (distance_meters is null or distance_meters >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'workout_logs_contacts_nonnegative') then
    alter table public.workout_logs add constraint workout_logs_contacts_nonnegative
      check (contacts is null or contacts >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'workout_logs_rounds_nonnegative') then
    alter table public.workout_logs add constraint workout_logs_rounds_nonnegative
      check (rounds is null or rounds >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'workout_logs_work_seconds_nonnegative') then
    alter table public.workout_logs add constraint workout_logs_work_seconds_nonnegative
      check (work_seconds is null or work_seconds >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'workout_logs_recovery_seconds_nonnegative') then
    alter table public.workout_logs add constraint workout_logs_recovery_seconds_nonnegative
      check (recovery_seconds is null or recovery_seconds >= 0) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'workout_logs_skipped_facts_empty') then
    alter table public.workout_logs add constraint workout_logs_skipped_facts_empty
      check (
        skipped = false or (
          weight_kg is null and reps is null and rir is null
          and duration_seconds is null and distance_meters is null
          and contacts is null and rounds is null
          and work_seconds is null and recovery_seconds is null
        )
      ) not valid;
  end if;
end
$$;

create index if not exists idx_workout_logs_movement_history
  on public.workout_logs (user_id, movement_id, created_at desc)
  where movement_id is not null;
