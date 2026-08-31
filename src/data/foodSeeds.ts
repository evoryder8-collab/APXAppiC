import { estimateWaterContent } from '../lib/hydration.ts'
import type { FoodRecord } from '../lib/food'
import { EXPANDED_FOOD_SPECS, type CatalogFoodSpec } from './foodCatalogExpansion.ts'

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
  '10000000-0000-4000-8000-000000000026': { ro: 'Ovăz integral organic', th: 'ข้าวโอ๊ตโฮลเกรนออร์แกนิก' },
  '10000000-0000-4000-8000-000000000027': { ro: 'Som tam thailandez, salată de papaya verde', th: 'ส้มตำไทย' },
  '10000000-0000-4000-8000-000000000028': { ro: 'Sos de pește', th: 'น้ำปลา' },
  '10000000-0000-4000-8000-000000000029': { ro: 'Avocado, crud', th: 'อะโวคาโด ดิบ' },
  '10000000-0000-4000-8000-000000000030': { ro: 'Ou întreg, crud', th: 'ไข่ไก่ทั้งฟอง ดิบ' },
  '10000000-0000-4000-8000-000000000031': { ro: 'Ou întreg, fiert tare', th: 'ไข่ต้มสุก' },
  '10000000-0000-4000-8000-000000000032': { ro: 'File de ton Nixe în suc propriu', th: 'เนื้อปลาทูน่า Nixe ในน้ำแร่' },
  '10000000-0000-4000-8000-000000000033': { ro: 'Afine proaspete, profil de referință elvețian', th: 'บลูเบอร์รีสด ข้อมูลอ้างอิงสำหรับสวิตเซอร์แลนด์' },
  '10000000-0000-4000-8000-000000000034': { ro: 'Afine congelate, fără zahăr, profil de referință elvețian', th: 'บลูเบอร์รีแช่แข็ง ไม่เติมน้ำตาล ข้อมูลอ้างอิงสำหรับสวิตเซอร์แลนด์' },
  '10000000-0000-4000-8000-000000000035': { ro: 'Zmeură proaspătă, profil de referință elvețian', th: 'ราสป์เบอร์รีสด ข้อมูลอ้างอิงสำหรับสวิตเซอร์แลนด์' },
  '10000000-0000-4000-8000-000000000036': { ro: 'Zmeură congelată, fără zahăr, profil de referință elvețian', th: 'ราสป์เบอร์รีแช่แข็ง ไม่เติมน้ำตาล ข้อมูลอ้างอิงสำหรับสวิตเซอร์แลนด์' },
  '10000000-0000-4000-8000-000000000037': { ro: 'Fructe de pădure congelate, fără zahăr, profil de referință elvețian', th: 'เบอร์รีรวมแช่แข็ง ไม่เติมน้ำตาล ข้อมูลอ้างอิงสำหรับสวิตเซอร์แลนด์' },
  '10000000-0000-4000-8000-000000000038': { ro: 'Spanac proaspăt, profil de referință elvețian', th: 'ผักโขมสด ข้อมูลอ้างอิงสำหรับสวิตเซอร์แลนด์' },
  '10000000-0000-4000-8000-000000000039': { ro: 'Spanac congelat, profil de referință elvețian', th: 'ผักโขมแช่แข็ง ข้อมูลอ้างอิงสำหรับสวิตเซอร์แลนด์' },
  '10000000-0000-4000-8000-000000000040': { ro: 'Mazăre verde congelată, profil de referință elvețian', th: 'ถั่วลันเตาแช่แข็ง ข้อมูลอ้างอิงสำหรับสวิตเซอร์แลนด์' },
  '10000000-0000-4000-8000-000000000041': { ro: 'Ulei de măsline extravirgin', th: 'น้ำมันมะกอกบริสุทธิ์พิเศษ' },
  '10000000-0000-4000-8000-000000000042': { ro: 'Ulei de măsline extravirgin M-Classic, presat la rece', th: 'น้ำมันมะกอกบริสุทธิ์พิเศษสกัดเย็น M-Classic' },
  '10000000-0000-4000-8000-000000000043': { ro: 'Ulei de măsline extravirgin grecesc LYTTOS, profil de referință', th: 'น้ำมันมะกอกบริสุทธิ์พิเศษกรีก LYTTOS ข้อมูลอ้างอิง' },
  '10000000-0000-4000-8000-000000000044': { ro: 'Ulei de măsline extravirgin Bellasan, profil de referință', th: 'น้ำมันมะกอกบริสุทธิ์พิเศษ Bellasan ข้อมูลอ้างอิง' },
  '10000000-0000-4000-8000-000000000045': { ro: 'Ulei de măsline extravirgin SABO, profil de referință', th: 'น้ำมันมะกอกบริสุทธิ์พิเศษ SABO ข้อมูลอ้างอิง' },
  '10000000-0000-4000-8000-000000000046': { ro: 'Căpșuni proaspete', th: 'สตรอว์เบอร์รีสด' },
  '10000000-0000-4000-8000-000000000047': { ro: 'Căpșuni congelate, fără zahăr', th: 'สตรอว์เบอร์รีแช่แข็ง ไม่เติมน้ำตาล' },
  '10000000-0000-4000-8000-000000000048': { ro: 'Mure proaspete', th: 'แบล็กเบอร์รีสด' },
  '10000000-0000-4000-8000-000000000049': { ro: 'Kiwi proaspăt', th: 'กีวีสด' },
  '10000000-0000-4000-8000-000000000050': { ro: 'Banană proaspătă', th: 'กล้วยสด' },
  '10000000-0000-4000-8000-000000000051': { ro: 'Măr cu coajă', th: 'แอปเปิลพร้อมเปลือก' },
  '10000000-0000-4000-8000-000000000052': { ro: 'Portocală proaspătă', th: 'ส้มสด' },
  '10000000-0000-4000-8000-000000000053': { ro: 'Mango proaspăt', th: 'มะม่วงสด' },
  '10000000-0000-4000-8000-000000000054': { ro: 'Ananas proaspăt', th: 'สับปะรดสด' },
  '10000000-0000-4000-8000-000000000055': { ro: 'Papaya proaspătă', th: 'มะละกอสด' },
  '10000000-0000-4000-8000-000000000056': { ro: 'Struguri proaspeți', th: 'องุ่นสด' },
  '10000000-0000-4000-8000-000000000057': { ro: 'Pepene verde proaspăt', th: 'แตงโมสด' },
  '10000000-0000-4000-8000-000000000058': { ro: 'Pară cu coajă', th: 'ลูกแพร์พร้อมเปลือก' },
  '10000000-0000-4000-8000-000000000059': { ro: 'Semințe de cânepă decorticate', th: 'เมล็ดกัญชงกะเทาะเปลือก' },
  '10000000-0000-4000-8000-000000000060': { ro: 'Semințe de in', th: 'เมล็ดแฟลกซ์' },
  '10000000-0000-4000-8000-000000000061': { ro: 'Semințe de susan negru', th: 'งาดำ' },
  '10000000-0000-4000-8000-000000000062': { ro: 'Semințe de dovleac decojite', th: 'เมล็ดฟักทองกะเทาะเปลือก' },
  '10000000-0000-4000-8000-000000000063': { ro: 'Bucăți de cacao', th: 'คาเคานิบส์' },
  '10000000-0000-4000-8000-000000000064': { ro: 'Fulgi de cocos neîndulciți', th: 'เกล็ดมะพร้าวไม่เติมน้ำตาล' },
  '10000000-0000-4000-8000-000000000065': { ro: 'Roșii cherry proaspete', th: 'มะเขือเทศเชอร์รีสด' },
  '10000000-0000-4000-8000-000000000066': { ro: 'Ceapă verde crudă', th: 'ต้นหอมสด' },
  '10000000-0000-4000-8000-000000000067': { ro: 'Somon afumat la cald', th: 'แซลมอนรมควันร้อน' },
  '10000000-0000-4000-8000-000000000068': { ro: 'File de pangasius, gătit fără ulei', th: 'เนื้อปลาแพนกาเซียส สุก ไม่เติมน้ำมัน' },
  '10000000-0000-4000-8000-000000000069': { ro: 'Inimi de pui, gătite', th: 'หัวใจไก่ สุก' },
  '10000000-0000-4000-8000-000000000070': { ro: 'Cluster Dextrin, fără aromă', th: 'คลัสเตอร์เดกซ์ทริน รสธรรมชาติ' },
  '10000000-0000-4000-8000-000000000071': { ro: 'Lapte Oh! bogat în proteine, fără lactoză', th: 'นม Oh! โปรตีนสูง ปราศจากแลคโตส' },
  '10000000-0000-4000-8000-000000000072': { ro: 'Castravete cu coajă, crud', th: 'แตงกวาพร้อมเปลือก ดิบ' },
  '10000000-0000-4000-8000-000000000073': { ro: 'Morcov crud', th: 'แครอทดิบ' },
  '10000000-0000-4000-8000-000000000074': { ro: 'Ardei gras roșu, crud', th: 'พริกหวานแดง ดิบ' },
  '10000000-0000-4000-8000-000000000075': { ro: 'Roșie crudă', th: 'มะเขือเทศดิบ' },
  '10000000-0000-4000-8000-000000000076': { ro: 'Dovlecel crud', th: 'ซูกินีดิบ' },
  '10000000-0000-4000-8000-000000000077': { ro: 'Conopidă crudă', th: 'ดอกกะหล่ำดิบ' },
  '10000000-0000-4000-8000-000000000078': { ro: 'Fasole verde crudă', th: 'ถั่วแขกดิบ' },
  '10000000-0000-4000-8000-000000000079': { ro: 'Migdale', th: 'อัลมอนด์' },
  '10000000-0000-4000-8000-000000000080': { ro: 'Semințe de chia', th: 'เมล็ดเจีย' },
  '10000000-0000-4000-8000-000000000081': { ro: 'Ayran, băutură de iaurt', th: 'ไอรัน เครื่องดื่มโยเกิร์ต' },
  '10000000-0000-4000-8000-000000000082': { ro: 'Ayran Milbona, pahar', th: 'ไอรัน Milbona แบบถ้วย' },
  '10000000-0000-4000-8000-000000000083': { ro: 'Ayran Milsani, pahar', th: 'ไอรัน Milsani แบบถ้วย' },
  '10000000-0000-4000-8000-000000000084': { ro: 'Ayran bio REWE, pahar', th: 'ไอรันออร์แกนิก REWE แบบถ้วย' },
}

interface FoodOptions {
  brand?: string
  barcode?: string
  providerId?: string
  servingGrams?: number
  servingAmount?: number
  servingUnit?: FoodRecord['serving_unit']
  packageQuantity?: string
  nutritionBasis?: FoodRecord['nutrition_basis']
  fibre?: number
  sugar?: number
  saturatedFat?: number
  salt?: number
  /** Grams of water per 100 g from a named reference. Omit and it is estimated. */
  water?: number
  waterSourceId?: string
  confidence?: FoodRecord['confidence']
}

