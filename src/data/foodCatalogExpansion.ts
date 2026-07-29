import type { FoodRecord, FoodUnit, NutritionBasis } from '../lib/food'

export interface CatalogNames {
  en: string
  de: string
  fr: string
  it: string
  ro: string
  th: string
}

export interface CatalogFoodSpec {
  slug: string
  names: CatalogNames
  kcal: number
  protein: number
  carbs: number
  fat: number
  preparation?: FoodRecord['preparation_state']
  fibre?: number
  sugar?: number
  saturatedFat?: number
  salt?: number
  pieceGrams?: number
  nutritionBasis?: NutritionBasis
  servingAmount?: number
  servingUnit?: FoodUnit
  retailerReference?: boolean
}

interface MacroProfile {
  kcal: number
  protein: number
  carbs: number
  fat: number
  fibre?: number
  sugar?: number
  saturatedFat?: number
}

type MethodKey =
  | 'raw'
  | 'cooked'
  | 'boiled'
  | 'poached'
  | 'steamed'
  | 'grilled'
  | 'baked'
  | 'roasted'
  | 'airFryer'
  | 'panSeared'
  | 'friedOil'
  | 'breadedFried'

const METHODS: Record<MethodKey, { slug: string; names: CatalogNames; preparation: FoodRecord['preparation_state'] }> = {
  raw: {
    slug: 'raw',
    preparation: 'as_sold',
    names: { en: 'raw', de: 'roh', fr: 'à l’état cru', it: 'allo stato crudo', ro: 'în stare crudă', th: 'ดิบ' },
  },
  cooked: {
    slug: 'cooked',
    preparation: 'cooked',
    names: { en: 'cooked, generic reference', de: 'gegart, allgemeiner Referenzwert', fr: 'cuit, valeur de référence générique', it: 'cotto, valore di riferimento generico', ro: 'gătit, profil generic de referință', th: 'สุก ข้อมูลอ้างอิงทั่วไป' },
  },
  boiled: {
    slug: 'boiled',
    preparation: 'cooked',
    names: { en: 'boiled, no added oil', de: 'gekocht, ohne Ölzugabe', fr: 'bouilli, sans huile ajoutée', it: 'bollito, senza olio aggiunto', ro: 'preparare prin fierbere, fără ulei adăugat', th: 'ต้ม ไม่เติมน้ำมัน' },
  },
  poached: {
    slug: 'poached',
    preparation: 'cooked',
    names: { en: 'poached, no added oil', de: 'pochiert, ohne Ölzugabe', fr: 'poché, sans huile ajoutée', it: 'in camicia, senza olio aggiunto', ro: 'preparare prin poșare, fără ulei adăugat', th: 'ลวกในน้ำ ไม่เติมน้ำมัน' },
  },
  steamed: {
    slug: 'steamed',
    preparation: 'cooked',
    names: { en: 'steamed, no added oil', de: 'gedämpft, ohne Ölzugabe', fr: 'cuit à la vapeur, sans huile ajoutée', it: 'al vapore, senza olio aggiunto', ro: 'preparare la abur, fără ulei adăugat', th: 'นึ่ง ไม่เติมน้ำมัน' },
  },
  grilled: {
    slug: 'grilled',
    preparation: 'cooked',
    names: { en: 'grilled, no added oil', de: 'gegrillt, ohne Ölzugabe', fr: 'grillé, sans huile ajoutée', it: 'alla griglia, senza olio aggiunto', ro: 'preparare la grătar, fără ulei adăugat', th: 'ย่าง ไม่เติมน้ำมัน' },
  },
  baked: {
    slug: 'baked',
    preparation: 'cooked',
    names: { en: 'baked, no added oil', de: 'gebacken, ohne Ölzugabe', fr: 'cuit au four, sans huile ajoutée', it: 'al forno, senza olio aggiunto', ro: 'preparare la cuptor, fără ulei adăugat', th: 'อบ ไม่เติมน้ำมัน' },
  },
  roasted: {
    slug: 'roasted',
    preparation: 'cooked',
    names: { en: 'roasted, no added oil', de: 'geröstet, ohne Ölzugabe', fr: 'rôti, sans huile ajoutée', it: 'arrosto, senza olio aggiunto', ro: 'preparare prin rumenire la cuptor, fără ulei adăugat', th: 'อบจนเกรียม ไม่เติมน้ำมัน' },
  },
  airFryer: {
    slug: 'air-fryer',
    preparation: 'cooked',
    names: { en: 'air fryer, no added oil', de: 'Heißluftfritteuse, ohne Ölzugabe', fr: 'air fryer, sans huile ajoutée', it: 'friggitrice ad aria, senza olio aggiunto', ro: 'preparare la air fryer, fără ulei adăugat', th: 'หม้อทอดไร้น้ำมัน ไม่เติมน้ำมัน' },
  },
  panSeared: {
    slug: 'pan-seared',
    preparation: 'cooked',
    names: { en: 'pan-seared, no added oil', de: 'in der Pfanne gebraten, ohne Ölzugabe', fr: 'saisi à la poêle, sans huile ajoutée', it: 'scottato in padella, senza olio aggiunto', ro: 'preparare în tigaie, fără ulei adăugat', th: 'จี่กระทะ ไม่เติมน้ำมัน' },
  },
  friedOil: {
    slug: 'fried-with-oil',
    preparation: 'prepared',
    names: { en: 'fried, 5 g absorbed oil per 100 g', de: 'gebraten, 5 g aufgenommenes Öl pro 100 g', fr: 'frit, 5 g d’huile absorbée pour 100 g', it: 'fritto, 5 g di olio assorbito per 100 g', ro: 'preparare prin prăjire, 5 g ulei absorbit la 100 g', th: 'ทอด ดูดซึมน้ำมัน 5 กรัมต่อ 100 กรัม' },
  },
  breadedFried: {
    slug: 'breaded-fried',
    preparation: 'prepared',
    names: { en: 'breaded and fried', de: 'paniert und frittiert', fr: 'pané et frit', it: 'impanato e fritto', ro: 'preparare pane, prin prăjire', th: 'ชุบเกล็ดขนมปังและทอด' },
  },
}

function namesWithMethod(base: CatalogNames, method: MethodKey): CatalogNames {
  const suffix = METHODS[method].names
  return {
    en: `${base.en}, ${suffix.en}`,
    de: `${base.de}, ${suffix.de}`,
    fr: `${base.fr}, ${suffix.fr}`,
    it: `${base.it}, ${suffix.it}`,
    ro: `${base.ro}, ${suffix.ro}`,
    th: `${base.th} ${suffix.th}`,
  }
}

function spec(
  slug: string,
  base: CatalogNames,
  method: MethodKey,
  macros: MacroProfile,
  retailerReference = false,
): CatalogFoodSpec {
  return {
    slug: `${slug}-${METHODS[method].slug}`,
    names: namesWithMethod(base, method),
    ...macros,
    preparation: METHODS[method].preparation,
    retailerReference,
  }
}

function withAbsorbedOil(macros: MacroProfile, grams = 5): MacroProfile {
  return {
    ...macros,
    kcal: Math.round(macros.kcal + grams * 9),
    fat: Math.round((macros.fat + grams) * 100) / 100,
    /* Saturated fat depends on the oil selected by the user, so a generic
       fried reference must not manufacture an exact saturated-fat value. */
    saturatedFat: undefined,
  }
}

/* FDC cooked dry-heat profiles are reused for the named no-added-oil dry
   methods. This avoids pretending that a generic recipe knows how much oil a
   user absorbed. The explicitly fried variant states its 5 g oil assumption. */
function rawAndCookedFamily(
  slug: string,
  names: CatalogNames,
  raw: MacroProfile,
  cooked: MacroProfile,
): CatalogFoodSpec[] {
  return [
    spec(slug, names, 'raw', raw, true),
    spec(slug, names, 'cooked', cooked, true),
    spec(slug, names, 'boiled', cooked),
    spec(slug, names, 'poached', cooked),
    spec(slug, names, 'steamed', cooked),
    spec(slug, names, 'grilled', cooked),
    spec(slug, names, 'baked', cooked),
    spec(slug, names, 'roasted', cooked),
    spec(slug, names, 'airFryer', cooked),
    spec(slug, names, 'panSeared', cooked),
    spec(slug, names, 'friedOil', withAbsorbedOil(cooked)),
  ]
}

