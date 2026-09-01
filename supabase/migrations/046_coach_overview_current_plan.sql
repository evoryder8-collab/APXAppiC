-- A coach must be able to reopen the last version before producing the next
-- one.  Returning the immutable version through the already consent-gated
-- overview prevents blind overwrite and keeps the version check meaningful.

create or replace function public.coach_get_client_overview(p_relationship_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_coach_id uuid := public.coach_authenticated_user_id();
  v_relationship public.coach_relationships%rowtype;
  v_profile public.profile%rowtype;
  v_current_plan jsonb;
  v_result jsonb;
begin
  select * into v_relationship from public.coach_relationships
  where id = p_relationship_id and coach_user_id = v_coach_id and status in ('active', 'grace');
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

revoke all on function public.coach_get_client_overview(uuid) from public;
grant execute on function public.coach_get_client_overview(uuid) to authenticated;

create or replace function public.coach_preview_invitation(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
  v_invitation public.coach_invitations%rowtype;
  v_coach_name text;
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{48}$' then
    raise exception 'invitation is invalid' using errcode = '22023';
  end if;
  select * into v_invitation from public.coach_invitations
  where token_hash = encode(digest(p_token, 'sha256'), 'hex');
  if v_invitation.id is null or v_invitation.status <> 'pending' or v_invitation.expires_at <= now() then
    raise exception 'invitation is unavailable' using errcode = '22023';
  end if;
  if v_email = '' or v_email <> v_invitation.invitee_email then
    raise exception 'sign in with the invited email address' using errcode = '42501';
  end if;
  select coalesce(nullif(btrim(display_name), ''), 'APEX coach') into v_coach_name
  from public.coach_profiles where user_id = v_invitation.coach_user_id;
  return jsonb_build_object(
    'coach_display_name', v_coach_name,
    'requested_scopes', to_jsonb(v_invitation.requested_scopes),
    'visual_progress_requested', v_invitation.visual_progress_requested,
    'expires_at', v_invitation.expires_at
  );
end;
$$;

revoke all on function public.coach_preview_invitation(text) from public;
grant execute on function public.coach_preview_invitation(text) to authenticated;

-- Include the complete offered boundary so a client can later re-enable a
-- category they initially declined without the coach issuing a new invite.
create or replace function public.coach_get_my_context()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := public.coach_authenticated_user_id();
  v_coach jsonb;
  v_sponsorship jsonb;
  v_current_plan jsonb;
  v_relationship_id uuid;
begin
  perform public.coach_release_expired_grace();
  select jsonb_build_object(
    'status', coach.status,
    'display_name', coach.display_name,
    'seat_limit', coach.seat_limit,
    'active_seats', (
      select count(*) from public.coach_relationships relationship
      where relationship.coach_user_id = coach.user_id and relationship.seat_state in ('active', 'grace')
    )
  ) into v_coach
  from public.coach_profiles coach
  where coach.user_id = v_user_id and coach.status in ('development', 'active');

  select relationship.id,
    jsonb_build_object(
      'relationship_id', relationship.id,
      'coach_display_name', coach.display_name,
      'relationship_status', relationship.status,
      'seat_state', relationship.seat_state,
      'offered_scopes', to_jsonb(relationship.offered_scopes),
      'consented_scopes', to_jsonb(relationship.consented_scopes),
      'grace_ends_at', relationship.grace_ends_at
    )
  into v_relationship_id, v_sponsorship
  from public.coach_relationships relationship
  join public.coach_profiles coach on coach.user_id = relationship.coach_user_id
  where relationship.client_user_id = v_user_id and relationship.status in ('active', 'grace')
  order by relationship.updated_at desc
  limit 1;

  if v_relationship_id is not null then
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
      'activated_at', acknowledgement.activated_at
    ) into v_current_plan
    from public.coach_plan_versions plan
    left join public.coach_plan_acknowledgements acknowledgement
      on acknowledgement.plan_version_id = plan.id and acknowledgement.client_user_id = v_user_id
    where plan.relationship_id = v_relationship_id and plan.status = 'published'
    order by plan.version desc
    limit 1;
  end if;

  return jsonb_build_object(
    'coach', v_coach,
    'sponsorship', v_sponsorship,
    'current_plan', v_current_plan,
    'capabilities', jsonb_build_object(
      'coach_workspace', v_coach is not null,
      'sponsored_client', v_sponsorship is not null
    )
  );
end;
$$;

revoke all on function public.coach_get_my_context() from public;
grant execute on function public.coach_get_my_context() to authenticated;
