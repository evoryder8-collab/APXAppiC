alter table public.profile add column avatar_starting_points jsonb;

-- Preserve a saved allocation when an offline client syncs an older profile.
create function public.validate_avatar_starting_points() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  points jsonb := new.avatar_starting_points;
  stat text;
  value numeric;
  total numeric := 0;
  stats constant text[] := array['health','joint','flexibility','endurance','strength_upper','strength_lower'];
begin
  if tg_op = 'UPDATE' and old.avatar_starting_points is not null then
    if points is not null and points <> old.avatar_starting_points then
      raise exception 'Avatar starting points have already been saved.' using errcode = '23514';
    end if;
    new.avatar_starting_points := old.avatar_starting_points;
    return new;
  end if;
  if points is null then return new; end if;
  if jsonb_typeof(points) <> 'object' or not (points ?& stats) or points - stats <> '{}'::jsonb then
    raise exception 'Provide all six Avatar stats.' using errcode = '23514';
  end if;
  foreach stat in array stats loop
    if jsonb_typeof(points->stat) <> 'number' then
      raise exception 'Starting points must be whole numbers.' using errcode = '23514';
    end if;
    value := (points->>stat)::numeric;
    if value <> trunc(value) or value not between 0 and 100 then
      raise exception 'Each Avatar stat must be a whole number from 0 to 100.' using errcode = '23514';
    end if;
    total := total + value;
  end loop;
  if total <> 300 then
    raise exception 'Allocate exactly 300 starting points.' using errcode = '23514';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_avatar_starting_points() from public, anon, authenticated;
create trigger validate_avatar_starting_points before insert or update of avatar_starting_points
  on public.profile for each row execute function public.validate_avatar_starting_points();
