-- Privacy-safe shadow validation for Fitness Brain v2.
--
-- The visible product remains on presentation model v1. This schema retains
-- only coarse bands, categorical confidence and aggregate source counts so
-- model disagreements can be reviewed without storing raw health values,
-- evidence identifiers, receipts, workout names or birth dates.

create or replace function public.fitness_brain_shadow_source_distribution_is_safe(
  p_value jsonb
)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select jsonb_typeof(p_value) = 'object'
    and not exists (
      select 1
      from jsonb_each(p_value) entry
      where entry.key not in (
        'structured_self_report',
        'legacy_unverified',
        'supported_device',
        'guided_field_test',
        'standardized_field_test',
        'clinical_lab'
      )
      or case
        when jsonb_typeof(entry.value) = 'number' then
          (entry.value #>> '{}')::numeric < 0
          or (entry.value #>> '{}')::numeric > 32
          or (entry.value #>> '{}')::numeric <> trunc((entry.value #>> '{}')::numeric)
        else true
      end
    )
$$;

create or replace function public.fitness_brain_shadow_issue_codes_are_safe(
  p_codes text[]
)
returns boolean
language sql
immutable
set search_path = public, pg_temp
as $$
  select cardinality(p_codes) <= 32
    and coalesce(bool_and(
      code ~ '^(duplicate_domain|invalid_unknown|missing_value|invalid_bounds|out_of_range|non_finite|invalid_coverage|invalid_model_version|invalid_reference_scale|invalid_confidence|missing_evidence|missing_receipt|band_too_narrow):[a-z_]+$'
      and char_length(code) <= 120
    ), true)
  from unnest(p_codes) code
$$;

revoke all on function public.fitness_brain_shadow_source_distribution_is_safe(jsonb)
  from public, anon, authenticated;
revoke all on function public.fitness_brain_shadow_issue_codes_are_safe(text[])
  from public, anon, authenticated;

create table if not exists public.fitness_brain_shadow_observations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  observed_on date not null,
  platform text not null,
  profile_kind text not null,
  age_band text not null,
  sex_group text not null,
  presentation_model_version integer not null,
  shadow_model_version integer not null,
  legacy_overall_band text not null,
  shadow_overall_band text not null,
  absolute_disagreement_band text not null,
  overall_coverage_band text not null,
  overall_confidence text not null,
  source_distribution jsonb not null default '{}'::jsonb,
  issue_codes text[] not null default '{}',
  invariant_codes text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint fitness_brain_shadow_daily_platform_model
    unique (user_id, observed_on, platform, shadow_model_version),
  constraint fitness_brain_shadow_observed_on_range
    check (observed_on between date '2020-01-01' and current_date + 1),
  constraint fitness_brain_shadow_platform_allowed
    check (platform in ('web', 'ios')),
  constraint fitness_brain_shadow_profile_kind_allowed
    check (profile_kind in ('standard', 'bespoke')),
  constraint fitness_brain_shadow_age_band_allowed
    check (age_band in ('under_30', '30_44', '45_59', '60_plus', 'unknown')),
  constraint fitness_brain_shadow_sex_group_allowed
    check (sex_group in ('female', 'male', 'unknown')),
  constraint fitness_brain_shadow_model_versions_locked
    check (presentation_model_version = 1 and shadow_model_version = 2),
  constraint fitness_brain_shadow_legacy_band_allowed
    check (legacy_overall_band in ('unavailable', '0_19', '20_39', '40_59', '60_79', '80_100')),
  constraint fitness_brain_shadow_v2_band_allowed
    check (shadow_overall_band in ('building_baseline', 'foundation', 'developing', 'capable', 'strong', 'exceptional')),
  constraint fitness_brain_shadow_disagreement_band_allowed
    check (absolute_disagreement_band in ('unavailable', 'under_5', '5_to_14', '15_to_24', '25_plus')),
  constraint fitness_brain_shadow_coverage_band_allowed
    check (overall_coverage_band in ('none', 'low', 'partial', 'sufficient')),
  constraint fitness_brain_shadow_confidence_allowed
    check (overall_confidence in ('unavailable', 'low', 'medium', 'high')),
  constraint fitness_brain_shadow_source_distribution_safe
    check (public.fitness_brain_shadow_source_distribution_is_safe(source_distribution)),
  constraint fitness_brain_shadow_issue_codes_safe
    check (public.fitness_brain_shadow_issue_codes_are_safe(issue_codes)),
  constraint fitness_brain_shadow_invariant_codes_safe
    check (
      cardinality(invariant_codes) <= 16
      and invariant_codes <@ array[
        'missing_data_changed_capacity',
        'readiness_changed_capacity',
        'adherence_changed_capacity',
        'adaptation_changed_capacity',
        'health_context_changed_capacity',
        'overall_confidence_exceeded_domain',
        'capacity_value_outside_bounds'
      ]::text[]
    )
);

create index if not exists fitness_brain_shadow_review_dimensions_idx
  on public.fitness_brain_shadow_observations (
    observed_on desc, platform, profile_kind, age_band, sex_group
  );

alter table public.fitness_brain_shadow_observations enable row level security;

drop policy if exists fitness_brain_shadow_owner_select
  on public.fitness_brain_shadow_observations;
create policy fitness_brain_shadow_owner_select
  on public.fitness_brain_shadow_observations
  for select
  to authenticated
  using (auth.uid() = user_id);

revoke all on table public.fitness_brain_shadow_observations from public, anon, authenticated;
grant select on table public.fitness_brain_shadow_observations to authenticated;
grant all on table public.fitness_brain_shadow_observations to service_role;

create or replace function public.record_fitness_brain_shadow_observation(
  p_observed_on date,
  p_platform text,
  p_presentation_model_version integer,
  p_shadow_model_version integer,
  p_legacy_overall_band text,
  p_shadow_overall_band text,
  p_absolute_disagreement_band text,
  p_overall_coverage_band text,
  p_overall_confidence text,
  p_source_distribution jsonb,
  p_issue_codes text[],
  p_invariant_codes text[]
)
returns public.fitness_brain_shadow_observations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile_kind text;
  v_age integer;
  v_age_band text;
  v_sex_group text;
  v_result public.fitness_brain_shadow_observations;
begin
  if v_user_id is null then
    raise exception 'Authentication is required';
  end if;

  select
    coalesce(p.profile_kind, 'standard'),
    extract(year from age(p_observed_on, p.birthdate))::integer,
    case lower(btrim(p.sex))
      when 'female' then 'female'
      when 'woman' then 'female'
      when 'male' then 'male'
      when 'man' then 'male'
      else 'unknown'
    end
  into v_profile_kind, v_age, v_sex_group
  from public.profile p
  where p.user_id = v_user_id;

  if not found then
    raise exception 'An owned profile is required';
  end if;

  v_age_band := case
    when v_age is null or v_age < 0 or v_age > 120 then 'unknown'
    when v_age < 30 then 'under_30'
    when v_age < 45 then '30_44'
    when v_age < 60 then '45_59'
    else '60_plus'
  end;

  insert into public.fitness_brain_shadow_observations (
    user_id,
    observed_on,
    platform,
    profile_kind,
    age_band,
    sex_group,
    presentation_model_version,
    shadow_model_version,
    legacy_overall_band,
    shadow_overall_band,
    absolute_disagreement_band,
    overall_coverage_band,
    overall_confidence,
    source_distribution,
    issue_codes,
    invariant_codes
  ) values (
    v_user_id,
    p_observed_on,
    p_platform,
    v_profile_kind,
    v_age_band,
    v_sex_group,
    p_presentation_model_version,
    p_shadow_model_version,
    p_legacy_overall_band,
    p_shadow_overall_band,
    p_absolute_disagreement_band,
    p_overall_coverage_band,
    p_overall_confidence,
    p_source_distribution,
    p_issue_codes,
    p_invariant_codes
  )
  on conflict (user_id, observed_on, platform, shadow_model_version)
  do update set
    profile_kind = excluded.profile_kind,
    age_band = excluded.age_band,
    sex_group = excluded.sex_group,
    presentation_model_version = excluded.presentation_model_version,
    legacy_overall_band = excluded.legacy_overall_band,
    shadow_overall_band = excluded.shadow_overall_band,
    absolute_disagreement_band = excluded.absolute_disagreement_band,
    overall_coverage_band = excluded.overall_coverage_band,
    overall_confidence = excluded.overall_confidence,
    source_distribution = excluded.source_distribution,
    issue_codes = excluded.issue_codes,
    invariant_codes = excluded.invariant_codes,
    updated_at = now()
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.record_fitness_brain_shadow_observation(
  date, text, integer, integer, text, text, text, text, text, jsonb, text[], text[]
) from public, anon;
grant execute on function public.record_fitness_brain_shadow_observation(
  date, text, integer, integer, text, text, text, text, text, jsonb, text[], text[]
) to authenticated;

create or replace view public.fitness_brain_shadow_review
with (security_invoker = true)
as
select
  observed_on,
  platform,
  profile_kind,
  age_band,
  sex_group,
  count(*)::bigint as observation_count,
  count(*) filter (where overall_coverage_band = 'sufficient')::bigint
    as sufficient_coverage_count,
  count(*) filter (where absolute_disagreement_band in ('15_to_24', '25_plus'))::bigint
    as disagreement_outlier_count,
  count(*) filter (where cardinality(invariant_codes) > 0)::bigint
    as invariant_violation_count
from public.fitness_brain_shadow_observations
group by observed_on, platform, profile_kind, age_band, sex_group;

revoke all on table public.fitness_brain_shadow_review from public, anon, authenticated;
grant select on table public.fitness_brain_shadow_review to service_role;

comment on table public.fitness_brain_shadow_observations is
  'Coarse, owner-scoped Fitness Brain v2 shadow telemetry. Raw health values and evidence identifiers are forbidden.';
comment on view public.fitness_brain_shadow_review is
  'Service-role-only subgroup aggregates for scientific, privacy and claim review before any controlled activation.';
