-- Derive Overall from the published components so replaying an older, rounded
-- composite cannot introduce a second rounding step on the calibration date.
create or replace function public.apply_manual_avatar_health_calibration() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare
  calibration jsonb;
  scores jsonb;
  raw_snapshot jsonb;
  verified_snapshot jsonb;
  raw_overall numeric;
  verified_overall numeric;
begin
  select s.avatar_health_calibration into calibration
  from public.settings s join public.profile p using (user_id)
  where s.user_id = new.user_id and p.profile_kind = 'bespoke'
    and s.avatar_health_calibration->>'date' = new.date::text;
  if calibration is null then return new; end if;

  scores := coalesce(calibration->'scores', '{}'::jsonb) || jsonb_build_object('health', calibration->'score');
  raw_snapshot := to_jsonb(new) || scores;
  verified_snapshot := new.verified_avatar || scores;
  select round(sum(weight * (raw_snapshot->>domain)::numeric), 1),
         round(sum(weight * (verified_snapshot->>domain)::numeric), 1)
    into raw_overall, verified_overall
  from (values ('health',0.20),('joint',0.20),('flexibility',0.15),('endurance',0.20),
               ('strength_upper',0.125),('strength_lower',0.125)) as weights(domain,weight);
  new := jsonb_populate_record(new, scores || jsonb_build_object('overall', raw_overall));
  if verified_snapshot is not null then
    new.verified_avatar := verified_snapshot || jsonb_build_object('overall', verified_overall);
  end if;
  return new;
end;
$$;
