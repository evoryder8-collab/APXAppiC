-- Exact-date, account-owned recovery add-ons. Existing programme rows remain
-- weekly and unchanged; a scheduled row is eligible only on its own date.
alter table public.program_days
  add column if not exists scheduled_date date,
  add column if not exists recovery_plan_id uuid,
  add column if not exists recovery_target text,
  add column if not exists recovery_source text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'program_days_recovery_metadata_check'
  ) then
    alter table public.program_days
      add constraint program_days_recovery_metadata_check check (
        (
          scheduled_date is null
          and recovery_plan_id is null
          and recovery_target is null
          and recovery_source is null
        )
        or
        (
          scheduled_date is not null
          and recovery_plan_id is not null
          and recovery_target in ('joint', 'flexibility')
          and recovery_source in ('guided', 'external')
          and day_type = 'mobility'
        )
      );
  end if;
end
$$;

create index if not exists program_days_user_scheduled_date_idx
  on public.program_days (user_id, scheduled_date, sort_order)
  where scheduled_date is not null and is_active;

comment on column public.program_days.scheduled_date is
  'Exact local calendar date for an additive recovery session; null rows retain weekly recurrence.';
comment on column public.program_days.recovery_plan_id is
  'Client-generated group identifier used to replace only future recovery add-ons without touching programme history.';
