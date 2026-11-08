-- Give the bundled recipe a public food ID for synced meals and previously shipped clients.
alter table public.foods add column if not exists search_aliases text[];
alter table public.foods add column if not exists reference_note text;

-- Keep migration 043's account filtering and ranking; include curated aliases in the same search.
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
      public.food_search_normalize(p_query) as needle,
      least(greatest(coalesce(p_limit, 25), 1), 50) as result_limit
  ), candidates as (
    select
      f.id,
      case
        when input.needle in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
          and coalesce(f.fat_100, 0) >= 90
          and coalesce(f.protein_100, 0) <= 1
          and coalesce(f.carbs_100, 0) <= 1
          and (haystack.value ~ '(extra virgin olive|olive extra virgin|evoo)')
          then -3
        when input.needle in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
          and coalesce(f.fat_100, 0) >= 90
          and coalesce(f.protein_100, 0) <= 1
          and coalesce(f.carbs_100, 0) <= 1
          and (haystack.value ~ '(olive oil|oil olive|vegetable oil|oil vegetable)')
          then -2
        when input.needle in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
          and coalesce(f.fat_100, 0) >= 90
          and coalesce(f.protein_100, 0) <= 1
          and coalesce(f.carbs_100, 0) <= 1
          and (' ' || haystack.value || ' ') ~ (' (oil|ulei|ol|huile|olio|aceite) ')
          then -1
        when input.needle in ('oil', 'ulei', 'ol', 'huile', 'olio', 'aceite')
          and haystack.value ~ '(margarine|margarin|margarina)'
          then 1
        else 0
      end as category_rank,
      case
        when public.food_search_normalize(f.name) = input.needle then 0
        when public.food_search_normalize(coalesce(fp.personal_name, '')) = input.needle then 0
        when exists (select from unnest(f.search_aliases) alias where public.food_search_normalize(alias) = input.needle) then 0
        when public.food_search_normalize(f.name) like input.needle || '%' then 1
        when haystack.value like '%' || input.needle || '%' then 2
        else 3
      end as search_rank,
      greatest(
        similarity(haystack.value, input.needle),
        similarity(public.food_search_normalize(f.name), input.needle),
        similarity(public.food_search_normalize(concat_ws(' ', f.brand, f.name)), input.needle)
      ) as fuzzy_rank,
      input.result_limit
    from public.foods f
    cross join input
    left join public.food_preferences fp
      on fp.food_id = f.id
     and fp.user_id = auth.uid()
    cross join lateral (
      select public.food_search_normalize(concat_ws(
        ' ', f.name, f.brand, f.names_i18n::text, array_to_string(f.search_aliases, ' '),
        fp.personal_name, array_to_string(fp.aliases, ' ')
      )) as value
    ) haystack
    where auth.uid() is not null
      and (f.owner_user_id is null or f.owner_user_id = auth.uid())
      and coalesce(fp.hidden, false) = false
      and length(input.needle) >= 2
      and public.food_search_every_query_token_matches(input.needle, haystack.value)
  )
  select f.*
  from candidates
  join public.foods f on f.id = candidates.id
  order by candidates.category_rank, candidates.search_rank, candidates.fuzzy_rank desc, f.name, candidates.id
  limit (select result_limit from input);
$function$;

-- Nutrients per 100 g use the 350 g edible bowl assumption in reference_note.
-- Royal Thai Air Force recipe ต้มยำขาหมู, pp. 119–120.
-- https://quarter.rtaf.mi.th/web/content/650?download=true&unique=824276502d592c946b673d8e3673771a8b451ff2
insert into public.foods (
  id, name, names_i18n, search_aliases, provider_product_id, serving_grams_or_ml, kcal_100, protein_100, carbs_100, fat_100, reference_note, source, nutrition_basis, preparation_state, confidence, serving_amount, serving_unit
) values (
  'd988c8b0-4aaa-46d9-9a13-20aaae43d2a9',
  'Spicy Pork Leg Soup',
  '{"en": "Spicy Pork Leg Soup", "th": "ต้มยำขาหมู", "de": "Scharfe thailändische Schweinshaxensuppe", "fr": "Soupe thaïlandaise épicée au jarret de porc", "it": "Zuppa thailandese piccante di stinco di maiale", "ro": "Supă thailandeză picantă cu ciolan de porc", "es": "Sopa tailandesa picante de codillo de cerdo", "pt": "Sopa tailandesa picante de joelho de porco", "ja": "タイ風豚すね肉の辛いスープ"}'::jsonb,
  array['Thai Spicy Pork Leg Soup', 'spicy pork hock soup', 'hot and sour pork leg soup', 'Thai pork knuckle soup', 'tom yum kha moo', 'tom yam kha mu', 'tom yum ka moo', 'tom saep kha moo', 'tom saeb kha moo', 'tom saab kha moo', 'tom zap kha moo', 'ต้มแซ่บขาหมู', 'ต้มแซบขาหมู', 'spicy pork leg suop', 'Thai spicy pork leg suop'],
  'apex-curated:spicy-pork-leg-soup',
  350,
  70.9,
  5.55,
  4.14,
  3.57,
  'Recipe estimate from the Royal Thai Air Force foodservice manual (pp. 119–120). One bowl assumes 350 g of edible soup, excluding bones and rice. Recipes vary.',
  'apex_cache',
  'per_100g',
  'prepared',
  'complete',
  1,
  'serving'
) on conflict (id) do nothing;
