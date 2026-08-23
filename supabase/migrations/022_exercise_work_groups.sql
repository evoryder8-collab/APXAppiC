-- One generic linked-work membership for supersets now and circuits later.
-- `sets` remains the number of rounds in which a member participates, and
-- workout_logs.set_no remains the completed round. No parallel history shape.

alter table public.exercises
  add column if not exists work_group_id uuid,
  add column if not exists work_group_position integer;

do $$
begin
  alter table public.exercises
    add constraint exercises_work_group_membership_complete
    check (
      (work_group_id is null and work_group_position is null)
      or
      (work_group_id is not null and work_group_position > 0)
    );
exception
  when duplicate_object then null;
end
$$;

create unique index if not exists exercises_work_group_position_unique
  on public.exercises (user_id, program_day_id, is_lite, work_group_id, work_group_position)
  where work_group_id is not null;

comment on column public.exercises.work_group_id is
  'Generic linked-work group. Two members form a superset; larger groups reuse the same round model.';
comment on column public.exercises.work_group_position is
  'One-based member order inside work_group_id. workout_logs.set_no is the round.';