const FISH_FOODS: CatalogFoodSpec[] = [
  ...rawAndCookedFamily(
    'salmon-fillet',
    { en: 'Salmon fillet', de: 'Lachsfilet', fr: 'Filet de saumon', it: 'Filetto di salmone', ro: 'File de somon', th: 'เนื้อปลาแซลมอน' },
    { kcal: 203, protein: 20.3, carbs: 0, fat: 13.1, saturatedFat: 2.28 },
    { kcal: 206, protein: 22.1, carbs: 0, fat: 12.4, saturatedFat: 2.4 },
  ),
  ...rawAndCookedFamily(
    'sockeye-salmon',
    { en: 'Sockeye salmon fillet', de: 'Rotlachsfilet', fr: 'Filet de saumon rouge', it: 'Filetto di salmone rosso', ro: 'File de somon sockeye', th: 'เนื้อปลาแซลมอนซ็อกอาย' },
    { kcal: 126, protein: 22.3, carbs: 0, fat: 4.94, saturatedFat: 0.72 },
    { kcal: 156, protein: 26.5, carbs: 0, fat: 5.57, saturatedFat: 0.97 },
  ),
  ...rawAndCookedFamily(
    'atlantic-cod',
    { en: 'Atlantic cod fillet', de: 'Atlantisches Kabeljaufilet', fr: 'Filet de cabillaud Atlantique', it: 'Filetto di merluzzo atlantico', ro: 'File de cod atlantic', th: 'เนื้อปลาค็อดแอตแลนติก' },
    { kcal: 82, protein: 17.8, carbs: 0, fat: 0.67, saturatedFat: 0.13 },
    { kcal: 105, protein: 22.8, carbs: 0, fat: 0.86, saturatedFat: 0.17 },
  ),
  ...rawAndCookedFamily(
    'tilapia-fillet',
    { en: 'Tilapia fillet', de: 'Tilapiafilet', fr: 'Filet de tilapia', it: 'Filetto di tilapia', ro: 'File de tilapia', th: 'เนื้อปลานิล' },
    { kcal: 96, protein: 20.1, carbs: 0, fat: 1.7, saturatedFat: 0.59 },
    { kcal: 128, protein: 26.2, carbs: 0, fat: 2.65, saturatedFat: 0.94 },
  ),
  ...rawAndCookedFamily(
    'yellowfin-tuna',
    { en: 'Yellowfin tuna steak', de: 'Gelbflossen-Thunfischsteak', fr: 'Steak de thon albacore', it: 'Trancio di tonno pinna gialla', ro: 'Steak de ton cu înotătoare galbenă', th: 'สเต๊กปลาทูน่าครีบเหลือง' },
    { kcal: 108, protein: 24.7, carbs: 0, fat: 0.39 },
    { kcal: 130, protein: 29.2, carbs: 0, fat: 0.59, saturatedFat: 0.21 },
  ),
  ...rawAndCookedFamily(
    'rainbow-trout',
    { en: 'Rainbow trout', de: 'Regenbogenforelle', fr: 'Truite arc-en-ciel', it: 'Trota iridea', ro: 'Păstrăv curcubeu', th: 'ปลาเทราต์สายรุ้ง' },
    { kcal: 141, protein: 19.9, carbs: 0, fat: 6.18, saturatedFat: 1.38 },
    { kcal: 168, protein: 23.8, carbs: 0, fat: 7.38, saturatedFat: 1.65 },
  ),
  ...rawAndCookedFamily(
    'atlantic-mackerel',
    { en: 'Atlantic mackerel', de: 'Atlantische Makrele', fr: 'Maquereau Atlantique', it: 'Sgombro atlantico', ro: 'Macrou atlantic', th: 'ปลาแมคเคอเรลแอตแลนติก' },
    { kcal: 205, protein: 18.6, carbs: 0, fat: 13.9, saturatedFat: 3.26 },
    { kcal: 262, protein: 23.8, carbs: 0, fat: 17.8, saturatedFat: 4.18 },
  ),
  ...rawAndCookedFamily(
    'halibut-fillet',
    { en: 'Halibut fillet', de: 'Heilbuttfilet', fr: 'Filet de flétan', it: 'Filetto di halibut', ro: 'File de halibut', th: 'เนื้อปลาฮาลิบัต' },
    { kcal: 91, protein: 18.6, carbs: 0, fat: 1.33, saturatedFat: 0.29 },
    { kcal: 111, protein: 22.5, carbs: 0, fat: 1.61, saturatedFat: 0.35 },
  ),
  ...rawAndCookedFamily(
    'swordfish-steak',
    { en: 'Swordfish steak', de: 'Schwertfischsteak', fr: 'Steak d’espadon', it: 'Trancio di pesce spada', ro: 'Steak de pește-spadă', th: 'สเต๊กปลากระโทงดาบ' },
    { kcal: 144, protein: 19.7, carbs: 0, fat: 6.65, saturatedFat: 1.61 },
    { kcal: 172, protein: 23.4, carbs: 0, fat: 7.93, saturatedFat: 1.91 },
  ),
  ...rawAndCookedFamily(
    'alaska-pollock',
    { en: 'Alaska pollock fillet', de: 'Alaska-Seelachsfilet', fr: 'Filet de colin d’Alaska', it: 'Filetto di merluzzo d’Alaska', ro: 'File de pollock de Alaska', th: 'เนื้อปลาอลาสกาพอลล็อก' },
    { kcal: 76, protein: 17.2, carbs: 0, fat: 0.82, saturatedFat: 0.15 },
    { kcal: 111, protein: 23.5, carbs: 0, fat: 1.18, saturatedFat: 0.16 },
  ),
  spec(
    'shrimp',
    { en: 'Shrimp', de: 'Garnelen', fr: 'Crevettes', it: 'Gamberi', ro: 'Creveți', th: 'กุ้ง' },
    'raw',
    { kcal: 85, protein: 20.1, carbs: 0, fat: 0.51, saturatedFat: 0.1 },
    true,
  ),
  spec(
    'shrimp',
    { en: 'Shrimp', de: 'Garnelen', fr: 'Crevettes', it: 'Gamberi', ro: 'Creveți', th: 'กุ้ง' },
    'steamed',
    { kcal: 99, protein: 24, carbs: 0.2, fat: 0.28, saturatedFat: 0.06 },
    true,
  ),
  spec(
    'shrimp',
    { en: 'Shrimp', de: 'Garnelen', fr: 'Crevettes', it: 'Gamberi', ro: 'Creveți', th: 'กุ้ง' },
    'breadedFried',
    { kcal: 242, protein: 21.4, carbs: 11.5, fat: 12.3, fibre: 0.4, sugar: 0.8, saturatedFat: 2.09 },
  ),
  spec(
    'scallops',
    { en: 'Sea scallops', de: 'Jakobsmuscheln', fr: 'Noix de Saint-Jacques', it: 'Capesante', ro: 'Scoici Saint-Jacques', th: 'หอยเชลล์' },
    'raw',
    { kcal: 66, protein: 13.5, carbs: 1.97, fat: 0.49 },
    true,
  ),
  spec(
    'scallops',
    { en: 'Sea scallops', de: 'Jakobsmuscheln', fr: 'Noix de Saint-Jacques', it: 'Capesante', ro: 'Scoici Saint-Jacques', th: 'หอยเชลล์' },
    'steamed',
    { kcal: 111, protein: 20.5, carbs: 5.41, fat: 0.84, saturatedFat: 0.22 },
    true,
  ),
  spec(
    'scallops',
    { en: 'Sea scallops', de: 'Jakobsmuscheln', fr: 'Noix de Saint-Jacques', it: 'Capesante', ro: 'Scoici Saint-Jacques', th: 'หอยเชลล์' },
    'breadedFried',
    { kcal: 216, protein: 18.1, carbs: 10.1, fat: 10.9, saturatedFat: 2.67 },
  ),
  spec(
    'squid',
    { en: 'Squid', de: 'Tintenfisch', fr: 'Calamar', it: 'Calamaro', ro: 'Calamar', th: 'ปลาหมึก' },
    'raw',
    { kcal: 92, protein: 15.6, carbs: 3.08, fat: 1.38, saturatedFat: 0.36 },
    true,
  ),
  spec(
    'squid',
    { en: 'Squid', de: 'Tintenfisch', fr: 'Calamar', it: 'Calamaro', ro: 'Calamar', th: 'ปลาหมึก' },
    'friedOil',
    { kcal: 175, protein: 17.9, carbs: 7.79, fat: 7.48, saturatedFat: 1.88 },
  ),
  spec(
    'lobster',
    { en: 'Lobster meat', de: 'Hummerfleisch', fr: 'Chair de homard', it: 'Polpa di astice', ro: 'Carne de homar', th: 'เนื้อล็อบสเตอร์' },
    'raw',
    { kcal: 77, protein: 16.5, carbs: 0, fat: 0.75, saturatedFat: 0.18 },
    true,
  ),
  spec(
    'lobster',
    { en: 'Lobster meat', de: 'Hummerfleisch', fr: 'Chair de homard', it: 'Polpa di astice', ro: 'Carne de homar', th: 'เนื้อล็อบสเตอร์' },
    'boiled',
    { kcal: 89, protein: 19, carbs: 0, fat: 0.86, saturatedFat: 0.21 },
    true,
  ),
  spec(
    'crab',
    { en: 'Crab meat', de: 'Krabbenfleisch', fr: 'Chair de crabe', it: 'Polpa di granchio', ro: 'Carne de crab', th: 'เนื้อปู' },
    'steamed',
    { kcal: 97, protein: 19.4, carbs: 0, fat: 1.54, saturatedFat: 0.13 },
    true,
  ),
  {
    slug: 'sardines-canned-oil-drained',
    names: { en: 'Sardines, canned in oil, drained', de: 'Sardinen in Öl, abgetropft', fr: 'Sardines à l’huile, égouttées', it: 'Sardine sott’olio, sgocciolate', ro: 'Sardine în ulei, scurse', th: 'ปลาซาร์ดีนในน้ำมัน สะเด็ดน้ำ' },
    kcal: 208, protein: 24.6, carbs: 0, fat: 11.4, saturatedFat: 1.53, preparation: 'drained', retailerReference: true,
  },
  {
    slug: 'anchovies-canned-oil-drained',
    names: { en: 'Anchovies, canned in oil, drained', de: 'Sardellen in Öl, abgetropft', fr: 'Anchois à l’huile, égouttés', it: 'Acciughe sott’olio, sgocciolate', ro: 'Anșoa în ulei, scurs', th: 'ปลาแอนโชวีในน้ำมัน สะเด็ดน้ำ' },
    kcal: 210, protein: 28.9, carbs: 0, fat: 9.71, saturatedFat: 2.2, preparation: 'drained', retailerReference: true,
  },
]

