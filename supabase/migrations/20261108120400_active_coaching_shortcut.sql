-- Grace retains the last plan. Only an active seat represents current coaching.
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
      'sponsored_client', coalesce(v_sponsorship->>'relationship_status' = 'active' and v_sponsorship->>'seat_state' = 'active', false)
    )
  );
end;
$$;
