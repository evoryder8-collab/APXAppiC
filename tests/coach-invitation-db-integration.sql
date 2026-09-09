-- Run as database administrator against the linked project. Everything created
-- here rolls back; no emails are sent and no test seats/invitations survive.
begin;
do $test$
declare
  coach uuid;
  client uuid := gen_random_uuid();
  email text := 'apex-invitation-regression-' || client || '@example.invalid';
  invitation jsonb;
  preview jsonb;
begin
  select c.user_id into coach from public.coach_profiles c
  where c.status in ('development', 'active')
    and (select count(*) from public.coach_relationships r
         where r.coach_user_id=c.user_id and r.seat_state in ('active','grace')) < c.seat_limit
  limit 1;
  if coach is null then raise exception 'Test requires an existing coach'; end if;
  insert into auth.users(id, email) values (client, email);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', coach, 'role', 'authenticated')::text, true);
  invitation := public.coach_create_invitation(email, array['workouts'], false);
  if coalesce(invitation->>'token', '') !~ '^[0-9a-f]{48}$' then raise exception 'Invalid token shape'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', client, 'email', email, 'role', 'authenticated')::text, true);
  preview := public.coach_preview_invitation(invitation->>'token');
  if preview->'requested_scopes' is distinct from '["workouts"]'::jsonb then raise exception 'Scopes changed'; end if;
  perform public.coach_accept_invitation(invitation->>'token', array['workouts'], false);
  if not exists(select 1 from public.coach_relationships
    where coach_user_id=coach and client_user_id=client and status='active'
      and consented_scopes=array['workouts']::text[] and visual_progress_consented_at is null)
  then raise exception 'Accepted relationship is incorrect'; end if;
  begin
    perform public.coach_accept_invitation(invitation->>'token', array['workouts'], false);
    raise exception 'Reused invitation accepted';
  exception when invalid_parameter_value then null;
  end;
end;
$test$;
rollback;
