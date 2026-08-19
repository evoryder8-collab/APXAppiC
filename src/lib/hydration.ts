/*
 * Water content of foods, and the share of it that counts as hydration.
 *
 * Every logged food carries grams of water per 100 g. Curated catalogue rows
 * carry a measured value; anything arriving from a provider or created by
 * hand is estimated here.
 *
 * Reference values: Swiss Food Composition Database V7.1 (FSVO/BLV,
 * naehrwertdaten.ch) and USDA FoodData Central. Estimation by difference -
 * water = 100 - protein - fat - carbohydrate - ash - alcohol - is the standard
 * composition-table method, used here only when nothing measured matches.
 */

export interface WaterEstimateInput {
  name?: string | null
  nutrition_basis?: string | null
  kcal_100?: number | null
  protein_100?: number | null
  carbs_100?: number | null
  fat_100?: number | null
  fibre_100?: number | null
  salt_100?: number | null
}

export interface WaterEstimate {
  /** Grams of water per 100 g of food. */
  water_ml_100: number
  /** How the number was reached, so the UI can hedge an estimate honestly. */
  basis: 'measured' | 'name' | 'difference'
}

/* Whole foods whose water content is stable enough to key off the name, in
   every language the app ships. Values are Swiss FSVO V7.1 unless noted. */
const NAMED_WATER: Array<{ water: number; pattern: RegExp }> = [
  { water: 99.5, pattern: /(^|[^a-z])(water|wasser|eau|acqua|apă|apa|น้ำเปล่า)([^a-z]|$)/i },
  { water: 96.0, pattern: /(^|[^a-z])(cucumber|gurke|concombre|cetriolo|castravete|แตงกวา)([^a-z]|$)/i },
  { water: 95.3, pattern: /(^|[^a-z])(celery|sellerie|céleri|sedano|țelină|telina|คื่นช่าย)([^a-z]|$)/i },
  { water: 94.0, pattern: /(^|[^a-z])(tomato|tomatoes|tomate|tomaten|pomodoro|roșie|rosie|มะเขือเทศ)([^a-z]|$)/i },
  { water: 92.0, pattern: /(^|[^a-z])(courgette|zucchini|zucchine|dovlecel|บวบ)([^a-z]|$)/i },
  { water: 91.5, pattern: /(^|[^a-z])(watermelon|wassermelone|pastèque|anguria|pepene verde|แตงโม)([^a-z]|$)/i },
  { water: 90.9, pattern: /(^|[^a-z])(lettuce|salat|kopfsalat|laitue|lattuga|salată verde|ผักกาดหอม)([^a-z]|$)/i },
  { water: 90.4, pattern: /(^|[^a-z])(broccoli|brokkoli|brocoli|broccolo|บรอกโคลี)([^a-z]|$)/i },
  { water: 89.1, pattern: /(^|[^a-z])(strawberry|strawberries|erdbeere|fraise|fragola|căpșun|capsun|สตรอว์เบอร์รี)([^a-z]|$)/i },
  { water: 88.1, pattern: /(^|[^a-z])(orange|orangen|arancia|portocal|ส้ม)([^a-z]|$)/i },
  { water: 87.9, pattern: /(^|[^a-z])(papaya|papaye|มะละกอ)([^a-z]|$)/i },
  { water: 87.4, pattern: /(^|[^a-z])(milk|milch|lait|latte|lapte|นม)([^a-z]|$)/i },
  { water: 85.6, pattern: /(^|[^a-z])(apple|apfel|äpfel|pomme|mela|măr|mar|แอปเปิล)([^a-z]|$)/i },
  { water: 85.5, pattern: /(^|[^a-z])(yoghurt|yogurt|joghurt|iaurt|โยเกิร์ต)([^a-z]|$)/i },
  { water: 84.2, pattern: /(^|[^a-z])(carrot|karotte|möhre|carotte|carota|morcov|แครอท)([^a-z]|$)/i },
  { water: 75.0, pattern: /(^|[^a-z])(banana|banane|banana|banană|กล้วย)([^a-z]|$)/i },
]

/* Products whose name is a poor guide: powders, oils and dried goods can carry
   a water-dense word without being water-dense themselves. */
const DRY_PRODUCT = /(powder|pulver|poudre|polvere|pudră|dried|getrocknet|séché|essiccato|uscat|concentrate|konzentrat|oil|öl|huile|olio|ulei|freeze[- ]dried|instant|isolate|isolat)/i

/* Ash - the mineral residue - is not stored on a food row, so it is taken from
   a small table by macro shape. These are conventional composition-table
   values; the error they carry is under a gram per 100 g. */
