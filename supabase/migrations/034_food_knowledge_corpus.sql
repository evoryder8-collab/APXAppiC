-- Canonical, provenance-preserving food composition corpus.
-- Raw publisher bundles remain outside the application repository and clients.

create extension if not exists pg_trgm;

create table if not exists public.food_corpus_sources (
  source_key text primary key,
  dataset_name text not null,
  publisher text not null,
  version text not null,
  release_date date,
  source_url text not null,
  licence_id text not null,
  licence_url text,
  attribution text not null,
  checksum_sha256 text not null check (checksum_sha256 ~ '^[a-f0-9]{64}$'),
  parser_version text not null,
  redistribution_scope text not null check (
    redistribution_scope in ('permissive', 'attribution', 'share_alike_isolated', 'review_required')
  ),
  ingest_status text not null default 'registered' check (
    ingest_status in ('registered', 'active', 'quarantined', 'retired')
  ),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.food_corpus_batches (
  id uuid primary key default gen_random_uuid(),
  source_key text not null references public.food_corpus_sources(source_key),
  source_checksum_sha256 text not null check (source_checksum_sha256 ~ '^[a-f0-9]{64}$'),
  parser_version text not null,
  status text not null default 'staging' check (
    status in ('staging', 'validated', 'active', 'failed', 'retired')
  ),
  records_seen bigint not null default 0 check (records_seen >= 0),
  records_accepted bigint not null default 0 check (records_accepted >= 0),
  records_rejected bigint not null default 0 check (records_rejected >= 0),
  validation_report jsonb not null default '{}'::jsonb,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  check (records_accepted + records_rejected <= records_seen)
);

create table if not exists public.food_corpus_records (
  id uuid primary key default gen_random_uuid(),
  source_key text not null references public.food_corpus_sources(source_key),
  source_record_id text not null,
  batch_id uuid not null references public.food_corpus_batches(id),
  canonical_name text not null,
  scientific_name text,
  brand text,
  barcode text,
  market text,
  primary_language text not null default 'und',
  basis_kind text not null check (
    basis_kind in ('per_100g', 'per_100ml', 'per_serving', 'edible_portion', 'dry_matter')
  ),
  basis_amount numeric not null check (basis_amount > 0),
  basis_unit text not null check (basis_unit in ('g', 'ml', 'serving', 'g_edible', 'g_dry_matter')),
  preparation_state text,
  edible_portion_percent numeric check (
    edible_portion_percent is null or edible_portion_percent between 0 and 100
  ),
  density_g_ml numeric check (density_g_ml is null or density_g_ml > 0),
  source_priority integer not null default 100,
  source_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_key, source_record_id)
);

create table if not exists public.food_corpus_names (
  id bigint generated always as identity primary key,
  record_id uuid not null references public.food_corpus_records(id) on delete cascade,
  language text not null default 'und',
  name text not null,
  normalized_name text not null,
  name_kind text not null check (
    name_kind in ('canonical', 'alias', 'regional', 'brand', 'scientific')
  ),
  market text,
  unique (record_id, language, normalized_name, name_kind)
);

create table if not exists public.food_corpus_nutrients (
  id bigint generated always as identity primary key,
  record_id uuid not null references public.food_corpus_records(id) on delete cascade,
  nutrient_code text not null,
  source_nutrient_code text not null,
  original_nutrient_name text not null,
  value numeric,
  unit text not null,
  original_value_text text not null default '',
  observation_status text not null check (
    observation_status in (
      'measured', 'calculated', 'estimated', 'trace', 'below_detection', 'not_measured', 'missing'
    )
  ),
  derivation_method text,
  source_reference text,
  check (
    (observation_status in ('measured', 'calculated', 'estimated') and value is not null)
    or
    (observation_status in ('trace', 'below_detection', 'not_measured', 'missing') and value is null)
  ),
  unique (record_id, source_nutrient_code)
);

create table if not exists public.food_corpus_search (
  record_id uuid primary key references public.food_corpus_records(id) on delete cascade,
  source_key text not null,
  source_record_id text not null,
  name text not null,
  names_i18n jsonb not null default '{}'::jsonb,
  aliases text[] not null default '{}',
  brand text,
  barcode text,
  market text,
  basis_kind text not null,
  preparation_state text,
  kcal numeric,
  protein_g numeric,
  carbs_g numeric,
  fat_g numeric,
  fibre_g numeric,
  sugar_g numeric,
  saturated_fat_g numeric,
  salt_g numeric,
  water_g numeric,
  source_priority integer not null default 100,
  search_text text not null,
  updated_at timestamptz not null default now(),
  unique (source_key, source_record_id)
);

create index if not exists idx_food_corpus_records_source_batch
  on public.food_corpus_records(source_key, batch_id);
create index if not exists idx_food_corpus_names_normalized
  on public.food_corpus_names(normalized_name);
create index if not exists idx_food_corpus_names_trgm
  on public.food_corpus_names using gin(normalized_name gin_trgm_ops);
create index if not exists idx_food_corpus_nutrients_record_code
  on public.food_corpus_nutrients(record_id, nutrient_code);
create index if not exists idx_food_corpus_search_barcode
  on public.food_corpus_search(barcode) where barcode is not null;
create index if not exists idx_food_corpus_search_document
  on public.food_corpus_search using gin(to_tsvector('simple', search_text));
