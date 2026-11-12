-- Sets queued by an older client can name an exercise row that never reached the server, or be
-- marked skipped while still carrying auto-counted facts. Both were refused, and those clients
-- retry the same rows forever, so the sets never arrive. Store what is true instead: the set
-- keeps its exercise name and movement, loses the dangling link (what the foreign key itself does
-- when an exercise is deleted), and a skipped set carries no facts, as current clients send it.
create or replace function public.apex_normalize_workout_log() returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.exercise_id is not null
     and not exists (select 1 from public.exercises e where e.id = new.exercise_id) then
    new.exercise_id := null;
  end if;
  if new.skipped then
    new.weight_kg := null; new.reps := null; new.rir := null; new.duration_seconds := null;
    new.distance_meters := null; new.contacts := null; new.rounds := null;
    new.work_seconds := null; new.recovery_seconds := null;
  end if;
  return new;
end;
$$;
revoke all on function public.apex_normalize_workout_log() from public, anon, authenticated;

drop trigger if exists apex_normalize_workout_log on public.workout_logs;
create trigger apex_normalize_workout_log
  before insert or update on public.workout_logs
  for each row execute function public.apex_normalize_workout_log();
