-- Independent of addons so queued preference writes from older clients preserve it.
alter table public.settings add column avatar_health_calibration jsonb
  check (avatar_health_calibration is null or (
    jsonb_typeof(avatar_health_calibration) = 'object'
    and avatar_health_calibration ?& array['source','date','score']
    and avatar_health_calibration->'source' = '"manual"'::jsonb
    and jsonb_typeof(avatar_health_calibration->'date') = 'string'
    and (avatar_health_calibration->>'date')::date::text = avatar_health_calibration->>'date'
    and jsonb_typeof(avatar_health_calibration->'score') = 'number'
    and (avatar_health_calibration->>'score')::numeric between 0 and 100
  ));
comment on column public.settings.avatar_health_calibration is
  'Manual end-of-day game score for an authored Avatar. Later days evolve from this score.';

-- Earlier apps can still publish their local pre-calibration score for this same day.
create function public.apply_manual_avatar_health_calibration() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  calibrated numeric;
begin
  select (s.avatar_health_calibration->>'score')::numeric into calibrated
  from public.settings s join public.profile p using (user_id)
  where s.user_id = new.user_id and p.profile_kind = 'bespoke'
    and s.avatar_health_calibration->>'date' = new.date::text;
  if calibrated is null then return new; end if;

  new.overall := round(new.overall + (calibrated - new.health) * 0.2, 1);
  new.health := calibrated;
  if new.verified_avatar is not null then
    new.verified_avatar := new.verified_avatar || jsonb_build_object(
      'health', calibrated,
      'overall', round((new.verified_avatar->>'overall')::numeric
        + (calibrated - (new.verified_avatar->>'health')::numeric) * 0.2, 1)
    );
  end if;
  return new;
end;
$$;
revoke all on function public.apply_manual_avatar_health_calibration() from public, anon, authenticated;
create trigger apply_manual_avatar_health_calibration before insert or update on public.rpg_snapshots
  for each row execute function public.apply_manual_avatar_health_calibration();