create index if not exists idx_food_corpus_search_trgm
  on public.food_corpus_search using gin(search_text gin_trgm_ops);

alter table public.food_corpus_sources enable row level security;
alter table public.food_corpus_batches enable row level security;
alter table public.food_corpus_records enable row level security;
alter table public.food_corpus_names enable row level security;
alter table public.food_corpus_nutrients enable row level security;
alter table public.food_corpus_search enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'food_corpus_sources'
      and policyname = 'food_corpus_sources_authenticated_read'
  ) then
    create policy food_corpus_sources_authenticated_read
      on public.food_corpus_sources for select to authenticated
      using (ingest_status = 'active');
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'food_corpus_records'
      and policyname = 'food_corpus_records_authenticated_read'
  ) then
    create policy food_corpus_records_authenticated_read
      on public.food_corpus_records for select to authenticated
      using (
        exists (
          select 1 from public.food_corpus_sources source
          where source.source_key = food_corpus_records.source_key
            and source.ingest_status = 'active'
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'food_corpus_names'
      and policyname = 'food_corpus_names_authenticated_read'
  ) then
    create policy food_corpus_names_authenticated_read
      on public.food_corpus_names for select to authenticated
      using (
        exists (
          select 1 from public.food_corpus_records record
          join public.food_corpus_sources source using (source_key)
          where record.id = food_corpus_names.record_id
            and source.ingest_status = 'active'
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'food_corpus_nutrients'
      and policyname = 'food_corpus_nutrients_authenticated_read'
  ) then
    create policy food_corpus_nutrients_authenticated_read
      on public.food_corpus_nutrients for select to authenticated
      using (
        exists (
          select 1 from public.food_corpus_records record
          join public.food_corpus_sources source using (source_key)
          where record.id = food_corpus_nutrients.record_id
            and source.ingest_status = 'active'
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'food_corpus_search'
      and policyname = 'food_corpus_search_authenticated_read'
  ) then
    create policy food_corpus_search_authenticated_read
      on public.food_corpus_search for select to authenticated
      using (
        exists (
          select 1 from public.food_corpus_sources source
          where source.source_key = food_corpus_search.source_key
            and source.ingest_status = 'active'
        )
      );
  end if;
end
$$;

revoke all on public.food_corpus_sources from anon, authenticated;
revoke all on public.food_corpus_batches from anon, authenticated;
revoke all on public.food_corpus_records from anon, authenticated;
revoke all on public.food_corpus_names from anon, authenticated;
revoke all on public.food_corpus_nutrients from anon, authenticated;
revoke all on public.food_corpus_search from anon, authenticated;

grant select on public.food_corpus_sources to authenticated;
grant select on public.food_corpus_records to authenticated;
grant select on public.food_corpus_names to authenticated;
grant select on public.food_corpus_nutrients to authenticated;
grant select on public.food_corpus_search to authenticated;

create or replace function public.food_corpus_search_catalog(
  p_query text,
  p_limit integer default 25
)
returns table (
  record_id uuid,
  source_key text,
  source_record_id text,
  name text,
  names_i18n jsonb,
  aliases text[],
  brand text,
  barcode text,
  market text,
  basis_kind text,
  preparation_state text,
  kcal numeric,
  protein_g numeric,
  carbs_g numeric,
  fat_g numeric,
  fibre_g numeric,
  sugar_g numeric,
  saturated_fat_g numeric,
  salt_g numeric,
  water_g numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with query as (
    select lower(trim(regexp_replace(coalesce(p_query, ''), '[[:space:]]+', ' ', 'g'))) as value
  )
  select
    search.record_id,
    search.source_key,
    search.source_record_id,
    search.name,
    search.names_i18n,
    search.aliases,
    search.brand,
    search.barcode,
    search.market,
    search.basis_kind,
    search.preparation_state,
    search.kcal,
    search.protein_g,
    search.carbs_g,
    search.fat_g,
    search.fibre_g,
    search.sugar_g,
    search.saturated_fat_g,
    search.salt_g,
    search.water_g
  from public.food_corpus_search search
  join public.food_corpus_sources source using (source_key)
  cross join query
  where source.ingest_status = 'active'
    and length(query.value) >= 2
    and (
      lower(search.search_text) like '%' || query.value || '%'
      or to_tsvector('simple', search.search_text) @@ websearch_to_tsquery('simple', query.value)
      or lower(search.search_text) % query.value
    )
  order by
    case
      when lower(search.name) = query.value then 0
      when lower(search.name) like query.value || '%' then 1
      when lower(coalesce(search.brand, '')) like query.value || '%' then 2
      else 3
    end,
    search.source_priority,
    similarity(lower(search.search_text), query.value) desc,
    search.name,
    search.source_key,
    search.source_record_id
  limit least(greatest(coalesce(p_limit, 25), 1), 50)
$$;

revoke all on function public.food_corpus_search_catalog(text, integer) from public, anon;
grant execute on function public.food_corpus_search_catalog(text, integer) to authenticated, service_role;

comment on table public.food_corpus_nutrients is
  'Evidence table: trace, below-detection, not-measured, and missing observations remain nullable states and are never coerced to zero.';
comment on table public.food_corpus_search is
  'Bounded server-side search projection; the full publisher bundles are never shipped in an APEX client.';
