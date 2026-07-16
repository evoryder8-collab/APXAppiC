import assert from 'node:assert/strict'
import test from 'node:test'
import { COMMON_FOODS } from '../src/data/foodSeeds.ts'
import {
  addLoggedMealToHistory,
  aggregateConsumedMeals,
  beginFoodSelection,
  calculatePortion,
  commitFoodSelection,
  displayFoodName,
  expandFoodSearchQueries,
  foodPreferenceUsageUpdates,
  mergeExtendedFoodResults,
  mergeMealsIdempotently,
  parseDecimalInput,
  rankFoods,
  reconcileConsumedMeals,
  snapshotEntry,
  suggestPresetAdaptation,
  type ComposerFoodItem,
  type FoodPreference,
  type LoggedMeal,
} from '../src/lib/food.ts'
import { normalizeBarcode, normalizeOpenFoodFactsProduct } from '../shared/openFoodFacts.ts'

function item(foodIndex = 0, quantity = 100): ComposerFoodItem {
  return {
    id: crypto.randomUUID(), food: COMMON_FOODS[foodIndex], quantity, unit: 'g', sort_order: 0,
    optional: false, locked: false, adjustable: true, minimum_amount: 20, maximum_amount: 200,
    step_amount: 5, adjustment_role: 'carb',
  }
}

test('food portions distinguish dry, cooked, piece and decimal-comma inputs', () => {
  assert.equal(calculatePortion(COMMON_FOODS[1], 100, 'g')?.kcal, 360)
  assert.equal(calculatePortion(COMMON_FOODS[2], 100, 'g')?.kcal, 130)
  assert.equal(calculatePortion(COMMON_FOODS[6], 2, 'piece')?.equivalent_amount, 116)
  assert.equal(parseDecimalInput('1,5'), 1.5)
  assert.equal(parseDecimalInput('1.234,5'), 1234.5)
  assert.equal(calculatePortion(COMMON_FOODS[0], 0, 'g'), null)
})

test('selecting a search result creates a draft and does not insert until explicit confirmation', () => {
  const original: ComposerFoodItem[] = []
  const draft = beginFoodSelection(COMMON_FOODS[0])
  assert.equal(original.length, 0)
  assert.equal(draft.quantity, 100)
  assert.equal(draft.unit, 'g')

  const confirmed = commitFoodSelection(original, draft, 'confirmed-food')
  assert.equal(original.length, 0, 'confirmation must not mutate the existing meal')
  assert.equal(confirmed.length, 1)
  assert.equal(confirmed[0].id, 'confirmed-food')
})

test('scanner foods default to weight units unless the record is genuinely portioned', () => {
  const weighedAldiFood = {
    ...COMMON_FOODS[1],
    source: 'open_food_facts' as const,
    brand: 'Aldi Suisse',
    serving_amount: 75,
    serving_unit: 'g' as const,
    serving_grams_or_ml: 75,
  }
  assert.deepEqual(
    { quantity: beginFoodSelection(weighedAldiFood).quantity, unit: beginFoodSelection(weighedAldiFood).unit },
    { quantity: 100, unit: 'g' },
  )

  const portionedFood = { ...weighedAldiFood, serving_unit: 'serving' as const }
  assert.deepEqual(
    { quantity: beginFoodSelection(portionedFood).quantity, unit: beginFoodSelection(portionedFood).unit },
    { quantity: 1, unit: 'serving' },
  )
  assert.equal(beginFoodSelection(COMMON_FOODS[6]).unit, 'piece')
})

test('configured quantities use the selected amount for every displayed macro', () => {
  const nixe = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:lidl-nixe-tuna-own-juice-label')!
  const draft = { ...beginFoodSelection(nixe), quantity: 200 }
  const portion = calculatePortion(draft.food, draft.quantity, draft.unit)!
  assert.deepEqual(
    { kcal: portion.kcal, protein: portion.protein_g, carbs: portion.carbs_g, fat: portion.fat_g, salt: portion.salt_g },
    { kcal: 222, protein: 52, carbs: 0, fat: 1.4, salt: 1.8 },
  )
})

