import type { FoodRecord } from '../lib/food'

const created = '2026-07-12T00:00:00.000Z'

const LOCALIZED_NAMES: Record<string, { ro: string; th: string }> = {
  '10000000-0000-4000-8000-000000000001': { ro: 'Fulgi de ovăz', th: 'ข้าวโอ๊ตรีดแผ่น' },
  '10000000-0000-4000-8000-000000000002': { ro: 'Orez alb, uscat', th: 'ข้าวขาว ดิบ' },
  '10000000-0000-4000-8000-000000000003': { ro: 'Orez alb, fiert', th: 'ข้าวขาว สุก' },
  '10000000-0000-4000-8000-000000000004': { ro: 'Bulgur, uscat', th: 'บัลเกอร์ ดิบ' },
  '10000000-0000-4000-8000-000000000005': { ro: 'Bulgur, fiert', th: 'บัลเกอร์ สุก' },
  '10000000-0000-4000-8000-000000000006': { ro: 'Iaurt grecesc simplu', th: 'กรีกโยเกิร์ตรสธรรมชาติ' },
  '10000000-0000-4000-8000-000000000007': { ro: 'Ou întreg', th: 'ไข่ทั้งฟอง' },
  '10000000-0000-4000-8000-000000000008': { ro: 'Piept de pui, gătit', th: 'อกไก่ สุก' },
  '10000000-0000-4000-8000-000000000009': { ro: 'Cartof dulce, gătit', th: 'มันหวาน สุก' },
  '10000000-0000-4000-8000-000000000010': { ro: 'Broccoli, gătit', th: 'บรอกโคลี สุก' },
  '10000000-0000-4000-8000-000000000011': { ro: 'Brânză cottage', th: 'คอตเทจชีส' },
  '10000000-0000-4000-8000-000000000012': { ro: 'Nuci', th: 'วอลนัต' },
  '10000000-0000-4000-8000-000000000013': { ro: 'Piept de pui, crud', th: 'อกไก่ ดิบ' },
  '10000000-0000-4000-8000-000000000014': { ro: 'Cartof dulce la microunde', th: 'มันหวานไมโครเวฟ' },
  '10000000-0000-4000-8000-000000000015': { ro: 'Piept de pui, fiert', th: 'อกไก่ ต้ม' },
  '10000000-0000-4000-8000-000000000016': { ro: 'Piept de pui, la air fryer, fără ulei adăugat', th: 'อกไก่ หม้อทอดไร้น้ำมัน ไม่เติมน้ำมัน' },
  '10000000-0000-4000-8000-000000000017': { ro: 'Cartof, crud', th: 'มันฝรั่ง ดิบ' },
  '10000000-0000-4000-8000-000000000018': { ro: 'Cartof, copt', th: 'มันฝรั่ง อบ' },
  '10000000-0000-4000-8000-000000000019': { ro: 'Cartof, la air fryer, fără ulei adăugat', th: 'มันฝรั่ง หม้อทอดไร้น้ำมัน ไม่เติมน้ำมัน' },
  '10000000-0000-4000-8000-000000000020': { ro: 'Cartofi prăjiți, la cuptor', th: 'เฟรนช์ฟรายส์ อบ' },
  '10000000-0000-4000-8000-000000000021': { ro: 'Proteină din zer CFM, neutră', th: 'เวย์โปรตีน CFM รสธรรมชาติ' },
  '10000000-0000-4000-8000-000000000022': { ro: 'Proteină din zer izolată, neutră', th: 'เวย์โปรตีนไอโซเลต รสธรรมชาติ' },
  '10000000-0000-4000-8000-000000000023': { ro: 'Proteină din cazeină izolată, neutră', th: 'เคซีนโปรตีนไอโซเลต รสธรรมชาติ' },
  '10000000-0000-4000-8000-000000000024': { ro: 'Proteină din zer M-Budget, vanilie', th: 'เวย์โปรตีน M-Budget วานิลลา' },
  '10000000-0000-4000-8000-000000000025': { ro: 'Proteină din zer izolată ESN, profil de referință', th: 'เวย์โปรตีนไอโซเลต ESN สูตรอ้างอิง' },
}

interface FoodOptions {
  brand?: string
  providerId?: string
  servingGrams?: number
  confidence?: FoodRecord['confidence']
}

