-- Account-safe Food Memory search and a small provider-verified burger baseline.
-- The attached full corpus remains a separate, deferred source-by-source import.

create or replace function public.search_food_catalog(
  p_query text,
  p_limit integer default 25
)
returns setof public.foods
language sql
stable
security definer
set search_path = public
as $function$
  with input as (
    select
      lower(trim(coalesce(p_query, ''))) as needle,
      least(greatest(coalesce(p_limit, 25), 1), 50) as result_limit
  ), candidates as (
    select
      f.id,
      case
        when lower(f.name) = input.needle then 0
        when lower(coalesce(fp.personal_name, '')) = input.needle then 0
        when lower(f.name) like input.needle || '%' then 1
        when lower(coalesce(f.brand, '')) like input.needle || '%' then 1
        when lower(f.name) like '%' || input.needle || '%' then 2
        when lower(coalesce(f.brand, '')) like '%' || input.needle || '%' then 2
        when lower(coalesce(f.names_i18n::text, '')) like '%' || input.needle || '%' then 3
        when lower(coalesce(fp.personal_name, '')) like '%' || input.needle || '%' then 3
        else 4
      end as search_rank,
      input.result_limit
    from public.foods f
    cross join input
    left join public.food_preferences fp
      on fp.food_id = f.id
     and fp.user_id = auth.uid()
    where auth.uid() is not null
      and (f.owner_user_id is null or f.owner_user_id = auth.uid())
      and coalesce(fp.hidden, false) = false
      and input.needle <> ''
      and (
        lower(f.name) like '%' || input.needle || '%'
        or lower(coalesce(f.brand, '')) like '%' || input.needle || '%'
        or lower(coalesce(f.names_i18n::text, '')) like '%' || input.needle || '%'
        or lower(coalesce(fp.personal_name, '')) like '%' || input.needle || '%'
        or exists (
          select 1 from unnest(coalesce(fp.aliases, '{}'::text[])) alias
          where lower(alias) like '%' || input.needle || '%'
        )
        or not exists (
          select 1
          from regexp_split_to_table(input.needle, '\s+') token
          where lower(concat_ws(
            ' ', f.name, f.brand, f.names_i18n::text,
            fp.personal_name, array_to_string(fp.aliases, ' ')
          )) not like '%' || token || '%'
        )
      )
  )
  select f.*
  from candidates
  join public.foods f on f.id = candidates.id
  order by candidates.search_rank, f.name, candidates.id
  limit (select result_limit from input);
$function$;

revoke all on function public.search_food_catalog(text, integer) from public, anon;
grant execute on function public.search_food_catalog(text, integer) to authenticated;