test('personal aliases, favourites and recent slot use rank before generic foods', () => {
  const preference: FoodPreference = {
    id: crypto.randomUUID(), user_id: crypto.randomUUID(), food_id: COMMON_FOODS[4].id,
    personal_name: 'golden grains', aliases: ['my lunch'], favourite: true, usual_amount: 150,
    usual_unit: 'g', usage_count: 8, last_used_at: new Date().toISOString(), hidden: false,
    slot_usage: { lunch: 7 }, version: 1, updated_at: new Date().toISOString(),
  }
  assert.equal(rankFoods('my lunch', COMMON_FOODS, [preference], 'lunch')[0].id, COMMON_FOODS[4].id)
})

test('Romanian and Thai food queries rank localized foods and expand for the remote provider', () => {
  const rawChicken = COMMON_FOODS.find((food) => food.name === 'Chicken breast, raw')!
  const microwavedSweetPotato = COMMON_FOODS.find((food) => food.name === 'Sweet potato, microwaved')!
  assert.equal(rankFoods('piept de pui crud', COMMON_FOODS, [], 'lunch')[0]?.id, rawChicken.id)
  assert.equal(rankFoods('มันหวานไมโครเวฟ', COMMON_FOODS, [], 'lunch')[0]?.id, microwavedSweetPotato.id)
  assert.ok(expandFoodSearchQueries('piept de pui crud', 'ro').includes('chicken breast raw'))
  assert.ok(expandFoodSearchQueries('มันหวานไมโครเวฟ', 'th').includes('sweet potato microwaved'))
  assert.equal(displayFoodName(rawChicken, 'ro'), 'Piept de pui, crud')
  assert.equal(displayFoodName(rawChicken, 'th'), 'อกไก่ ดิบ')
})

test('localized staple search finds oats, som tam, fish sauce, avocado and prepared eggs', () => {
  const organicOats = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:usda-fdc-173904')!
  const somTam = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:som-tam-thai-reference')!
  const fishSauce = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:usda-fdc-2706457')!
  const avocado = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:usda-fdc-171705')!
  const rawEgg = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:usda-fdc-171287')!
  const boiledEgg = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:usda-fdc-173424')!

  assert.equal(rankFoods('ovaz', COMMON_FOODS, [], 'breakfast')[0]?.id, organicOats.id)
  assert.equal(rankFoods('ส้มตำ', COMMON_FOODS, [], 'lunch')[0]?.id, somTam.id)
  assert.equal(rankFoods('sos de peste', COMMON_FOODS, [], 'lunch')[0]?.id, fishSauce.id)
  assert.equal(rankFoods('อะโวคาโด', COMMON_FOODS, [], 'breakfast')[0]?.id, avocado.id)
  assert.equal(rankFoods('ou crud', COMMON_FOODS, [], 'breakfast')[0]?.id, rawEgg.id)
  assert.equal(rankFoods('ไข่ต้ม', COMMON_FOODS, [], 'breakfast')[0]?.id, boiledEgg.id)

  assert.ok(expandFoodSearchQueries('ovăz integral organic', 'ro').includes('organic whole grain oats'))
  assert.ok(expandFoodSearchQueries('ส้มตำไทย', 'th').includes('som tam thai green papaya salad'))
  assert.equal(displayFoodName(organicOats, 'ro'), 'Ovăz integral organic')
  assert.equal(displayFoodName(somTam, 'th'), 'ส้มตำไทย')
})

