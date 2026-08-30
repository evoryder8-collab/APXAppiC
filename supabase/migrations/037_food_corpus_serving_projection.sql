-- Add serving evidence to the search boundary without changing or removing the
-- original corpus RPC. Clients may normalize a published gram-weighted serving
-- while records and archived observations retain the publisher's original basis.
create or replace function public.food_corpus_search_catalog_v2(
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
  basis_amount numeric,
  basis_unit text,
  source_metadata jsonb,
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
  select
    result.record_id,
    result.source_key,
    result.source_record_id,
    result.name,
    result.names_i18n,
    result.aliases,
    result.brand,
    result.barcode,
    result.market,
    result.basis_kind,
    record.basis_amount,
    record.basis_unit,
    record.source_metadata,
    result.preparation_state,
    result.kcal,
    result.protein_g,
    result.carbs_g,
    result.fat_g,
    result.fibre_g,
    result.sugar_g,
    result.saturated_fat_g,
    result.salt_g,
    result.water_g
  from public.food_corpus_search_catalog(p_query, p_limit) with ordinality as result (
    record_id,
    source_key,
    source_record_id,
    name,
    names_i18n,
    aliases,
    brand,
    barcode,
    market,
    basis_kind,
    preparation_state,
    kcal,
    protein_g,
    carbs_g,
    fat_g,
    fibre_g,
    sugar_g,
    saturated_fat_g,
    salt_g,
    water_g,
    result_order
  )
  join public.food_corpus_records record on record.id = result.record_id
  order by result.result_order
$$;

revoke all on function public.food_corpus_search_catalog_v2(text, integer) from public, anon;
grant execute on function public.food_corpus_search_catalog_v2(text, integer) to authenticated, service_role;

notify pgrst, 'reload schema';
