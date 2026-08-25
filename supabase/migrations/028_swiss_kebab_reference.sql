-- Swiss generic kebab reference from the Federal Food Safety and Veterinary
-- Office food-composition database V7.1, food 1572 "Kebab im Fladenbrot".
-- The composition database calculates this generic profile from ingredients;
-- restaurant recipes and sauces still vary, so the display name says reference.
-- Source: https://naehrwertdaten.ch/de/downloads/

insert into public.foods (
  id, owner_user_id, name, names_i18n, brand, source, provider_product_id,
  nutrition_basis, preparation_state, kcal_100, protein_100, carbs_100, fat_100,
  fibre_100, sugar_100, saturated_fat_100, salt_100, water_ml_100,
  water_basis, water_source_id, confidence
) values (
  '10000000-0000-4000-8000-000000000085',
  null,
  'Kebab in flatbread, Swiss reference',
  '{"en":"Kebab in flatbread, Swiss reference","de":"Kebab im Fladenbrot, Schweizer Referenz","fr":"Kebab dans du pain pita, référence suisse","it":"Kebab nel pane pita, riferimento svizzero","ro":"Kebab în lipie, referință elvețiană","th":"เคบับในขนมปังพิตา สูตรอ้างอิงสวิส"}',
  null,
  'apex_cache',
  'apex-curated:swiss-fsvo-v7.1:1572',
  'per_100g',
  'prepared',
  121, 7.6, 14.6, 3.4,
  1.1, 2.2, 0.6, 0.6, 73.6,
  'reference',
  'swiss-fsvo-v7.1:1572',
  'complete'
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
  salt_100 = excluded.salt_100,
  water_ml_100 = excluded.water_ml_100,
  water_basis = excluded.water_basis,
  water_source_id = excluded.water_source_id,
  confidence = excluded.confidence,
  updated_at = now();

notify pgrst, 'reload schema';