function estimateAsh(input: WaterEstimateInput): number {
  const salt = input.salt_100 ?? null
  if (salt != null && salt > 0) {
    /* Salt is mostly what ash measures in a seasoned or cured product. */
    return Math.min(20, Math.max(0.5, salt * 1.1))
  }
  const protein = input.protein_100 ?? 0
  const fat = input.fat_100 ?? 0
  if (protein >= 60) return 3.5 // isolated protein powders
  if (protein >= 15 && fat <= 12) return 1.2 // lean meat, fish, pulses
  if (fat >= 50) return 1.8 // nuts, seeds
  return 0.9
}

/** How much of 100 g is not already accounted for by macros and minerals.
 * Nothing measured or guessed may exceed it. */
function headroom(input: WaterEstimateInput): number {
  const protein = input.protein_100
  const carbs = input.carbs_100
  const fat = input.fat_100
  if (protein == null || carbs == null || fat == null) return 100
  return Math.max(0, 100 - (protein + carbs + fat + estimateAsh(input)))
}

/** Water by difference. Fibre is added only when the stored carbohydrate
 * figure clearly excludes it, which the sum-to-100 test decides. */
export function waterByDifference(input: WaterEstimateInput): number | null {
  const protein = input.protein_100
  const carbs = input.carbs_100
  const fat = input.fat_100
  if (protein == null || carbs == null || fat == null) return null
  /* A pressed or refined oil is fat all the way down; residual water sits
     below 0.1 g and is reported as none rather than left unknown. */
  const perMl = input.nutrition_basis === 'per_100ml'
  if (fat >= (perMl ? 80 : 90) && protein + carbs <= 2) return 0
  /* Difference arithmetic assumes 100 g of food. A per-100 ml row only obeys it
     when the liquid is about as dense as water; a fatty liquid's missing grams
     are density, not water, and calling that hydration would be wrong. */
  if (perMl && fat >= 20) return null
  const ash = estimateAsh(input)
  const fibre = input.fibre_100 ?? 0
  const withoutFibre = 100 - (protein + carbs + fat + ash)
  const withFibre = withoutFibre - fibre
  /* A row storing carbohydrate excluding fibre leaves a gap that only the
     fibre fills; one storing total carbohydrate is already complete. */
  const candidate = fibre > 0 && withFibre >= 0 && withoutFibre > 100 - ash - 0.5
    ? withFibre
    : withoutFibre
  if (!Number.isFinite(candidate)) return null
  return Math.min(100, Math.max(0, Math.round(candidate * 10) / 10))
}

/** Best available water content for a food, with the basis it rests on. */
export function estimateWaterContent(
  input: WaterEstimateInput,
  measured?: number | null,
): WaterEstimate | null {
  if (measured != null && Number.isFinite(measured) && measured >= 0) {
    return { water_ml_100: Math.min(100, measured), basis: 'measured' }
  }
  const name = (input.name ?? '').trim()
  if (name && !DRY_PRODUCT.test(name)) {
    const match = NAMED_WATER.find((entry) => entry.pattern.test(name))
    /* A name is only a hint. "Tuna in water" and "milk chocolate" both carry a
       water-dense word while being mostly something else, so the guess is kept
       only when the food's own macros leave room for that much water. */
    if (match && match.water <= headroom(input)) {
      return { water_ml_100: match.water, basis: 'name' }
    }
  }
  const derived = waterByDifference(input)
  if (derived == null) return null
  return { water_ml_100: derived, basis: 'difference' }
}

/** Millilitres of water in a portion of a food. */
export function portionWater(waterPer100: number | null | undefined, equivalentAmount: number): number | null {
  if (waterPer100 == null || !Number.isFinite(waterPer100)) return null
  if (!Number.isFinite(equivalentAmount) || equivalentAmount <= 0) return 0
  return Math.round(waterPer100 * equivalentAmount) / 100
}

/*
 * Food water is real intake - EFSA puts it at roughly a fifth to a third of
 * total water - but it is not interchangeable with drinking. The drink target
 * stays the target; food water is reported beside it, never folded into it.
 */
export interface HydrationBreakdown {
  /** Litres from drinks and Apple Health dietary-water samples. */
  drinkL: number
  /** Litres from the water naturally present in logged food. */
  foodL: number
  /** Litres from every source. */
  totalL: number
}

export function hydrationBreakdown(drinkL: number, foodMl: number): HydrationBreakdown {
  const drink = Number.isFinite(drinkL) && drinkL > 0 ? drinkL : 0
  const food = Number.isFinite(foodMl) && foodMl > 0 ? foodMl / 1000 : 0
  return {
    drinkL: Math.round(drink * 100) / 100,
    foodL: Math.round(food * 100) / 100,
    totalL: Math.round((drink + food) * 100) / 100,
  }
}