test('Romanian and Thai berry searches prioritize fresh and frozen Swiss retail references', () => {
  const freshBlueberries = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:swiss-retail-blueberries-fresh-reference')!
  const frozenBlueberries = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:swiss-retail-blueberries-frozen-reference')!

  assert.equal(rankFoods('afine', COMMON_FOODS, [], 'snack')[0]?.id, freshBlueberries.id)
  assert.equal(rankFoods('บลูเบอร์รีแช่แข็ง', COMMON_FOODS, [], 'snack')[0]?.id, frozenBlueberries.id)
  assert.ok(expandFoodSearchQueries('afine congelate', 'ro').includes('frozen blueberries'))
  assert.ok(expandFoodSearchQueries('บลูเบอร์รี่สด', 'th').includes('fresh blueberries'))
  assert.ok(rankFoods('aldi frozen berries', COMMON_FOODS, [], 'snack').length > 0)
  assert.ok(rankFoods('lidl frozen peas', COMMON_FOODS, [], 'lunch').length > 0)
})

test('Nixe tuna label facts and localized names match the supplied per-100 g label', () => {
  const nixe = COMMON_FOODS.find((food) => food.provider_product_id === 'apex-curated:lidl-nixe-tuna-own-juice-label')!
  assert.equal(nixe.kcal_100, 111)
  assert.equal(nixe.fat_100, 0.7)
  assert.equal(nixe.carbs_100, 0)
  assert.equal(nixe.protein_100, 26)
  assert.equal(nixe.saturated_fat_100, 0)
  assert.equal(nixe.sugar_100, 0)
  assert.equal(nixe.fibre_100, 0)
  assert.equal(nixe.salt_100, 0.9)
  assert.equal(nixe.package_quantity, '195 g')
  assert.equal(displayFoodName(nixe, 'de'), 'Nixe Thunfischfilets im eigenen Saft')
  assert.equal(rankFoods('ton in suc propriu', COMMON_FOODS, [], 'lunch')[0]?.id, nixe.id)
})

test('fundamental chicken and potato preparations stay first before and after extended search', () => {
  const chicken = rankFoods('piept de pui', COMMON_FOODS, [], 'lunch')
  assert.deepEqual(chicken.slice(0, 3).map((food) => food.name), [
    'Chicken breast, raw',
    'Chicken breast, boiled',
    'Chicken breast, air fryer, no added oil',
  ])

  const chips = {
    ...COMMON_FOODS[0],
    id: 'off:chips',
    name: 'Pringles potato crisps',
    names_i18n: { en: 'Pringles potato crisps', ro: 'Chipsuri de cartofi Pringles' },
    brand: 'Pringles',
    source: 'open_food_facts' as const,
    provider_product_id: 'chips',
  }
  const plain = {
    ...COMMON_FOODS[0],
    id: 'off:plain-potato',
    name: 'Whole potato, steamed',
    names_i18n: { en: 'Whole potato, steamed', ro: 'Cartof întreg, la abur' },
    brand: 'Generic',
    source: 'open_food_facts' as const,
    provider_product_id: 'plain-potato',
  }
  const potatoes = rankFoods('cartof', COMMON_FOODS, [], 'lunch')
  assert.deepEqual(potatoes.slice(0, 3).map((food) => food.name), [
    'Potato, raw',
    'Potato, baked',
    'Potato, air fryer, no added oil',
  ])
  const extended = mergeExtendedFoodResults('cartof', potatoes, [chips, plain])
  assert.deepEqual(extended.slice(0, 3).map((food) => food.name), potatoes.slice(0, 3).map((food) => food.name))
  assert.equal(extended.at(-1)?.name, 'Pringles potato crisps')
})

test('whey and protein searches work in English, Romanian and Thai with verified brands', () => {
  for (const query of ['whey', 'protein', 'proteină din zer', 'เวย์โปรตีน']) {
    const brands = new Set(rankFoods(query, COMMON_FOODS, [], 'snack').map((food) => food.brand))
    assert.ok(brands.has('Lee-Sport'), `${query} should find Lee-Sport`)
    assert.ok(brands.has('M-Budget'), `${query} should find M-Budget`)
    assert.ok(brands.has('ESN'), `${query} should find ESN`)
  }
})

test('raw chicken uses the current USDA Foundation fat reference', () => {
  const rawChicken = COMMON_FOODS.find((food) => food.name === 'Chicken breast, raw')!
  assert.equal(rawChicken.kcal_100, 106)
  assert.equal(rawChicken.protein_100, 22.5)
  assert.equal(rawChicken.fat_100, 1.93)
})

