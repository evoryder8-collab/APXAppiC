-- Canonicalize legacy/provider nutrient units before they reach immutable logs,
-- optional detail UI, or cross-day nutrient aggregation. Equivalent vitamin
-- semantics remain distinct; opaque publisher units are omitted, never guessed.

create or replace function public.apex_canonical_nutrient_unit(p_unit text)
returns text
language plpgsql
immutable
parallel safe
set search_path = public
as $$
declare
  v_unit text := lower(regexp_replace(translate(btrim(coalesce(p_unit, '')), 'μ', 'µ'), '[[:space:]]+', ' ', 'g'));
  v_match text[];
begin
  if v_unit = '' then return null; end if;

  if v_unit ~ '^(kcal|kilocalories?)([[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?$' then
    return 'kcal';
  elsif v_unit ~ '^(g|grams?)([[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?$' then
    return 'g';
  elsif v_unit ~ '^(mg|milligrams?)([[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?$' then
    return 'mg';
  elsif v_unit ~ '^(µg|ug|mcg|micrograms?)([[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?$' then
    return 'µg';
  elsif v_unit ~ '^(ml|millilit(er|re)s?)([[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?$' then
    return 'ml';
  elsif v_unit ~ '^i\.?[[:space:]]*u\.?(?:[[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?$' then
    return 'IU';
  end if;

  v_match := regexp_match(
    v_unit,
    '^(µg|ug|mcg|micrograms?)[[:space:]]+(re|rae)([[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?$'
  );
  if v_match is not null then return 'µg ' || upper(v_match[2]); end if;

  v_match := regexp_match(
    v_unit,
    '^(re|rae)[[:space:]]*\([[:space:]]*(µg|ug|mcg|micrograms?)([[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?[[:space:]]*\)$'
  );
  if v_match is not null then return 'µg ' || upper(v_match[1]); end if;

  if v_unit ~ '^(mg|milligrams?)[[:space:]]*(α|alpha|alfa)[[:space:]-]*te([[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?$'
    or v_unit ~ '^(α|alpha|alfa)[[:space:]-]*te([[:space:]]*(/|per)[[:space:]]*100[[:space:]]*(g|ml))?$'
  then
    return 'mg α-TE';
  end if;
  return null;
end;
$$;

revoke all on function public.apex_canonical_nutrient_unit(text) from public, anon, authenticated;

create or replace function public.apex_canonicalize_nutrient_evidence(p_value jsonb)
returns jsonb
language sql
immutable
parallel safe
security definer
set search_path = public
as $$
  select case when jsonb_typeof(p_value) = 'array' then coalesce((
    select jsonb_agg(
      jsonb_set(observation.value, '{unit}', to_jsonb(unit.canonical), false)
      order by observation.ordinality
    )
    from jsonb_array_elements(p_value) with ordinality observation(value, ordinality)
    cross join lateral (
      select public.apex_canonical_nutrient_unit(observation.value->>'unit') as canonical
    ) unit
    where jsonb_typeof(observation.value) = 'object'
      and unit.canonical is not null
  ), '[]'::jsonb) else '[]'::jsonb end;
$$;

revoke all on function public.apex_canonicalize_nutrient_evidence(jsonb) from public, anon, authenticated;

-- Repair retained food evidence and immutable historical snapshots in place.
-- No food, meal, or source record is deleted.
update public.foods
set nutrient_evidence = public.apex_canonicalize_nutrient_evidence(nutrient_evidence),
    updated_at = now()
where nutrient_evidence is distinct from public.apex_canonicalize_nutrient_evidence(nutrient_evidence);

update public.logged_food_entries
set snapshot_nutrient_evidence = public.apex_canonicalize_nutrient_evidence(snapshot_nutrient_evidence)
where snapshot_nutrient_evidence is distinct from public.apex_canonicalize_nutrient_evidence(snapshot_nutrient_evidence);

