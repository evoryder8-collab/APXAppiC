-- Localized staple foods that remain discoverable without a branded-provider lookup.
-- USDA FoodData Central identifiers are retained for traceability. Som tam is a
-- reference recipe because its nutrition varies with the preparation.

insert into foods (
  id, owner_user_id, name, names_i18n, brand, source, provider_product_id,
  nutrition_basis, preparation_state, kcal_100, protein_100, carbs_100, fat_100,
  serving_amount, serving_unit, serving_grams_or_ml, piece_grams_or_ml, confidence
) values
  ('10000000-0000-4000-8000-000000000026', null, 'Organic whole-grain rolled oats', '{"en":"Organic whole-grain rolled oats","de":"Bio-Vollkorn-Haferflocken","fr":"Flocons d’avoine complète bio","it":"Fiocchi d’avena integrale biologica","ro":"Ovăz integral organic","th":"ข้าวโอ๊ตโฮลเกรนออร์แกนิก"}', null, 'apex_cache', 'apex-curated:usda-fdc-173904', 'per_100g', 'dry', 379, 13.2, 67.7, 6.52, null, null, null, null, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000027', null, 'Som tam Thai, green papaya salad', '{"en":"Som tam Thai, green papaya salad","de":"Som Tam Thai, grüner Papayasalat","fr":"Som tam thaï, salade de papaye verte","it":"Som tam thai, insalata di papaya verde","ro":"Som tam thailandez, salată de papaya verde","th":"ส้มตำไทย"}', null, 'apex_cache', 'apex-curated:som-tam-thai-reference', 'per_100g', 'prepared', 92, 4, 13.7, 3.3, 250, 'g', 250, null, 'complete'),
  ('10000000-0000-4000-8000-000000000028', null, 'Fish sauce', '{"en":"Fish sauce","de":"Fischsauce","fr":"Sauce de poisson","it":"Salsa di pesce","ro":"Sos de pește","th":"น้ำปลา"}', null, 'apex_cache', 'apex-curated:usda-fdc-2706457', 'per_100g', 'as_sold', 35, 5.06, 3.64, 0.01, null, null, null, null, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000029', null, 'Avocado, raw', '{"en":"Avocado, raw","de":"Avocado, roh","fr":"Avocat, cru","it":"Avocado, crudo","ro":"Avocado, crud","th":"อะโวคาโด ดิบ"}', null, 'apex_cache', 'apex-curated:usda-fdc-171705', 'per_100g', 'as_sold', 160, 2, 8.53, 14.7, null, null, null, 150, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000030', null, 'Whole egg, raw', '{"en":"Whole egg, raw","de":"Vollei, roh","fr":"Œuf entier, cru","it":"Uovo intero, crudo","ro":"Ou întreg, crud","th":"ไข่ไก่ทั้งฟอง ดิบ"}', null, 'apex_cache', 'apex-curated:usda-fdc-171287', 'per_100g', 'as_sold', 143, 12.6, 0.72, 9.51, null, null, null, 50, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000031', null, 'Whole egg, hard-boiled', '{"en":"Whole egg, hard-boiled","de":"Vollei, hartgekocht","fr":"Œuf entier, dur","it":"Uovo intero, sodo","ro":"Ou întreg, fiert tare","th":"ไข่ต้มสุก"}', null, 'apex_cache', 'apex-curated:usda-fdc-173424', 'per_100g', 'cooked', 155, 12.6, 1.12, 10.6, null, null, null, 50, 'provider_verified')
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
  serving_amount = excluded.serving_amount,
  serving_unit = excluded.serving_unit,
  serving_grams_or_ml = excluded.serving_grams_or_ml,
  piece_grams_or_ml = excluded.piece_grams_or_ml,
  confidence = excluded.confidence,
  updated_at = now();

notify pgrst, 'reload schema';
