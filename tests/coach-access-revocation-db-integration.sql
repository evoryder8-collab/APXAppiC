-- Disposable database only. Fixtures and changes roll back.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id,email) values ('aaaaaaaa-1111-4111-8111-111111111111','c@example.invalid'),('bbbbbbbb-2222-4222-8222-222222222222','u@example.invalid');
insert into public.profile(id,user_id,weight_kg,display_name) values(gen_random_uuid(),'bbbbbbbb-2222-4222-8222-222222222222',71.5,'Synthetic fixture');
insert into public.coach_profiles(user_id,display_name,status) values('aaaaaaaa-1111-4111-8111-111111111111','Test coach','active');
insert into public.coach_relationships(id,coach_user_id,client_user_id,offered_scopes,consented_scopes) values ('dddddddd-4444-4444-8444-444444444444','aaaaaaaa-1111-4111-8111-111111111111','bbbbbbbb-2222-4222-8222-222222222222',array['measurements','workouts'],array['measurements','workouts']);
set local role authenticated;
select set_config('request.jwt.claim.sub','bbbbbbbb-2222-4222-8222-222222222222',true), set_config('audit.uid','bbbbbbbb-2222-4222-8222-222222222222',true), set_config('request.jwt.claims',json_build_object('sub','bbbbbbbb-2222-4222-8222-222222222222','role','authenticated')::text,true);
select 'client ended access',end_coach_relationship('dddddddd-4444-4444-8444-444444444444');
do $$declare ctx jsonb := coach_get_my_context(); begin
  if ctx#>>'{capabilities,sponsored_client}' is distinct from 'false' or ctx#>>'{sponsorship,relationship_status}' is distinct from 'grace'
    then raise exception 'ending coaching must remove active shortcut and keep archive context'; end if;
end$$;
reset role;
update profile set weight_kg=72.6 where user_id='bbbbbbbb-2222-4222-8222-222222222222';
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-1111-4111-8111-111111111111',true), set_config('audit.uid','aaaaaaaa-1111-4111-8111-111111111111',true), set_config('request.jwt.claims',json_build_object('sub','aaaaaaaa-1111-4111-8111-111111111111','role','authenticated')::text,true);
do $$begin
  begin perform coach_get_client_overview('dddddddd-4444-4444-8444-444444444444');
    raise exception 'unexpected coach read'; exception when insufficient_privilege then null; end;
  begin perform coach_save_plan_draft('dddddddd-4444-4444-8444-444444444444','{}',0);
    raise exception 'unexpected plan write'; exception when insufficient_privilege then null; end;
end$$;
reset role;
update coach_relationships set status='active',seat_state='active' where id='dddddddd-4444-4444-8444-444444444444';
update coach_profiles set status='suspended' where user_id='aaaaaaaa-1111-4111-8111-111111111111';
set local role authenticated;
do $$begin
  begin perform coach_get_client_overview('dddddddd-4444-4444-8444-444444444444');
    raise exception 'unexpected coach read'; exception when insufficient_privilege then null; end;
  begin perform coach_save_plan_draft('dddddddd-4444-4444-8444-444444444444','{}',0);
    raise exception 'unexpected plan write'; exception when insufficient_privilege then null; end;
end$$;
do $$begin
  begin perform delete_my_account('bbbbbbbb-2222-4222-8222-222222222222'); raise exception 'foreign deletion'; exception when insufficient_privilege then null; end;
end$$;
select set_config('request.jwt.claim.sub','bbbbbbbb-2222-4222-8222-222222222222',true), set_config('audit.uid','bbbbbbbb-2222-4222-8222-222222222222',true), set_config('request.jwt.claims',json_build_object('sub','bbbbbbbb-2222-4222-8222-222222222222','role','authenticated')::text,true);
select delete_my_account('bbbbbbbb-2222-4222-8222-222222222222');
reset role;
do $$begin
  if exists(select from auth.users where id='bbbbbbbb-2222-4222-8222-222222222222') or not exists(select from auth.users where id='aaaaaaaa-1111-4111-8111-111111111111') then raise exception 'deletion isolation'; end if;
end$$;
rollback;
