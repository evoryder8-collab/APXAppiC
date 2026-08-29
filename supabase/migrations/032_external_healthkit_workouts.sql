-- Account-owned, read-only receipts for workouts whose source of truth remains
-- Apple Health. APEX never deletes the originating HKWorkout.
alter table public.imported_activities
  add column if not exists healthkit_workout_id uuid,
  add column if not exists started_at timestamptz,
  add column if not exists ended_at timestamptz,
  add column if not exists workout_name_key text,
  add column if not exists distance_km double precision,
  add column if not exists active_energy_kcal double precision,
  add column if not exists source_bundle_id text,
  add column if not exists activity_type_raw bigint,
  add column if not exists apex_workout_session_id uuid,
  add column if not exists hidden_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'imported_activities_owner_healthkit_workout_key'
      and conrelid = 'public.imported_activities'::regclass
  ) then
    alter table public.imported_activities
      add constraint imported_activities_owner_healthkit_workout_key
      unique (user_id, healthkit_workout_id);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'imported_activities_external_metrics_nonnegative'
      and conrelid = 'public.imported_activities'::regclass
  ) then
    alter table public.imported_activities
      add constraint imported_activities_external_metrics_nonnegative
      check (
        (distance_km is null or distance_km >= 0)
        and (active_energy_kcal is null or active_energy_kcal >= 0)
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'imported_activities_external_time_order'
      and conrelid = 'public.imported_activities'::regclass
  ) then
    alter table public.imported_activities
      add constraint imported_activities_external_time_order
      check (started_at is null or ended_at is null or ended_at >= started_at);
  end if;
end $$;

create index if not exists idx_imported_activities_owner_started
  on public.imported_activities (user_id, started_at desc)
  where healthkit_workout_id is not null and hidden_at is null;

comment on column public.imported_activities.healthkit_workout_id is
  'Stable HKWorkout UUID used for owner-scoped deduplication; the HealthKit object remains the source of truth.';
comment on column public.imported_activities.hidden_at is
  'When set, hides the receipt from APEX without deleting the original workout from Apple Health.';