insert into public.foods (
  id, owner_user_id, name, names_i18n, brand, source, provider_product_id,
  nutrition_basis, preparation_state, kcal_100, protein_100, carbs_100, fat_100,
  fibre_100, sugar_100, saturated_fat_100, confidence
) values
  (
    '33000000-0000-4000-8000-000000000001', null, 'Hamburger, single patty, plain',
    '{"en":"Hamburger, single patty, plain","de":"Hamburger, einfach, natur","de-CH":"Hamburger, einfach, natur","es":"Hamburguesa sencilla, sola","it":"Hamburger singolo, semplice","ja":"ハンバーガー、シングル、プレーン","pt":"Hambúrguer simples, sem acompanhamentos","ro":"Hamburger simplu, fără garnituri","th":"แฮมเบอร์เกอร์ชิ้นเดียว แบบธรรมดา"}',
    'Generic fast food', 'apex_cache', 'apex-curated:usda-fdc-170693',
    'per_100g', 'prepared', 297, 16.52, 31.5, 12.01, 1.7, 4.88, 4.493, 'provider_verified'
  ),
  (
    '33000000-0000-4000-8000-000000000002', null, 'McDonald''s Hamburger',
    '{"en":"McDonald''s Hamburger","de":"McDonald''s Hamburger","de-CH":"McDonald''s Hamburger","es":"Hamburguesa de McDonald''s","it":"Hamburger McDonald''s","ja":"マクドナルド ハンバーガー","pt":"Hambúrguer do McDonald''s","ro":"Hamburger McDonald''s","th":"แมคโดนัลด์ แฮมเบอร์เกอร์"}',
    'McDonald''s', 'apex_cache', 'apex-curated:usda-fdc-170717',
    'per_100g', 'as_sold', 264, 12.92, 30.28, 10.09, 1.3, 6.03, 3.504, 'provider_verified'
  ),
  (
    '33000000-0000-4000-8000-000000000003', null, 'McDonald''s Cheeseburger',
    '{"en":"McDonald''s Cheeseburger","de":"McDonald''s Cheeseburger","de-CH":"McDonald''s Cheeseburger","es":"Cheeseburger de McDonald''s","it":"Cheeseburger McDonald''s","ja":"マクドナルド チーズバーガー","pt":"Cheeseburger do McDonald''s","ro":"Cheeseburger McDonald''s","th":"แมคโดนัลด์ ชีสเบอร์เกอร์"}',
    'McDonald''s', 'apex_cache', 'apex-curated:usda-fdc-170320',
    'per_100g', 'as_sold', 263, 12.97, 27.81, 11.79, 1.1, 6.22, 4.435, 'provider_verified'
  ),
  (
    '33000000-0000-4000-8000-000000000004', null, 'McDonald''s Double Cheeseburger',
    '{"en":"McDonald''s Double Cheeseburger","de":"McDonald''s Doppel-Cheeseburger","de-CH":"McDonald''s Doppel-Cheeseburger","es":"Doble cheeseburger de McDonald''s","it":"Doppio cheeseburger McDonald''s","ja":"マクドナルド ダブルチーズバーガー","pt":"Cheeseburger duplo do McDonald''s","ro":"Cheeseburger dublu McDonald''s","th":"แมคโดนัลด์ ดับเบิลชีสเบอร์เกอร์"}',
    'McDonald''s', 'apex_cache', 'apex-curated:usda-fdc-172065',
    'per_100g', 'as_sold', 282, 15.5, 18.79, 16.09, 0.8, 4.23, 6.998, 'provider_verified'
  ),
  (
    '33000000-0000-4000-8000-000000000005', null, 'Burger King Hamburger',
    '{"en":"Burger King Hamburger","de":"Burger King Hamburger","de-CH":"Burger King Hamburger","es":"Hamburguesa de Burger King","it":"Hamburger Burger King","ja":"バーガーキング ハンバーガー","pt":"Hambúrguer do Burger King","ro":"Hamburger Burger King","th":"เบอร์เกอร์คิง แฮมเบอร์เกอร์"}',
    'Burger King', 'apex_cache', 'apex-curated:usda-fdc-170328',
    'per_100g', 'as_sold', 261, 14.85, 26.76, 10.55, 1, 5.6, 3.821, 'provider_verified'
  ),
  (
    '33000000-0000-4000-8000-000000000006', null, 'Burger King Cheeseburger',
    '{"en":"Burger King Cheeseburger","de":"Burger King Cheeseburger","de-CH":"Burger King Cheeseburger","es":"Cheeseburger de Burger King","it":"Cheeseburger Burger King","ja":"バーガーキング チーズバーガー","pt":"Cheeseburger do Burger King","ro":"Cheeseburger Burger King","th":"เบอร์เกอร์คิง ชีสเบอร์เกอร์"}',
    'Burger King', 'apex_cache', 'apex-curated:usda-fdc-170329',
    'per_100g', 'as_sold', 286, 14.57, 23.71, 14.81, 1, 4.49, 6.842, 'provider_verified'
  )
on conflict (id) do update set
  name = excluded.name,
  names_i18n = excluded.names_i18n,
  brand = excluded.brand,
  source = excluded.source,
  provider_product_id = excluded.provider_product_id,
  nutrition_basis = excluded.nutrition_basis,
  preparation_state = excluded.preparation_state,
  kcal_100 = excluded.kcal_100,
  protein_100 = excluded.protein_100,
  carbs_100 = excluded.carbs_100,
  fat_100 = excluded.fat_100,
  fibre_100 = excluded.fibre_100,
  sugar_100 = excluded.sugar_100,
  saturated_fat_100 = excluded.saturated_fat_100,
  confidence = excluded.confidence,
  updated_at = now();

notify pgrst, 'reload schema';
