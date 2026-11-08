-- Run on an isolated migrated Supabase fixture. All synthetic rows and claim changes roll back.
begin;
do $coverage$
declare
  coach uuid := gen_random_uuid();
  client uuid := gen_random_uuid();
  protocol_fixture constant uuid := 'f1cc8158-0480-47c9-a2f1-bd03890182f9';
  rel uuid := gen_random_uuid();
  row_id uuid := gen_random_uuid();
  visible jsonb;
  snap jsonb;
begin
  insert into auth.users(id,email) values (coach,coach || '@example.invalid'), (client,client || '@example.invalid');
  insert into public.profile(id,user_id,display_name) values (client,client,'Fixture');
  insert into public.coach_profiles(user_id,display_name,status) values(coach,'Coach','active');
  insert into public.coach_relationships(id,coach_user_id,client_user_id,offered_scopes,consented_scopes)
    values(rel,coach,client,array['avatar'],array['avatar']);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',coach,'role','authenticated')::text,true);
  insert into public.rpg_snapshots(id,user_id,date,overall,health,joint,flexibility,endurance,strength,strength_upper,strength_lower)
    values(row_id,client,current_date,50.8,60,55,40,45,51,60,42);
  if public.coach_get_client_overview(rel)->'avatar' is distinct from 'null'::jsonb then
    raise exception 'unverified standard baseline was exposed';
  end if;
  select to_jsonb(row_data) - array['id','user_id','verified_avatar'] into snap
    from public.rpg_snapshots row_data where id = row_id;
  update public.rpg_snapshots set verified_avatar = snap where id = row_id;
  if public.coach_get_client_overview(rel)->'avatar' is distinct from snap then
    raise exception 'completed in-scope snapshot did not reach the coach';
  end if;
  update public.rpg_snapshots set overall = 39.8 where id = row_id;
  if public.coach_get_client_overview(rel)->'avatar' is distinct from snap then
    raise exception 'old client overwrote evidence-backed projection';
  end if;
  begin
    update public.rpg_snapshots set verified_avatar = snap || '{"overall":151}'::jsonb where id = row_id;
    raise exception 'out-of-range snapshot accepted';
  exception when check_violation then null;
  end;
  update public.coach_relationships set consented_scopes='{}' where id=rel;
  if public.coach_get_client_overview(rel)->'avatar' is distinct from 'null'::jsonb then
    raise exception 'revoked avatar consent ignored';
  end if;
  update public.coach_relationships set consented_scopes=array['avatar'] where id=rel;
  update public.rpg_snapshots set verified_avatar=null where id=row_id;
  if public.coach_get_client_overview(rel)->'avatar' is distinct from 'null'::jsonb then
    raise exception 'invalidated snapshot survived';
  end if;
  update public.coach_relationships set status='grace', grace_ends_at=now()+interval '1 day' where id=rel;
  begin
    select public.coach_get_client_overview(rel) into visible;
    raise exception 'ended relationship could read overview';
  exception when insufficient_privilege then null;
  end;
  -- Only use the reserved identity when it is absent from this synthetic database.
  if not exists(select 1 from auth.users where id=protocol_fixture) then
    insert into auth.users(id,email) values(protocol_fixture,'bespoke-fixture@example.invalid');
    insert into public.profile(id,user_id,persona,display_name,profile_kind,bespoke_protocol_id)
      values(protocol_fixture,protocol_fixture,'june','Bespoke fixture','bespoke','june-v8.4');
    insert into public.coach_relationships(coach_user_id,client_user_id,offered_scopes,consented_scopes)
      values(coach,protocol_fixture,array['avatar'],array['avatar']) returning id into rel;
    insert into public.rpg_snapshots(id,user_id,date,overall,health,joint,flexibility,endurance,strength,strength_upper,strength_lower)
      values(gen_random_uuid(),protocol_fixture,current_date,59,54,55,56,57,58,59,60);
    if public.coach_get_client_overview(rel)#>>'{avatar,overall}' is distinct from '59' then
      raise exception 'protected authored baseline was hidden';
    end if;
  end if;
end;
$coverage$;
rollback;