function food(
  id: string,
  name: string,
  de: string,
  fr: string,
  it: string,
  kcal: number,
  protein: number,
  carbs: number,
  fat: number,
  preparation: FoodRecord['preparation_state'] = 'as_sold',
  options: FoodOptions = {},
): FoodRecord {
  return {
    id,
    owner_user_id: null,
    name,
    names_i18n: { en: name, de, fr, it, ...LOCALIZED_NAMES[id] },
    brand: options.brand ?? null,
    barcode: null,
    source: 'apex_cache',
    provider_product_id: options.providerId ?? `apex-common:${id}`,
    external_image_url: null,
    package_quantity: null,
    nutrition_basis: 'per_100g',
    preparation_state: preparation,
    kcal_100: kcal,
    protein_100: protein,
    carbs_100: carbs,
    fat_100: fat,
    fibre_100: null,
    sugar_100: null,
    saturated_fat_100: null,
    salt_100: null,
    serving_amount: options.servingGrams ?? null,
    serving_unit: options.servingGrams ? 'g' : null,
    serving_grams_or_ml: options.servingGrams ?? null,
    piece_grams_or_ml: null,
    provider_updated_at: null,
    confidence: options.confidence ?? 'complete',
    created_at: created,
    updated_at: created,
  }
}

export const COMMON_FOODS: FoodRecord[] = [
  food('10000000-0000-4000-8000-000000000001', 'Rolled oats', 'Haferflocken', "Flocons d’avoine", "Fiocchi d’avena", 372, 13.5, 58.7, 7),
  food('10000000-0000-4000-8000-000000000002', 'White rice, dry', 'Weisser Reis, trocken', 'Riz blanc, sec', 'Riso bianco, secco', 360, 7, 79, 0.7, 'dry'),
  food('10000000-0000-4000-8000-000000000003', 'White rice, cooked', 'Weisser Reis, gekocht', 'Riz blanc, cuit', 'Riso bianco, cotto', 130, 2.7, 28, 0.3, 'cooked'),
  food('10000000-0000-4000-8000-000000000004', 'Bulgur, dry', 'Bulgur, trocken', 'Boulgour, sec', 'Bulgur, secco', 342, 12.3, 63.4, 1.3, 'dry'),
  food('10000000-0000-4000-8000-000000000005', 'Bulgur, cooked', 'Bulgur, gekocht', 'Boulgour, cuit', 'Bulgur, cotto', 83, 3.1, 18.6, 0.2, 'cooked'),
  food('10000000-0000-4000-8000-000000000006', 'Greek yoghurt, plain', 'Griechischer Joghurt, nature', 'Yaourt grec, nature', 'Yogurt greco, naturale', 97, 9, 3.9, 5),
  { ...food('10000000-0000-4000-8000-000000000007', 'Whole egg', 'Vollei', 'Œuf entier', 'Uovo intero', 143, 12.6, 0.7, 9.5), piece_grams_or_ml: 58 },
  food('10000000-0000-4000-8000-000000000008', 'Chicken breast, cooked', 'Pouletbrust, gegart', 'Blanc de poulet, cuit', 'Petto di pollo, cotto', 165, 31, 0, 3.6, 'cooked'),
  food('10000000-0000-4000-8000-000000000009', 'Sweet potato, cooked', 'Süsskartoffel, gegart', 'Patate douce, cuite', 'Patata dolce, cotta', 90, 2, 20.7, 0.2, 'cooked'),
  food('10000000-0000-4000-8000-000000000010', 'Broccoli, cooked', 'Brokkoli, gegart', 'Brocoli, cuit', 'Broccoli, cotti', 35, 2.4, 7.2, 0.4, 'cooked'),
  food('10000000-0000-4000-8000-000000000011', 'Cottage cheese', 'Hüttenkäse', 'Cottage cheese', 'Fiocchi di latte', 98, 11.1, 3.4, 4.3),
  food('10000000-0000-4000-8000-000000000012', 'Walnuts', 'Walnüsse', 'Noix', 'Noci', 654, 15.2, 13.7, 65.2),
  food('10000000-0000-4000-8000-000000000013', 'Chicken breast, raw', 'Hähnchenbrust, roh', 'Blanc de poulet, cru', 'Petto di pollo, crudo', 106, 22.5, 0, 1.93, 'as_sold', { providerId: 'apex-curated:usda-fdc-2646170', confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000014', 'Sweet potato, microwaved', 'Süßkartoffel, Mikrowelle', 'Patate douce, micro-ondes', 'Patata dolce, microonde', 90, 2, 20.7, 0.2, 'cooked', { providerId: 'apex-curated:sweet-potato-microwaved' }),
  food('10000000-0000-4000-8000-000000000015', 'Chicken breast, boiled', 'Hähnchenbrust, gekocht', 'Blanc de poulet, bouilli', 'Petto di pollo, bollito', 151, 29, 0, 3, 'cooked', { providerId: 'apex-curated:chicken-breast-boiled', confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000016', 'Chicken breast, air fryer, no added oil', 'Hähnchenbrust, Heißluftfritteuse, ohne Ölzugabe', 'Blanc de poulet, air fryer, sans ajout d’huile', 'Petto di pollo, friggitrice ad aria, senza olio aggiunto', 165, 31, 0, 3.6, 'cooked', { providerId: 'apex-curated:chicken-breast-air-fryer' }),
  food('10000000-0000-4000-8000-000000000017', 'Potato, raw', 'Kartoffel, roh', 'Pomme de terre, crue', 'Patata, cruda', 77, 2.1, 17.5, 0.1, 'as_sold', { providerId: 'apex-curated:potato-raw', confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000018', 'Potato, baked', 'Kartoffel, gebacken', 'Pomme de terre, cuite au four', 'Patata, al forno', 93, 2.5, 21.2, 0.1, 'cooked', { providerId: 'apex-curated:potato-baked', confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000019', 'Potato, air fryer, no added oil', 'Kartoffel, Heißluftfritteuse, ohne Ölzugabe', 'Pomme de terre, air fryer, sans ajout d’huile', 'Patata, friggitrice ad aria, senza olio aggiunto', 93, 2.5, 21.2, 0.1, 'cooked', { providerId: 'apex-curated:potato-air-fryer' }),
  food('10000000-0000-4000-8000-000000000020', 'Potato french fries, oven-baked', 'Pommes frites, im Ofen gebacken', 'Frites, cuites au four', 'Patatine fritte, al forno', 152, 2.7, 23.2, 5.8, 'cooked', { providerId: 'apex-curated:french-fries-oven' }),
  food('10000000-0000-4000-8000-000000000021', 'CFM whey protein, unflavoured', 'CFM Whey Protein, neutral', 'Protéine whey CFM, neutre', 'Proteine whey CFM, neutre', 410, 80, 3.1, 7, 'as_sold', { brand: 'Lee-Sport', providerId: 'apex-curated:lee-sport-cfm-whey-neutral', servingGrams: 30, confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000022', 'Whey protein isolate, unflavoured', 'Whey Isolate, neutral', 'Isolat de protéine whey, neutre', 'Proteine whey isolate, neutre', 364, 86, 1.2, 1.2, 'as_sold', { brand: 'Lee-Sport', providerId: 'apex-curated:lee-sport-whey-isolate-neutral', servingGrams: 30, confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000023', 'Casein protein isolate, unflavoured', 'Casein Isolate, neutral', 'Isolat de caséine, neutre', 'Caseina isolata, neutra', 379, 90, 0.2, 1, 'as_sold', { brand: 'Lee-Sport', providerId: 'apex-curated:lee-sport-casein-isolate-neutral', servingGrams: 30, confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000024', 'M-Budget whey protein, vanilla', 'M-Budget Whey Protein, Vanille', 'Protéine whey M-Budget, vanille', 'Proteine whey M-Budget, vaniglia', 379, 75, 8.8, 4.9, 'as_sold', { brand: 'M-Budget', providerId: 'apex-curated:m-budget-whey-vanilla', servingGrams: 25, confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000025', 'ESN Iso Whey Protein, reference profile', 'ESN Iso Whey Protein, Referenzprofil', 'ESN Iso Whey Protein, profil de référence', 'ESN Iso Whey Protein, profilo di riferimento', 364, 86, 3.3, 0.7, 'as_sold', { brand: 'ESN', providerId: 'apex-curated:esn-iso-whey-reference', servingGrams: 30, confidence: 'provider_verified' }),
]