const MEAT_FOODS: CatalogFoodSpec[] = [
  ...rawAndCookedFamily(
    'chicken-breast',
    { en: 'Chicken breast, skinless', de: 'Hähnchenbrust ohne Haut', fr: 'Blanc de poulet sans peau', it: 'Petto di pollo senza pelle', ro: 'Piept de pui fără piele', th: 'อกไก่ลอกหนัง' },
    { kcal: 106, protein: 22.5, carbs: 0, fat: 1.93 },
    { kcal: 165, protein: 31, carbs: 0, fat: 3.57, saturatedFat: 1.01 },
  ),
  ...rawAndCookedFamily(
    'chicken-thigh',
    { en: 'Chicken thigh, skinless', de: 'Hähnchenschenkel ohne Haut', fr: 'Cuisse de poulet sans peau', it: 'Coscia di pollo senza pelle', ro: 'Pulpă de pui fără piele', th: 'สะโพกไก่ลอกหนัง' },
    { kcal: 121, protein: 19.7, carbs: 0, fat: 4.12, saturatedFat: 1.1 },
    { kcal: 179, protein: 24.8, carbs: 0, fat: 8.15, saturatedFat: 2.31 },
  ),
  ...rawAndCookedFamily(
    'turkey-breast-skinless',
    { en: 'Turkey breast, skinless', de: 'Putenbrust ohne Haut', fr: 'Blanc de dinde sans peau', it: 'Petto di tacchino senza pelle', ro: 'Piept de curcan fără piele', th: 'อกไก่งวงลอกหนัง' },
    { kcal: 114, protein: 23.3, carbs: 0, fat: 2.33, saturatedFat: 0.34 },
    { kcal: 127, protein: 27, carbs: 0, fat: 2.08, saturatedFat: 0.59 },
  ),
  ...rawAndCookedFamily(
    'lean-ground-beef',
    { en: 'Ground beef, 95% lean', de: 'Rinderhackfleisch, 95% mager', fr: 'Bœuf haché, 95% maigre', it: 'Manzo macinato, 95% magro', ro: 'Carne tocată de vită, 95% slabă', th: 'เนื้อวัวบด ไขมัน 5%' },
    { kcal: 137, protein: 21.4, carbs: 0, fat: 5, saturatedFat: 2.18 },
    { kcal: 193, protein: 29.2, carbs: 0, fat: 7.58, saturatedFat: 3.3 },
  ),
  ...rawAndCookedFamily(
    'beef-sirloin',
    { en: 'Beef top sirloin, lean', de: 'Rinderhüfte, mager', fr: 'Faux-filet de bœuf maigre', it: 'Controfiletto di manzo magro', ro: 'Mușchi de vită tip sirloin, slab', th: 'เนื้อสันนอกวัวไม่ติดมัน' },
    { kcal: 134, protein: 21.4, carbs: 0, fat: 5.36, saturatedFat: 1.88 },
    { kcal: 181, protein: 28.3, carbs: 0.73, fat: 7.23, saturatedFat: 2.65 },
  ),
  ...rawAndCookedFamily(
    'pork-tenderloin',
    { en: 'Pork tenderloin, lean', de: 'Schweinefilet, mager', fr: 'Filet mignon de porc maigre', it: 'Filetto di maiale magro', ro: 'Mușchiuleț de porc, slab', th: 'สันในหมูไม่ติดมัน' },
    { kcal: 109, protein: 21, carbs: 0, fat: 2.17, saturatedFat: 0.7 },
    { kcal: 143, protein: 26.2, carbs: 0, fat: 3.51, saturatedFat: 1.2 },
  ),
  ...rawAndCookedFamily(
    'lamb-leg',
    { en: 'Lamb leg, lean', de: 'Lammkeule, mager', fr: 'Gigot d’agneau maigre', it: 'Cosciotto d’agnello magro', ro: 'Pulpă de miel, slabă', th: 'ขาแกะไม่ติดมัน' },
    { kcal: 125, protein: 20.5, carbs: 0, fat: 4.19, saturatedFat: 1.5 },
    { kcal: 180, protein: 28.2, carbs: 0, fat: 6.67, saturatedFat: 2.38 },
  ),
  ...rawAndCookedFamily(
    'duck-meat',
    { en: 'Duck meat, skinless', de: 'Entenfleisch ohne Haut', fr: 'Viande de canard sans peau', it: 'Carne d’anatra senza pelle', ro: 'Carne de rață fără piele', th: 'เนื้อเป็ดลอกหนัง' },
    { kcal: 135, protein: 18.3, carbs: 0.94, fat: 5.95, saturatedFat: 2.32 },
    { kcal: 201, protein: 23.5, carbs: 0, fat: 11.2, saturatedFat: 3.95 },
  ),
  ...rawAndCookedFamily(
    'rabbit-meat',
    { en: 'Rabbit meat', de: 'Kaninchenfleisch', fr: 'Viande de lapin', it: 'Carne di coniglio', ro: 'Carne de iepure', th: 'เนื้อกระต่าย' },
    { kcal: 136, protein: 20, carbs: 0, fat: 5.55, saturatedFat: 1.66 },
    { kcal: 197, protein: 29.1, carbs: 0, fat: 8.05, saturatedFat: 2.4 },
  ),
  ...rawAndCookedFamily(
    'venison',
    { en: 'Venison, lean', de: 'Hirschfleisch, mager', fr: 'Venaison maigre', it: 'Carne di cervo magra', ro: 'Carne de cerb, slabă', th: 'เนื้อกวางไม่ติดมัน' },
    { kcal: 120, protein: 23, carbs: 0, fat: 2.42, saturatedFat: 0.95 },
    { kcal: 158, protein: 30.2, carbs: 0, fat: 3.19, saturatedFat: 1.25 },
  ),
  ...rawAndCookedFamily(
    'bison',
    { en: 'Bison, lean', de: 'Bisonfleisch, mager', fr: 'Bison maigre', it: 'Carne di bisonte magra', ro: 'Carne de bizon, slabă', th: 'เนื้อไบซันไม่ติดมัน' },
    { kcal: 109, protein: 21.6, carbs: 0, fat: 1.84, saturatedFat: 0.69 },
    { kcal: 143, protein: 28.4, carbs: 0, fat: 2.42, saturatedFat: 0.91 },
  ),
  ...rawAndCookedFamily(
    'veal-loin',
    { en: 'Veal loin', de: 'Kalbsrücken', fr: 'Longe de veau', it: 'Lombo di vitello', ro: 'Mușchi de vițel', th: 'สันลูกวัว' },
    { kcal: 177, protein: 20.1, carbs: 0.07, fat: 10.1, saturatedFat: 3.61 },
    { kcal: 217, protein: 24.8, carbs: 0, fat: 12.3, saturatedFat: 5.26 },
  ),
  ...rawAndCookedFamily(
    'goat-meat',
    { en: 'Goat meat', de: 'Ziegenfleisch', fr: 'Viande de chèvre', it: 'Carne di capra', ro: 'Carne de capră', th: 'เนื้อแพะ' },
    { kcal: 109, protein: 20.6, carbs: 0, fat: 2.31, saturatedFat: 0.71 },
    { kcal: 143, protein: 27.1, carbs: 0, fat: 3.03, saturatedFat: 0.93 },
  ),
]

function vegetableFamily(
  slug: string,
  names: CatalogNames,
  raw: MacroProfile,
  cooked: MacroProfile,
): CatalogFoodSpec[] {
  return [
    spec(slug, names, 'raw', raw, true),
    spec(slug, names, 'boiled', cooked, true),
    spec(slug, names, 'steamed', cooked),
    spec(slug, names, 'grilled', cooked),
    spec(slug, names, 'roasted', cooked),
    spec(slug, names, 'airFryer', cooked),
    spec(slug, names, 'panSeared', cooked),
    spec(slug, names, 'friedOil', withAbsorbedOil(cooked)),
  ]
}

