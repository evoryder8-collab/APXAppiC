-- A Health-only preferences sync may also carry an older Health value for this date.
create or replace function public.preserve_manual_avatar_domains() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if old.avatar_health_calibration ? 'scores'
     and not (new.avatar_health_calibration ? 'scores')
     and new.avatar_health_calibration->>'date' = old.avatar_health_calibration->>'date' then
    new.avatar_health_calibration := old.avatar_health_calibration;
  end if;
  return new;
end;
$$;
