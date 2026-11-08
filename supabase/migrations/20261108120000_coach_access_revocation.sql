-- Keep a client's plan grace period independent of coach access to live data.
create or replace function public.coach_require_workspace()
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $$
declare actor uuid := public.coach_authenticated_user_id();
begin
  perform 1 from public.coach_profiles where user_id = actor and status in ('active','development') for share;
  if not found then raise exception 'coach workspace unavailable' using errcode = '42501'; end if;
  return actor;
end;
$$;
revoke all on function public.coach_require_workspace() from public, anon, authenticated;

create or replace function public.coach_get_roster(p_query text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coach_id uuid := public.coach_require_workspace();
  v_today date := current_date;
  v_result jsonb;
begin
  perform public.coach_release_expired_grace();

  select coalesce(jsonb_agg(item order by sort_attention desc, display_name), '[]'::jsonb)
  into v_result
  from (
    select jsonb_build_object(
      'id', relationship.id,
      'client_user_id', relationship.client_user_id,
      'display_name', coalesce(nullif(btrim(profile.display_name), ''), 'APEX client'),
      'relationship_status', relationship.status,
      'seat_state', relationship.seat_state,
      'consented_scopes', to_jsonb(relationship.consented_scopes),
      'plan_version', plan.version,
      'plan_title', plan.title,
      'review_date', plan.review_date,
      'published_at', plan.published_at,
      'acknowledged_at', acknowledgement.acknowledged_at,
      'activated_at', acknowledgement.activated_at,
      'attention', case
        when relationship.status = 'grace' then jsonb_build_array('seat_grace')
        when plan.id is null then jsonb_build_array('plan_missing')
        else (case when plan.review_date <= v_today + 7 then jsonb_build_array('review_due') else '[]'::jsonb end)
          || (case when acknowledgement.acknowledged_at is null then jsonb_build_array('awaiting_acknowledgement') else '[]'::jsonb end)
      end
    ) item,
    coalesce(nullif(btrim(profile.display_name), ''), 'APEX client') display_name,
    case
      when relationship.status = 'grace' then 3
      when plan.id is null then 2
      when plan.review_date <= v_today + 7 or acknowledgement.acknowledged_at is null then 1
      else 0
    end sort_attention
    from public.coach_relationships relationship
    join public.profile profile on profile.user_id = relationship.client_user_id
    left join public.coach_plan_versions plan
      on plan.relationship_id = relationship.id and plan.status = 'published'
    left join public.coach_plan_acknowledgements acknowledgement
      on acknowledgement.plan_version_id = plan.id
      and acknowledgement.client_user_id = relationship.client_user_id
    where relationship.coach_user_id = v_coach_id
      and relationship.status = 'active'
      and (
        nullif(btrim(coalesce(p_query, '')), '') is null
        or profile.display_name ilike '%' || btrim(p_query) || '%'
      )
  ) roster;
  return v_result;
end;
$$;

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
      select to_jsonb(snapshot) from (
        select date, overall, health, joint, flexibility, endurance, strength, strength_upper, strength_lower
        from public.rpg_snapshots
        where user_id = v_relationship.client_user_id order by date desc limit 1
      ) snapshot
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

create or replace function public.coach_write_plan_version(
  p_relationship_id uuid,
  p_plan jsonb,
  p_expected_version integer,
  p_publish boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coach_id uuid := public.coach_require_workspace();
  v_relationship public.coach_relationships%rowtype;
  v_current integer;
  v_plan public.coach_plan_versions%rowtype;
  v_status text := case when p_publish then 'published' else 'draft' end;
begin
  select * into v_relationship from public.coach_relationships
  where id = p_relationship_id and coach_user_id = v_coach_id and status = 'active' for update;
  if v_relationship.id is null then raise exception 'active client relationship required' using errcode = '42501'; end if;
  select coalesce(max(version), 0) into v_current
  from public.coach_plan_versions where relationship_id = p_relationship_id;
  if coalesce(p_expected_version, -1) <> v_current then
    raise exception 'plan changed on another device' using errcode = '40001';
  end if;
  perform public.coach_validate_plan(p_plan, p_publish);
  if p_publish then
    update public.coach_plan_versions
    set status = 'superseded'
    where relationship_id = p_relationship_id and status = 'published';
  end if;
  insert into public.coach_plan_versions (
    relationship_id, coach_user_id, version, status, title, objective,
    coach_note, review_date, checklist, plan, published_at
  ) values (
    p_relationship_id, v_coach_id, v_current + 1, v_status,
    coalesce(p_plan ->> 'title', ''),
    coalesce(p_plan ->> 'objective', ''),
    coalesce(p_plan ->> 'coach_note', ''),
    nullif(p_plan ->> 'review_date', '')::date,
    coalesce(p_plan -> 'checklist', '{}'::jsonb),
    p_plan,
    case when p_publish then now() else null end
  ) returning * into v_plan;
  insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
  values (v_coach_id, p_relationship_id, case when p_publish then 'plan_published' else 'plan_draft_saved' end,
    jsonb_build_object('plan_version_id', v_plan.id, 'version', v_plan.version));
  return jsonb_build_object(
    'id', v_plan.id,
    'relationship_id', v_plan.relationship_id,
    'version', v_plan.version,
    'status', v_plan.status
  );
end;
$$;

create or replace function public.end_coach_relationship(p_relationship_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.coach_authenticated_user_id();
  v_relationship public.coach_relationships%rowtype;
begin
  select * into v_relationship from public.coach_relationships
  where id = p_relationship_id
    and (coach_user_id = v_actor or client_user_id = v_actor)
    and status = 'active'
  for update;
  if v_relationship.id is null then raise exception 'active coach relationship unavailable' using errcode = '42501'; end if;
  update public.coach_relationships set
    status = 'grace',
    consented_scopes = '{}', visual_progress_consented_at = null,
    seat_state = 'grace',
    grace_ends_at = now() + interval '30 days',
    ended_at = now(),
    updated_at = now()
  where id = v_relationship.id;
  insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
  values (v_actor, v_relationship.id, 'relationship_entered_grace', jsonb_build_object(
    'initiated_by', case when v_actor = v_relationship.coach_user_id then 'coach' else 'client' end,
    'grace_days', 30
  ));
  return true;
end;
$$;

create or replace function public.client_update_coach_scopes(
  p_relationship_id uuid,
  p_scopes text[],
  p_visual_progress_consent boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_client_id uuid := public.coach_authenticated_user_id();
  v_relationship public.coach_relationships%rowtype;
  v_scopes text[];
begin
  select * into v_relationship from public.coach_relationships
  where id = p_relationship_id and client_user_id = v_client_id and status = 'active' for update;
  if v_relationship.id is null then raise exception 'coach relationship unavailable' using errcode = '42501'; end if;
  select coalesce(array_agg(distinct scope order by scope), '{}'::text[])
  into v_scopes from unnest(coalesce(p_scopes, '{}'::text[])) scope
  where scope = any(v_relationship.offered_scopes)
    and (scope <> 'visual_progress' or p_visual_progress_consent);
  if not public.coach_scopes_valid(v_scopes) then raise exception 'unknown consent scope' using errcode = '22023'; end if;
  update public.coach_relationships set
    consented_scopes = v_scopes,
    visual_progress_consented_at = case when 'visual_progress' = any(v_scopes) then now() else null end,
    updated_at = now()
  where id = v_relationship.id;
  insert into public.coach_audit_log(actor_user_id, relationship_id, event_type, metadata)
  values (v_client_id, v_relationship.id, 'consent_scopes_updated', jsonb_build_object(
    'previous_scopes', to_jsonb(v_relationship.consented_scopes),
    'next_scopes', to_jsonb(v_scopes),
    'visual_progress_consent', p_visual_progress_consent
  ));
  return public.coach_get_my_context();
end;
$$;

update public.coach_relationships set consented_scopes = '{}', visual_progress_consented_at = null where status in ('ended','grace') and cardinality(consented_scopes) > 0;