const VEGETABLE_FOODS: CatalogFoodSpec[] = [
  ...vegetableFamily(
    'broccoli',
    { en: 'Broccoli florets', de: 'Brokkoliröschen', fr: 'Fleurettes de brocoli', it: 'Cimette di broccoli', ro: 'Buchețele de broccoli', th: 'บรอกโคลี' },
    { kcal: 34, protein: 2.82, carbs: 6.64, fat: 0.37, fibre: 2.6, sugar: 1.7, saturatedFat: 0.11 },
    { kcal: 35, protein: 2.38, carbs: 7.18, fat: 0.41, fibre: 3.3, sugar: 1.39, saturatedFat: 0.08 },
  ),
  ...vegetableFamily(
    'cauliflower',
    { en: 'Cauliflower florets', de: 'Blumenkohlröschen', fr: 'Fleurettes de chou-fleur', it: 'Cimette di cavolfiore', ro: 'Buchețele de conopidă', th: 'ดอกกะหล่ำ' },
    { kcal: 25, protein: 1.92, carbs: 4.97, fat: 0.28, fibre: 2, sugar: 1.91, saturatedFat: 0.13 },
    { kcal: 23, protein: 1.84, carbs: 4.11, fat: 0.45, fibre: 2.3, sugar: 2.08, saturatedFat: 0.07 },
  ),
  ...vegetableFamily(
    'carrots',
    { en: 'Carrots', de: 'Karotten', fr: 'Carottes', it: 'Carote', ro: 'Morcovi', th: 'แครอท' },
    { kcal: 41, protein: 0.93, carbs: 9.58, fat: 0.24, fibre: 2.8, sugar: 4.74, saturatedFat: 0.03 },
    { kcal: 35, protein: 0.76, carbs: 8.22, fat: 0.18, fibre: 3, sugar: 3.45, saturatedFat: 0.03 },
  ),
  ...vegetableFamily(
    'zucchini',
    { en: 'Zucchini with skin', de: 'Zucchini mit Schale', fr: 'Courgette avec peau', it: 'Zucchina con buccia', ro: 'Dovlecel cu coajă', th: 'ซูกินีพร้อมเปลือก' },
    { kcal: 17, protein: 1.21, carbs: 3.11, fat: 0.32, fibre: 1, sugar: 2.5, saturatedFat: 0.08 },
    { kcal: 15, protein: 1.14, carbs: 2.69, fat: 0.36, fibre: 1, sugar: 1.71, saturatedFat: 0.07 },
  ),
  ...vegetableFamily(
    'red-bell-pepper',
    { en: 'Red bell pepper', de: 'Rote Paprika', fr: 'Poivron rouge', it: 'Peperone rosso', ro: 'Ardei gras roșu', th: 'พริกหวานแดง' },
    { kcal: 26, protein: 0.99, carbs: 6.03, fat: 0.3, fibre: 2.1, sugar: 4.2, saturatedFat: 0.06 },
    { kcal: 28, protein: 0.92, carbs: 6.7, fat: 0.2, fibre: 1.2, sugar: 4.39, saturatedFat: 0.03 },
  ),
  ...vegetableFamily(
    'asparagus',
    { en: 'Asparagus', de: 'Spargel', fr: 'Asperges', it: 'Asparagi', ro: 'Sparanghel', th: 'หน่อไม้ฝรั่ง' },
    { kcal: 20, protein: 2.2, carbs: 3.88, fat: 0.12, fibre: 2.1, sugar: 1.88, saturatedFat: 0.04 },
    { kcal: 22, protein: 2.4, carbs: 4.11, fat: 0.22, fibre: 2, sugar: 1.3, saturatedFat: 0.05 },
  ),
  ...vegetableFamily(
    'brussels-sprouts',
    { en: 'Brussels sprouts', de: 'Rosenkohl', fr: 'Choux de Bruxelles', it: 'Cavolini di Bruxelles', ro: 'Varză de Bruxelles', th: 'กะหล่ำดาว' },
    { kcal: 43, protein: 3.38, carbs: 8.95, fat: 0.3, fibre: 3.8, sugar: 2.2, saturatedFat: 0.06 },
    { kcal: 36, protein: 2.55, carbs: 7.1, fat: 0.5, fibre: 2.6, sugar: 1.74, saturatedFat: 0.1 },
  ),
  ...vegetableFamily(
    'spinach',
    { en: 'Spinach leaves', de: 'Spinatblätter', fr: 'Feuilles d’épinards', it: 'Foglie di spinaci', ro: 'Frunze de spanac', th: 'ใบผักโขม' },
    { kcal: 23, protein: 2.86, carbs: 3.63, fat: 0.39, fibre: 2.2, sugar: 0.42, saturatedFat: 0.06 },
    { kcal: 23, protein: 2.97, carbs: 3.75, fat: 0.26, fibre: 2.4, sugar: 0.43, saturatedFat: 0.04 },
  ),
  ...vegetableFamily(
    'green-beans',
    { en: 'Green beans', de: 'Grüne Bohnen', fr: 'Haricots verts', it: 'Fagiolini', ro: 'Fasole verde', th: 'ถั่วแขก' },
    { kcal: 31, protein: 1.83, carbs: 6.97, fat: 0.22, fibre: 2.7, sugar: 3.26, saturatedFat: 0.05 },
    { kcal: 35, protein: 1.89, carbs: 7.88, fat: 0.28, fibre: 3.2, sugar: 3.63, saturatedFat: 0.06 },
  ),
  ...vegetableFamily(
    'green-peas',
    { en: 'Green peas', de: 'Grüne Erbsen', fr: 'Petits pois', it: 'Piselli', ro: 'Mazăre verde', th: 'ถั่วลันเตา' },
    { kcal: 81, protein: 5.42, carbs: 14.4, fat: 0.4, fibre: 5.7, sugar: 5.67, saturatedFat: 0.07 },
    { kcal: 84, protein: 5.36, carbs: 15.6, fat: 0.22, fibre: 5.5, sugar: 5.93, saturatedFat: 0.04 },
  ),
  ...vegetableFamily(
    'sweet-corn',
    { en: 'Sweet corn kernels', de: 'Zuckermaiskörner', fr: 'Grains de maïs doux', it: 'Chicchi di mais dolce', ro: 'Boabe de porumb dulce', th: 'เมล็ดข้าวโพดหวาน' },
    { kcal: 86, protein: 3.27, carbs: 18.7, fat: 1.35, fibre: 2, sugar: 6.26, saturatedFat: 0.33 },
    { kcal: 96, protein: 3.41, carbs: 21, fat: 1.5, fibre: 2.4, sugar: 4.54, saturatedFat: 0.2 },
  ),
  ...vegetableFamily(
    'eggplant',
    { en: 'Eggplant', de: 'Aubergine', fr: 'Aubergine', it: 'Melanzana', ro: 'Vânătă', th: 'มะเขือยาว' },
    { kcal: 25, protein: 0.98, carbs: 5.88, fat: 0.18, fibre: 3, sugar: 3.53, saturatedFat: 0.03 },
    { kcal: 35, protein: 0.83, carbs: 8.73, fat: 0.23, fibre: 2.5, sugar: 3.2, saturatedFat: 0.04 },
  ),
  ...vegetableFamily(
    'white-mushrooms',
    { en: 'White mushrooms', de: 'Weiße Champignons', fr: 'Champignons blancs', it: 'Funghi bianchi', ro: 'Ciuperci albe', th: 'เห็ดแชมปิญองขาว' },
    { kcal: 22, protein: 3.09, carbs: 3.26, fat: 0.34, fibre: 1, sugar: 1.98, saturatedFat: 0.05 },
    { kcal: 28, protein: 2.17, carbs: 5.29, fat: 0.47, fibre: 2.2, sugar: 2.34, saturatedFat: 0.06 },
  ),
  ...vegetableFamily(
    'white-cabbage',
    { en: 'White cabbage', de: 'Weißkohl', fr: 'Chou blanc', it: 'Cavolo bianco', ro: 'Varză albă', th: 'กะหล่ำปลีขาว' },
    { kcal: 25, protein: 1.28, carbs: 5.8, fat: 0.1, fibre: 2.5, sugar: 3.2, saturatedFat: 0.03 },
    { kcal: 23, protein: 1.27, carbs: 5.51, fat: 0.06, fibre: 1.9, sugar: 2.79, saturatedFat: 0 },
  ),
  ...vegetableFamily(
    'kale',
    { en: 'Kale', de: 'Grünkohl', fr: 'Chou kale', it: 'Cavolo riccio', ro: 'Kale', th: 'เคล' },
    { kcal: 35, protein: 2.92, carbs: 4.42, fat: 1.49, fibre: 4.1, sugar: 0.99, saturatedFat: 0.18 },
    { kcal: 36, protein: 2.94, carbs: 5.3, fat: 1.21, fibre: 4, sugar: 1.21, saturatedFat: 0.18 },
  ),
  ...vegetableFamily(
    'beets',
    { en: 'Beets', de: 'Rote Bete', fr: 'Betteraves', it: 'Barbabietole', ro: 'Sfeclă roșie', th: 'บีตรูต' },
    { kcal: 43, protein: 1.61, carbs: 9.56, fat: 0.17, fibre: 2.8, sugar: 6.76, saturatedFat: 0.03 },
    { kcal: 44, protein: 1.68, carbs: 9.96, fat: 0.18, fibre: 2, sugar: 7.96, saturatedFat: 0.03 },
  ),
  ...vegetableFamily(
    'onions',
    { en: 'Onions', de: 'Zwiebeln', fr: 'Oignons', it: 'Cipolle', ro: 'Ceapă', th: 'หัวหอม' },
    { kcal: 40, protein: 1.1, carbs: 9.34, fat: 0.1, fibre: 1.7, sugar: 4.24, saturatedFat: 0.04 },
    { kcal: 44, protein: 1.36, carbs: 10.2, fat: 0.19, fibre: 1.4, sugar: 4.73, saturatedFat: 0.03 },
  ),
  {
    slug: 'garlic-raw',
    names: { en: 'Garlic, raw', de: 'Knoblauch, roh', fr: 'Ail cru', it: 'Aglio crudo', ro: 'Usturoi crud', th: 'กระเทียมดิบ' },
    kcal: 149, protein: 6.36, carbs: 33.1, fat: 0.5, fibre: 2.1, sugar: 1, saturatedFat: 0.09, retailerReference: true,
  },
]

