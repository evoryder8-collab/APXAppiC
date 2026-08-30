-- Swiss fast-food whole-item references used by resilient Food Memory search.
-- Burger King and KFC values are published per 100 g. Popeyes Switzerland
-- publishes complete-sandwich totals; those values are converted here to the
-- canonical per-100 g basis while retaining the exact official serving mass.
-- McRaclette remains an honestly labelled historical seasonal reference.

with references (
  id, name, names_i18n, brand, provider_product_id, grams,
  kcal_100, protein_100, carbs_100, fat_100, fibre_100, sugar_100,
  saturated_fat_100, salt_100, confidence
) as (
  values
    ('f4570000-0000-4000-8000-000000000001'::uuid, 'Cheeseburger Royal', '{"en":"Cheeseburger Royal","de":"Cheeseburger Royal","de-CH":"Cheeseburger Royal","fr":"Cheeseburger Royal","it":"Cheeseburger Royal","es":"Cheeseburger Royal","pt":"Cheeseburger Royal","ro":"Cheeseburger Royal","th":"ชีสเบอร์เกอร์รอยัล","ja":"チーズバーガー・ロイヤル"}'::jsonb, 'McDonald''s Switzerland', 'fsvo-v5.3:10675', 207.0, 256.0, 15.5, 17.4, 13.5, 1.4, 4.3, null, null, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000002'::uuid, 'McRaclette Classic, seasonal reference', '{"en":"McRaclette Classic, seasonal reference","de":"McRaclette Classic, Saisonreferenz","de-CH":"McRaclette Classic, Saisonreferenz","fr":"McRaclette Classic, référence saisonnière","it":"McRaclette Classic, riferimento stagionale","es":"McRaclette Classic, referencia de temporada","pt":"McRaclette Classic, referência sazonal","ro":"McRaclette Classic, referință sezonieră","th":"McRaclette Classic ข้อมูลอ้างอิงตามฤดูกาล","ja":"McRaclette Classic（季節限定参考値）"}'::jsonb, 'McDonald''s Switzerland', 'mcdonalds-ch:mcraclette-classic-archive', 269.0, 272.0, 16.0, 16.0, 16.0, 1.0, null, null, null, 'complete'),
    ('f4570000-0000-4000-8000-000000000003'::uuid, 'WHOPPER', '{"en":"WHOPPER","de":"WHOPPER","de-CH":"WHOPPER","fr":"WHOPPER","it":"WHOPPER","es":"WHOPPER","pt":"WHOPPER","ro":"WHOPPER","th":"WHOPPER","ja":"WHOPPER"}'::jsonb, 'Burger King Switzerland', 'burger-king-ch:whopper', 281.2, 227.6, 10.9, 17.9, 12.3, null, 3.9, 3.2, 0.1, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000004'::uuid, 'Big King', '{"en":"Big King","de":"Big King","de-CH":"Big King","fr":"Big King","it":"Big King","es":"Big King","pt":"Big King","ro":"Big King","th":"Big King","ja":"Big King"}'::jsonb, 'Burger King Switzerland', 'burger-king-ch:big-king', 242.7, 252.8, 12.8, 17.6, 14.3, null, 3.5, 4.4, 0.3, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000005'::uuid, 'Cheeseburger', '{"en":"Cheeseburger","de":"Cheeseburger","de-CH":"Cheeseburger","fr":"Cheeseburger","it":"Cheeseburger","es":"Cheeseburger","pt":"Cheeseburger","ro":"Cheeseburger","th":"ชีสเบอร์เกอร์","ja":"チーズバーガー"}'::jsonb, 'Burger King Switzerland', 'burger-king-ch:cheeseburger', 124.5, 269.2, 14.7, 24.4, 12.2, null, 4.6, 4.9, 0.4, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000006'::uuid, 'Hamburger', '{"en":"Hamburger","de":"Hamburger","de-CH":"Hamburger","fr":"Hamburger","it":"Hamburger","es":"Hamburguesa","pt":"Hambúrguer","ro":"Hamburger","th":"แฮมเบอร์เกอร์","ja":"ハンバーガー"}'::jsonb, 'Burger King Switzerland', 'burger-king-ch:hamburger', 113.0, 261.4, 14.2, 26.5, 10.7, null, 4.7, 3.6, 0.1, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000007'::uuid, 'Double Crispy Classic', '{"en":"Double Crispy Classic","de":"Double Crispy Classic","de-CH":"Double Crispy Classic","fr":"Double Crispy Classic","it":"Double Crispy Classic","es":"Double Crispy Classic","pt":"Double Crispy Classic","ro":"Double Crispy Classic","th":"Double Crispy Classic","ja":"Double Crispy Classic"}'::jsonb, 'KFC Switzerland', 'kfc-ch:double-crispy-classic', 167.0, 239.0, 12.0, 23.0, 11.0, null, 2.0, null, 1.3, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000008'::uuid, 'Crispy Cheese', '{"en":"Crispy Cheese","de":"Crispy Cheese","de-CH":"Crispy Cheese","fr":"Crispy Cheese","it":"Crispy Cheese","es":"Crispy Cheese","pt":"Crispy Cheese","ro":"Crispy Cheese","th":"Crispy Cheese","ja":"Crispy Cheese"}'::jsonb, 'KFC Switzerland', 'kfc-ch:crispy-cheese', 116.0, 239.0, 11.0, 31.0, 8.0, null, 5.0, null, 1.6, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000009'::uuid, 'Crispy Chili Cheese', '{"en":"Crispy Chili Cheese","de":"Crispy Chili Cheese","de-CH":"Crispy Chili Cheese","fr":"Crispy Chili Cheese","it":"Crispy Chili Cheese","es":"Crispy Chili Cheese","pt":"Crispy Chili Cheese","ro":"Crispy Chili Cheese","th":"Crispy Chili Cheese","ja":"Crispy Chili Cheese"}'::jsonb, 'KFC Switzerland', 'kfc-ch:crispy-chili-cheese', 116.0, 283.0, 11.0, 29.0, 14.0, null, 4.0, null, 1.5, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000010'::uuid, 'Classic Original', '{"en":"Classic Original","de":"Classic Original","de-CH":"Classic Original","fr":"Classic Original","it":"Classic Original","es":"Classic Original","pt":"Classic Original","ro":"Classic Original","th":"Classic Original","ja":"Classic Original"}'::jsonb, 'KFC Switzerland', 'kfc-ch:classic-original', 205.0, 241.0, 13.0, 23.0, 10.0, null, 3.0, null, 1.5, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000011'::uuid, 'Classic Zinger', '{"en":"Classic Zinger","de":"Classic Zinger","de-CH":"Classic Zinger","fr":"Classic Zinger","it":"Classic Zinger","es":"Classic Zinger","pt":"Classic Zinger","ro":"Classic Zinger","th":"Classic Zinger","ja":"Classic Zinger"}'::jsonb, 'KFC Switzerland', 'kfc-ch:classic-zinger', 200.0, 245.0, 13.0, 23.0, 11.0, null, 3.0, null, 1.1, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000012'::uuid, 'Classic Veggie', '{"en":"Classic Veggie","de":"Classic Veggie","de-CH":"Classic Veggie","fr":"Classic Veggie","it":"Classic Veggie","es":"Classic Veggie","pt":"Classic Veggie","ro":"Classic Veggie","th":"Classic Veggie","ja":"Classic Veggie"}'::jsonb, 'KFC Switzerland', 'kfc-ch:classic-veggie', 191.0, 226.0, 9.0, 25.0, 9.0, null, 3.0, null, 1.1, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000013'::uuid, 'Colonel Original', '{"en":"Colonel Original","de":"Colonel Original","de-CH":"Colonel Original","fr":"Colonel Original","it":"Colonel Original","es":"Colonel Original","pt":"Colonel Original","ro":"Colonel Original","th":"Colonel Original","ja":"Colonel Original"}'::jsonb, 'KFC Switzerland', 'kfc-ch:colonel-original', 243.0, 234.0, 12.0, 20.0, 11.0, null, 4.0, null, 1.5, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000014'::uuid, 'Cheese & Bacon', '{"en":"Cheese & Bacon","de":"Cheese & Bacon","de-CH":"Cheese & Bacon","fr":"Cheese & Bacon","it":"Cheese & Bacon","es":"Cheese & Bacon","pt":"Cheese & Bacon","ro":"Cheese & Bacon","th":"Cheese & Bacon","ja":"Cheese & Bacon"}'::jsonb, 'KFC Switzerland', 'kfc-ch:cheese-bacon', 239.0, 249.0, 14.0, 20.0, 12.0, null, 3.0, null, 1.7, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000015'::uuid, 'Classic Chicken Sandwich', '{"en":"Classic Chicken Sandwich","de":"Classic Chicken Sandwich","de-CH":"Classic Chicken Sandwich","fr":"Sandwich au poulet Classic","it":"Panino di pollo Classic","es":"Sándwich de pollo Classic","pt":"Sanduíche de frango Classic","ro":"Sandviș Classic cu pui","th":"แซนด์วิชไก่คลาสสิก","ja":"クラシック・チキンサンド"}'::jsonb, 'Popeyes Switzerland', 'popeyes-ch:item_54262', 254.0, 831.0 * 100 / 254, 33.0 * 100 / 254, 53.0 * 100 / 254, 53.0 * 100 / 254, 2.5 * 100 / 254, 7.5 * 100 / 254, 17.0 * 100 / 254, 3.7 * 100 / 254, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000016'::uuid, 'Spicy Chicken Sandwich', '{"en":"Spicy Chicken Sandwich","de":"Spicy Chicken Sandwich","de-CH":"Spicy Chicken Sandwich","fr":"Sandwich au poulet Spicy","it":"Panino di pollo Spicy","es":"Sándwich de pollo Spicy","pt":"Sanduíche de frango Spicy","ro":"Sandviș picant cu pui","th":"แซนด์วิชไก่สไปซี","ja":"スパイシー・チキンサンド"}'::jsonb, 'Popeyes Switzerland', 'popeyes-ch:item_54295', 254.0, 826.0 * 100 / 254, 33.0 * 100 / 254, 53.0 * 100 / 254, 53.0 * 100 / 254, 2.5 * 100 / 254, 7.2 * 100 / 254, 17.0 * 100 / 254, 4.3 * 100 / 254, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000017'::uuid, 'Deluxe Chicken Sandwich', '{"en":"Deluxe Chicken Sandwich","de":"Deluxe Chicken Sandwich","de-CH":"Deluxe Chicken Sandwich","fr":"Sandwich au poulet Deluxe","it":"Panino di pollo Deluxe","es":"Sándwich de pollo Deluxe","pt":"Sanduíche de frango Deluxe","ro":"Sandviș Deluxe cu pui","th":"แซนด์วิชไก่ดีลักซ์","ja":"デラックス・チキンサンド"}'::jsonb, 'Popeyes Switzerland', 'popeyes-ch:item_55735', 308.0, 931.0 * 100 / 308, 39.0 * 100 / 308, 54.0 * 100 / 308, 61.0 * 100 / 308, 2.7 * 100 / 308, 8.6 * 100 / 308, 22.0 * 100 / 308, 5.1 * 100 / 308, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000018'::uuid, 'Deluxe Spicy Chicken Sandwich', '{"en":"Deluxe Spicy Chicken Sandwich","de":"Deluxe Spicy Chicken Sandwich","de-CH":"Deluxe Spicy Chicken Sandwich","fr":"Sandwich au poulet Deluxe Spicy","it":"Panino di pollo Deluxe Spicy","es":"Sándwich de pollo Deluxe Spicy","pt":"Sanduíche de frango Deluxe Spicy","ro":"Sandviș Deluxe picant cu pui","th":"แซนด์วิชไก่ดีลักซ์สไปซี","ja":"デラックス・スパイシー・チキンサンド"}'::jsonb, 'Popeyes Switzerland', 'popeyes-ch:item_55738', 298.0, 926.0 * 100 / 298, 39.0 * 100 / 298, 55.0 * 100 / 298, 61.0 * 100 / 298, 2.6 * 100 / 298, 8.3 * 100 / 298, 22.0 * 100 / 298, 5.5 * 100 / 298, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000019'::uuid, 'Cheesy Chicken Sandwich', '{"en":"Cheesy Chicken Sandwich","de":"Cheesy Chicken Sandwich","de-CH":"Cheesy Chicken Sandwich","fr":"Sandwich au poulet Cheesy","it":"Panino di pollo Cheesy","es":"Sándwich de pollo Cheesy","pt":"Sanduíche de frango Cheesy","ro":"Sandviș cu pui și brânză","th":"แซนด์วิชไก่ชีส","ja":"チージー・チキンサンド"}'::jsonb, 'Popeyes Switzerland', 'popeyes-ch:02ee86b1-f8cf-4cf1-ba92-82e7fdf0f2a5', 285.0, 836.0 * 100 / 285, 38.0 * 100 / 285, 55.0 * 100 / 285, 51.0 * 100 / 285, 3.0 * 100 / 285, 8.8 * 100 / 285, 21.0 * 100 / 285, 6.5 * 100 / 285, 'provider_verified'),
    ('f4570000-0000-4000-8000-000000000020'::uuid, 'BBQ Chicken Sandwich', '{"en":"BBQ Chicken Sandwich","de":"BBQ Chicken Sandwich","de-CH":"BBQ Chicken Sandwich","fr":"Sandwich au poulet BBQ","it":"Panino di pollo BBQ","es":"Sándwich de pollo BBQ","pt":"Sanduíche de frango BBQ","ro":"Sandviș BBQ cu pui","th":"แซนด์วิชไก่บาร์บีคิว","ja":"BBQチキンサンド"}'::jsonb, 'Popeyes Switzerland', 'popeyes-ch:a384363f-80dc-4777-864b-ff6dd5e86048', 284.0, 744.0 * 100 / 284, 37.0 * 100 / 284, 63.0 * 100 / 284, 37.0 * 100 / 284, 3.1 * 100 / 284, 16.0 * 100 / 284, 18.0 * 100 / 284, 5.0 * 100 / 284, 'provider_verified')
)
insert into public.foods (
  id, owner_user_id, name, names_i18n, brand, source, provider_product_id,
  package_quantity, nutrition_basis, preparation_state,
  kcal_100, protein_100, carbs_100, fat_100, fibre_100, sugar_100,
  saturated_fat_100, salt_100, water_ml_100, water_basis, water_source_id,
  serving_amount, serving_unit, serving_grams_or_ml, confidence
)
select
  id, null, name, names_i18n, brand, 'apex_cache', provider_product_id,
  concat(grams, ' g'), 'per_100g', 'as_sold',
  kcal_100, protein_100, carbs_100, fat_100, fibre_100, sugar_100,
  saturated_fat_100, salt_100, null, 'unknown', null,
  1, 'serving', grams, confidence
from references
on conflict (id) do update set
  name = excluded.name,
  names_i18n = excluded.names_i18n,
  brand = excluded.brand,
  source = excluded.source,
  provider_product_id = excluded.provider_product_id,
  package_quantity = excluded.package_quantity,
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
  serving_amount = excluded.serving_amount,
  serving_unit = excluded.serving_unit,
  serving_grams_or_ml = excluded.serving_grams_or_ml,
  confidence = excluded.confidence,
  updated_at = now();

notify pgrst, 'reload schema';
