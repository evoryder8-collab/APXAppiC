-- Old clients still write the legacy numeric columns. Keep their updates separate
-- from the scored values a coverage-aware client explicitly published for a coach.
alter table public.rpg_snapshots add column if not exists verified_avatar jsonb;
comment on column public.rpg_snapshots.verified_avatar is
  'Client-observed training scores after all six domains have evidence; null means building a baseline.';

alter table public.rpg_snapshots drop constraint if exists rpg_verified_avatar_shape;
alter table public.rpg_snapshots add constraint rpg_verified_avatar_shape check (
  verified_avatar is null or (
    jsonb_typeof(verified_avatar) = 'object'
    and verified_avatar ?& array['date','overall','health','joint','flexibility','endurance','strength','strength_upper','strength_lower']
    and verified_avatar - array['date','overall','health','joint','flexibility','endurance','strength','strength_upper','strength_lower'] = '{}'::jsonb
    and verified_avatar->>'date' = date::text
    and jsonb_path_exists(verified_avatar, '$.* ? (@.type() == "number" && (@ < 0 || @ > 100))') = false
    and jsonb_typeof(verified_avatar->'date') = 'string'
    and jsonb_typeof(verified_avatar->'overall') = 'number'
    and jsonb_typeof(verified_avatar->'health') = 'number'
    and jsonb_typeof(verified_avatar->'joint') = 'number'
    and jsonb_typeof(verified_avatar->'flexibility') = 'number'
    and jsonb_typeof(verified_avatar->'endurance') = 'number'
    and jsonb_typeof(verified_avatar->'strength') = 'number'
    and jsonb_typeof(verified_avatar->'strength_upper') = 'number'
    and jsonb_typeof(verified_avatar->'strength_lower') = 'number'
  )
);

create or replace function public.coach_get_client_overview(p_relationship_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coach_id uuid := public.coach_require_workspace();
  v_relationship public.coach_relationships%rowtype;
  v_profile public.profile%rowtype;
  v_current_plan jsonb;
  v_result jsonb;
begin
  select * into v_relationship from public.coach_relationships
  where id = p_relationship_id and coach_user_id = v_coach_id and status = 'active' for share;
  if v_relationship.id is null then raise exception 'client relationship unavailable' using errcode = '42501'; end if;
  select * into v_profile from public.profile where user_id = v_relationship.client_user_id;

  select jsonb_build_object(
    'id', plan.id,
    'relationship_id', plan.relationship_id,
    'version', plan.version,
    'status', plan.status,
    'title', plan.title,
    'objective', plan.objective,
    'coach_note', plan.coach_note,
    'review_date', plan.review_date,
    'checklist', plan.checklist,
    'plan', plan.plan,
    'published_at', plan.published_at,
    'acknowledged_at', acknowledgement.acknowledged_at,
    'activated_at', installation.activated_at
  ) into v_current_plan
  from public.coach_plan_versions plan
  left join public.coach_plan_acknowledgements acknowledgement on acknowledgement.plan_version_id = plan.id
  left join public.coach_plan_installations installation on installation.plan_version_id = plan.id
  where plan.relationship_id = v_relationship.id
  order by plan.version desc
  limit 1;

  v_result := jsonb_build_object(
    'relationship_id', v_relationship.id,
    'client_user_id', v_relationship.client_user_id,
    'display_name', coalesce(nullif(btrim(v_profile.display_name), ''), 'APEX client'),
    'relationship_status', v_relationship.status,
    'seat_state', v_relationship.seat_state,
    'consented_scopes', to_jsonb(v_relationship.consented_scopes),
    'measurements', case when 'measurements' = any(v_relationship.consented_scopes) then jsonb_build_object(
      'sex', v_profile.sex,
      'height_cm', v_profile.height_cm,
      'weight_kg', v_profile.weight_kg,
      'body_fat_pct', v_profile.body_fat_pct,
      'birthdate', v_profile.birthdate
    ) else null end,
    'avatar', case when 'avatar' = any(v_relationship.consented_scopes) then (
      select case
        when current_row.verified_avatar is not null then current_row.verified_avatar
        when v_profile.profile_kind = 'bespoke' and v_profile.bespoke_protocol_id is not null then
          to_jsonb(current_row) - 'verified_avatar'
        else null end
      from (
        select date, overall, health, joint, flexibility, endurance, strength, strength_upper, strength_lower, verified_avatar
        from public.rpg_snapshots
        where user_id = v_relationship.client_user_id
        order by date desc limit 1
      ) current_row
    ) else null end,
    'workouts', case when 'workouts' = any(v_relationship.consented_scopes) then jsonb_build_object(
      'completed_30d', (select count(*) from public.workout_sessions
        where user_id = v_relationship.client_user_id and completed and date >= current_date - 29),
      'last_completed_at', (select max(completed_at) from public.workout_sessions
        where user_id = v_relationship.client_user_id and completed)
    ) else null end,
    'nutrition', case when 'nutrition' = any(v_relationship.consented_scopes) then (
      select jsonb_build_object('days_observed', count(*), 'average_kcal', round(avg(kcal)))
      from public.daily_logs where user_id = v_relationship.client_user_id and date >= current_date - 6 and kcal is not null
    ) else null end,
    'hydration', case when 'hydration' = any(v_relationship.consented_scopes) then (
      select jsonb_build_object('days_observed', count(*), 'average_litres', round(avg(water_l)::numeric, 2))
      from public.daily_logs where user_id = v_relationship.client_user_id and date >= current_date - 6
    ) else null end,
    'visual_progress_shared', 'visual_progress' = any(v_relationship.consented_scopes),
    'current_plan', v_current_plan
  );
  return v_result;
end;
$$;

notify pgrst, 'reload schema';