const STARCH_FOODS: CatalogFoodSpec[] = [
  ...vegetableFamily(
    'white-potato',
    { en: 'White potato with skin', de: 'Kartoffel mit Schale', fr: 'Pomme de terre avec peau', it: 'Patata con buccia', ro: 'Cartof alb cu coajă', th: 'มันฝรั่งพร้อมเปลือก' },
    { kcal: 77, protein: 2.05, carbs: 17.5, fat: 0.09, fibre: 2.1, sugar: 0.82, saturatedFat: 0.03 },
    { kcal: 87, protein: 1.87, carbs: 20.1, fat: 0.1, fibre: 1.8, sugar: 0.91, saturatedFat: 0.03 },
  ),
  ...vegetableFamily(
    'sweet-potato',
    { en: 'Sweet potato', de: 'Süßkartoffel', fr: 'Patate douce', it: 'Patata dolce', ro: 'Cartof dulce', th: 'มันหวาน' },
    { kcal: 86, protein: 1.57, carbs: 20.1, fat: 0.05, fibre: 3, sugar: 4.18, saturatedFat: 0.02 },
    { kcal: 76, protein: 1.37, carbs: 17.7, fat: 0.14, fibre: 2.5, sugar: 5.74, saturatedFat: 0.03 },
  ),
  {
    slug: 'brown-rice-cooked',
    names: { en: 'Brown rice, cooked', de: 'Vollkornreis, gekocht', fr: 'Riz complet, cuit', it: 'Riso integrale, cotto', ro: 'Orez brun, fiert', th: 'ข้าวกล้อง สุก' },
    kcal: 123, protein: 2.74, carbs: 25.6, fat: 0.97, fibre: 1.6, sugar: 0.24, saturatedFat: 0.26, preparation: 'cooked', retailerReference: true,
  },
  {
    slug: 'quinoa-cooked',
    names: { en: 'Quinoa, cooked', de: 'Quinoa, gekocht', fr: 'Quinoa, cuit', it: 'Quinoa, cotta', ro: 'Quinoa, fiartă', th: 'ควินัว สุก' },
    kcal: 120, protein: 4.4, carbs: 21.3, fat: 1.92, fibre: 2.8, sugar: 0.87, saturatedFat: 0.23, preparation: 'cooked', retailerReference: true,
  },
  {
    slug: 'couscous-cooked',
    names: { en: 'Couscous, cooked', de: 'Couscous, gekocht', fr: 'Couscous, cuit', it: 'Couscous, cotto', ro: 'Cuscus, fiert', th: 'คูสคูส สุก' },
    kcal: 112, protein: 3.79, carbs: 23.2, fat: 0.16, fibre: 1.4, sugar: 0.1, saturatedFat: 0.03, preparation: 'cooked', retailerReference: true,
  },
  {
    slug: 'wholegrain-pasta-cooked',
    names: { en: 'Wholegrain pasta, cooked', de: 'Vollkornpasta, gekocht', fr: 'Pâtes complètes, cuites', it: 'Pasta integrale, cotta', ro: 'Paste integrale, fierte', th: 'พาสต้าโฮลเกรน สุก' },
    kcal: 149, protein: 5.99, carbs: 30.1, fat: 1.71, fibre: 3.9, sugar: 0.75, saturatedFat: 0.24, preparation: 'cooked', retailerReference: true,
  },
  {
    slug: 'pearl-barley-cooked',
    names: { en: 'Pearl barley, cooked', de: 'Perlgraupen, gekocht', fr: 'Orge perlé, cuit', it: 'Orzo perlato, cotto', ro: 'Orz perlat, fiert', th: 'ข้าวบาร์เลย์มุก สุก' },
    kcal: 123, protein: 2.26, carbs: 28.2, fat: 0.44, fibre: 3.8, sugar: 0.28, saturatedFat: 0.09, preparation: 'cooked', retailerReference: true,
  },
  {
    slug: 'millet-cooked',
    names: { en: 'Millet, cooked', de: 'Hirse, gekocht', fr: 'Millet, cuit', it: 'Miglio, cotto', ro: 'Mei, fiert', th: 'ลูกเดือย สุก' },
    kcal: 119, protein: 3.51, carbs: 23.7, fat: 1, fibre: 1.3, sugar: 0.13, saturatedFat: 0.17, preparation: 'cooked', retailerReference: true,
  },
]

function liquidOil(
  slug: string,
  names: CatalogNames,
  saturatedFatPer100g?: number,
): CatalogFoodSpec {
  return {
    slug,
    names,
    kcal: 828,
    protein: 0,
    carbs: 0,
    fat: 92,
    saturatedFat: saturatedFatPer100g == null ? undefined : Math.round(saturatedFatPer100g * 92) / 100,
    fibre: 0,
    sugar: 0,
    salt: 0,
    nutritionBasis: 'per_100ml',
    servingAmount: 15,
    servingUnit: 'ml',
    preparation: 'as_sold',
    retailerReference: true,
  }
}

const OIL_FOODS: CatalogFoodSpec[] = [
  liquidOil('olive-oil-refined', { en: 'Olive oil, refined', de: 'Olivenöl, raffiniert', fr: 'Huile d’olive raffinée', it: 'Olio d’oliva raffinato', ro: 'Ulei de măsline rafinat', th: 'น้ำมันมะกอกผ่านกรรมวิธี' }, 13.8),
  liquidOil('rapeseed-oil-cold-pressed', { en: 'Rapeseed oil, cold-pressed', de: 'Rapsöl, kaltgepresst', fr: 'Huile de colza pressée à froid', it: 'Olio di colza spremuto a freddo', ro: 'Ulei de rapiță presat la rece', th: 'น้ำมันคาโนลาสกัดเย็น' }, 7.36),
  liquidOil('canola-oil-refined', { en: 'Canola oil, refined', de: 'Rapsöl, raffiniert', fr: 'Huile de colza raffinée', it: 'Olio di canola raffinato', ro: 'Ulei de rapiță rafinat', th: 'น้ำมันคาโนลาผ่านกรรมวิธี' }, 7.36),
  liquidOil('sunflower-oil-linoleic', { en: 'Sunflower oil, linoleic', de: 'Sonnenblumenöl, linolsäurereich', fr: 'Huile de tournesol linoléique', it: 'Olio di girasole linoleico', ro: 'Ulei de floarea-soarelui, linoleic', th: 'น้ำมันดอกทานตะวันชนิดไลโนเลอิก' }, 10.1),
  liquidOil('sunflower-oil-high-oleic', { en: 'Sunflower oil, high-oleic', de: 'Sonnenblumenöl, High-Oleic', fr: 'Huile de tournesol riche en acide oléique', it: 'Olio di girasole alto oleico', ro: 'Ulei de floarea-soarelui, bogat în acid oleic', th: 'น้ำมันดอกทานตะวันโอเลอิกสูง' }, 9.86),
  liquidOil('sunflower-oil-cold-pressed', { en: 'Sunflower oil, cold-pressed', de: 'Sonnenblumenöl, kaltgepresst', fr: 'Huile de tournesol pressée à froid', it: 'Olio di girasole spremuto a freddo', ro: 'Ulei de floarea-soarelui presat la rece', th: 'น้ำมันดอกทานตะวันสกัดเย็น' }, 10.1),
  liquidOil('avocado-oil-refined', { en: 'Avocado oil, refined', de: 'Avocadoöl, raffiniert', fr: 'Huile d’avocat raffinée', it: 'Olio di avocado raffinato', ro: 'Ulei de avocado rafinat', th: 'น้ำมันอะโวคาโดผ่านกรรมวิธี' }, 11.6),
  liquidOil('avocado-oil-cold-pressed', { en: 'Avocado oil, cold-pressed', de: 'Avocadoöl, kaltgepresst', fr: 'Huile d’avocat pressée à froid', it: 'Olio di avocado spremuto a freddo', ro: 'Ulei de avocado presat la rece', th: 'น้ำมันอะโวคาโดสกัดเย็น' }, 11.6),
  liquidOil('walnut-oil-cold-pressed', { en: 'Walnut oil, cold-pressed', de: 'Walnussöl, kaltgepresst', fr: 'Huile de noix pressée à froid', it: 'Olio di noce spremuto a freddo', ro: 'Ulei de nucă presat la rece', th: 'น้ำมันวอลนัตสกัดเย็น' }, 9.1),
  liquidOil('flaxseed-oil-cold-pressed', { en: 'Flaxseed oil, cold-pressed', de: 'Leinöl, kaltgepresst', fr: 'Huile de lin pressée à froid', it: 'Olio di semi di lino spremuto a freddo', ro: 'Ulei de semințe de in presat la rece', th: 'น้ำมันเมล็ดแฟลกซ์สกัดเย็น' }, 8.98),
  liquidOil('sesame-oil', { en: 'Sesame oil', de: 'Sesamöl', fr: 'Huile de sésame', it: 'Olio di sesamo', ro: 'Ulei de susan', th: 'น้ำมันงา' }, 14.2),
  liquidOil('sesame-oil-toasted', { en: 'Toasted sesame oil', de: 'Geröstetes Sesamöl', fr: 'Huile de sésame grillé', it: 'Olio di sesamo tostato', ro: 'Ulei de susan prăjit', th: 'น้ำมันงาคั่ว' }, 14.2),
  liquidOil('coconut-oil-virgin', { en: 'Coconut oil, virgin', de: 'Kokosöl, nativ', fr: 'Huile de coco vierge', it: 'Olio di cocco vergine', ro: 'Ulei de cocos virgin', th: 'น้ำมันมะพร้าวบริสุทธิ์' }, 82.5),
  liquidOil('coconut-oil-refined', { en: 'Coconut oil, refined', de: 'Kokosöl, raffiniert', fr: 'Huile de coco raffinée', it: 'Olio di cocco raffinato', ro: 'Ulei de cocos rafinat', th: 'น้ำมันมะพร้าวผ่านกรรมวิธี' }, 82.5),
  liquidOil('peanut-oil', { en: 'Peanut oil', de: 'Erdnussöl', fr: 'Huile d’arachide', it: 'Olio di arachidi', ro: 'Ulei de arahide', th: 'น้ำมันถั่วลิสง' }, 16.9),
  liquidOil('corn-oil', { en: 'Corn oil', de: 'Maiskeimöl', fr: 'Huile de maïs', it: 'Olio di mais', ro: 'Ulei de porumb', th: 'น้ำมันข้าวโพด' }, 12.9),
  liquidOil('soybean-oil', { en: 'Soybean oil', de: 'Sojaöl', fr: 'Huile de soja', it: 'Olio di soia', ro: 'Ulei de soia', th: 'น้ำมันถั่วเหลือง' }, 15.6),
  liquidOil('grapeseed-oil', { en: 'Grapeseed oil', de: 'Traubenkernöl', fr: 'Huile de pépins de raisin', it: 'Olio di vinaccioli', ro: 'Ulei din sâmburi de struguri', th: 'น้ำมันเมล็ดองุ่น' }, 9.6),
  liquidOil('rice-bran-oil', { en: 'Rice bran oil', de: 'Reiskleieöl', fr: 'Huile de son de riz', it: 'Olio di crusca di riso', ro: 'Ulei din tărâțe de orez', th: 'น้ำมันรำข้าว' }, 19.7),
  liquidOil('safflower-oil-linoleic', { en: 'Safflower oil, linoleic', de: 'Distelöl, linolsäurereich', fr: 'Huile de carthame linoléique', it: 'Olio di cartamo linoleico', ro: 'Ulei de șofrănel, linoleic', th: 'น้ำมันดอกคำฝอยชนิดไลโนเลอิก' }, 6.2),
  liquidOil('safflower-oil-high-oleic', { en: 'Safflower oil, high-oleic', de: 'Distelöl, High-Oleic', fr: 'Huile de carthame riche en acide oléique', it: 'Olio di cartamo alto oleico', ro: 'Ulei de șofrănel, bogat în acid oleic', th: 'น้ำมันดอกคำฝอยโอเลอิกสูง' }, 7.54),
  liquidOil('cottonseed-oil', { en: 'Cottonseed oil', de: 'Baumwollsamenöl', fr: 'Huile de coton', it: 'Olio di semi di cotone', ro: 'Ulei din semințe de bumbac', th: 'น้ำมันเมล็ดฝ้าย' }, 25.9),
  liquidOil('palm-oil', { en: 'Palm oil', de: 'Palmöl', fr: 'Huile de palme', it: 'Olio di palma', ro: 'Ulei de palmier', th: 'น้ำมันปาล์ม' }, 49.3),
  liquidOil('palm-kernel-oil', { en: 'Palm kernel oil', de: 'Palmkernöl', fr: 'Huile de palmiste', it: 'Olio di palmisto', ro: 'Ulei din sâmburi de palmier', th: 'น้ำมันเมล็ดในปาล์ม' }, 81.5),
  liquidOil('pumpkin-seed-oil', { en: 'Pumpkin seed oil, cold-pressed', de: 'Kürbiskernöl, kaltgepresst', fr: 'Huile de pépins de courge pressée à froid', it: 'Olio di semi di zucca spremuto a freddo', ro: 'Ulei din semințe de dovleac presat la rece', th: 'น้ำมันเมล็ดฟักทองสกัดเย็น' }),
  liquidOil('hemp-seed-oil', { en: 'Hemp seed oil, cold-pressed', de: 'Hanföl, kaltgepresst', fr: 'Huile de chanvre pressée à froid', it: 'Olio di canapa spremuto a freddo', ro: 'Ulei de cânepă presat la rece', th: 'น้ำมันเมล็ดกัญชงสกัดเย็น' }),
  liquidOil('mustard-oil', { en: 'Mustard oil', de: 'Senföl', fr: 'Huile de moutarde', it: 'Olio di senape', ro: 'Ulei de muștar', th: 'น้ำมันมัสตาร์ด' }),
  liquidOil('hazelnut-oil', { en: 'Hazelnut oil', de: 'Haselnussöl', fr: 'Huile de noisette', it: 'Olio di nocciola', ro: 'Ulei de alune de pădure', th: 'น้ำมันเฮเซลนัต' }),
  liquidOil('almond-oil', { en: 'Almond oil, edible', de: 'Mandelöl, essbar', fr: 'Huile d’amande alimentaire', it: 'Olio di mandorle alimentare', ro: 'Ulei de migdale alimentar', th: 'น้ำมันอัลมอนด์สำหรับอาหาร' }),
  liquidOil('mct-oil', { en: 'MCT oil', de: 'MCT-Öl', fr: 'Huile MCT', it: 'Olio MCT', ro: 'Ulei MCT', th: 'น้ำมันเอ็มซีที' }, 100),
]

