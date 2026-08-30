\set ON_ERROR_STOP on

begin;

create role anon nologin;
create role authenticated nologin;
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

grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;

create table public.profile (
  user_id uuid primary key references auth.users (id) on delete cascade,
  body_fat_pct double precision,
  body_fat_source text,
  body_fat_measured_at text
);

create table public.settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  addons jsonb not null default '{}'::jsonb
);

create table public.health_metrics (
  id uuid primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  date date not null,
  weight_kg double precision,
  vo2max double precision,
  resting_hr double precision
);

insert into auth.users (id) values
  ('11111111-1111-4111-8111-111111111111'),
  ('22222222-2222-4222-8222-222222222222');

insert into public.profile (user_id, body_fat_pct, body_fat_source, body_fat_measured_at) values
  ('11111111-1111-4111-8111-111111111111', 18.4, 'dexa', '2026-08-01 08:00:00'),
  ('22222222-2222-4222-8222-222222222222', 24.1, 'legacy_unverified', null);

insert into public.settings (user_id, addons) values
  ('11111111-1111-4111-8111-111111111111', '{"custom_bmr":1683}'),
  ('22222222-2222-4222-8222-222222222222', '{"custom_bmr":"not measured"}');

insert into public.health_metrics (
  id, user_id, date, weight_kg, vo2max, resting_hr
) values (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '11111111-1111-4111-8111-111111111111',
  '2026-08-29', 78.2, 47.2, 54
);

\ir ../supabase/migrations/041_fitness_evidence.sql
\ir ../supabase/migrations/041_fitness_evidence.sql

do $$
begin
  if has_table_privilege('authenticated', 'public.fitness_evidence', 'INSERT')
     or has_table_privilege('authenticated', 'public.fitness_evidence', 'UPDATE')
     or has_table_privilege('authenticated', 'public.fitness_evidence', 'DELETE') then
    raise exception 'authenticated clients can mutate the immutable evidence table';
  end if;
  if not has_table_privilege('authenticated', 'public.fitness_evidence', 'SELECT') then
    raise exception 'authenticated clients cannot read evidence through RLS';
  end if;
  if (select count(*) from public.fitness_evidence where user_id = '11111111-1111-4111-8111-111111111111') <> 5 then
    raise exception 'legacy evidence backfill was not complete and idempotent';
  end if;
  if exists (
    select 1 from public.fitness_evidence
    where source = 'dexa_measurement' or confidence = 'high'
  ) then
    raise exception 'legacy labels were incorrectly promoted to trusted evidence';
  end if;
end
$$;

set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);

select id as flexibility_v1_id
from public.record_user_fitness_evidence(
  p_metric => 'flexibility_score',
  p_value => 72,
  p_unit => 'score_0_100',
  p_measured_at => '2026-08-30 09:00:00+00',
  p_client_idempotency_key => 'calibration:flexibility:v1',
  p_metadata => '{"assessment":"guided"}'
)
\gset

select public.record_user_fitness_evidence(
  p_metric => 'flexibility_score',
  p_value => 72,
  p_unit => 'score_0_100',
  p_measured_at => '2026-08-30 09:00:00+00',
  p_client_idempotency_key => 'calibration:flexibility:v1',
  p_metadata => '{"assessment":"guided"}'
);

select public.record_user_fitness_evidence(
  p_metric => 'flexibility_score',
  p_value => 78,
  p_unit => 'score_0_100',
  p_measured_at => '2026-08-30 09:15:00+00',
  p_client_idempotency_key => 'calibration:flexibility:v2',
  p_metadata => '{"assessment":"guided"}',
  p_supersedes_id => :'flexibility_v1_id'::uuid
);

do $$
begin
  if exists (
    select 1 from public.fitness_evidence where user_id <> auth.uid()
  ) then
    raise exception 'RLS exposed another account';
  end if;
  if (select count(*) from public.fitness_evidence where client_idempotency_key = 'calibration:flexibility:v1') <> 1 then
    raise exception 'RPC idempotency created duplicate evidence';
  end if;
  if exists (
    select 1 from public.fitness_evidence
    where client_idempotency_key like 'calibration:%' and confidence <> 'low'
  ) then
    raise exception 'user RPC manufactured trusted confidence';
  end if;

  begin
    perform public.record_user_fitness_evidence(
      p_metric => 'vo2_max',
      p_value => 50,
      p_unit => 'ml_per_kg_min',
      p_measured_at => '2026-08-30 09:20:00+00',
      p_client_idempotency_key => 'forbidden:trusted-source',
      p_source => 'supported_device'
    );
    raise exception 'trusted source was admitted through the user RPC';
  exception when others then
    if sqlerrm = 'trusted source was admitted through the user RPC' then raise; end if;
  end;

  begin
    perform public.record_user_fitness_evidence(
      p_metric => 'flexibility_score',
      p_value => 72,
      p_unit => 'score_0_100',
      p_measured_at => '2026-08-30 09:00:00+00',
      p_client_idempotency_key => 'calibration:flexibility:v1',
      p_metadata => '{"assessment":"different"}'
    );
    raise exception 'idempotency collision was accepted';
  exception when others then
    if sqlerrm = 'idempotency collision was accepted' then raise; end if;
  end;

  begin
    perform public.record_user_fitness_evidence(
      p_metric => 'balance_score',
      p_value => 65,
      p_unit => 'score_0_100',
      p_measured_at => '2026-08-30 09:25:00+00',
      p_client_idempotency_key => 'forbidden:cross-metric-lineage',
      p_supersedes_id => (
        select id from public.fitness_evidence
        where client_idempotency_key = 'calibration:flexibility:v1'
      )
    );
    raise exception 'cross-metric supersession was accepted';
  exception when others then
    if sqlerrm = 'cross-metric supersession was accepted' then raise; end if;
  end;
end
$$;

reset role;

do $$
begin
  if (select count(*) from public.fitness_evidence where client_idempotency_key like 'calibration:flexibility:v%') <> 2 then
    raise exception 'correction lineage did not retain exactly two immutable facts';
  end if;
end
$$;

rollback;
