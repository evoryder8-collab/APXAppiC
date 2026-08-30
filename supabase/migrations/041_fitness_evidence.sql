-- Immutable, account-owned evidence for Fitness Brain v2.
--
-- Authenticated clients can read their own evidence but cannot write this
-- table directly. User-reported evidence enters through the constrained RPC
-- below, which derives ownership from auth.uid() and caps confidence at low.

create table if not exists public.fitness_evidence (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  metric text not null,
  value double precision not null,
  unit text not null,
  source text not null,
  protocol text,
  device text,
  measured_at timestamptz not null,
  imported_at timestamptz not null default now(),
  confidence text not null,
  metadata jsonb not null default '{}'::jsonb,
  supersedes_id uuid,
  client_idempotency_key text not null,

  constraint fitness_evidence_owner_id_metric_key unique (user_id, id, metric),
  constraint fitness_evidence_owner_idempotency_key unique (user_id, client_idempotency_key),
  constraint fitness_evidence_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  constraint fitness_evidence_identifier_lengths
    check (
      char_length(client_idempotency_key) between 1 and 160
      and (protocol is null or char_length(protocol) between 1 and 160)
      and (device is null or char_length(device) between 1 and 200)
    ),
  constraint fitness_evidence_time_order
    check (
      measured_at >= timestamptz '1900-01-01 00:00:00+00'
      and measured_at <= imported_at + interval '24 hours'
    ),
  constraint fitness_evidence_source_allowed
    check (
      source in (
        'indirect_calorimetry',
        'dexa_measurement',
        'dexa_derived_estimate',
        'clinical_measurement',
        'supported_device',
        'guided_apex_field_test',
        'structured_self_report',
        'user_entered_external_result',
        'legacy_unverified'
      )
    ),
  constraint fitness_evidence_confidence_allowed
    check (confidence in ('low', 'medium', 'high')),
  constraint fitness_evidence_source_confidence
    check (
      (
        source in ('indirect_calorimetry', 'dexa_measurement', 'clinical_measurement')
        and confidence in ('low', 'medium', 'high')
      )
      or (
        source in ('dexa_derived_estimate', 'supported_device', 'guided_apex_field_test')
        and confidence in ('low', 'medium')
      )
      or (
        source in ('structured_self_report', 'user_entered_external_result', 'legacy_unverified')
        and confidence = 'low'
      )
    ),
  constraint fitness_evidence_metric_unit_range
    check (
      (metric = 'body_mass' and unit = 'kg' and value between 10 and 500)
      or (metric = 'height' and unit = 'cm' and value between 50 and 260)
      or (metric = 'body_fat_percentage' and unit = 'percent' and value between 2 and 70)
      or (metric = 'resting_metabolic_rate' and unit = 'kcal_per_day' and value between 400 and 8000)
      or (metric = 'vo2_max' and unit = 'ml_per_kg_min' and value between 5 and 120)
      or (metric = 'resting_heart_rate' and unit = 'bpm' and value between 20 and 250)
      or (metric = 'waist_circumference' and unit = 'cm' and value between 30 and 300)
      or (
        metric in (
          'cardio_capacity_score',
          'upper_body_strength_score',
          'lower_body_strength_score',
          'flexibility_score',
          'joint_health_score',
          'balance_score'
        )
        and unit = 'score_0_100'
        and value between 0 and 100
      )
    ),
  constraint fitness_evidence_not_self_superseding
    check (supersedes_id is null or supersedes_id <> id),
  constraint fitness_evidence_same_owner_metric_lineage
    foreign key (user_id, supersedes_id, metric)
    references public.fitness_evidence (user_id, id, metric)
    on delete restrict
);

create unique index if not exists fitness_evidence_one_successor_per_record
  on public.fitness_evidence (user_id, supersedes_id)
  where supersedes_id is not null;

create index if not exists fitness_evidence_owner_metric_measured_idx
  on public.fitness_evidence (user_id, metric, measured_at desc, id);

alter table public.fitness_evidence enable row level security;

drop policy if exists fitness_evidence_owner_select on public.fitness_evidence;
create policy fitness_evidence_owner_select
  on public.fitness_evidence
  for select
  to authenticated
  using (auth.uid() = user_id);

revoke all on table public.fitness_evidence from anon, authenticated;
grant select on table public.fitness_evidence to authenticated;

create or replace function public.record_user_fitness_evidence(
  p_metric text,
  p_value double precision,
  p_unit text,
  p_measured_at timestamptz,
  p_client_idempotency_key text,
  p_source text default 'structured_self_report',
  p_protocol text default null,
  p_device text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_supersedes_id uuid default null
)
returns public.fitness_evidence
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_result public.fitness_evidence;
begin
  if v_user_id is null then
    raise exception 'Authentication is required';
  end if;

  if p_source not in ('structured_self_report', 'user_entered_external_result') then
    raise exception 'This evidence source requires a trusted ingestion path';
  end if;

  if p_client_idempotency_key is null or btrim(p_client_idempotency_key) = '' then
    raise exception 'An idempotency key is required';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata) <> 'object' then
    raise exception 'Evidence metadata must be a JSON object';
  end if;

  insert into public.fitness_evidence (
    user_id,
    metric,
    value,
    unit,
    source,
    protocol,
    device,
    measured_at,
    confidence,
    metadata,
    supersedes_id,
    client_idempotency_key
  ) values (
    v_user_id,
    p_metric,
    p_value,
    p_unit,
    p_source,
    nullif(btrim(p_protocol), ''),
    nullif(btrim(p_device), ''),
    p_measured_at,
    'low',
    p_metadata,
    p_supersedes_id,
    btrim(p_client_idempotency_key)
  )
  on conflict (user_id, client_idempotency_key) do nothing
  returning * into v_result;

  if v_result.id is null then
    select *
      into strict v_result
    from public.fitness_evidence
    where user_id = v_user_id
      and client_idempotency_key = btrim(p_client_idempotency_key);

    if v_result.metric <> p_metric
      or v_result.value <> p_value
      or v_result.unit <> p_unit
      or v_result.source <> p_source
      or v_result.protocol is distinct from nullif(btrim(p_protocol), '')
      or v_result.device is distinct from nullif(btrim(p_device), '')
      or v_result.measured_at <> p_measured_at
      or v_result.metadata is distinct from p_metadata
      or v_result.supersedes_id is distinct from p_supersedes_id
    then
      raise exception 'The idempotency key is already associated with different evidence';
    end if;
  end if;

  return v_result;
