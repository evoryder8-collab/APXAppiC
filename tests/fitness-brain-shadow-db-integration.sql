\set ON_ERROR_STOP on

begin;

create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema auth;

create table auth.users (
  id uuid primary key
);

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

create table public.profile (
  id uuid primary key,
  user_id uuid not null unique references auth.users (id) on delete cascade,
  sex text not null,
  birthdate date not null,
  profile_kind text not null
);

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into public.profile (id, user_id, sex, birthdate, profile_kind) values
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    '11111111-1111-4111-8111-111111111111',
    'female',
    '1986-04-12',
    'bespoke'
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    '22222222-2222-4222-8222-222222222222',
    'male',
    '2000-06-20',
    'standard'
  );

\ir ../supabase/migrations/042_fitness_brain_shadow_validation.sql
\ir ../supabase/migrations/042_fitness_brain_shadow_validation.sql

do $$
begin
  if has_table_privilege('authenticated', 'public.fitness_brain_shadow_observations', 'INSERT')
     or has_table_privilege('authenticated', 'public.fitness_brain_shadow_observations', 'UPDATE')
     or has_table_privilege('authenticated', 'public.fitness_brain_shadow_observations', 'DELETE') then
    raise exception 'authenticated clients can mutate shadow observations directly';
  end if;
  if not has_table_privilege('authenticated', 'public.fitness_brain_shadow_observations', 'SELECT') then
    raise exception 'authenticated clients cannot inspect their own shadow observations';
  end if;
  if has_table_privilege('authenticated', 'public.fitness_brain_shadow_review', 'SELECT') then
    raise exception 'authenticated clients can inspect cross-account review aggregates';
  end if;
end
$$;

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

select public.record_fitness_brain_shadow_observation(
  p_observed_on => date '2026-08-31',
  p_platform => 'ios',
  p_presentation_model_version => 1,
  p_shadow_model_version => 2,
  p_legacy_overall_band => '40_59',
  p_shadow_overall_band => 'capable',
  p_absolute_disagreement_band => '5_to_14',
  p_overall_coverage_band => 'sufficient',
  p_overall_confidence => 'medium',
  p_source_distribution => '{"guided_field_test":4,"supported_device":1}',
  p_issue_codes => '{}',
  p_invariant_codes => '{}'
);

select public.record_fitness_brain_shadow_observation(
  p_observed_on => date '2026-08-31',
  p_platform => 'ios',
  p_presentation_model_version => 1,
  p_shadow_model_version => 2,
  p_legacy_overall_band => '40_59',
  p_shadow_overall_band => 'strong',
  p_absolute_disagreement_band => '15_to_24',
  p_overall_coverage_band => 'sufficient',
  p_overall_confidence => 'medium',
  p_source_distribution => '{"guided_field_test":5}',
  p_issue_codes => '{}',
  p_invariant_codes => '{}'
);

do $$
begin
  if (select count(*) from public.fitness_brain_shadow_observations) <> 1 then
    raise exception 'same-day retry created duplicate telemetry';
  end if;
  if exists (
    select 1 from public.fitness_brain_shadow_observations
    where user_id <> auth.uid()
  ) then
    raise exception 'RLS exposed another account';
  end if;
  if not exists (
    select 1 from public.fitness_brain_shadow_observations
    where profile_kind = 'bespoke'
      and age_band = '30_44'
      and sex_group = 'female'
      and shadow_overall_band = 'strong'
  ) then
    raise exception 'server-derived subgroup or idempotent update is incorrect';
  end if;

  begin
    perform public.record_fitness_brain_shadow_observation(
      date '2026-08-30', 'ios', 1, 2, '40_59', 'capable', 'under_5',
      'sufficient', 'medium', '{"heart_rate":1}', '{}', '{}'
    );
    raise exception 'raw health-shaped source key was accepted';
  exception when check_violation then null;
  end;

  begin
    perform public.record_fitness_brain_shadow_observation(
      date '2026-08-30', 'ios', 1, 2, '40_59', 'capable', 'under_5',
      'sufficient', 'medium', '{"supported_device":1}',
      array['duplicate_domain:cardio-123'], '{}'
    );
    raise exception 'identifier-shaped issue code was accepted';
  exception when check_violation then null;
  end;
end
$$;

reset role;
set role service_role;

do $$
begin
  if (select count(*) from public.fitness_brain_shadow_review) <> 1 then
    raise exception 'service review did not expose one aggregate subgroup row';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fitness_brain_shadow_review'
      and column_name = 'user_id'
  ) then
    raise exception 'service review exposes account identifiers';
  end if;
end
$$;

reset role;
rollback;