/* Water content of the curated catalogue, per 100 g. Measured values from the
   Swiss Food Composition Database V7.1 (FSVO) and USDA FoodData Central; the
   rest derived by difference. Kept beside the seeds so the local catalogue and
   migration 010 cannot drift apart. */
const CURATED_WATER: Record<string, number> = {
  '10000000-0000-4000-8000-000000000001': 8.7,
  '10000000-0000-4000-8000-000000000002': 12.3,
  '10000000-0000-4000-8000-000000000003': 68.5,
  '10000000-0000-4000-8000-000000000004': 9.0,
  '10000000-0000-4000-8000-000000000005': 77.8,
  '10000000-0000-4000-8000-000000000006': 81.4,
  '10000000-0000-4000-8000-000000000007': 76.0,
  '10000000-0000-4000-8000-000000000008': 65.3,
  '10000000-0000-4000-8000-000000000009': 73.2,
  '10000000-0000-4000-8000-000000000010': 90.4,
  '10000000-0000-4000-8000-000000000011': 78.6,
  '10000000-0000-4000-8000-000000000012': 4.0,
  '10000000-0000-4000-8000-000000000013': 74.8,
  '10000000-0000-4000-8000-000000000014': 73.2,
  '10000000-0000-4000-8000-000000000015': 66.9,
  '10000000-0000-4000-8000-000000000016': 65.3,
  '10000000-0000-4000-8000-000000000017': 79.7,
  '10000000-0000-4000-8000-000000000018': 71.0,
  '10000000-0000-4000-8000-000000000019': 71.0,
  '10000000-0000-4000-8000-000000000020': 66.7,
  '10000000-0000-4000-8000-000000000021': 6.4,
  '10000000-0000-4000-8000-000000000022': 8.6,
  '10000000-0000-4000-8000-000000000023': 5.3,
  '10000000-0000-4000-8000-000000000024': 7.3,
  '10000000-0000-4000-8000-000000000025': 7.0,
  '10000000-0000-4000-8000-000000000026': 10.8,
  '10000000-0000-4000-8000-000000000027': 76.8,
  '10000000-0000-4000-8000-000000000028': 71.1,
  '10000000-0000-4000-8000-000000000029': 73.2,
  '10000000-0000-4000-8000-000000000030': 76.2,
  '10000000-0000-4000-8000-000000000031': 74.6,
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
  const estimatedWater = estimateWaterContent({
    name, nutrition_basis: options.nutritionBasis ?? 'per_100g',
    kcal_100: kcal, protein_100: protein, carbs_100: carbs,
    fat_100: fat, fibre_100: options.fibre ?? null, salt_100: options.salt ?? null,
  })
  const referencedWater = options.water ?? CURATED_WATER[id]
  const waterBasis: NonNullable<FoodRecord['water_basis']> = referencedWater != null
    ? 'reference'
    : estimatedWater?.basis ?? 'unknown'
  return {
    id,
    owner_user_id: null,
    name,
    names_i18n: { en: name, de, fr, it, ...LOCALIZED_NAMES[id] },
    brand: options.brand ?? null,
    barcode: options.barcode ?? null,
    source: 'apex_cache',
    provider_product_id: options.providerId ?? `apex-common:${id}`,
    external_image_url: null,
    package_quantity: options.packageQuantity ?? null,
    nutrition_basis: options.nutritionBasis ?? 'per_100g',
    preparation_state: preparation,
    kcal_100: kcal,
    protein_100: protein,
    carbs_100: carbs,
    fat_100: fat,
    fibre_100: options.fibre ?? null,
    sugar_100: options.sugar ?? null,
    saturated_fat_100: options.saturatedFat ?? null,
    salt_100: options.salt ?? null,
    water_ml_100: referencedWater ?? estimatedWater?.water_ml_100 ?? null,
    water_basis: waterBasis,
    water_source_id: options.waterSourceId ?? null,
    serving_amount: options.servingAmount ?? options.servingGrams ?? null,
    serving_unit: options.servingUnit ?? (options.servingGrams ? 'g' : null),
    serving_grams_or_ml: options.servingGrams ?? options.servingAmount ?? null,
    piece_grams_or_ml: null,
    provider_updated_at: null,
    confidence: options.confidence ?? 'complete',
    created_at: created,
    updated_at: created,
  }
}