create or replace function public.apex_valid_nutrient_evidence(p_value jsonb)
returns boolean
language sql
immutable
parallel safe
security definer
set search_path = public
as $$
  select case
    when jsonb_typeof(p_value) = 'array' then
      jsonb_array_length(p_value) <= 96
      and octet_length(p_value::text) <= 65536
      and not exists (
        select 1
        from jsonb_array_elements(p_value) observation
        where jsonb_typeof(observation) <> 'object'
          or exists (
            select 1
            from jsonb_object_keys(
              case when jsonb_typeof(observation) = 'object' then observation else '{}'::jsonb end
            ) field(key)
            where field.key not in (
              'nutrient_code', 'name', 'value_per_100', 'unit',
              'observation_status', 'original_value_text', 'derivation_method',
              'source_key', 'source_reference'
            )
          )
          or jsonb_typeof(observation->'nutrient_code') <> 'string'
          or length(coalesce(observation->>'nutrient_code', '')) not between 1 and 80
          or jsonb_typeof(observation->'name') <> 'string'
          or length(coalesce(observation->>'name', '')) not between 1 and 180
          or jsonb_typeof(observation->'unit') <> 'string'
          or length(coalesce(observation->>'unit', '')) not between 1 and 24
          or public.apex_canonical_nutrient_unit(observation->>'unit') is null
          or jsonb_typeof(observation->'observation_status') <> 'string'
          or coalesce(observation->>'observation_status', '') not in (
            'measured', 'calculated', 'estimated', 'reported', 'trace',
            'below_detection', 'not_measured', 'missing'
          )
          or (
            observation ? 'value_per_100'
            and jsonb_typeof(observation->'value_per_100') not in ('number', 'null')
          )
          or case
            when jsonb_typeof(observation->'value_per_100') = 'number'
              then (observation->>'value_per_100')::numeric not between 0 and 1000000000000
            else false
          end
          or (
            observation ? 'original_value_text'
            and (
              jsonb_typeof(observation->'original_value_text') not in ('string', 'null')
              or length(coalesce(observation->>'original_value_text', '')) not between 0 and 180
            )
          )
          or (
            observation ? 'derivation_method'
            and (
              jsonb_typeof(observation->'derivation_method') not in ('string', 'null')
              or length(coalesce(observation->>'derivation_method', '')) not between 0 and 180
            )
          )
          or (
            observation ? 'source_key'
            and (
              jsonb_typeof(observation->'source_key') not in ('string', 'null')
              or length(coalesce(observation->>'source_key', '')) not between 0 and 120
            )
          )
          or (
            observation ? 'source_reference'
            and (
              jsonb_typeof(observation->'source_reference') not in ('string', 'null')
              or length(coalesce(observation->>'source_reference', '')) not between 0 and 240
            )
          )
          or (
            coalesce(observation->>'observation_status', '') in (
              'trace', 'below_detection', 'not_measured', 'missing'
            )
            and jsonb_typeof(observation->'value_per_100') = 'number'
          )
      )
    else false
  end;
$$;

revoke all on function public.apex_valid_nutrient_evidence(jsonb) from public, anon, authenticated;
grant execute on function public.apex_valid_nutrient_evidence(jsonb) to authenticated, service_role;

alter table public.foods drop constraint if exists foods_nutrient_evidence_valid;
alter table public.foods add constraint foods_nutrient_evidence_valid
  check (public.apex_valid_nutrient_evidence(nutrient_evidence));
alter table public.logged_food_entries drop constraint if exists logged_food_entries_nutrient_evidence_valid;
alter table public.logged_food_entries add constraint logged_food_entries_nutrient_evidence_valid
  check (public.apex_valid_nutrient_evidence(snapshot_nutrient_evidence));

-- Every future direct write is normalized before the bounded constraint runs,
-- including recognized legacy spellings from an older client release.
create or replace function public.apex_normalize_nutrient_evidence_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_table_name = 'foods' then
    new.nutrient_evidence := public.apex_canonicalize_nutrient_evidence(new.nutrient_evidence);
  elsif tg_table_name = 'logged_food_entries' then
    new.snapshot_nutrient_evidence := public.apex_canonicalize_nutrient_evidence(new.snapshot_nutrient_evidence);
  end if;
  return new;
