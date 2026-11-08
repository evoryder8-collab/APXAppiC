alter table public.settings add constraint avatar_manual_domain_scores_valid check (
  not (avatar_health_calibration ? 'scores') or (
    jsonb_typeof(avatar_health_calibration->'scores') = 'object'
    and (avatar_health_calibration->'scores') - array['joint','flexibility','endurance'] = '{}'::jsonb
    and not jsonb_path_exists(avatar_health_calibration->'scores',
      '$.* ? (@.type() != "number" || @ < 0 || @ > 100)')
  )
);

-- A Health-only iOS build re-encodes this object on unrelated settings edits.
create function public.preserve_manual_avatar_domains() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if old.avatar_health_calibration ? 'scores'
     and not (new.avatar_health_calibration ? 'scores')
     and new.avatar_health_calibration->>'date' = old.avatar_health_calibration->>'date' then
    new.avatar_health_calibration := new.avatar_health_calibration
      || jsonb_build_object('scores', old.avatar_health_calibration->'scores');
  end if;
  return new;
end;
$$;
revoke all on function public.preserve_manual_avatar_domains() from public, anon, authenticated;
create trigger preserve_manual_avatar_domains before update of avatar_health_calibration on public.settings
  for each row execute function public.preserve_manual_avatar_domains();

create or replace function public.apply_manual_avatar_health_calibration() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  calibration jsonb;
  scores jsonb;
  raw_snapshot jsonb;
  raw_delta numeric;
  verified_delta numeric;
begin
  select s.avatar_health_calibration into calibration
  from public.settings s join public.profile p using (user_id)
  where s.user_id = new.user_id and p.profile_kind = 'bespoke'
    and s.avatar_health_calibration->>'date' = new.date::text;
  if calibration is null then return new; end if;

  raw_snapshot := to_jsonb(new);
  scores := coalesce(calibration->'scores', '{}'::jsonb) || jsonb_build_object('health', calibration->'score');
  select sum(weight * ((scores->>domain)::numeric - (raw_snapshot->>domain)::numeric)),
         sum(weight * ((scores->>domain)::numeric - (new.verified_avatar->>domain)::numeric))
    into raw_delta, verified_delta
  from (values ('health',0.20),('joint',0.20),('flexibility',0.15),('endurance',0.20)) as weights(domain,weight)
  where scores ? domain;

  new := jsonb_populate_record(new, scores || jsonb_build_object('overall', round(new.overall + raw_delta, 1)));
  if new.verified_avatar is not null then
    new.verified_avatar := new.verified_avatar || scores || jsonb_build_object('overall',
      round((new.verified_avatar->>'overall')::numeric + verified_delta, 1));
  end if;
  return new;
end;
$$;
comment on column public.settings.avatar_health_calibration is
  'Dated manual Health score and optional joint, flexibility and endurance scores for an authored Avatar. Later days evolve normally.';