const CORE_FOODS: FoodRecord[] = [
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
  food('10000000-0000-4000-8000-000000000026', 'Organic whole-grain rolled oats', 'Bio-Vollkorn-Haferflocken', 'Flocons d’avoine complète bio', 'Fiocchi d’avena integrale biologica', 379, 13.2, 67.7, 6.52, 'dry', { providerId: 'apex-curated:usda-fdc-173904', confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000027', 'Som tam Thai, green papaya salad', 'Som Tam Thai, grüner Papayasalat', 'Som tam thaï, salade de papaye verte', 'Som tam thai, insalata di papaya verde', 92, 4, 13.7, 3.3, 'prepared', { providerId: 'apex-curated:som-tam-thai-reference', servingGrams: 250, confidence: 'complete' }),
  food('10000000-0000-4000-8000-000000000028', 'Fish sauce', 'Fischsauce', 'Sauce de poisson', 'Salsa di pesce', 35, 5.06, 3.64, 0.01, 'as_sold', { providerId: 'apex-curated:usda-fdc-2706457', confidence: 'provider_verified' }),
  { ...food('10000000-0000-4000-8000-000000000029', 'Avocado, raw', 'Avocado, roh', 'Avocat, cru', 'Avocado, crudo', 160, 2, 8.53, 14.7, 'as_sold', { providerId: 'apex-curated:usda-fdc-171705', confidence: 'provider_verified' }), piece_grams_or_ml: 150 },
  { ...food('10000000-0000-4000-8000-000000000030', 'Whole egg, raw', 'Vollei, roh', 'Œuf entier, cru', 'Uovo intero, crudo', 143, 12.6, 0.72, 9.51, 'as_sold', { providerId: 'apex-curated:usda-fdc-171287', confidence: 'provider_verified' }), piece_grams_or_ml: 50 },
  { ...food('10000000-0000-4000-8000-000000000031', 'Whole egg, hard-boiled', 'Vollei, hartgekocht', 'Œuf entier, dur', 'Uovo intero, sodo', 155, 12.6, 1.12, 10.6, 'cooked', { providerId: 'apex-curated:usda-fdc-173424', confidence: 'provider_verified' }), piece_grams_or_ml: 50 },
  food('10000000-0000-4000-8000-000000000032', 'Nixe tuna fillets in own juice', 'Nixe Thunfischfilets im eigenen Saft', 'Filets de thon Nixe au naturel', 'Filetti di tonno Nixe al naturale', 111, 26, 0, 0.7, 'drained', { brand: 'Nixe', providerId: 'apex-curated:lidl-nixe-tuna-own-juice-label', packageQuantity: '195 g', fibre: 0, sugar: 0, saturatedFat: 0, salt: 0.9, confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000033', 'Blueberries, fresh, Swiss retail reference', 'Heidelbeeren, frisch, Schweizer Handelsreferenz', 'Myrtilles, fraîches, référence commerce suisse', 'Mirtilli, freschi, riferimento retail svizzero', 57, 0.74, 14.49, 0.33, 'as_sold', { providerId: 'apex-curated:swiss-retail-blueberries-fresh-reference' }),
  food('10000000-0000-4000-8000-000000000034', 'Blueberries, frozen, unsweetened, Swiss retail reference', 'Heidelbeeren, tiefgekühlt, ungezuckert, Schweizer Handelsreferenz', 'Myrtilles, surgelées, sans sucre, référence commerce suisse', 'Mirtilli, surgelati, senza zucchero, riferimento retail svizzero', 51, 0.42, 12.17, 0.64, 'as_sold', { providerId: 'apex-curated:swiss-retail-blueberries-frozen-reference' }),
  food('10000000-0000-4000-8000-000000000035', 'Raspberries, fresh, Swiss retail reference', 'Himbeeren, frisch, Schweizer Handelsreferenz', 'Framboises, fraîches, référence commerce suisse', 'Lamponi, freschi, riferimento retail svizzero', 52, 1.2, 11.94, 0.65, 'as_sold', { providerId: 'apex-curated:swiss-retail-raspberries-fresh-reference' }),
  food('10000000-0000-4000-8000-000000000036', 'Raspberries, frozen, unsweetened, Swiss retail reference', 'Himbeeren, tiefgekühlt, ungezuckert, Schweizer Handelsreferenz', 'Framboises, surgelées, sans sucre, référence commerce suisse', 'Lamponi, surgelati, senza zucchero, riferimento retail svizzero', 52, 1.2, 11.94, 0.65, 'as_sold', { providerId: 'apex-curated:swiss-retail-raspberries-frozen-reference' }),
  food('10000000-0000-4000-8000-000000000037', 'Mixed berries, frozen, unsweetened, Swiss retail reference', 'Beerenmischung, tiefgekühlt, ungezuckert, Schweizer Handelsreferenz', 'Mélange de baies, surgelé, sans sucre, référence commerce suisse', 'Frutti di bosco misti, surgelati, senza zucchero, riferimento retail svizzero', 48, 1, 10, 0.4, 'as_sold', { providerId: 'apex-curated:swiss-retail-mixed-berries-frozen-reference' }),
  food('10000000-0000-4000-8000-000000000038', 'Spinach, fresh, Swiss retail reference', 'Spinat, frisch, Schweizer Handelsreferenz', 'Épinards, frais, référence commerce suisse', 'Spinaci, freschi, riferimento retail svizzero', 23, 2.86, 3.63, 0.39, 'as_sold', { providerId: 'apex-curated:swiss-retail-spinach-fresh-reference' }),
  food('10000000-0000-4000-8000-000000000039', 'Spinach, frozen, Swiss retail reference', 'Spinat, tiefgekühlt, Schweizer Handelsreferenz', 'Épinards, surgelés, référence commerce suisse', 'Spinaci, surgelati, riferimento retail svizzero', 29, 3.63, 4.21, 0.57, 'as_sold', { providerId: 'apex-curated:swiss-retail-spinach-frozen-reference' }),
  food('10000000-0000-4000-8000-000000000040', 'Green peas, frozen, Swiss retail reference', 'Erbsen, tiefgekühlt, Schweizer Handelsreferenz', 'Petits pois, surgelés, référence commerce suisse', 'Piselli, surgelati, riferimento retail svizzero', 77, 5.22, 13.62, 0.4, 'as_sold', { providerId: 'apex-curated:swiss-retail-green-peas-frozen-reference' }),
  food('10000000-0000-4000-8000-000000000041', 'Extra virgin olive oil', 'Olivenöl, nativ extra', 'Huile d’olive vierge extra', 'Olio extravergine di oliva', 828, 0, 0, 92, 'as_sold', { providerId: 'apex-curated:extra-virgin-olive-oil-reference', nutritionBasis: 'per_100ml', servingAmount: 15, servingUnit: 'ml', fibre: 0, sugar: 0, saturatedFat: 14, salt: 0 }),
  food('10000000-0000-4000-8000-000000000042', 'M-Classic cold-pressed extra virgin olive oil', 'M-Classic Olivenöl, nativ extra, kaltgepresst', 'Huile d’olive vierge extra pressée à froid M-Classic', 'Olio extravergine di oliva spremuto a freddo M-Classic', 819, 0, 0, 91, 'as_sold', { brand: 'M-Classic', providerId: 'apex-curated:migros-m-classic-cold-pressed-extra-virgin-olive-oil-label', nutritionBasis: 'per_100ml', servingAmount: 15, servingUnit: 'ml', fibre: 0, sugar: 0, saturatedFat: 13, salt: 0, confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000043', 'LYTTOS Greek extra virgin olive oil, reference profile', 'LYTTOS Griechisches Olivenöl, extra nativ, Referenzprofil', 'Huile d’olive grecque vierge extra LYTTOS, profil de référence', 'Olio d’oliva greco extra vergine LYTTOS, profilo di riferimento', 828, 0, 0, 92, 'as_sold', { brand: 'LYTTOS', providerId: 'apex-curated:aldi-suisse-lyttos-greek-extra-virgin-olive-oil-reference', nutritionBasis: 'per_100ml', servingAmount: 15, servingUnit: 'ml', fibre: 0, sugar: 0, saturatedFat: 14, salt: 0 }),
  food('10000000-0000-4000-8000-000000000044', 'Bellasan extra virgin olive oil, reference profile', 'Bellasan Olivenöl, nativ extra, Referenzprofil', 'Huile d’olive vierge extra Bellasan, profil de référence', 'Olio extravergine di oliva Bellasan, profilo di riferimento', 828, 0, 0, 92, 'as_sold', { brand: 'Bellasan', providerId: 'apex-curated:aldi-suisse-bellasan-extra-virgin-olive-oil-reference', nutritionBasis: 'per_100ml', servingAmount: 15, servingUnit: 'ml', fibre: 0, sugar: 0, saturatedFat: 14, salt: 0 }),
  food('10000000-0000-4000-8000-000000000045', 'SABO extra virgin olive oil, reference profile', 'SABO Olivenöl, extra vergine, Referenzprofil', 'Huile d’olive vierge extra SABO, profil de référence', 'Olio d’oliva extra vergine SABO, profilo di riferimento', 828, 0, 0, 92, 'as_sold', { brand: 'SABO', providerId: 'apex-curated:swiss-retail-sabo-extra-virgin-olive-oil-reference', nutritionBasis: 'per_100ml', servingAmount: 15, servingUnit: 'ml', fibre: 0, sugar: 0, saturatedFat: 14, salt: 0 }),
  food('10000000-0000-4000-8000-000000000046', 'Strawberries, fresh', 'Erdbeeren, frisch', 'Fraises, fraîches', 'Fragole, fresche', 32, 0.67, 7.68, 0.3, 'as_sold', { providerId: 'apex-curated:swiss-retail-strawberries-fresh-reference', fibre: 2, sugar: 4.89 }),
  food('10000000-0000-4000-8000-000000000047', 'Strawberries, frozen, unsweetened', 'Erdbeeren, tiefgekühlt, ungezuckert', 'Fraises, surgelées, sans sucre', 'Fragole, surgelate, senza zucchero', 35, 0.43, 9.13, 0.11, 'as_sold', { providerId: 'apex-curated:swiss-retail-strawberries-frozen-reference', fibre: 2.1, sugar: 4.56 }),
  food('10000000-0000-4000-8000-000000000048', 'Blackberries, fresh', 'Brombeeren, frisch', 'Mûres, fraîches', 'More, fresche', 43, 1.39, 9.61, 0.49, 'as_sold', { providerId: 'apex-curated:swiss-retail-blackberries-fresh-reference', fibre: 5.3, sugar: 4.88 }),
  food('10000000-0000-4000-8000-000000000049', 'Kiwi fruit, fresh', 'Kiwi, frisch', 'Kiwi, frais', 'Kiwi, fresco', 61, 1.14, 14.66, 0.52, 'as_sold', { providerId: 'apex-curated:swiss-retail-kiwi-fresh-reference', fibre: 3, sugar: 8.99 }),
  food('10000000-0000-4000-8000-000000000050', 'Banana, fresh', 'Banane, frisch', 'Banane, fraîche', 'Banana, fresca', 89, 1.09, 22.84, 0.33, 'as_sold', { providerId: 'apex-curated:swiss-retail-banana-fresh-reference', fibre: 2.6, sugar: 12.23 }),
  food('10000000-0000-4000-8000-000000000051', 'Apple with skin, fresh', 'Apfel mit Schale, frisch', 'Pomme avec peau, fraîche', 'Mela con buccia, fresca', 52, 0.26, 13.81, 0.17, 'as_sold', { providerId: 'apex-curated:swiss-retail-apple-fresh-reference', fibre: 2.4, sugar: 10.39 }),
  food('10000000-0000-4000-8000-000000000052', 'Orange, fresh', 'Orange, frisch', 'Orange, fraîche', 'Arancia, fresca', 47, 0.94, 11.75, 0.12, 'as_sold', { providerId: 'apex-curated:swiss-retail-orange-fresh-reference', fibre: 2.4, sugar: 9.35 }),
  food('10000000-0000-4000-8000-000000000053', 'Mango, fresh', 'Mango, frisch', 'Mangue, fraîche', 'Mango, fresco', 60, 0.82, 14.98, 0.38, 'as_sold', { providerId: 'apex-curated:swiss-retail-mango-fresh-reference', fibre: 1.6, sugar: 13.66 }),
  food('10000000-0000-4000-8000-000000000054', 'Pineapple, fresh', 'Ananas, frisch', 'Ananas, frais', 'Ananas, fresco', 50, 0.54, 13.12, 0.12, 'as_sold', { providerId: 'apex-curated:swiss-retail-pineapple-fresh-reference', fibre: 1.4, sugar: 9.85 }),
  food('10000000-0000-4000-8000-000000000055', 'Papaya, fresh', 'Papaya, frisch', 'Papaye, fraîche', 'Papaya, fresca', 43, 0.47, 10.82, 0.26, 'as_sold', { providerId: 'apex-curated:swiss-retail-papaya-fresh-reference', fibre: 1.7, sugar: 7.82 }),
  food('10000000-0000-4000-8000-000000000056', 'Grapes, fresh', 'Trauben, frisch', 'Raisins, frais', 'Uva, fresca', 69, 0.72, 18.1, 0.16, 'as_sold', { providerId: 'apex-curated:swiss-retail-grapes-fresh-reference', fibre: 0.9, sugar: 15.48 }),
  food('10000000-0000-4000-8000-000000000057', 'Watermelon, fresh', 'Wassermelone, frisch', 'Pastèque, fraîche', 'Anguria, fresca', 30, 0.61, 7.55, 0.15, 'as_sold', { providerId: 'apex-curated:swiss-retail-watermelon-fresh-reference', fibre: 0.4, sugar: 6.2 }),
  food('10000000-0000-4000-8000-000000000058', 'Pear with skin, fresh', 'Birne mit Schale, frisch', 'Poire avec peau, fraîche', 'Pera con buccia, fresca', 57, 0.36, 15.23, 0.14, 'as_sold', { providerId: 'apex-curated:swiss-retail-pear-fresh-reference', fibre: 3.1, sugar: 9.75 }),
  food('10000000-0000-4000-8000-000000000059', 'Hemp seeds, hulled', 'Hanfsamen, geschält', 'Graines de chanvre décortiquées', 'Semi di canapa decorticati', 553, 31.56, 8.67, 48.75, 'as_sold', { providerId: 'apex-curated:swiss-retail-hemp-seeds-reference', fibre: 4, sugar: 1.5 }),
  food('10000000-0000-4000-8000-000000000060', 'Flaxseed', 'Leinsamen', 'Graines de lin', 'Semi di lino', 534, 18.29, 28.88, 42.16, 'as_sold', { providerId: 'apex-curated:swiss-retail-flaxseed-reference', fibre: 27.3, sugar: 1.55 }),
  food('10000000-0000-4000-8000-000000000061', 'Black sesame seeds', 'Schwarzer Sesam', 'Graines de sésame noir', 'Semi di sesamo nero', 573, 17.73, 23.45, 49.67, 'as_sold', { providerId: 'apex-curated:swiss-retail-black-sesame-reference', fibre: 11.8, sugar: 0.3 }),
  food('10000000-0000-4000-8000-000000000062', 'Pumpkin seeds, hulled', 'Kürbiskerne, geschält', 'Graines de courge décortiquées', 'Semi di zucca decorticati', 559, 30.23, 10.71, 49.05, 'as_sold', { providerId: 'apex-curated:swiss-retail-pumpkin-seeds-reference', fibre: 6, sugar: 1.4 }),
  food('10000000-0000-4000-8000-000000000063', 'Cacao nibs', 'Kakaonibs', 'Éclats de cacao', 'Granella di cacao', 600, 13.3, 26.7, 46.7, 'as_sold', { providerId: 'apex-curated:swiss-retail-cacao-nibs-reference', fibre: 20, sugar: 0.7 }),
  food('10000000-0000-4000-8000-000000000064', 'Coconut flakes, unsweetened', 'Kokosflocken, ungesüßt', 'Flocons de noix de coco, sans sucre', 'Scaglie di cocco, senza zucchero', 660, 6.88, 23.65, 64.53, 'as_sold', { providerId: 'apex-curated:swiss-retail-coconut-flakes-reference', fibre: 16.3, sugar: 7.35 }),
  food('10000000-0000-4000-8000-000000000065', 'Cherry tomatoes, fresh', 'Cherrytomaten, frisch', 'Tomates cerises, fraîches', 'Pomodorini, freschi', 18, 0.88, 3.89, 0.2, 'as_sold', { providerId: 'apex-curated:swiss-retail-cherry-tomatoes-reference', fibre: 1.2, sugar: 2.63 }),
  food('10000000-0000-4000-8000-000000000066', 'Green onion, raw', 'Frühlingszwiebel, roh', 'Oignon vert, cru', 'Cipollotto, crudo', 32, 1.83, 7.34, 0.19, 'as_sold', { providerId: 'apex-curated:swiss-retail-green-onion-reference', fibre: 2.6, sugar: 2.33 }),
  food('10000000-0000-4000-8000-000000000067', 'Salmon, hot-smoked', 'Stremellachs, heißgeräuchert', 'Saumon fumé à chaud', 'Salmone affumicato a caldo', 171, 23, 0, 8.8, 'prepared', { providerId: 'apex-curated:swiss-retail-hot-smoked-salmon-reference' }),
  food('10000000-0000-4000-8000-000000000068', 'Pangasius fillet, cooked without oil', 'Pangasiusfilet, ohne Öl gegart', 'Filet de pangasius, cuit sans huile', 'Filetto di pangasio, cotto senza olio', 92, 15, 0, 3.5, 'cooked', { providerId: 'apex-curated:swiss-retail-pangasius-cooked-reference' }),
  food('10000000-0000-4000-8000-000000000069', 'Chicken hearts, cooked', 'Hühnerherzen, gegart', 'Cœurs de poulet, cuits', 'Cuori di pollo, cotti', 185, 26.41, 0.1, 7.92, 'cooked', { providerId: 'apex-curated:swiss-retail-chicken-hearts-cooked-reference' }),
  food('10000000-0000-4000-8000-000000000070', 'Cluster Dextrin, unflavoured', 'Cluster Dextrin, neutral', 'Cluster Dextrin, neutre', 'Cluster Dextrin, neutro', 381, 0.5, 97, 0.1, 'as_sold', { brand: 'Bodylab', providerId: 'apex-curated:bodylab-cluster-dextrin-label', servingGrams: 60, sugar: 0.5, saturatedFat: 0.1, salt: 0.01, confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000071', 'Oh! High Protein Milk, lactose-free', 'Oh! High Protein Milch, laktosefrei', 'Lait Oh! riche en protéines, sans lactose', 'Latte Oh! ad alto contenuto proteico, senza lattosio', 47, 7, 4.5, 0.1, 'as_sold', { brand: 'Oh! Migros', providerId: 'apex-curated:migros-oh-high-protein-milk-label', nutritionBasis: 'per_100ml', servingAmount: 250, servingUnit: 'ml', fibre: 0, sugar: 4.5, saturatedFat: 0.1, salt: 0.1, confidence: 'provider_verified' }),
  food('10000000-0000-4000-8000-000000000072', 'Cucumber with peel, raw', 'Gurke mit Schale, roh', 'Concombre avec peau, cru', 'Cetriolo con buccia, crudo', 15, 0.65, 3.63, 0.11, 'as_sold', { providerId: 'apex-curated:swiss-retail-cucumber-reference', fibre: 0.5, sugar: 1.67 }),
  food('10000000-0000-4000-8000-000000000073', 'Carrot, raw', 'Karotte, roh', 'Carotte, crue', 'Carota, cruda', 41, 0.93, 9.58, 0.24, 'as_sold', { providerId: 'apex-curated:swiss-retail-carrot-reference', fibre: 2.8, sugar: 4.74 }),
  food('10000000-0000-4000-8000-000000000074', 'Red bell pepper, raw', 'Rote Paprika, roh', 'Poivron rouge, cru', 'Peperone rosso, crudo', 31, 1, 6.03, 0.3, 'as_sold', { providerId: 'apex-curated:swiss-retail-red-bell-pepper-reference', fibre: 2.1, sugar: 4.2 }),
  food('10000000-0000-4000-8000-000000000075', 'Tomato, raw', 'Tomate, roh', 'Tomate, crue', 'Pomodoro, crudo', 18, 0.88, 3.89, 0.2, 'as_sold', { providerId: 'apex-curated:swiss-retail-tomato-reference', fibre: 1.2, sugar: 2.63 }),
  food('10000000-0000-4000-8000-000000000076', 'Zucchini, raw', 'Zucchini, roh', 'Courgette, crue', 'Zucchina, cruda', 17, 1.21, 3.11, 0.32, 'as_sold', { providerId: 'apex-curated:swiss-retail-zucchini-reference', fibre: 1, sugar: 2.5 }),
  food('10000000-0000-4000-8000-000000000077', 'Cauliflower, raw', 'Blumenkohl, roh', 'Chou-fleur, cru', 'Cavolfiore, crudo', 25, 1.92, 4.97, 0.28, 'as_sold', { providerId: 'apex-curated:swiss-retail-cauliflower-reference', fibre: 2, sugar: 1.91 }),
  food('10000000-0000-4000-8000-000000000078', 'Green beans, raw', 'Grüne Bohnen, roh', 'Haricots verts, crus', 'Fagiolini, crudi', 31, 1.83, 6.97, 0.22, 'as_sold', { providerId: 'apex-curated:swiss-retail-green-beans-reference', fibre: 2.7, sugar: 3.26 }),
  food('10000000-0000-4000-8000-000000000079', 'Almonds', 'Mandeln', 'Amandes', 'Mandorle', 579, 21.15, 21.55, 49.93, 'as_sold', { providerId: 'apex-curated:swiss-retail-almonds-reference', fibre: 12.5, sugar: 4.35 }),
  food('10000000-0000-4000-8000-000000000080', 'Chia seeds', 'Chiasamen', 'Graines de chia', 'Semi di chia', 486, 16.54, 42.12, 30.74, 'as_sold', { providerId: 'apex-curated:swiss-retail-chia-seeds-reference', fibre: 34.4, sugar: 0 }),
  food('10000000-0000-4000-8000-000000000081', 'Ayran yoghurt drink', 'Ayran Joghurtgetränk', 'Boisson au yaourt Ayran', 'Bevanda allo yogurt Ayran', 38, 2, 3.5, 1.8, 'as_sold', { providerId: 'apex-curated:ayran-yogurt-drink-reference', nutritionBasis: 'per_100ml', servingAmount: 250, servingUnit: 'ml', packageQuantity: '250 ml', sugar: 3.5, saturatedFat: 1.2, salt: 0.8 }),
  food('10000000-0000-4000-8000-000000000082', 'Milbona Ayran, cup', 'Milbona Ayran, Becher', 'Ayran Milbona, gobelet', 'Ayran Milbona, bicchiere', 38, 2.4, 2.4, 1.9, 'as_sold', { brand: 'Milbona', providerId: 'apex-curated:lidl-milbona-ayran-cup-reference', nutritionBasis: 'per_100ml', servingAmount: 250, servingUnit: 'ml', packageQuantity: '250 ml', sugar: 2.4, saturatedFat: 1.2, salt: 0.7 }),
  food('10000000-0000-4000-8000-000000000083', 'Milsani Ayran, cup', 'Milsani Ayran, Becher', 'Ayran Milsani, gobelet', 'Ayran Milsani, bicchiere', 38, 2, 3.5, 1.8, 'as_sold', { brand: 'Milsani', providerId: 'apex-curated:aldi-milsani-ayran-cup-reference', nutritionBasis: 'per_100ml', servingAmount: 250, servingUnit: 'ml', packageQuantity: '250 ml', sugar: 3.5, saturatedFat: 1.2, salt: 0.8 }),
  food('10000000-0000-4000-8000-000000000084', 'REWE Bio Ayran, cup', 'REWE Bio Ayran, Becher', 'Ayran bio REWE, gobelet', 'Ayran bio REWE, bicchiere', 39, 2.1, 2.6, 2.2, 'as_sold', { brand: 'REWE Bio', providerId: 'apex-curated:rewe-bio-ayran-cup-label', nutritionBasis: 'per_100ml', servingAmount: 250, servingUnit: 'ml', packageQuantity: '250 ml', sugar: 2.6, saturatedFat: 1.6, salt: 0.7, confidence: 'provider_verified' }),
  {
    ...food('b70c0000-0000-4000-8000-000000000001', 'Wild broccoli (broccoli rabe / rapini), raw', 'Stängelkohl (Cime di rapa / Rapini), roh', 'Brocoli-rave (rapini), cru', 'Cime di rapa (rapini), crude', 22, 3.17, 2.85, 0.49, 'as_sold', { providerId: 'apex-curated:usda-fdc-170381', fibre: 2.7, water: 92.55, waterSourceId: 'usda-fdc-sr-170381:water', confidence: 'provider_verified' }),
    names_i18n: {
      en: 'Wild broccoli (broccoli rabe / rapini), raw',
      de: 'Stängelkohl (Cime di rapa / Rapini), roh',
      'de-CH': 'Stängelkohl (Cime di rapa / Rapini), roh',
      fr: 'Brocoli-rave (rapini), cru',
      it: 'Cime di rapa (rapini), crude',
      es: 'Grelo (rapini / brócoli rabe), crudo',
      pt: 'Grelos (rapini), crus',
      ro: 'Broccoli rabe (rapini), crud',
      th: 'บรอกโคลีราเบ (ราพินี) ดิบ',
      ja: 'ブロッコリーラーブ（ラピーニ）、生',
    },
  },
  {
    ...food('b70c0000-0000-4000-8000-000000000002', 'Broccolini (thin-stem broccoli), raw', 'Broccolini (Spargelbrokkoli), roh', 'Broccolini (brocoli à tiges fines), cru', 'Broccolini (broccoli a gambo sottile), crudi', 29, 3.2, 2, 0.4, 'as_sold', { providerId: 'apex-curated:afcd-F001909', fibre: 2.5, sugar: 1.3, water: 92.2, waterSourceId: 'afcd-r3:F001909:moisture', confidence: 'provider_verified' }),
    names_i18n: {
      en: 'Broccolini (thin-stem broccoli), raw',
      de: 'Broccolini (Spargelbrokkoli), roh',
      'de-CH': 'Broccolini (Spargelbrokkoli), roh',
      fr: 'Broccolini (brocoli à tiges fines), cru',
      it: 'Broccolini (broccoli a gambo sottile), crudi',
      es: 'Broccolini (brócoli de tallo fino), crudo',
      pt: 'Broccolini (brócolos de talo fino), cru',
      ro: 'Broccolini (broccoli cu tulpină subțire), crud',
      th: 'บรอกโคลินี (บรอกโคลีต้นเรียว) ดิบ',
      ja: 'ブロッコリーニ（細茎ブロッコリー）、生',
    },
  },
]

/* Nutrition V3 uses a broad offline foundation instead of a tiny list of
   hand-picked products. These values describe the named food per 100 g and
   deliberately remain generic references. Exact packaged labels still win
   when a barcode or provider result is available. */
const BASE_PROTOCOL_FOOD_SPECS: CatalogFoodSpec[] = [
  {
    slug: 'cherries-fresh',
    names: { en: 'Cherries, fresh', de: 'Kirschen, frisch', fr: 'Cerises, fraîches', it: 'Ciliegie, fresche', ro: 'Cireșe proaspete', th: 'เชอร์รีสด' },
    kcal: 63, protein: 1.06, carbs: 16.01, fat: 0.2, fibre: 2.1, sugar: 12.82,
  },
  {
    slug: 'cherries-frozen',
    names: { en: 'Cherries, frozen, unsweetened', de: 'Kirschen, tiefgekühlt, ungezuckert', fr: 'Cerises, surgelées, sans sucre', it: 'Ciliegie, surgelate, senza zucchero', ro: 'Cireșe congelate, fără zahăr', th: 'เชอร์รีแช่แข็ง ไม่เติมน้ำตาล' },
    kcal: 46, protein: 0.92, carbs: 11.02, fat: 0.44, fibre: 1.6, sugar: 9.42,
  },
  {
    slug: 'sour-cherries-frozen',
    names: { en: 'Sour cherries, frozen, unsweetened', de: 'Sauerkirschen, tiefgekühlt, ungezuckert', fr: 'Griottes, surgelées, sans sucre', it: 'Amarene, surgelate, senza zucchero', ro: 'Vișine congelate, fără zahăr', th: 'เชอร์รีเปรี้ยวแช่แข็ง ไม่เติมน้ำตาล' },
    kcal: 46, protein: 0.92, carbs: 11.02, fat: 0.44, fibre: 1.6, sugar: 9.42,
  },
  {
    slug: 'mango-frozen',
    names: { en: 'Mango chunks, frozen, unsweetened', de: 'Mangowürfel, tiefgekühlt, ungezuckert', fr: 'Morceaux de mangue, surgelés, sans sucre', it: 'Cubetti di mango, surgelati, senza zucchero', ro: 'Bucăți de mango congelate, fără zahăr', th: 'มะม่วงแช่แข็ง ไม่เติมน้ำตาล' },
    kcal: 60, protein: 0.82, carbs: 14.98, fat: 0.38, fibre: 1.6, sugar: 13.66,
  },
  {
    slug: 'pineapple-frozen',
    names: { en: 'Pineapple chunks, frozen, unsweetened', de: 'Ananasstücke, tiefgekühlt, ungezuckert', fr: 'Morceaux d’ananas, surgelés, sans sucre', it: 'Pezzi di ananas, surgelati, senza zucchero', ro: 'Bucăți de ananas congelate, fără zahăr', th: 'สับปะรดหั่นชิ้นแช่แข็ง ไม่เติมน้ำตาล' },
    kcal: 50, protein: 0.54, carbs: 13.12, fat: 0.12, fibre: 1.4, sugar: 9.85,
  },
  {
    slug: 'summer-fruit-frozen',
    names: { en: 'Summer fruit mix, frozen, unsweetened', de: 'Sommerfrüchte-Mix, tiefgekühlt, ungezuckert', fr: 'Mélange de fruits d’été, surgelé, sans sucre', it: 'Mix di frutta estiva, surgelato, senza zucchero', ro: 'Amestec de fructe de vară congelate, fără zahăr', th: 'ผลไม้ฤดูร้อนรวมแช่แข็ง ไม่เติมน้ำตาล' },
    kcal: 49, protein: 0.8, carbs: 11.4, fat: 0.35, fibre: 2.4, sugar: 8.8,
  },
  {
    slug: 'banana-frozen',
    names: { en: 'Banana slices, frozen', de: 'Bananenscheiben, tiefgekühlt', fr: 'Rondelles de banane, surgelées', it: 'Fette di banana, surgelate', ro: 'Felii de banană congelate', th: 'กล้วยหั่นแว่นแช่แข็ง' },
    kcal: 89, protein: 1.09, carbs: 22.84, fat: 0.33, fibre: 2.6, sugar: 12.23,
  },
  {
    slug: 'low-fat-quark',
    names: { en: 'Low-fat quark, plain', de: 'Magerquark, nature', fr: 'Séré maigre, nature', it: 'Quark magro, naturale', ro: 'Quark degresat, simplu', th: 'ควาร์กไขมันต่ำ รสธรรมชาติ' },
    kcal: 67, protein: 12, carbs: 4, fat: 0.3, sugar: 4,
  },
  {
    slug: 'skyr-plain',
    names: { en: 'Skyr, plain', de: 'Skyr, nature', fr: 'Skyr, nature', it: 'Skyr, naturale', ro: 'Skyr simplu', th: 'สกีร์รสธรรมชาติ' },
    kcal: 63, protein: 11, carbs: 4, fat: 0.2, sugar: 4,
  },
  {
    slug: 'yoghurt-plain-two-percent',
    names: { en: 'Yoghurt, plain, 2% fat', de: 'Joghurt, nature, 2% Fett', fr: 'Yaourt nature, 2% de matière grasse', it: 'Yogurt naturale, 2% di grassi', ro: 'Iaurt simplu, 2% grăsime', th: 'โยเกิร์ตรสธรรมชาติ ไขมัน 2%' },
    kcal: 61, protein: 4.3, carbs: 4.7, fat: 2, sugar: 4.7,
  },
  {
    slug: 'protein-yoghurt-plain',
    names: { en: 'High-protein yoghurt, plain', de: 'High-Protein-Joghurt, nature', fr: 'Yaourt riche en protéines, nature', it: 'Yogurt ad alto contenuto proteico, naturale', ro: 'Iaurt bogat în proteine, simplu', th: 'โยเกิร์ตโปรตีนสูง รสธรรมชาติ' },
    kcal: 68, protein: 10, carbs: 5, fat: 0.9, sugar: 4.5,
  },
  {
    slug: 'honey',
    names: { en: 'Honey', de: 'Honig', fr: 'Miel', it: 'Miele', ro: 'Miere', th: 'น้ำผึ้ง' },
    kcal: 304, protein: 0.3, carbs: 82.4, fat: 0, sugar: 82.1,
  },
  {
    slug: 'wholegrain-toast',
    names: { en: 'Wholegrain toast', de: 'Vollkorntoast', fr: 'Pain de mie complet', it: 'Pane tostato integrale', ro: 'Pâine prăjită integrală', th: 'ขนมปังโฮลเกรนปิ้ง' },
    kcal: 247, protein: 12.5, carbs: 41.3, fat: 4.2, fibre: 6.8, sugar: 4.4, pieceGrams: 35,
  },
  {
    slug: 'wholegrain-bread',
    names: { en: 'Wholegrain bread', de: 'Vollkornbrot', fr: 'Pain complet', it: 'Pane integrale', ro: 'Pâine integrală', th: 'ขนมปังโฮลเกรน' },
    kcal: 247, protein: 12.5, carbs: 41.3, fat: 4.2, fibre: 6.8, sugar: 4.4, pieceGrams: 40,
  },
  {
    slug: 'peanut-butter',
    names: { en: 'Peanut butter, 100% peanuts', de: 'Erdnussmus, 100% Erdnüsse', fr: 'Beurre de cacahuète, 100% cacahuètes', it: 'Burro di arachidi, 100% arachidi', ro: 'Unt de arahide, 100% arahide', th: 'เนยถั่วลิสง 100%' },
    kcal: 588, protein: 25.1, carbs: 20, fat: 50.4, fibre: 6, sugar: 9.2,
  },
  {
    slug: 'almond-butter',
    names: { en: 'Almond butter, 100% almonds', de: 'Mandelmus, 100% Mandeln', fr: 'Purée d’amandes, 100% amandes', it: 'Crema di mandorle, 100% mandorle', ro: 'Unt de migdale, 100% migdale', th: 'เนยอัลมอนด์ 100%' },
    kcal: 614, protein: 21.1, carbs: 18.8, fat: 55.5, fibre: 10.3, sugar: 4.4,
  },
  {
    slug: 'mixed-seeds',
    names: { en: 'Mixed seed blend', de: 'Samenmischung', fr: 'Mélange de graines', it: 'Mix di semi', ro: 'Amestec de semințe', th: 'เมล็ดรวม' },
    kcal: 560, protein: 23, carbs: 16, fat: 45, fibre: 14, sugar: 2,
  },
  {
    slug: 'turkey-breast-raw',
    names: { en: 'Turkey breast, raw', de: 'Putenbrust, roh', fr: 'Blanc de dinde, cru', it: 'Petto di tacchino, crudo', ro: 'Piept de curcan, crud', th: 'อกไก่งวง ดิบ' },
    kcal: 114, protein: 23.7, carbs: 0, fat: 1.5,
  },
  {
    slug: 'turkey-breast-cooked',
    names: { en: 'Turkey breast, cooked', de: 'Putenbrust, gegart', fr: 'Blanc de dinde, cuit', it: 'Petto di tacchino, cotto', ro: 'Piept de curcan, gătit', th: 'อกไก่งวง สุก' },
    kcal: 147, protein: 30.1, carbs: 0, fat: 2.1, preparation: 'cooked',
  },
  {
    slug: 'lean-beef-cooked',
    names: { en: 'Lean beef, cooked', de: 'Mageres Rindfleisch, gegart', fr: 'Bœuf maigre, cuit', it: 'Manzo magro, cotto', ro: 'Carne slabă de vită, gătită', th: 'เนื้อวัวไม่ติดมัน สุก' },
    kcal: 206, protein: 29, carbs: 0, fat: 9.2, preparation: 'cooked',
  },
  {
    slug: 'cod-cooked',
    names: { en: 'Cod fillet, cooked', de: 'Kabeljaufilet, gegart', fr: 'Filet de cabillaud, cuit', it: 'Filetto di merluzzo, cotto', ro: 'File de cod, gătit', th: 'เนื้อปลาค็อด สุก' },
    kcal: 89, protein: 19.9, carbs: 0, fat: 0.7, preparation: 'cooked',
  },
  {
    slug: 'tuna-drained',
    names: { en: 'Tuna in water, drained', de: 'Thunfisch in Wasser, abgetropft', fr: 'Thon au naturel, égoutté', it: 'Tonno al naturale, sgocciolato', ro: 'Ton în apă, scurs', th: 'ทูน่าในน้ำ สะเด็ดน้ำ' },
    kcal: 116, protein: 25.5, carbs: 0, fat: 0.8, preparation: 'drained',
  },
  {
    slug: 'salmon-cooked',
    names: { en: 'Salmon fillet, cooked', de: 'Lachsfilet, gegart', fr: 'Filet de saumon, cuit', it: 'Filetto di salmone, cotto', ro: 'File de somon, gătit', th: 'เนื้อปลาแซลมอน สุก' },
    kcal: 206, protein: 22.1, carbs: 0, fat: 12.4, preparation: 'cooked',
  },
  {
    slug: 'shrimp-cooked',
    names: { en: 'Shrimp, cooked', de: 'Garnelen, gegart', fr: 'Crevettes, cuites', it: 'Gamberi, cotti', ro: 'Creveți gătiți', th: 'กุ้ง สุก' },
    kcal: 99, protein: 24, carbs: 0.2, fat: 0.3, preparation: 'cooked',
  },
  {
    slug: 'sweet-potato-baked',
    names: { en: 'Sweet potato, baked', de: 'Süsskartoffel, gebacken', fr: 'Patate douce, cuite au four', it: 'Patata dolce, al forno', ro: 'Cartof dulce, copt', th: 'มันหวาน อบ' },
    kcal: 90, protein: 2, carbs: 20.7, fat: 0.2, fibre: 3.3, sugar: 6.5, preparation: 'cooked',
  },
  {
    slug: 'basmati-rice-dry',
    names: { en: 'Basmati rice, dry', de: 'Basmatireis, trocken', fr: 'Riz basmati, sec', it: 'Riso basmati, secco', ro: 'Orez basmati, uscat', th: 'ข้าวบาสมาติ ดิบ' },
    kcal: 356, protein: 8.9, carbs: 77.8, fat: 0.9, fibre: 1, preparation: 'dry',
  },
  {
    slug: 'jasmine-rice-dry',
    names: { en: 'Jasmine rice, dry', de: 'Jasminreis, trocken', fr: 'Riz jasmin, sec', it: 'Riso jasmine, secco', ro: 'Orez jasmine, uscat', th: 'ข้าวหอมมะลิ ดิบ' },
    kcal: 356, protein: 7.1, carbs: 79.2, fat: 0.7, fibre: 0.9, preparation: 'dry',
  },
  {
    slug: 'brown-rice-dry',
    names: { en: 'Brown rice, dry', de: 'Vollkornreis, trocken', fr: 'Riz complet, sec', it: 'Riso integrale, secco', ro: 'Orez brun, uscat', th: 'ข้าวกล้อง ดิบ' },
    kcal: 370, protein: 7.9, carbs: 77.2, fat: 2.9, fibre: 3.5, preparation: 'dry',
  },
  {
    slug: 'quinoa-dry',
    names: { en: 'Quinoa, dry', de: 'Quinoa, trocken', fr: 'Quinoa, sec', it: 'Quinoa, secca', ro: 'Quinoa, uscată', th: 'ควินัว ดิบ' },
    kcal: 368, protein: 14.1, carbs: 64.2, fat: 6.1, fibre: 7, preparation: 'dry',
  },
  {
    slug: 'couscous-dry',
    names: { en: 'Couscous, dry', de: 'Couscous, trocken', fr: 'Couscous, sec', it: 'Couscous, secco', ro: 'Cuscus, uscat', th: 'คูสคูส ดิบ' },
    kcal: 376, protein: 12.8, carbs: 77.4, fat: 0.6, fibre: 5, preparation: 'dry',
  },
  {
    slug: 'wholegrain-pasta-dry',
    names: { en: 'Wholegrain pasta, dry', de: 'Vollkornpasta, trocken', fr: 'Pâtes complètes, sèches', it: 'Pasta integrale, secca', ro: 'Paste integrale, uscate', th: 'พาสต้าโฮลเกรน แห้ง' },
    kcal: 348, protein: 14.6, carbs: 64.8, fat: 2.5, fibre: 8, preparation: 'dry',
  },
  {
    slug: 'lentils-cooked',
    names: { en: 'Lentils, cooked', de: 'Linsen, gekocht', fr: 'Lentilles, cuites', it: 'Lenticchie, cotte', ro: 'Linte fiartă', th: 'ถั่วเลนทิล สุก' },
    kcal: 116, protein: 9, carbs: 20.1, fat: 0.4, fibre: 7.9, preparation: 'cooked',
  },
  {
    slug: 'chickpeas-cooked',
    names: { en: 'Chickpeas, cooked', de: 'Kichererbsen, gekocht', fr: 'Pois chiches, cuits', it: 'Ceci, cotti', ro: 'Năut fiert', th: 'ถั่วลูกไก่ สุก' },
    kcal: 164, protein: 8.9, carbs: 27.4, fat: 2.6, fibre: 7.6, preparation: 'cooked',
  },
  {
    slug: 'kidney-beans-cooked',
    names: { en: 'Kidney beans, cooked', de: 'Kidneybohnen, gekocht', fr: 'Haricots rouges, cuits', it: 'Fagioli rossi, cotti', ro: 'Fasole roșie fiartă', th: 'ถั่วแดง สุก' },
    kcal: 127, protein: 8.7, carbs: 22.8, fat: 0.5, fibre: 6.4, preparation: 'cooked',
  },
  {
    slug: 'broccoli-frozen',
    names: { en: 'Broccoli florets, frozen', de: 'Brokkoliröschen, tiefgekühlt', fr: 'Fleurettes de brocoli, surgelées', it: 'Cimette di broccoli, surgelate', ro: 'Buchețele de broccoli congelate', th: 'บรอกโคลีแช่แข็ง' },
    kcal: 34, protein: 2.8, carbs: 6.6, fat: 0.4, fibre: 2.6,
  },
  {
    slug: 'cauliflower-frozen',
    names: { en: 'Cauliflower florets, frozen', de: 'Blumenkohlröschen, tiefgekühlt', fr: 'Fleurettes de chou-fleur, surgelées', it: 'Cimette di cavolfiore, surgelate', ro: 'Buchețele de conopidă congelate', th: 'ดอกกะหล่ำแช่แข็ง' },
    kcal: 24, protein: 2, carbs: 4.7, fat: 0.3, fibre: 2.3,
  },
  {
    slug: 'green-beans-frozen',
    names: { en: 'Green beans, frozen', de: 'Grüne Bohnen, tiefgekühlt', fr: 'Haricots verts, surgelés', it: 'Fagiolini, surgelati', ro: 'Fasole verde congelată', th: 'ถั่วแขกแช่แข็ง' },
    kcal: 31, protein: 1.8, carbs: 7, fat: 0.2, fibre: 2.7,
  },
  {
    slug: 'peas-carrots-frozen',
    names: { en: 'Peas and carrots, frozen', de: 'Erbsen und Karotten, tiefgekühlt', fr: 'Petits pois et carottes, surgelés', it: 'Piselli e carote, surgelati', ro: 'Mazăre și morcovi congelați', th: 'ถั่วลันเตาและแครอทแช่แข็ง' },
    kcal: 64, protein: 3.5, carbs: 11.5, fat: 0.4, fibre: 4,
  },
  {
    slug: 'mixed-vegetables-frozen',
    names: { en: 'Mixed vegetables, frozen', de: 'Gemüsemischung, tiefgekühlt', fr: 'Mélange de légumes, surgelé', it: 'Verdure miste, surgelate', ro: 'Amestec de legume congelate', th: 'ผักรวมแช่แข็ง' },
    kcal: 54, protein: 3, carbs: 9, fat: 0.5, fibre: 3.5,
  },
  {
    slug: 'wok-vegetables-frozen',
    names: { en: 'Wok vegetable mix, frozen', de: 'Wok-Gemüsemischung, tiefgekühlt', fr: 'Mélange de légumes pour wok, surgelé', it: 'Mix di verdure per wok, surgelato', ro: 'Amestec de legume pentru wok, congelat', th: 'ผักรวมสำหรับผัด แช่แข็ง' },
    kcal: 42, protein: 2.2, carbs: 6.8, fat: 0.7, fibre: 3,
  },
  {
    slug: 'spinach-leaf-frozen',
    names: { en: 'Leaf spinach, frozen', de: 'Blattspinat, tiefgekühlt', fr: 'Épinards en feuilles, surgelés', it: 'Spinaci in foglia, surgelati', ro: 'Spanac frunze congelat', th: 'ผักโขมใบแช่แข็ง' },
    kcal: 29, protein: 3.6, carbs: 4.2, fat: 0.6, fibre: 3.2,
  },
  {
    slug: 'edamame-frozen',
    names: { en: 'Edamame, frozen', de: 'Edamame, tiefgekühlt', fr: 'Edamame, surgelé', it: 'Edamame, surgelato', ro: 'Edamame congelat', th: 'ถั่วแระญี่ปุ่นแช่แข็ง' },
    kcal: 121, protein: 11.9, carbs: 8.9, fat: 5.2, fibre: 5.2,
  },
  {
    slug: 'sweetcorn-frozen',
    names: { en: 'Sweetcorn, frozen', de: 'Zuckermais, tiefgekühlt', fr: 'Maïs doux, surgelé', it: 'Mais dolce, surgelato', ro: 'Porumb dulce congelat', th: 'ข้าวโพดหวานแช่แข็ง' },
    kcal: 86, protein: 3.2, carbs: 19, fat: 1.2, fibre: 2.7,
  },
  {
    slug: 'kale-frozen',
    names: { en: 'Kale, frozen', de: 'Grünkohl, tiefgekühlt', fr: 'Chou kale, surgelé', it: 'Cavolo riccio, surgelato', ro: 'Kale congelat', th: 'เคลแช่แข็ง' },
    kcal: 35, protein: 2.9, carbs: 4.4, fat: 1.5, fibre: 4.1,
  },
  {
    slug: 'mushrooms-frozen',
    names: { en: 'Mushrooms, frozen', de: 'Pilze, tiefgekühlt', fr: 'Champignons, surgelés', it: 'Funghi, surgelati', ro: 'Ciuperci congelate', th: 'เห็ดแช่แข็ง' },
    kcal: 22, protein: 3.1, carbs: 3.3, fat: 0.3, fibre: 1,
  },
  {
    slug: 'ratatouille-vegetables-frozen',
    names: { en: 'Ratatouille vegetables, frozen', de: 'Ratatouille-Gemüse, tiefgekühlt', fr: 'Légumes pour ratatouille, surgelés', it: 'Verdure per ratatouille, surgelate', ro: 'Legume pentru ratatouille, congelate', th: 'ผักราตาตูยแช่แข็ง' },
    kcal: 39, protein: 1.5, carbs: 6.3, fat: 0.7, fibre: 2.6,
  },
  {
    slug: 'summer-vegetables-frozen',
    names: { en: 'Summer vegetable mix, frozen', de: 'Sommergemüse-Mix, tiefgekühlt', fr: 'Mélange de légumes d’été, surgelé', it: 'Mix di verdure estive, surgelato', ro: 'Amestec de legume de vară congelate', th: 'ผักฤดูร้อนรวมแช่แข็ง' },
    kcal: 40, protein: 2, carbs: 6.8, fat: 0.5, fibre: 3,
  },
  {
    slug: 'zucchini-frozen',
    names: { en: 'Zucchini slices, frozen', de: 'Zucchinischeiben, tiefgekühlt', fr: 'Rondelles de courgette, surgelées', it: 'Fette di zucchina, surgelate', ro: 'Felii de dovlecel congelate', th: 'ซูกินีหั่นแว่นแช่แข็ง' },
    kcal: 17, protein: 1.2, carbs: 3.1, fat: 0.3, fibre: 1,
  },
  {
    slug: 'bell-peppers-frozen',
    names: { en: 'Bell pepper strips, frozen', de: 'Paprikastreifen, tiefgekühlt', fr: 'Lanières de poivrons, surgelées', it: 'Strisce di peperoni, surgelate', ro: 'Fâșii de ardei gras congelate', th: 'พริกหวานหั่นเส้นแช่แข็ง' },
    kcal: 29, protein: 1, carbs: 6, fat: 0.3, fibre: 2.1,
  },
  {
    slug: 'ravioli-cheese-cooked',
    names: { en: 'Cheese ravioli, cooked', de: 'Käse-Ravioli, gekocht', fr: 'Ravioli au fromage, cuits', it: 'Ravioli al formaggio, cotti', ro: 'Ravioli cu brânză, fierți', th: 'ราวิโอลีชีส สุก' },
    kcal: 165, protein: 7, carbs: 25, fat: 4, fibre: 1.7, preparation: 'cooked',
  },
  {
    slug: 'ravioli-meat-cooked',
    names: { en: 'Meat ravioli, cooked', de: 'Fleisch-Ravioli, gekocht', fr: 'Ravioli à la viande, cuits', it: 'Ravioli di carne, cotti', ro: 'Ravioli cu carne, fierți', th: 'ราวิโอลีเนื้อ สุก' },
    kcal: 180, protein: 8, carbs: 24, fat: 6, fibre: 1.6, preparation: 'cooked',
  },
  {
    slug: 'ravioli-tomato-sauce',
    names: { en: 'Ravioli with tomato sauce, prepared', de: 'Ravioli mit Tomatensauce, zubereitet', fr: 'Ravioli à la sauce tomate, préparés', it: 'Ravioli al sugo di pomodoro, preparati', ro: 'Ravioli cu sos de roșii, preparați', th: 'ราวิโอลีกับซอสมะเขือเทศ พร้อมรับประทาน' },
    kcal: 132, protein: 5.2, carbs: 20.5, fat: 3.4, fibre: 2, preparation: 'prepared',
  },
  {
    slug: 'ravioli-cream-sauce',
    names: { en: 'Ravioli with cream sauce, prepared', de: 'Ravioli mit Rahmsauce, zubereitet', fr: 'Ravioli à la sauce à la crème, préparés', it: 'Ravioli con salsa alla panna, preparati', ro: 'Ravioli cu sos de smântână, preparați', th: 'ราวิโอลีกับซอสครีม พร้อมรับประทาน' },
    kcal: 190, protein: 7, carbs: 22, fat: 8.5, fibre: 1.4, preparation: 'prepared',
  },
  {
    slug: 'omelette-plain',
    names: { en: 'Omelette, plain', de: 'Omelett, natur', fr: 'Omelette nature', it: 'Frittata semplice', ro: 'Omletă simplă', th: 'ไข่เจียวแบบธรรมดา' },
    kcal: 154, protein: 10.6, carbs: 0.6, fat: 12, preparation: 'prepared',
  },
  {
    slug: 'omelette-cheese',
    names: { en: 'Cheese omelette', de: 'Käseomelett', fr: 'Omelette au fromage', it: 'Frittata al formaggio', ro: 'Omletă cu brânză', th: 'ไข่เจียวชีส' },
    kcal: 205, protein: 14, carbs: 1.5, fat: 16, preparation: 'prepared',
  },
  {
    slug: 'scrambled-eggs-plain',
    names: { en: 'Scrambled eggs, plain', de: 'Rührei, natur', fr: 'Œufs brouillés nature', it: 'Uova strapazzate semplici', ro: 'Ouă jumări simple', th: 'ไข่คนแบบธรรมดา' },
    kcal: 149, protein: 10, carbs: 1.6, fat: 11, preparation: 'prepared',
  },
  {
    slug: 'scrambled-eggs-butter',
    names: { en: 'Scrambled eggs with butter', de: 'Rührei mit Butter', fr: 'Œufs brouillés au beurre', it: 'Uova strapazzate al burro', ro: 'Ouă jumări cu unt', th: 'ไข่คนใส่เนย' },
    kcal: 175, protein: 10, carbs: 1.5, fat: 14, preparation: 'prepared',
  },
  {
    slug: 'wienerli-im-teig',
    names: { en: 'Wienerli in pastry, sausage roll', de: 'Wienerli im Teig', fr: 'Saucisse en croûte', it: 'Würstel in pasta sfoglia', ro: 'Crenvurșt în aluat', th: 'ไส้กรอกห่อแป้งอบ' },
    kcal: 310, protein: 11, carbs: 28, fat: 17, saturatedFat: 7, salt: 1.6, preparation: 'prepared', pieceGrams: 110,
  },
  {
    slug: 'butter-croissant',
    names: { en: 'Butter croissant', de: 'Buttergipfel', fr: 'Croissant au beurre', it: 'Cornetto al burro', ro: 'Croissant cu unt', th: 'ครัวซองต์เนย' },
    kcal: 406, protein: 8.2, carbs: 45.8, fat: 21, sugar: 11, saturatedFat: 12, preparation: 'prepared', pieceGrams: 55,
  },
  {
    slug: 'pain-au-chocolat',
    names: { en: 'Chocolate pastry, pain au chocolat', de: 'Schokoladengipfel', fr: 'Pain au chocolat', it: 'Saccottino al cioccolato', ro: 'Foietaj cu ciocolată', th: 'เพนโอช็อกโกแลต' },
    kcal: 414, protein: 7.4, carbs: 48, fat: 21.5, sugar: 22, saturatedFat: 12, preparation: 'prepared', pieceGrams: 75,
  },
  {
    slug: 'apple-turnover',
    names: { en: 'Apple turnover pastry', de: 'Apfeltasche', fr: 'Chausson aux pommes', it: 'Sfoglia alle mele', ro: 'Foietaj cu mere', th: 'พายพัฟไส้แอปเปิล' },
    kcal: 330, protein: 4, carbs: 47, fat: 14, sugar: 20, preparation: 'prepared', pieceGrams: 95,
  },
  {
    slug: 'cheese-pastry',
    names: { en: 'Cheese pastry', de: 'Käsegebäck', fr: 'Feuilleté au fromage', it: 'Sfoglia al formaggio', ro: 'Foietaj cu brânză', th: 'พายพัฟไส้ชีส' },
    kcal: 350, protein: 11, carbs: 31, fat: 20, salt: 1.4, preparation: 'prepared', pieceGrams: 90,
  },
  {
    slug: 'sea-buckthorn-fruit-spread',
    names: { en: 'Sea buckthorn fruit spread', de: 'Sanddornzubereitung', fr: 'Préparation à l’argousier', it: 'Preparazione all’olivello spinoso', ro: 'Preparat tartinabil din cătină', th: 'แยมซีบัคธอร์น' },
    kcal: 240, protein: 0.5, carbs: 57, fat: 0.5, sugar: 52, preparation: 'prepared',
  },
  {
    slug: 'espresso-decaffeinato-capsule-brewed',
    names: { en: 'Decaffeinated espresso capsule, brewed', de: 'Espresso Decaffeinato Kapsel, zubereitet', fr: 'Capsule espresso décaféiné, préparé', it: 'Capsula espresso decaffeinato, preparato', ro: 'Capsulă espresso decofeinizat, preparat', th: 'กาแฟเอสเปรสโซแคปซูลดีแคฟ ชงแล้ว' },
    kcal: 2, protein: 0.1, carbs: 0.3, fat: 0, nutritionBasis: 'per_100ml', servingAmount: 40, servingUnit: 'ml', preparation: 'prepared',
  },
  {
    slug: 'lungo-decaffeinato-capsule-brewed',
    names: { en: 'Decaffeinated lungo capsule, brewed', de: 'Lungo Decaffeinato Kapsel, zubereitet', fr: 'Capsule lungo décaféiné, préparé', it: 'Capsula lungo decaffeinato, preparato', ro: 'Capsulă lungo decofeinizat, preparat', th: 'กาแฟลุงโกแคปซูลดีแคฟ ชงแล้ว' },
    kcal: 2, protein: 0.1, carbs: 0.3, fat: 0, nutritionBasis: 'per_100ml', servingAmount: 110, servingUnit: 'ml', preparation: 'prepared',
  },
]

const PROTOCOL_FOOD_SPECS: CatalogFoodSpec[] = [
  ...BASE_PROTOCOL_FOOD_SPECS,
  ...EXPANDED_FOOD_SPECS,
]

const RETAILER_REFERENCES = [
  { slug: 'migros', brand: 'Migros' },
  { slug: 'lidl-suisse', brand: 'Lidl Suisse' },
  { slug: 'aldi-suisse', brand: 'ALDI Suisse' },
  { slug: 'rewe', brand: 'REWE' },
] as const

function protocolFoodId(namespace: number, index: number): string {
  return `${namespace.toString().padStart(8, '0')}-0000-4000-8000-${(index + 1).toString().padStart(12, '0')}`
}

function protocolFood(
  spec: CatalogFoodSpec,
  index: number,
  retailer?: (typeof RETAILER_REFERENCES)[number],
  retailerIndex = 0,
): FoodRecord {
  const namespace = retailer ? 30_000_000 + retailerIndex : 20_000_000
  const id = !retailer && spec.id ? spec.id : protocolFoodId(namespace, index)
  const base = food(
    id,
    spec.names.en,
    spec.names.de,
    spec.names.fr,
    spec.names.it,
    spec.kcal,
    spec.protein,
    spec.carbs,
    spec.fat,
    spec.preparation ?? 'as_sold',
    {
      brand: retailer?.brand ?? spec.brand,
      barcode: spec.barcode,
      providerId: retailer
        ? `apex-protocol:${retailer.slug}:${spec.slug}`
        : spec.providerId ?? `apex-protocol:generic:${spec.slug}`,
      fibre: spec.fibre,
      sugar: spec.sugar,
      saturatedFat: spec.saturatedFat,
      salt: spec.salt,
      water: spec.water,
      waterSourceId: spec.waterSourceId,
      nutritionBasis: spec.nutritionBasis,
      servingAmount: spec.servingAmount,
      servingUnit: spec.servingUnit,
      confidence: spec.confidence ?? 'complete',
    },
  )
  return {
    ...base,
    names_i18n: { ...spec.names },
    piece_grams_or_ml: spec.pieceGrams ?? null,
  }
}

const PROTOCOL_FOODS = PROTOCOL_FOOD_SPECS.map((spec, index) => protocolFood(spec, index))
const RETAILER_REFERENCE_FOODS = RETAILER_REFERENCES.flatMap((retailer, retailerIndex) =>
  PROTOCOL_FOOD_SPECS.flatMap((spec, index) =>
    spec.retailerReference === false ? [] : [protocolFood(spec, index, retailer, retailerIndex)],
  ),
)

interface SwissFastFoodReference {
  name: string
  names?: Partial<Record<'de' | 'de-CH' | 'fr' | 'it' | 'es' | 'pt' | 'ro' | 'th' | 'ja', string>>
  brand: string
  providerId: string
  grams: number
  kcal: number
  protein: number
  carbs: number
  fat: number
  fibre?: number
  sugar?: number
  saturatedFat?: number
  salt?: number
  valuesArePerServing?: boolean
  confidence?: FoodRecord['confidence']
}

/* Current Swiss provider references. Burger King and KFC publish per-100 g
   values and whole-item weights. Popeyes Switzerland publishes totals for the
   complete sandwich, which are converted deterministically to the per-100 g
   storage basis without inventing absent nutrients. McRaclette is explicitly
   kept as a historical seasonal reference rather than marked provider-verified. */
const SWISS_FAST_FOOD_SPECS: SwissFastFoodReference[] = [
  {
    name: 'Cheeseburger Royal', brand: "McDonald's Switzerland", providerId: 'fsvo-v5.3:10675', grams: 207,
    kcal: 256, protein: 15.5, carbs: 17.4, fat: 13.5, fibre: 1.4, sugar: 4.3,
    names: { de: 'Cheeseburger Royal', 'de-CH': 'Cheeseburger Royal', fr: 'Cheeseburger Royal', it: 'Cheeseburger Royal', es: 'Cheeseburger Royal', pt: 'Cheeseburger Royal', ro: 'Cheeseburger Royal', th: 'ชีสเบอร์เกอร์รอยัล', ja: 'チーズバーガー・ロイヤル' },
  },
  {
    name: 'McRaclette Classic, seasonal reference', brand: "McDonald's Switzerland", providerId: 'mcdonalds-ch:mcraclette-classic-archive', grams: 269,
    kcal: 272, protein: 16, carbs: 16, fat: 16, fibre: 1, confidence: 'complete',
    names: { de: 'McRaclette Classic, Saisonreferenz', 'de-CH': 'McRaclette Classic, Saisonreferenz', fr: 'McRaclette Classic, référence saisonnière', it: 'McRaclette Classic, riferimento stagionale', es: 'McRaclette Classic, referencia de temporada', pt: 'McRaclette Classic, referência sazonal', ro: 'McRaclette Classic, referință sezonieră', th: 'McRaclette Classic ข้อมูลอ้างอิงตามฤดูกาล', ja: 'McRaclette Classic（季節限定参考値）' },
  },
  {
    name: 'WHOPPER', brand: 'Burger King Switzerland', providerId: 'burger-king-ch:whopper', grams: 281.2,
    kcal: 227.6, protein: 10.9, carbs: 17.9, fat: 12.3, sugar: 3.9, saturatedFat: 3.2, salt: 0.1,
  },
  {
    name: 'Big King', brand: 'Burger King Switzerland', providerId: 'burger-king-ch:big-king', grams: 242.7,
    kcal: 252.8, protein: 12.8, carbs: 17.6, fat: 14.3, sugar: 3.5, saturatedFat: 4.4, salt: 0.3,
  },
  {
    name: 'Cheeseburger', brand: 'Burger King Switzerland', providerId: 'burger-king-ch:cheeseburger', grams: 124.5,
    kcal: 269.2, protein: 14.7, carbs: 24.4, fat: 12.2, sugar: 4.6, saturatedFat: 4.9, salt: 0.4,
  },
  {
    name: 'Hamburger', brand: 'Burger King Switzerland', providerId: 'burger-king-ch:hamburger', grams: 113,
    kcal: 261.4, protein: 14.2, carbs: 26.5, fat: 10.7, sugar: 4.7, saturatedFat: 3.6, salt: 0.1,
  },
  {
    name: 'Double Crispy Classic', brand: 'KFC Switzerland', providerId: 'kfc-ch:double-crispy-classic', grams: 167,
    kcal: 239, protein: 12, carbs: 23, fat: 11, sugar: 2, salt: 1.3,
  },
  {
    name: 'Crispy Cheese', brand: 'KFC Switzerland', providerId: 'kfc-ch:crispy-cheese', grams: 116,
    kcal: 239, protein: 11, carbs: 31, fat: 8, sugar: 5, salt: 1.6,
  },
  {
    name: 'Crispy Chili Cheese', brand: 'KFC Switzerland', providerId: 'kfc-ch:crispy-chili-cheese', grams: 116,
    kcal: 283, protein: 11, carbs: 29, fat: 14, sugar: 4, salt: 1.5,
  },
  {
    name: 'Classic Original', brand: 'KFC Switzerland', providerId: 'kfc-ch:classic-original', grams: 205,
    kcal: 241, protein: 13, carbs: 23, fat: 10, sugar: 3, salt: 1.5,
  },
  {
    name: 'Classic Zinger', brand: 'KFC Switzerland', providerId: 'kfc-ch:classic-zinger', grams: 200,
    kcal: 245, protein: 13, carbs: 23, fat: 11, sugar: 3, salt: 1.1,
  },
  {
    name: 'Classic Veggie', brand: 'KFC Switzerland', providerId: 'kfc-ch:classic-veggie', grams: 191,
    kcal: 226, protein: 9, carbs: 25, fat: 9, sugar: 3, salt: 1.1,
  },
  {
    name: 'Colonel Original', brand: 'KFC Switzerland', providerId: 'kfc-ch:colonel-original', grams: 243,
    kcal: 234, protein: 12, carbs: 20, fat: 11, sugar: 4, salt: 1.5,
  },
  {
    name: 'Cheese & Bacon', brand: 'KFC Switzerland', providerId: 'kfc-ch:cheese-bacon', grams: 239,
    kcal: 249, protein: 14, carbs: 20, fat: 12, sugar: 3, salt: 1.7,
  },
  {
    name: 'Classic Chicken Sandwich', brand: 'Popeyes Switzerland', providerId: 'popeyes-ch:item_54262', grams: 254,
    kcal: 831, protein: 33, carbs: 53, fat: 53, fibre: 2.5, sugar: 7.5, saturatedFat: 17, salt: 3.7, valuesArePerServing: true,
    names: { de: 'Classic Chicken Sandwich', 'de-CH': 'Classic Chicken Sandwich', fr: 'Sandwich au poulet Classic', it: 'Panino di pollo Classic', es: 'Sándwich de pollo Classic', pt: 'Sanduíche de frango Classic', ro: 'Sandviș Classic cu pui', th: 'แซนด์วิชไก่คลาสสิก', ja: 'クラシック・チキンサンド' },
  },
  {
    name: 'Spicy Chicken Sandwich', brand: 'Popeyes Switzerland', providerId: 'popeyes-ch:item_54295', grams: 254,
    kcal: 826, protein: 33, carbs: 53, fat: 53, fibre: 2.5, sugar: 7.2, saturatedFat: 17, salt: 4.3, valuesArePerServing: true,
    names: { de: 'Spicy Chicken Sandwich', 'de-CH': 'Spicy Chicken Sandwich', fr: 'Sandwich au poulet Spicy', it: 'Panino di pollo Spicy', es: 'Sándwich de pollo Spicy', pt: 'Sanduíche de frango Spicy', ro: 'Sandviș picant cu pui', th: 'แซนด์วิชไก่สไปซี', ja: 'スパイシー・チキンサンド' },
  },
  {
    name: 'Deluxe Chicken Sandwich', brand: 'Popeyes Switzerland', providerId: 'popeyes-ch:item_55735', grams: 308,
    kcal: 931, protein: 39, carbs: 54, fat: 61, fibre: 2.7, sugar: 8.6, saturatedFat: 22, salt: 5.1, valuesArePerServing: true,
  },
  {
    name: 'Deluxe Spicy Chicken Sandwich', brand: 'Popeyes Switzerland', providerId: 'popeyes-ch:item_55738', grams: 298,
    kcal: 926, protein: 39, carbs: 55, fat: 61, fibre: 2.6, sugar: 8.3, saturatedFat: 22, salt: 5.5, valuesArePerServing: true,
  },
  {
    name: 'Cheesy Chicken Sandwich', brand: 'Popeyes Switzerland', providerId: 'popeyes-ch:02ee86b1-f8cf-4cf1-ba92-82e7fdf0f2a5', grams: 285,
    kcal: 836, protein: 38, carbs: 55, fat: 51, fibre: 3, sugar: 8.8, saturatedFat: 21, salt: 6.5, valuesArePerServing: true,
  },
  {
    name: 'BBQ Chicken Sandwich', brand: 'Popeyes Switzerland', providerId: 'popeyes-ch:a384363f-80dc-4777-864b-ff6dd5e86048', grams: 284,
    kcal: 744, protein: 37, carbs: 63, fat: 37, fibre: 3.1, sugar: 16, saturatedFat: 18, salt: 5, valuesArePerServing: true,
  },
]

const SWISS_FAST_FOOD_REFERENCE_FOODS = SWISS_FAST_FOOD_SPECS.map((spec, index) => {
  const factor = spec.valuesArePerServing ? 100 / spec.grams : 1
  const id = `f4570000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`
  const base = food(
    id,
    spec.name,
    spec.names?.de ?? spec.name,
    spec.names?.fr ?? spec.name,
    spec.names?.it ?? spec.name,
    spec.kcal * factor,
    spec.protein * factor,
    spec.carbs * factor,
    spec.fat * factor,
    'as_sold',
    {
      brand: spec.brand,
      providerId: spec.providerId,
      packageQuantity: `${spec.grams} g`,
      servingAmount: 1,
      servingUnit: 'serving',
      servingGrams: spec.grams,
      fibre: spec.fibre == null ? undefined : spec.fibre * factor,
      sugar: spec.sugar == null ? undefined : spec.sugar * factor,
      saturatedFat: spec.saturatedFat == null ? undefined : spec.saturatedFat * factor,
      salt: spec.salt == null ? undefined : spec.salt * factor,
      confidence: spec.confidence ?? 'provider_verified',
    },
  )
  return {
    ...base,
    names_i18n: {
      en: spec.name,
      de: spec.names?.de ?? spec.name,
      'de-CH': spec.names?.['de-CH'] ?? spec.names?.de ?? spec.name,
      fr: spec.names?.fr ?? spec.name,
      it: spec.names?.it ?? spec.name,
      es: spec.names?.es ?? spec.name,
      pt: spec.names?.pt ?? spec.name,
      ro: spec.names?.ro ?? spec.name,
      th: spec.names?.th ?? spec.name,
      ja: spec.names?.ja ?? spec.name,
    },
  }
})

export const COMMON_FOODS: FoodRecord[] = [
  ...CORE_FOODS,
  ...PROTOCOL_FOODS,
  ...RETAILER_REFERENCE_FOODS,
  ...SWISS_FAST_FOOD_REFERENCE_FOODS,
]