end;
$$;

revoke all on function public.apex_normalize_nutrient_evidence_write() from public, anon, authenticated;

drop trigger if exists foods_normalize_nutrient_evidence on public.foods;
create trigger foods_normalize_nutrient_evidence
before insert or update of nutrient_evidence on public.foods
for each row execute function public.apex_normalize_nutrient_evidence_write();

drop trigger if exists logged_food_entries_normalize_nutrient_evidence on public.logged_food_entries;
create trigger logged_food_entries_normalize_nutrient_evidence
before insert or update of snapshot_nutrient_evidence on public.logged_food_entries
for each row execute function public.apex_normalize_nutrient_evidence_write();

-- Corpus adapters retain both their best-effort nutrient_code and the exact
-- publisher source_nutrient_code. Only reviewed source/code pairs are promoted
-- to a shared identity; every other identity is preserved unchanged.
create or replace function public.apex_canonical_corpus_nutrient_code(
  p_source_key text,
  p_source_nutrient_code text,
  p_existing_nutrient_code text
)
returns text
language plpgsql
immutable
parallel safe
set search_path = public
as $$
declare
  v_source text := btrim(coalesce(p_source_key, ''));
  v_code text := btrim(coalesce(p_source_nutrient_code, ''));
  v_fallback text := coalesce(
    nullif(btrim(coalesce(p_existing_nutrient_code, '')), ''),
    nullif(v_code, '')
  );
begin
  if v_source in ('usda-sr-legacy', 'usda-foundation') then
    case v_code
      when '1008' then return 'ENERC_KCAL';
      when '2047' then return 'ENERC_KCAL';
      when '2048' then return 'ENERC_KCAL';
      when '1003' then return 'PROT';
      when '1005' then return 'CHOAVL';
      when '1079' then return 'FIBT';
      when '2000' then return 'SUGAR';
      when '1009' then return 'STARCH';
      when '1004' then return 'FAT';
      when '1258' then return 'FASAT';
      when '1257' then return 'FATRN';
      when '1292' then return 'FAMS';
      when '1293' then return 'FAPU';
      when '1404' then return 'OMEGA3_ALA';
      when '1270' then return 'OMEGA3_ALA';
      when '1278' then return 'OMEGA3_EPA';
      when '1280' then return 'OMEGA3_DPA';
      when '1272' then return 'OMEGA3_DHA';
      when '1316' then return 'OMEGA6_LA';
      when '1269' then return 'OMEGA6_LA';
      when '1321' then return 'OMEGA6_GLA';
      when '1253' then return 'CHOLE';
      when '1093' then return 'NA';
      when '1051' then return 'WATER';
      when '1106' then return 'VITA';
      when '1104' then return 'VITA';
      when '1162' then return 'VITC';
      when '1114' then return 'VITD';
      when '1112' then return 'VITD';
      when '1110' then return 'VITD';
      when '1109' then return 'VITE';
      when '1185' then return 'VITK';
      when '1183' then return 'VITK';
      when '1184' then return 'VITK';
      when '1165' then return 'VITB1';
      when '1166' then return 'VITB2';
      when '1167' then return 'VITB3';
      when '1170' then return 'VITB5';
      when '1175' then return 'VITB6';
      when '1176' then return 'VITB7';
      when '1177' then return 'VITB9';
      when '1190' then return 'VITB9';
      when '1187' then return 'VITB9';
      when '1178' then return 'VITB12';
      when '1107' then return 'CARTB';
      when '1087' then return 'CA';
      when '1089' then return 'FE';
      when '1090' then return 'MG';
      when '1091' then return 'P';
      when '1092' then return 'K';
      when '1095' then return 'ZN';
      when '1098' then return 'CU';
      when '1101' then return 'MN';
      when '1103' then return 'SE';
      when '1100' then return 'I';
      when '1406' then
        if v_source = 'usda-sr-legacy' then return 'OMEGA6_AA'; end if;
      else null;
    end case;
  elsif v_source = 'dk-frida' then
    case v_code
      when '356' then return 'ENERC_KCAL';
      when '359' then return 'ENERC_KCAL';
      when '218' then return 'PROT';
      when '172' then return 'CHOAVL';
      when '168' then return 'FIBT';
      when '245' then return 'SUGAR';
      when '243' then return 'STARCH';
      when '141' then return 'FAT';
      when '248' then return 'FASAT';
      when '261' then return 'FATRN';
      when '247' then return 'FAMS';
      when '251' then return 'FAPU';
      when '249' then return 'OMEGA3';
      when '250' then return 'OMEGA6';
      when '115' then return 'CHOLE';
      when '201' then return 'NA';
      when '327' then return 'NACL';
      when '268' then return 'WATER';
      when '12' then return 'VITA';
      when '47' then return 'VITC';
      when '126' then return 'VITD';
      when '135' then return 'VITE';
      when '442' then return 'VITK';
      when '164' then return 'VITK';
      when '37' then return 'VITB1';
      when '36' then return 'VITB1';
      when '39' then return 'VITB2';
      when '294' then return 'VITB3';
      when '210' then return 'VITB5';
      when '40' then return 'VITB6';
      when '42' then return 'VITB7';
      when '143' then return 'VITB9';
      when '38' then return 'VITB12';
      when '303' then return 'CARTB';
      when '108' then return 'CA';
      when '162' then return 'FE';
      when '184' then return 'MG';
      when '214' then return 'P';
      when '165' then return 'K';
      when '274' then return 'ZN';
      when '166' then return 'CU';
      when '187' then return 'MN';
      when '230' then return 'SE';
      when '163' then return 'I';
      else null;
    end case;
  end if;
  return v_fallback;
