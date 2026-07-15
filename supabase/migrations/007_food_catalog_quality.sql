-- Curated whole-food preparations and verified protein products.
-- These rows keep essential foods available ahead of branded provider results.

insert into foods (
  id, owner_user_id, name, names_i18n, brand, source, provider_product_id,
  nutrition_basis, preparation_state, kcal_100, protein_100, carbs_100, fat_100,
  serving_amount, serving_unit, serving_grams_or_ml, confidence
) values
  ('10000000-0000-4000-8000-000000000013', null, 'Chicken breast, raw', '{"en":"Chicken breast, raw","de":"Hähnchenbrust, roh","fr":"Blanc de poulet, cru","it":"Petto di pollo, crudo","ro":"Piept de pui, crud","th":"อกไก่ ดิบ"}', null, 'apex_cache', 'apex-curated:usda-fdc-2646170', 'per_100g', 'as_sold', 106, 22.5, 0, 1.93, null, null, null, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000014', null, 'Sweet potato, microwaved', '{"en":"Sweet potato, microwaved","de":"Süßkartoffel, Mikrowelle","fr":"Patate douce, micro-ondes","it":"Patata dolce, microonde","ro":"Cartof dulce la microunde","th":"มันหวานไมโครเวฟ"}', null, 'apex_cache', 'apex-curated:sweet-potato-microwaved', 'per_100g', 'cooked', 90, 2, 20.7, 0.2, null, null, null, 'complete'),
  ('10000000-0000-4000-8000-000000000015', null, 'Chicken breast, boiled', '{"en":"Chicken breast, boiled","de":"Hähnchenbrust, gekocht","fr":"Blanc de poulet, bouilli","it":"Petto di pollo, bollito","ro":"Piept de pui, fiert","th":"อกไก่ ต้ม"}', null, 'apex_cache', 'apex-curated:chicken-breast-boiled', 'per_100g', 'cooked', 151, 29, 0, 3, null, null, null, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000016', null, 'Chicken breast, air fryer, no added oil', '{"en":"Chicken breast, air fryer, no added oil","de":"Hähnchenbrust, Heißluftfritteuse, ohne Ölzugabe","fr":"Blanc de poulet, air fryer, sans ajout d’huile","it":"Petto di pollo, friggitrice ad aria, senza olio aggiunto","ro":"Piept de pui, la air fryer, fără ulei adăugat","th":"อกไก่ หม้อทอดไร้น้ำมัน ไม่เติมน้ำมัน"}', null, 'apex_cache', 'apex-curated:chicken-breast-air-fryer', 'per_100g', 'cooked', 165, 31, 0, 3.6, null, null, null, 'complete'),
  ('10000000-0000-4000-8000-000000000017', null, 'Potato, raw', '{"en":"Potato, raw","de":"Kartoffel, roh","fr":"Pomme de terre, crue","it":"Patata, cruda","ro":"Cartof, crud","th":"มันฝรั่ง ดิบ"}', null, 'apex_cache', 'apex-curated:potato-raw', 'per_100g', 'as_sold', 77, 2.1, 17.5, 0.1, null, null, null, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000018', null, 'Potato, baked', '{"en":"Potato, baked","de":"Kartoffel, gebacken","fr":"Pomme de terre, cuite au four","it":"Patata, al forno","ro":"Cartof, copt","th":"มันฝรั่ง อบ"}', null, 'apex_cache', 'apex-curated:potato-baked', 'per_100g', 'cooked', 93, 2.5, 21.2, 0.1, null, null, null, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000019', null, 'Potato, air fryer, no added oil', '{"en":"Potato, air fryer, no added oil","de":"Kartoffel, Heißluftfritteuse, ohne Ölzugabe","fr":"Pomme de terre, air fryer, sans ajout d’huile","it":"Patata, friggitrice ad aria, senza olio aggiunto","ro":"Cartof, la air fryer, fără ulei adăugat","th":"มันฝรั่ง หม้อทอดไร้น้ำมัน ไม่เติมน้ำมัน"}', null, 'apex_cache', 'apex-curated:potato-air-fryer', 'per_100g', 'cooked', 93, 2.5, 21.2, 0.1, null, null, null, 'complete'),
  ('10000000-0000-4000-8000-000000000020', null, 'Potato french fries, oven-baked', '{"en":"Potato french fries, oven-baked","de":"Pommes frites, im Ofen gebacken","fr":"Frites, cuites au four","it":"Patatine fritte, al forno","ro":"Cartofi prăjiți, la cuptor","th":"เฟรนช์ฟรายส์ อบ"}', null, 'apex_cache', 'apex-curated:french-fries-oven', 'per_100g', 'cooked', 152, 2.7, 23.2, 5.8, null, null, null, 'complete'),
  ('10000000-0000-4000-8000-000000000021', null, 'CFM whey protein, unflavoured', '{"en":"CFM whey protein, unflavoured","de":"CFM Whey Protein, neutral","fr":"Protéine whey CFM, neutre","it":"Proteine whey CFM, neutre","ro":"Proteină din zer CFM, neutră","th":"เวย์โปรตีน CFM รสธรรมชาติ"}', 'Lee-Sport', 'apex_cache', 'apex-curated:lee-sport-cfm-whey-neutral', 'per_100g', 'as_sold', 410, 80, 3.1, 7, 30, 'g', 30, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000022', null, 'Whey protein isolate, unflavoured', '{"en":"Whey protein isolate, unflavoured","de":"Whey Isolate, neutral","fr":"Isolat de protéine whey, neutre","it":"Proteine whey isolate, neutre","ro":"Proteină din zer izolată, neutră","th":"เวย์โปรตีนไอโซเลต รสธรรมชาติ"}', 'Lee-Sport', 'apex_cache', 'apex-curated:lee-sport-whey-isolate-neutral', 'per_100g', 'as_sold', 364, 86, 1.2, 1.2, 30, 'g', 30, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000023', null, 'Casein protein isolate, unflavoured', '{"en":"Casein protein isolate, unflavoured","de":"Casein Isolate, neutral","fr":"Isolat de caséine, neutre","it":"Caseina isolata, neutra","ro":"Proteină din cazeină izolată, neutră","th":"เคซีนโปรตีนไอโซเลต รสธรรมชาติ"}', 'Lee-Sport', 'apex_cache', 'apex-curated:lee-sport-casein-isolate-neutral', 'per_100g', 'as_sold', 379, 90, 0.2, 1, 30, 'g', 30, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000024', null, 'M-Budget whey protein, vanilla', '{"en":"M-Budget whey protein, vanilla","de":"M-Budget Whey Protein, Vanille","fr":"Protéine whey M-Budget, vanille","it":"Proteine whey M-Budget, vaniglia","ro":"Proteină din zer M-Budget, vanilie","th":"เวย์โปรตีน M-Budget วานิลลา"}', 'M-Budget', 'apex_cache', 'apex-curated:m-budget-whey-vanilla', 'per_100g', 'as_sold', 379, 75, 8.8, 4.9, 25, 'g', 25, 'provider_verified'),
  ('10000000-0000-4000-8000-000000000025', null, 'ESN Iso Whey Protein, reference profile', '{"en":"ESN Iso Whey Protein, reference profile","de":"ESN Iso Whey Protein, Referenzprofil","fr":"ESN Iso Whey Protein, profil de référence","it":"ESN Iso Whey Protein, profilo di riferimento","ro":"Proteină din zer izolată ESN, profil de referință","th":"เวย์โปรตีนไอโซเลต ESN สูตรอ้างอิง"}', 'ESN', 'apex_cache', 'apex-curated:esn-iso-whey-reference', 'per_100g', 'as_sold', 364, 86, 3.3, 0.7, 30, 'g', 30, 'provider_verified')
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
  confidence = excluded.confidence,
  updated_at = now();

notify pgrst, 'reload schema';