const FAT_AND_BUTTER_FOODS: CatalogFoodSpec[] = [
  {
    slug: 'butter-salted',
    names: { en: 'Butter, salted', de: 'Butter, gesalzen', fr: 'Beurre salé', it: 'Burro salato', ro: 'Unt sărat', th: 'เนยเค็ม' },
    kcal: 717, protein: 0.85, carbs: 0.06, fat: 81.1, saturatedFat: 51.4, salt: 1.63, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'butter-unsalted',
    names: { en: 'Butter, unsalted', de: 'Butter, ungesalzen', fr: 'Beurre doux', it: 'Burro non salato', ro: 'Unt nesărat', th: 'เนยจืด' },
    kcal: 717, protein: 0.85, carbs: 0.06, fat: 81.1, saturatedFat: 50.5, salt: 0.03, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'ghee-clarified-butter',
    names: { en: 'Ghee, clarified butter', de: 'Ghee, geklärte Butter', fr: 'Ghee, beurre clarifié', it: 'Ghee, burro chiarificato', ro: 'Ghee, unt clarificat', th: 'กี เนยใส' },
    kcal: 900, protein: 0, carbs: 0, fat: 100, saturatedFat: 60, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'beef-tallow',
    names: { en: 'Beef tallow', de: 'Rindertalg', fr: 'Suif de bœuf', it: 'Sego di manzo', ro: 'Seu de vită', th: 'ไขมันวัวเจียว' },
    kcal: 902, protein: 0, carbs: 0, fat: 100, saturatedFat: 49.8, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'pork-lard',
    names: { en: 'Pork lard', de: 'Schweineschmalz', fr: 'Saindoux', it: 'Strutto', ro: 'Untură de porc', th: 'มันหมู' },
    kcal: 902, protein: 0, carbs: 0, fat: 100, saturatedFat: 39.2, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'chicken-fat',
    names: { en: 'Rendered chicken fat', de: 'Ausgelassenes Hühnerfett', fr: 'Graisse de poulet fondue', it: 'Grasso di pollo fuso', ro: 'Grăsime de pui topită', th: 'มันไก่เจียว' },
    kcal: 900, protein: 0, carbs: 0, fat: 99.8, saturatedFat: 29.8, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'duck-fat',
    names: { en: 'Rendered duck fat', de: 'Ausgelassenes Entenfett', fr: 'Graisse de canard fondue', it: 'Grasso d’anatra fuso', ro: 'Grăsime de rață topită', th: 'มันเป็ดเจียว' },
    kcal: 900, protein: 0, carbs: 0, fat: 99.8, saturatedFat: 33.2, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'goose-fat',
    names: { en: 'Rendered goose fat', de: 'Ausgelassenes Gänsefett', fr: 'Graisse d’oie fondue', it: 'Grasso d’oca fuso', ro: 'Grăsime de gâscă topită', th: 'มันห่านเจียว' },
    kcal: 900, protein: 0, carbs: 0, fat: 99.8, saturatedFat: 27.7, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'turkey-fat',
    names: { en: 'Rendered turkey fat', de: 'Ausgelassenes Putenfett', fr: 'Graisse de dinde fondue', it: 'Grasso di tacchino fuso', ro: 'Grăsime de curcan topită', th: 'มันไก่งวงเจียว' },
    kcal: 900, protein: 0, carbs: 0, fat: 99.8, saturatedFat: 29.4, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'cocoa-butter',
    names: { en: 'Cocoa butter, edible', de: 'Kakaobutter, essbar', fr: 'Beurre de cacao alimentaire', it: 'Burro di cacao alimentare', ro: 'Unt de cacao alimentar', th: 'เนยโกโก้สำหรับอาหาร' },
    kcal: 884, protein: 0, carbs: 0, fat: 100, saturatedFat: 59.7, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'cashew-butter',
    names: { en: 'Cashew butter, 100% cashews', de: 'Cashewmus, 100% Cashews', fr: 'Purée de noix de cajou, 100%', it: 'Crema di anacardi, 100%', ro: 'Unt de caju, 100% caju', th: 'เนยเม็ดมะม่วงหิมพานต์ 100%' },
    kcal: 587, protein: 17.6, carbs: 27.6, fat: 49.4, fibre: 2.8, sugar: 5, saturatedFat: 9.8, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'hazelnut-butter',
    names: { en: 'Hazelnut butter, 100% hazelnuts', de: 'Haselnussmus, 100% Haselnüsse', fr: 'Purée de noisettes, 100%', it: 'Crema di nocciole, 100%', ro: 'Unt de alune de pădure, 100%', th: 'เนยเฮเซลนัต 100%' },
    kcal: 628, protein: 15, carbs: 16.7, fat: 60.8, fibre: 9.7, sugar: 4.3, saturatedFat: 4.5, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'sunflower-seed-butter',
    names: { en: 'Sunflower seed butter, unsweetened', de: 'Sonnenblumenkernmus, ungesüßt', fr: 'Purée de graines de tournesol, sans sucre', it: 'Crema di semi di girasole, senza zucchero', ro: 'Unt din semințe de floarea-soarelui, neîndulcit', th: 'เนยเมล็ดทานตะวัน ไม่เติมน้ำตาล' },
    kcal: 617, protein: 17.3, carbs: 17.3, fat: 55.2, fibre: 9.7, sugar: 3.1, saturatedFat: 5.2, preparation: 'as_sold', retailerReference: true,
  },
  {
    slug: 'tahini-sesame-butter',
    names: { en: 'Tahini, sesame seed butter', de: 'Tahini, Sesammus', fr: 'Tahini, purée de sésame', it: 'Tahina, crema di sesamo', ro: 'Tahini, unt de susan', th: 'ทาฮินี เนยงา' },
    kcal: 595, protein: 17, carbs: 21.2, fat: 53.8, fibre: 9.3, sugar: 0.5, saturatedFat: 7.5, preparation: 'as_sold', retailerReference: true,
  },
]

/*
 * Curated Thai/Asian essentials for offline discovery. Mixed dishes are named
 * as recipe references because oil, meat fat and sauces can materially change
 * their macros; exact packaged products still come from barcode/provider
 * records. Rice hydration variants deliberately state their cooking ratio so
 * people do not confuse a dry value with a prepared value.
 */