end;
$$;

revoke all on function public.apex_canonical_corpus_nutrient_code(text, text, text)
  from public, anon, authenticated;

create or replace function public.apex_canonical_corpus_nutrient_unit(
  p_source_key text,
  p_source_nutrient_code text,
  p_canonical_nutrient_code text,
  p_unit text
)
returns text
language plpgsql
immutable
parallel safe
set search_path = public
as $$
declare
  v_unit text := public.apex_canonical_nutrient_unit(p_unit);
begin
  if p_source_key in ('usda-sr-legacy', 'usda-foundation')
    and p_source_nutrient_code = '1106'
    and p_canonical_nutrient_code = 'VITA'
  then
    if v_unit in ('µg', 'µg RAE') then return 'µg RAE'; end if;
    return null;
  elsif p_source_key in ('usda-sr-legacy', 'usda-foundation')
    and p_source_nutrient_code = '1104'
    and p_canonical_nutrient_code = 'VITA'
  then
    if v_unit = 'IU' then return 'IU'; end if;
    return null;
  elsif p_source_key = 'dk-frida'
    and p_source_nutrient_code = '12'
    and p_canonical_nutrient_code = 'VITA'
  then
    if v_unit = 'µg RE' then return 'µg RE'; end if;
    return null;
  end if;
  return v_unit;
end;
$$;

revoke all on function public.apex_canonical_corpus_nutrient_unit(text, text, text, text)
  from public, anon, authenticated;