test('logged entries are immutable nutrition snapshots', () => {
  const original = item(0, 80)
  const snapshot = snapshotEntry(original, crypto.randomUUID(), crypto.randomUUID())!
  const oldCalories = snapshot.kcal
  original.food.kcal_100 = 999
  assert.equal(snapshot.kcal, oldCalories)
  assert.notEqual(snapshot.snapshot_kcal_100, original.food.kcal_100)
})

test('adaptive suggestions respect locked items, bounds and explicit apply', () => {
  const locked = { ...item(0, 60), id: 'locked', locked: true }
  const adjustable = { ...item(1, 50), id: 'flex', maximum_amount: 80 }
  const before = adjustable.quantity
  const suggestions = suggestPresetAdaptation([locked, adjustable], {
    target: { kcal: 900, protein_g: 45, carbs_g: 120, fat_g: 25 },
    consumed: { kcal: 200, protein_g: 30, carbs_g: 20, fat_g: 10 },
    activityLabel: 'Very active', trainingToday: true,
  })
  assert.equal(adjustable.quantity, before, 'suggestions must never silently mutate a preset')
  assert.equal(suggestions[0].item_id, 'flex')
  assert.ok(suggestions[0].proposed_quantity <= 80)
})

test('meal merge is idempotent by user and client key', () => {
  const base: LoggedMeal = {
    id: crypto.randomUUID(), user_id: crypto.randomUUID(), local_date: '2026-07-12', meal_slot: 'lunch',
    display_name: 'Lunch', source_preset_id: null, source_planned_meal_id: null,
    logged_at: new Date().toISOString(), client_idempotency_key: 'same', logged_as: 'custom',
    total_kcal: 500, total_protein_g: 30, total_carbs_g: 55, total_fat_g: 15,
    created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
  }
  assert.equal(mergeMealsIdempotently([base], [{ ...base, id: crypto.randomUUID() }]).length, 1)
})

test('rapid calendar paste accumulates every meal from the latest committed history', () => {
  const base: LoggedMeal = {
    id: 'breakfast-copy', user_id: crypto.randomUUID(), local_date: '2026-07-17', meal_slot: 'breakfast',
    display_name: 'Breakfast', source_preset_id: null, source_planned_meal_id: 'breakfast',
    logged_at: '2026-07-17T07:00:00Z', client_idempotency_key: 'breakfast-copy', logged_as: 'planned',
    total_kcal: 404, total_protein_g: 25, total_carbs_g: 9, total_fat_g: 21,
    created_at: '2026-07-17T07:00:00Z', updated_at: '2026-07-17T07:00:00Z',
  }
  const lunch: LoggedMeal = {
    ...base, id: 'lunch-copy', meal_slot: 'lunch', display_name: 'Lunch', source_planned_meal_id: 'lunch',
    client_idempotency_key: 'lunch-copy', total_kcal: 713,
  }
  const breakfastOnly = addLoggedMealToHistory([], base)
  const bothMeals = addLoggedMealToHistory(breakfastOnly, lunch)
  assert.deepEqual(bothMeals.map((meal) => meal.id), ['lunch-copy', 'breakfast-copy'])
  assert.equal(bothMeals.reduce((sum, meal) => sum + meal.total_kcal, 0), 1117)
})

test('repeated foods increment preference history across items and pasted meals', () => {
  const userId = crypto.randomUUID()
  const first = foodPreferenceUsageUpdates([], [item(0), item(0)], userId, 'breakfast', '2026-07-17T07:00:00Z', () => 'preference')
  assert.equal(first.length, 1)
  assert.equal(first[0].usage_count, 2)
  assert.equal(first[0].slot_usage.breakfast, 2)

  const second = foodPreferenceUsageUpdates(first, [item(0)], userId, 'lunch', '2026-07-17T12:00:00Z', () => 'unused')
  assert.equal(second[0].usage_count, 3)
  assert.deepEqual(second[0].slot_usage, { breakfast: 2, lunch: 1 })
  assert.equal(second[0].id, 'preference')
})