const THAI_AND_ASIAN_FOODS: CatalogFoodSpec[] = [
  {
    slug: 'jasmine-rice-white-dry',
    names: { en: 'Jasmine rice, white, dry', de: 'Jasminreis, weiß, trocken', fr: 'Riz jasmin blanc, sec', it: 'Riso jasmine bianco, secco', ro: 'Orez jasmine alb, uscat', th: 'ข้าวหอมมะลิขาว ดิบ' },
    kcal: 356, protein: 6.5, carbs: 79.9, fat: 0.7, fibre: 1.3, preparation: 'dry', retailerReference: true,
  },
  {
    slug: 'jasmine-rice-brown-dry',
    names: { en: 'Brown jasmine rice, dry', de: 'Jasmin-Vollkornreis, trocken', fr: 'Riz jasmin complet, sec', it: 'Riso jasmine integrale, secco', ro: 'Orez jasmine integral, uscat', th: 'ข้าวกล้องหอมมะลิ ดิบ' },
    kcal: 363, protein: 7.34, carbs: 74.93, fat: 2.95, fibre: 3.3, preparation: 'dry', retailerReference: true,
  },
  {
    slug: 'jasmine-rice-cooked-ratio-1-1-5',
    names: { en: 'Jasmine rice, cooked, 1:1.5 rice-to-water reference', de: 'Jasminreis, gekocht, Reis-Wasser 1:1,5 Referenz', fr: 'Riz jasmin cuit, référence riz-eau 1:1,5', it: 'Riso jasmine cotto, riferimento riso-acqua 1:1,5', ro: 'Orez jasmine fiert, reper orez-apă 1:1,5', th: 'ข้าวหอมมะลิหุงสุก อัตราข้าวต่อน้ำ 1:1.5' },
    kcal: 148, protein: 2.7, carbs: 33.2, fat: 0.3, fibre: 0.5, preparation: 'cooked', retailerReference: false,
  },
  {
    slug: 'jasmine-rice-cooked-ratio-1-2',
    names: { en: 'Jasmine rice, cooked, 1:2 rice-to-water reference', de: 'Jasminreis, gekocht, Reis-Wasser 1:2 Referenz', fr: 'Riz jasmin cuit, référence riz-eau 1:2', it: 'Riso jasmine cotto, riferimento riso-acqua 1:2', ro: 'Orez jasmine fiert, reper orez-apă 1:2', th: 'ข้าวหอมมะลิหุงสุก อัตราข้าวต่อน้ำ 1:2' },
    kcal: 130, protein: 2.4, carbs: 28.7, fat: 0.2, fibre: 0.4, preparation: 'cooked', retailerReference: false,
  },
  {
    slug: 'jasmine-rice-cooked-ratio-1-2-5',
    names: { en: 'Jasmine rice, cooked, 1:2.5 rice-to-water reference', de: 'Jasminreis, gekocht, Reis-Wasser 1:2,5 Referenz', fr: 'Riz jasmin cuit, référence riz-eau 1:2,5', it: 'Riso jasmine cotto, riferimento riso-acqua 1:2,5', ro: 'Orez jasmine fiert, reper orez-apă 1:2,5', th: 'ข้าวหอมมะลิหุงสุก อัตราข้าวต่อน้ำ 1:2.5' },
    kcal: 114, protein: 2.1, carbs: 25.2, fat: 0.2, fibre: 0.4, preparation: 'cooked', retailerReference: false,
  },
  {
    slug: 'jasmine-rice-ready-to-eat',
    names: { en: 'Jasmine rice, ready to eat, package-label reference', de: 'Jasminreis, verzehrfertig, Etikett-Referenz', fr: 'Riz jasmin prêt à consommer, référence d’étiquette', it: 'Riso jasmine pronto, riferimento da etichetta', ro: 'Orez jasmine gata de consum, reper de etichetă', th: 'ข้าวหอมมะลิพร้อมรับประทาน ค่าอ้างอิงจากฉลาก' },
    kcal: 154, protein: 3.1, carbs: 34, fat: 0.4, fibre: 0.5, preparation: 'prepared', servingAmount: 150, servingUnit: 'g', retailerReference: false,
  },
  {
    slug: 'sticky-rice-white-dry',
    names: { en: 'Thai sticky rice, white, dry', de: 'Thailändischer Klebreis, weiß, trocken', fr: 'Riz gluant thaï blanc, sec', it: 'Riso glutinoso thailandese bianco, secco', ro: 'Orez lipicios thailandez alb, uscat', th: 'ข้าวเหนียวขาว ดิบ' },
    kcal: 354, protein: 6.3, carbs: 81, fat: 0.6, fibre: 1.0, preparation: 'dry', retailerReference: true,
  },
  {
    slug: 'sticky-rice-white-steamed',
    names: { en: 'Thai sticky rice, steamed', de: 'Thailändischer Klebreis, gedämpft', fr: 'Riz gluant thaï, cuit à la vapeur', it: 'Riso glutinoso thailandese al vapore', ro: 'Orez lipicios thailandez, gătit la abur', th: 'ข้าวเหนียวนึ่ง' },
    kcal: 169, protein: 3.5, carbs: 37.4, fat: 0.3, fibre: 0.6, preparation: 'cooked', retailerReference: false,
  },
  {
    slug: 'rice-noodles-dry',
    names: { en: 'Rice noodles, dry', de: 'Reisnudeln, trocken', fr: 'Nouilles de riz, sèches', it: 'Spaghetti di riso, secchi', ro: 'Tăiței de orez, uscați', th: 'เส้นก๋วยเตี๋ยวแห้ง' },
    kcal: 364, protein: 5.9, carbs: 80.2, fat: 0.6, fibre: 1.6, preparation: 'dry', retailerReference: true,
  },
  {
    slug: 'rice-noodles-boiled',
    names: { en: 'Rice noodles, boiled and drained', de: 'Reisnudeln, gekocht und abgetropft', fr: 'Nouilles de riz, cuites et égouttées', it: 'Spaghetti di riso, bolliti e scolati', ro: 'Tăiței de orez, fierți și scurși', th: 'เส้นก๋วยเตี๋ยวต้ม สะเด็ดน้ำ' },
    kcal: 109, protein: 1.8, carbs: 24.9, fat: 0.2, fibre: 1.0, preparation: 'cooked', retailerReference: false,
  },
  {
    slug: 'rice-vermicelli-dry',
    names: { en: 'Rice vermicelli, dry', de: 'Reisvermicelli, trocken', fr: 'Vermicelles de riz, secs', it: 'Vermicelli di riso, secchi', ro: 'Fidea de orez, uscată', th: 'เส้นหมี่ข้าว แห้ง' },
    kcal: 364, protein: 5.6, carbs: 81, fat: 0.5, fibre: 1.4, preparation: 'dry', retailerReference: true,
  },
  {
    slug: 'rice-vermicelli-cooked',
    names: { en: 'Rice vermicelli, cooked and drained', de: 'Reisvermicelli, gekocht und abgetropft', fr: 'Vermicelles de riz, cuits et égouttés', it: 'Vermicelli di riso, cotti e scolati', ro: 'Fidea de orez, fiartă și scursă', th: 'เส้นหมี่ข้าวลวก สะเด็ดน้ำ' },
    kcal: 108, protein: 1.8, carbs: 24.6, fat: 0.2, fibre: 0.8, preparation: 'cooked', retailerReference: false,
  },
  {
    slug: 'crispy-fried-pork-belly-recipe',
    names: { en: 'Crispy fried pork belly, Thai recipe reference', de: 'Knusprig frittierter Schweinebauch, Thai-Rezeptreferenz', fr: 'Poitrine de porc frite croustillante, référence thaïe', it: 'Pancetta di maiale fritta croccante, riferimento thailandese', ro: 'Burtă de porc prăjită crocant, reper de rețetă thailandeză', th: 'หมูกรอบ สูตรอ้างอิง' },
    kcal: 430, protein: 20, carbs: 4, fat: 37, saturatedFat: 13, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'pad-kra-pao-moo-sab-no-rice-egg',
    names: { en: 'Phad Kaprao Moo Sab, minced pork, no rice or egg, recipe reference', de: 'Phad Kaprao Moo Sab mit Schweinehack, ohne Reis oder Ei, Rezeptreferenz', fr: 'Phad Kaprao Moo Sab au porc haché, sans riz ni œuf, référence', it: 'Phad Kaprao Moo Sab con maiale macinato, senza riso o uovo, riferimento', ro: 'Phad Kaprao Moo Sab cu porc tocat, fără orez sau ou, reper de rețetă', th: 'ผัดกะเพราหมูสับ ไม่รวมข้าวหรือไข่ สูตรอ้างอิง' },
    kcal: 216, protein: 15, carbs: 7, fat: 14.5, sugar: 2.5, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'pad-kra-pao-neua-sab-no-rice-egg',
    names: { en: 'Phad Kaprao Neua Sab, minced beef, no rice or egg, recipe reference', de: 'Phad Kaprao Neua Sab mit Rinderhack, ohne Reis oder Ei, Rezeptreferenz', fr: 'Phad Kaprao Neua Sab au bœuf haché, sans riz ni œuf, référence', it: 'Phad Kaprao Neua Sab con manzo macinato, senza riso o uovo, riferimento', ro: 'Phad Kaprao Neua Sab cu vită tocată, fără orez sau ou, reper de rețetă', th: 'ผัดกะเพราเนื้อสับ ไม่รวมข้าวหรือไข่ สูตรอ้างอิง' },
    kcal: 190, protein: 17, carbs: 7, fat: 10.5, sugar: 2.5, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'pad-thai-shrimp-recipe',
    names: { en: 'Pad Thai with shrimp, recipe reference', de: 'Pad Thai mit Garnelen, Rezeptreferenz', fr: 'Pad thaï aux crevettes, référence de recette', it: 'Pad Thai con gamberi, riferimento ricetta', ro: 'Pad Thai cu creveți, reper de rețetă', th: 'ผัดไทยกุ้ง สูตรอ้างอิง' },
    kcal: 195, protein: 8, carbs: 27, fat: 6.5, fibre: 1.4, sugar: 5, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'nam-tok-neua-recipe',
    names: { en: 'Nam tok neua, Thai beef salad, recipe reference', de: 'Nam Tok Neua, thailändischer Rindfleischsalat, Rezeptreferenz', fr: 'Nam tok neua, salade thaïe de bœuf, référence', it: 'Nam tok neua, insalata thailandese di manzo, riferimento', ro: 'Nam tok neua, salată thailandeză cu vită, reper de rețetă', th: 'น้ำตกเนื้อ สูตรอ้างอิง' },
    kcal: 168, protein: 18, carbs: 5, fat: 8.5, fibre: 0.8, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'larb-moo-recipe',
    names: { en: 'Larb moo, minced pork salad, recipe reference', de: 'Larb Moo, Schweinehacksalat, Rezeptreferenz', fr: 'Larb moo, salade de porc haché, référence', it: 'Larb moo, insalata di maiale macinato, riferimento', ro: 'Larb moo, salată cu porc tocat, reper de rețetă', th: 'ลาบหมู สูตรอ้างอิง' },
    kcal: 174, protein: 17, carbs: 6, fat: 9, fibre: 0.8, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'som-tam-thai-recipe',
    names: { en: 'Som tam Thai, green papaya salad, recipe reference', de: 'Som Tam Thai, grüner Papayasalat, Rezeptreferenz', fr: 'Som tam thaï, salade de papaye verte, référence', it: 'Som tam thai, insalata di papaya verde, riferimento', ro: 'Som tam Thai, salată de papaya verde, reper de rețetă', th: 'ส้มตำไทย สูตรอ้างอิง' },
    kcal: 76, protein: 2, carbs: 14, fat: 1.5, fibre: 2.4, sugar: 8, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'tom-yum-goong-recipe',
    names: { en: 'Tom yum goong, shrimp soup, recipe reference', de: 'Tom Yum Goong, Garnelensuppe, Rezeptreferenz', fr: 'Tom yum goong, soupe de crevettes, référence', it: 'Tom yum goong, zuppa di gamberi, riferimento', ro: 'Tom yum goong, supă cu creveți, reper de rețetă', th: 'ต้มยำกุ้ง สูตรอ้างอิง' },
    kcal: 63, protein: 6.5, carbs: 4.5, fat: 2.1, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'tom-kha-gai-recipe',
    names: { en: 'Tom kha gai, coconut chicken soup, recipe reference', de: 'Tom Kha Gai, Kokos-Hühnersuppe, Rezeptreferenz', fr: 'Tom kha gai, soupe de poulet au lait de coco, référence', it: 'Tom kha gai, zuppa di pollo al cocco, riferimento', ro: 'Tom kha gai, supă de pui cu cocos, reper de rețetă', th: 'ต้มข่าไก่ สูตรอ้างอิง' },
    kcal: 112, protein: 7, carbs: 5, fat: 7.2, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'thai-green-curry-chicken-no-rice',
    names: { en: 'Thai green curry with chicken, no rice, recipe reference', de: 'Thailändisches grünes Curry mit Huhn, ohne Reis, Rezeptreferenz', fr: 'Curry vert thaï au poulet, sans riz, référence', it: 'Curry verde thailandese con pollo, senza riso, riferimento', ro: 'Curry verde thailandez cu pui, fără orez, reper de rețetă', th: 'แกงเขียวหวานไก่ ไม่รวมข้าว สูตรอ้างอิง' },
    kcal: 156, protein: 9, carbs: 7, fat: 10, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'thai-red-curry-chicken-no-rice',
    names: { en: 'Thai red curry with chicken, no rice, recipe reference', de: 'Thailändisches rotes Curry mit Huhn, ohne Reis, Rezeptreferenz', fr: 'Curry rouge thaï au poulet, sans riz, référence', it: 'Curry rosso thailandese con pollo, senza riso, riferimento', ro: 'Curry roșu thailandez cu pui, fără orez, reper de rețetă', th: 'แกงเผ็ดไก่ ไม่รวมข้าว สูตรอ้างอิง' },
    kcal: 162, protein: 9, carbs: 7, fat: 10.7, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'massaman-curry-beef-no-rice',
    names: { en: 'Massaman curry with beef, no rice, recipe reference', de: 'Massaman-Curry mit Rind, ohne Reis, Rezeptreferenz', fr: 'Curry massaman au bœuf, sans riz, référence', it: 'Curry massaman con manzo, senza riso, riferimento', ro: 'Curry massaman cu vită, fără orez, reper de rețetă', th: 'แกงมัสมั่นเนื้อ ไม่รวมข้าว สูตรอ้างอิง' },
    kcal: 196, protein: 10, carbs: 12, fat: 12, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'pad-see-ew-chicken-recipe',
    names: { en: 'Pad see ew with chicken, recipe reference', de: 'Pad See Ew mit Huhn, Rezeptreferenz', fr: 'Pad see ew au poulet, référence', it: 'Pad see ew con pollo, riferimento', ro: 'Pad see ew cu pui, reper de rețetă', th: 'ผัดซีอิ๊วไก่ สูตรอ้างอิง' },
    kcal: 181, protein: 9, carbs: 25, fat: 5.5, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'thai-omelette-kai-jeow',
    names: { en: 'Thai omelette, kai jeow, recipe reference', de: 'Thailändisches Omelett, Kai Jeow, Rezeptreferenz', fr: 'Omelette thaïe kai jeow, référence', it: 'Omelette thailandese kai jeow, riferimento', ro: 'Omletă thailandeză kai jeow, reper de rețetă', th: 'ไข่เจียวไทย สูตรอ้างอิง' },
    kcal: 235, protein: 12, carbs: 2.5, fat: 19.5, preparation: 'prepared', servingAmount: 1, servingUnit: 'piece', pieceGrams: 100, retailerReference: false,
  },
  {
    slug: 'gai-yang-grilled-chicken',
    names: { en: 'Gai yang, Thai grilled chicken, recipe reference', de: 'Gai Yang, thailändisches Grillhuhn, Rezeptreferenz', fr: 'Gai yang, poulet grillé thaï, référence', it: 'Gai yang, pollo grigliato thailandese, riferimento', ro: 'Gai yang, pui thailandez la grătar, reper de rețetă', th: 'ไก่ย่าง สูตรอ้างอิง' },
    kcal: 190, protein: 25, carbs: 4, fat: 8, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'moo-ping-grilled-pork',
    names: { en: 'Moo ping, Thai grilled pork skewer, recipe reference', de: 'Moo Ping, thailändischer Schweinespieß, Rezeptreferenz', fr: 'Moo ping, brochette de porc thaïe, référence', it: 'Moo ping, spiedino di maiale thailandese, riferimento', ro: 'Moo ping, frigăruie thailandeză de porc, reper de rețetă', th: 'หมูปิ้ง สูตรอ้างอิง' },
    kcal: 245, protein: 18, carbs: 9, fat: 15, preparation: 'prepared', servingAmount: 1, servingUnit: 'piece', pieceGrams: 45, retailerReference: false,
  },
  {
    slug: 'mango-sticky-rice-recipe',
    names: { en: 'Mango sticky rice, recipe reference', de: 'Mango-Klebreis, Rezeptreferenz', fr: 'Riz gluant à la mangue, référence', it: 'Riso glutinoso al mango, riferimento', ro: 'Orez lipicios cu mango, reper de rețetă', th: 'ข้าวเหนียวมะม่วง สูตรอ้างอิง' },
    kcal: 214, protein: 3, carbs: 42, fat: 4.3, sugar: 17, preparation: 'prepared', retailerReference: false,
  },
  {
    slug: 'kap-moo-thai-pork-cracklings',
    names: { en: 'Kap Moo, Thai pork cracklings, recipe reference', de: 'Kap Moo, thailändische Schweineschwarten-Chips, Rezeptreferenz', fr: 'Kap Moo, couennes de porc croustillantes thaïes, référence', it: 'Kap Moo, cotenne di maiale croccanti thailandesi, riferimento', ro: 'Kap Moo, șorici de porc crocant thailandez, reper de rețetă', th: 'แคปหมู สูตรอ้างอิง' },
    kcal: 544, protein: 61.3, carbs: 0, fat: 31.3, saturatedFat: 11.4, preparation: 'prepared', servingAmount: 30, servingUnit: 'g', retailerReference: false,
  },
  {
    slug: 'khai-dao-thai-fried-egg',
    names: { en: 'Khai Dao, Thai fried egg, recipe reference', de: 'Khai Dao, thailändisches Spiegelei, Rezeptreferenz', fr: 'Khai Dao, œuf frit thaï, référence', it: 'Khai Dao, uovo fritto thailandese, riferimento', ro: 'Khai Dao, ou prăjit thailandez, reper de rețetă', th: 'ไข่ดาว สูตรอ้างอิง' },
    kcal: 196, protein: 13.6, carbs: 0.8, fat: 14.8, saturatedFat: 4.2, preparation: 'prepared', servingAmount: 1, servingUnit: 'piece', pieceGrams: 46, retailerReference: false,
  },
]

export const EXPANDED_FOOD_SPECS: CatalogFoodSpec[] = [
  ...FISH_FOODS,
  ...MEAT_FOODS,
  ...VEGETABLE_FOODS,
  ...STARCH_FOODS,
  ...OIL_FOODS,
  ...FAT_AND_BUTTER_FOODS,
  ...THAI_AND_ASIAN_FOODS,
]