create or replace function public.apex_corpus_nutrient_precedence(
  p_source_key text,
  p_source_nutrient_code text,
  p_canonical_nutrient_code text
)
returns integer
language sql
immutable
parallel safe
set search_path = public
as $$
  select coalesce(case
    when p_source_key in ('usda-sr-legacy', 'usda-foundation') then case p_canonical_nutrient_code
      when 'ENERC_KCAL' then array_position(array['1008', '2047', '2048'], p_source_nutrient_code)
      when 'OMEGA3_ALA' then array_position(array['1404', '1270'], p_source_nutrient_code)
      when 'OMEGA6_LA' then array_position(array['1316', '1269'], p_source_nutrient_code)
      when 'VITA' then array_position(array['1106', '1104'], p_source_nutrient_code)
      when 'VITD' then array_position(array['1114', '1112', '1110'], p_source_nutrient_code)
      when 'VITK' then array_position(array['1185', '1183', '1184'], p_source_nutrient_code)
      when 'VITB9' then array_position(array['1177', '1190', '1187'], p_source_nutrient_code)
      else 1
    end
    when p_source_key = 'dk-frida' then case p_canonical_nutrient_code
      when 'ENERC_KCAL' then array_position(array['356', '359'], p_source_nutrient_code)
      when 'VITK' then array_position(array['442', '164'], p_source_nutrient_code)
      when 'VITB1' then array_position(array['37', '36'], p_source_nutrient_code)
      else 1
    end
    else 1
  end, 2147483647);
$$;

revoke all on function public.apex_corpus_nutrient_precedence(text, text, text)
  from public, anon, authenticated;

create or replace function public.apex_corpus_nutrient_evidence(p_record_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with ranked as (
    select
      nutrient.id as sort_order,
      jsonb_strip_nulls(jsonb_build_object(
        'nutrient_code', identity.canonical,
        'name', nutrient.original_nutrient_name,
        'value_per_100', case
          when nutrient.observation_status in ('measured', 'calculated', 'estimated')
            and record.basis_kind in ('per_100g', 'per_100ml')
            and record.basis_amount > 0
            then round(nutrient.value * 100 / record.basis_amount, 8)
          when nutrient.observation_status in ('measured', 'calculated', 'estimated')
            and record.basis_kind = 'per_serving'
            and coalesce(record.source_metadata->>'published_serving', '') ~ '\([0-9]+([.,][0-9]+)?[[:space:]]*g\)'
            then round(
              nutrient.value * 100 / replace(
                substring(record.source_metadata->>'published_serving' from '\(([0-9]+([.,][0-9]+)?)[[:space:]]*g\)'),
                ',', '.'
              )::numeric,
              8
            )
          else null
        end,
        'unit', unit.canonical,
        'observation_status', nutrient.observation_status,
        'original_value_text', nutrient.original_value_text,
        'derivation_method', nutrient.derivation_method,
        'source_key', record.source_key,
        'source_reference', nutrient.source_reference
      )) as payload,
      row_number() over (
        partition by case
          when public.apex_canonical_corpus_nutrient_code(
            record.source_key,
            nutrient.source_nutrient_code,
            nutrient.source_nutrient_code
          ) is distinct from nutrient.source_nutrient_code
            then 'reviewed:' || identity.canonical
          else 'unmapped:' || nutrient.source_nutrient_code
        end
        order by
          public.apex_corpus_nutrient_precedence(
            record.source_key,
            nutrient.source_nutrient_code,
            identity.canonical
          ),
          nutrient.id
      ) as identity_rank
    from public.food_corpus_records record
    join public.food_corpus_sources source using (source_key)
    join public.food_corpus_batches batch on record.batch_id = batch.id
    join public.food_corpus_nutrients nutrient on nutrient.record_id = record.id
    cross join lateral (
      select public.apex_canonical_corpus_nutrient_code(
        record.source_key,
        nutrient.source_nutrient_code,
        nutrient.nutrient_code
      ) as canonical
    ) identity
    cross join lateral (
      select public.apex_canonical_corpus_nutrient_unit(
        record.source_key,
        nutrient.source_nutrient_code,
        identity.canonical,
        nutrient.unit
      ) as canonical
    ) unit
    where record.id = p_record_id
      and source.ingest_status = 'active'
      and batch.status = 'active'
      and unit.canonical is not null
  ), bounded as (
    select payload, sort_order
    from ranked
    where identity_rank = 1
    order by sort_order
    limit 96
  )
  select coalesce(jsonb_agg(bounded.payload order by bounded.sort_order), '[]'::jsonb)
  from bounded;
$$;

revoke all on function public.apex_corpus_nutrient_evidence(uuid) from public, anon, authenticated;