test('checked planned meals and an edited replacement reconcile into one consumed total', () => {
  const userId = crypto.randomUUID()
  const now = new Date().toISOString()
  const replacement: LoggedMeal = {
    id: crypto.randomUUID(), user_id: userId, local_date: '2026-07-14', meal_slot: 'snack',
    display_name: 'Migros ready meal', source_preset_id: null, source_planned_meal_id: 'bulgur',
    logged_at: now, client_idempotency_key: 'replacement', logged_as: 'changed',
    total_kcal: 562, total_protein_g: 22, total_carbs_g: 67, total_fat_g: 22,
    created_at: now, updated_at: now,
  }
  const rows = reconcileConsumedMeals([replacement], [
    { id: 'breakfast', name: 'Breakfast', kcal: 404, protein_g: 25, carbs_g: 9, fat_g: 21 },
    { id: 'lunch', name: 'Oat jar', kcal: 713, protein_g: 39, carbs_g: 120, fat_g: 14 },
    { id: 'bulgur', name: 'Bulgur snack', kcal: 349, protein_g: 24, carbs_g: 59, fat_g: 5 },
  ], new Set(['breakfast', 'lunch', 'bulgur']))
  assert.equal(rows.length, 3)
  assert.equal(rows.find((row) => row.planned_meal_id === 'bulgur')?.name, 'Migros ready meal')
  assert.deepEqual(aggregateConsumedMeals(rows), { kcal: 1679, protein_g: 86, carbs_g: 196, fat_g: 57 })
})

test('a linked actual meal wins over duplicate plan checkoffs and stale linked snapshots', () => {
  const userId = crypto.randomUUID()
  const base = {
    id: 'old', user_id: userId, local_date: '2026-07-14', meal_slot: 'lunch' as const,
    display_name: 'Old lunch', source_preset_id: null, source_planned_meal_id: 'lunch',
    logged_at: '2026-07-14T12:00:00Z', client_idempotency_key: 'old', logged_as: 'changed' as const,
    total_kcal: 500, total_protein_g: 20, total_carbs_g: 60, total_fat_g: 15,
    created_at: '2026-07-14T12:00:00Z', updated_at: '2026-07-14T12:00:00Z',
  }
  const rows = reconcileConsumedMeals([base, { ...base, id: 'new', display_name: 'Current lunch', total_kcal: 620, updated_at: '2026-07-14T13:00:00Z' }], [
    { id: 'lunch', name: 'Planned lunch', kcal: 700, protein_g: 30, carbs_g: 90, fat_g: 18 },
  ], ['lunch'])
  assert.equal(rows.length, 1)
  assert.equal(rows[0].name, 'Current lunch')
  assert.equal(rows[0].kcal, 620)
})

test('Open Food Facts normalization validates barcodes, converts kJ and preserves missing fields', () => {
  assert.equal(normalizeBarcode('4006381333931'), '4006381333931')
  assert.equal(normalizeBarcode('4006381333932'), null)
  const food = normalizeOpenFoodFactsProduct({
    status: 1,
    product: {
      code: '4006381333931', product_name_en: 'Test oats', brands: 'Test',
      nutriments: { 'energy-kj_100g': 418.4, proteins_100g: 3, carbohydrates_100g: 20, fat_100g: 1 },
    },
  } as never, '4006381333931')
  assert.equal(food?.kcal_100, 100)
  assert.equal(food?.fibre_100, null)
  const romanianOnly = normalizeOpenFoodFactsProduct({
    status: 1,
    product: {
      code: '4006381333931', product_name_ro: 'Piept de pui crud',
      nutriments: { 'energy-kcal_100g': 120, proteins_100g: 22.5, carbohydrates_100g: 0, fat_100g: 2.6 },
    },
  } as never, '4006381333931')
  assert.equal(romanianOnly?.name, 'Piept de pui crud')
  assert.equal(romanianOnly?.names_i18n.ro, 'Piept de pui crud')
})
