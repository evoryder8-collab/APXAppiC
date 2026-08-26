-- Exact photographed product: Sportyfeel Clear Whey, Eistee-Pfirsich.
-- The owner-supplied label confirms the product/flavour and 21 g protein per
-- 25 g portion. EAN and per-100 g nutrition were cross-checked against the
-- matching retail catalogue and nutrition-provider records:
-- https://www.mynetfair.com/de/produktinformation/3382196/clear-whey-protein-pulver-eistee-pfirsich-geschmack-4335619267756-sportyfeel-lidl-pro-dimi-healthcare-gmbh-und-co--kg%2C3382196/
-- https://www.fatsecret.de/Kalorien-Ern%C3%A4hrung/sportyfeel/clear-whey-eistee-pfirsich/100g

insert into public.foods (
  id, owner_user_id, name, names_i18n, brand, barcode, source, provider_product_id,
  nutrition_basis, preparation_state, kcal_100, protein_100, carbs_100, fat_100,
  water_ml_100, water_basis, water_source_id,
  serving_amount, serving_unit, serving_grams_or_ml, confidence
) values (
  '10000000-0000-4000-8000-000000000086',
  null,
  'Clear Whey, peach iced tea',
  '{"en":"Clear Whey, peach iced tea","de":"Clear Whey, Eistee-Pfirsich-Geschmack","fr":"Clear Whey, thé glacé à la pêche","it":"Clear Whey, tè freddo alla pesca","ro":"Clear Whey, ceai rece cu piersică","th":"เคลียร์เวย์ รสชาพีชเย็น"}',
  'Sportyfeel',
  '4335619267756',
  'apex_cache',
  'apex-curated:sportyfeel-clear-whey-peach-iced-tea-label',
  'per_100g',
  'as_sold',
  347, 84, 2.4, 0.1,
  10, 'difference', null,
  25, 'g', 25,
  'provider_verified'
)
on conflict (id) do update set
  name = excluded.name,
  names_i18n = excluded.names_i18n,
  brand = excluded.brand,
  barcode = excluded.barcode,
  source = excluded.source,
  provider_product_id = excluded.provider_product_id,
  nutrition_basis = excluded.nutrition_basis,
  preparation_state = excluded.preparation_state,
  kcal_100 = excluded.kcal_100,
  protein_100 = excluded.protein_100,
  carbs_100 = excluded.carbs_100,
  fat_100 = excluded.fat_100,
  water_ml_100 = excluded.water_ml_100,
  water_basis = excluded.water_basis,
  water_source_id = excluded.water_source_id,
  serving_amount = excluded.serving_amount,
  serving_unit = excluded.serving_unit,
  serving_grams_or_ml = excluded.serving_grams_or_ml,
  confidence = excluded.confidence,
  updated_at = now();

notify pgrst, 'reload schema';