end;
$$;

revoke all on function public.record_user_fitness_evidence(
  text, double precision, text, timestamptz, text, text, text, text, jsonb, uuid
) from public, anon;
grant execute on function public.record_user_fitness_evidence(
  text, double precision, text, timestamptz, text, text, text, text, jsonb, uuid
) to authenticated;

-- Preserve legacy facts while refusing to upgrade a reported label into
-- verified DEXA/clinical provenance. Unknown measurement dates are made
-- explicitly stale rather than pretending the migration time was the test.
insert into public.fitness_evidence (
  user_id,
  metric,
  value,
  unit,
  source,
  protocol,
  measured_at,
  confidence,
  metadata,
  client_idempotency_key
)
select
  p.user_id,
  'body_fat_percentage',
  p.body_fat_pct::double precision,
  'percent',
  case
    when p.body_fat_source = 'legacy_unverified' then 'legacy_unverified'
    else 'user_entered_external_result'
  end,
  case
    when p.body_fat_source is null then null
    else 'reported:' || p.body_fat_source
  end,
  coalesce(
    p.body_fat_measured_at::timestamp at time zone 'UTC',
    timestamptz '1970-01-01 00:00:00+00'
  ),
  'low',
  jsonb_build_object(
    'backfilled_from', 'profile.body_fat_pct',
    'reported_source', p.body_fat_source,
    'measurement_time_known', p.body_fat_measured_at is not null
  ),
  'backfill:profile:' || p.user_id::text || ':body_fat_percentage'
from public.profile p
where p.body_fat_pct between 2 and 70
on conflict (user_id, client_idempotency_key) do nothing;

insert into public.fitness_evidence (
  user_id,
  metric,
  value,
  unit,
  source,
  protocol,
  measured_at,
  confidence,
  metadata,
  client_idempotency_key
)
select
  s.user_id,
  'resting_metabolic_rate',
  (s.addons->>'custom_bmr')::double precision,
  'kcal_per_day',
  'user_entered_external_result',
  'legacy_custom_bmr',
  timestamptz '1970-01-01 00:00:00+00',
  'low',
  jsonb_build_object(
    'backfilled_from', 'settings.addons.custom_bmr',
    'measurement_time_known', false
  ),
  'backfill:settings:' || s.user_id::text || ':resting_metabolic_rate'
from public.settings s
where jsonb_typeof(s.addons) = 'object'
  and coalesce(s.addons->>'custom_bmr', '') ~ '^[0-9]+([.][0-9]+)?$'
  and (s.addons->>'custom_bmr')::double precision between 400 and 8000
on conflict (user_id, client_idempotency_key) do nothing;

insert into public.fitness_evidence (
  user_id,
  metric,
  value,
  unit,
  source,
  device,
  measured_at,
  confidence,
  metadata,
  client_idempotency_key
)
select
  h.user_id,
  facts.metric,
  facts.value,
  facts.unit,
  'supported_device',
  'Apple Health',
  h.date::timestamp at time zone 'UTC',
  'medium',
  jsonb_build_object(
    'backfilled_from', 'health_metrics',
    'legacy_row_id', h.id,
    'measurement_time_known', false
  ),
  'backfill:health_metrics:' || h.id::text || ':' || facts.metric
from public.health_metrics h
cross join lateral (
  values
    ('body_mass'::text, h.weight_kg::double precision, 'kg'::text),
    ('vo2_max'::text, h.vo2max::double precision, 'ml_per_kg_min'::text),
    ('resting_heart_rate'::text, h.resting_hr::double precision, 'bpm'::text)
) as facts(metric, value, unit)
where facts.value is not null
  and (
    (facts.metric = 'body_mass' and facts.value between 10 and 500)
    or (facts.metric = 'vo2_max' and facts.value between 5 and 120)
    or (facts.metric = 'resting_heart_rate' and facts.value between 20 and 250)
  )
on conflict (user_id, client_idempotency_key) do nothing;

comment on table public.fitness_evidence is
  'Append-only source evidence for Fitness Brain v2. Corrections create a successor; clients cannot mutate rows directly.';
comment on column public.fitness_evidence.source is
  'Provenance class, not a user-facing claim. Trusted sources require a server-controlled ingestion path.';
comment on column public.fitness_evidence.confidence is
  'Confidence may be lower than a source ceiling but never higher.';
comment on column public.fitness_evidence.supersedes_id is
  'Optional same-owner, same-metric predecessor. A predecessor may have only one successor.';

notify pgrst, 'reload schema';
