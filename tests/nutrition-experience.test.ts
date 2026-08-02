import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { COMMON_FOODS } from '../src/data/foodSeeds.ts'
import type { LoggedFoodEntry, LoggedMeal, MealPreset } from '../src/lib/food.ts'
import {
  loggedMealEditorState,
  mealRowSwipeOffset,
  rankMealHistoryRecommendations,
} from '../src/lib/mealExperience.ts'
import { createCustomMealBlock, normalizeMealBlockSettings } from '../src/lib/mealBlocks.ts'

function meal(patch: Partial<LoggedMeal> = {}): LoggedMeal {
  return {
    id: crypto.randomUUID(), user_id: 'user-1', local_date: '2026-07-09', meal_slot: 'lunch',
    display_name: 'Chicken lunch', source_preset_id: 'preset-lunch', source_planned_meal_id: null,
    logged_at: '2026-07-09T13:05:00.000Z', client_idempotency_key: 'meal|apex-meal-block=lunch',
    logged_as: 'custom', total_kcal: 500, total_protein_g: 40, total_carbs_g: 50, total_fat_g: 14,
    created_at: '2026-07-09T13:05:00.000Z', updated_at: '2026-07-09T13:05:00.000Z',
    ...patch,
  }
}

function entry(mealId: string, foodId: string, quantity = 100): LoggedFoodEntry {
  const food = COMMON_FOODS.find((candidate) => candidate.id === foodId)!
  return {
    id: crypto.randomUUID(), meal_id: mealId, user_id: 'user-1', food_id: food.id, sort_order: 0,
    snapshot_name: food.name, snapshot_brand: food.brand, snapshot_preparation_state: food.preparation_state,
    snapshot_nutrition_basis: food.nutrition_basis, snapshot_kcal_100: food.kcal_100 ?? 0,
    snapshot_protein_100: food.protein_100 ?? 0, snapshot_carbs_100: food.carbs_100 ?? 0,
    snapshot_fat_100: food.fat_100 ?? 0, snapshot_fibre_100: food.fibre_100,
    snapshot_sugar_100: food.sugar_100, snapshot_saturated_fat_100: food.saturated_fat_100,
    snapshot_salt_100: food.salt_100, quantity, unit: 'g', equivalent_amount: quantity,
    kcal: (food.kcal_100 ?? 0) * quantity / 100, protein_g: (food.protein_100 ?? 0) * quantity / 100, carbs_g: (food.carbs_100 ?? 0) * quantity / 100,
    fat_g: (food.fat_100 ?? 0) * quantity / 100, fibre_g: food.fibre_100 == null ? null : food.fibre_100 * quantity / 100, sugar_g: food.sugar_100 == null ? null : food.sugar_100 * quantity / 100,
    saturated_fat_g: food.saturated_fat_100, salt_g: food.salt_100, created_at: '2026-07-09T13:05:00.000Z',
  }
}

test('meal row gestures own horizontal deletion without producing day offsets', () => {
  assert.equal(mealRowSwipeOffset({ x: 220, y: 100 }, { x: 140, y: 104 }), -104)
  assert.equal(mealRowSwipeOffset({ x: 220, y: 100 }, { x: 210, y: 180 }), 0)
  assert.equal(mealRowSwipeOffset({ x: 140, y: 100 }, { x: 200, y: 104 }, true), 0)
  assert.equal(mealRowSwipeOffset({ x: 140, y: 100 }, { x: 142, y: 102 }, true), -104)

  const source = readFileSync(new URL('../src/components/food/ActualFoodTracker.tsx', import.meta.url), 'utf8')
  assert.match(source, /data-nutrition-local-gesture/)
  assert.match(source, /data-meal-row-gesture/)
  assert.match(source, /event\.stopPropagation\(\)/)
  assert.match(source, /tabIndex=\{open \? 0 : -1\}/)
  assert.match(source, /standaloneLoggedBlockStatuses/)
  assert.doesNotMatch(source, /confirmDelete/)
})

test('meal completion callbacks are invalidated at the account boundary', () => {
  const source = readFileSync(new URL('../src/store/FoodStore.tsx', import.meta.url), 'utf8')
  assert.match(source, /userIdRef\.current = null/)
  assert.match(source, /The meal was kept for its original account/)
})

test('meal food picker keeps configure and exact-amount quick add as separate actions', () => {
  const source = readFileSync(new URL('../src/components/food/MealComposer.tsx', import.meta.url), 'utf8')
  assert.match(source, /const quickAddFood = async \(food: FoodRecord\)/)
  assert.match(source, /const draft = selectionDraftForFood\(food\)/)
  assert.match(source, /commitFoodSelection\(current, \{ \.\.\.draft, food: trackableFood \}\)/)
  assert.match(source, /onClick=\{\(\) => void selectFood\(food\)\}/)
  assert.match(source, /onClick=\{\(\) => void quickAddFood\(food\)\}/)
  assert.match(source, /hasSavedAmount \? 'Last used' : 'Suggested portion'/)
  assert.match(source, /Tap a food to change its amount/)
  assert.match(source, /window\.setTimeout\(\(\) => \{/)
  assert.match(source, /store\.widerSearch\(trimmed, language\)/)
  assert.match(source, /quickAddedFoodId/)
  assert.match(source, /aria-live="polite"/)
  assert.match(source, /Searching the full food catalog/)
  assert.doesNotMatch(source, />\s*\{translateInterfaceText\(searching \? 'Searching more foods…' : 'Extend search'/)
})

test('meal composer starts with two suggestions and can save a preset from selected foods', () => {
  const source = readFileSync(new URL('../src/components/food/MealComposer.tsx', import.meta.url), 'utf8')
  assert.match(source, /displayedFoods\.slice\(0, 2\)/)
  assert.match(source, /onFocus=\{\(\) => setFoodFinderExpanded\(true\)\}/)
  assert.match(source, /visibleDisplayedFoods\.map\(\(food\) =>/)
  assert.match(source, /const \[itemSelectionMode, setItemSelectionMode\]/)
  assert.match(source, /const selectedPresetItems = useMemo/)
  assert.match(source, /items: presetItems/)
  assert.match(source, /Create preset from selected foods/)
  assert.match(source, /Save selected preset/)
})

test('logged meal editor state always replaces the selected snapshot meal', () => {
  const saved = meal({ id: 'meal-to-replace', source_planned_meal_id: 'planned-1', display_name: 'Renamed meal' })
  assert.deepEqual(loggedMealEditorState(saved, 'lunch', '13:00'), {
    slot: 'lunch', blockId: 'lunch', mealIdentity: 'lunch', title: 'Renamed meal', plannedMealId: 'planned-1',
    replaceMealId: 'meal-to-replace', targetTime: '13:00',
  })
})

test('custom meal blocks normalize safely inside synced settings JSON', () => {
  const created = createCustomMealBlock({ label: '  Second   lunch  ', time: '15:30', slot: 'snack' }, () => 'ABC-12345')
  assert.deepEqual(created, { id: 'custom:abc-12345', label: 'Second lunch', time: '15:30', slot: 'snack', enabled: true })

  const normalized = normalizeMealBlockSettings({
    custom_blocks: [created, created, { id: 'custom:no', label: '', slot: 'wrong', time: '91:00' }],
  })
  assert.deepEqual(normalized.custom_blocks, [created])
  assert.equal(normalized.blocks.length, 5, 'canonical blocks remain compatible with existing clients')

  const customMeal = meal({ client_idempotency_key: `saved|apex-meal-block=${created.id}` })
  assert.equal(loggedMealEditorState(customMeal).mealIdentity, created.id)
})

test('blank composer history prioritizes same block, weekday, hour and sequence', () => {
  const chicken = COMMON_FOODS[0]
  const oats = COMMON_FOODS[1]
  const sameMoment = meal({ id: 'same-moment' })
  const recentWrongSlot = meal({
    id: 'wrong-slot', local_date: '2026-07-15', meal_slot: 'breakfast', display_name: 'Recent breakfast',
    source_preset_id: null, logged_at: '2026-07-15T07:00:00.000Z', client_idempotency_key: 'breakfast',
  })
  const olderLunch = meal({
    id: 'older-lunch', local_date: '2026-07-02', source_preset_id: null,
    logged_at: '2026-07-02T16:30:00.000Z', client_idempotency_key: 'lunch',
  })
  const preset: MealPreset = {
    id: 'preset-lunch', user_id: 'user-1', name: 'Reliable lunch', meal_slot: 'lunch',
    source_planned_meal_id: null, archived: false, version: 1,
    created_at: '2026-06-01T00:00:00.000Z', updated_at: '2026-07-09T00:00:00.000Z',
  }
  const ranked = rankMealHistoryRecommendations({
    context: { date: '2026-07-16', slot: 'lunch', blockId: 'lunch', targetTime: '13:00', sequenceIndex: 0 },
    meals: [recentWrongSlot, olderLunch, sameMoment],
    entries: [entry(sameMoment.id, chicken.id, 175), entry(recentWrongSlot.id, oats.id)],
    foods: COMMON_FOODS,
    presets: [preset],
  })
  assert.equal(ranked.meals[0]?.id, sameMoment.id)
  assert.equal(ranked.foods[0]?.id, chicken.id)
  assert.deepEqual(ranked.selections[0], { foodId: chicken.id, quantity: 175, unit: 'g' })
  assert.equal(ranked.presets[0]?.id, preset.id)
})

test('history preserves exact grams and remains usable without its optional food row', () => {
  const original = COMMON_FOODS[0]
  const breakfast = meal({ id: 'detached-breakfast', meal_slot: 'breakfast', local_date: '2026-07-31' })
  const detachedEntry = {
    ...entry(breakfast.id, original.id, 163),
    food_id: null,
  }
  const ranked = rankMealHistoryRecommendations({
    context: { date: '2026-08-01', slot: 'breakfast', blockId: 'breakfast', targetTime: '07:00' },
    meals: [breakfast],
    entries: [detachedEntry],
    foods: [],
    presets: [],
  })
  assert.match(ranked.foods[0]?.id ?? '', /^history:/)
  assert.equal(ranked.foods[0]?.name, original.name)
  assert.deepEqual(ranked.selections[0], { foodId: ranked.foods[0].id, quantity: 163, unit: 'g' })
})

test('blank composer history learns frequency before recency while retaining weekday relevance', () => {
  const thursdays = ['2026-06-04', '2026-06-11', '2026-06-18', '2026-06-25', '2026-07-02', '2026-07-09']
  const repeated = thursdays.map((date, index) => meal({
    id: `repeated-${index}`,
    local_date: date,
    display_name: 'Thursday oats',
    source_preset_id: 'repeated-preset',
    logged_at: `${date}T07:30:00.000Z`,
    client_idempotency_key: 'breakfast|apex-meal-block=breakfast',
    meal_slot: 'breakfast',
  }))
  const oneOff = meal({
    id: 'one-off',
    local_date: '2026-07-15',
    display_name: 'One-off breakfast',
    source_preset_id: null,
    logged_at: '2026-07-15T07:30:00.000Z',
    client_idempotency_key: 'breakfast|apex-meal-block=breakfast',
    meal_slot: 'breakfast',
  })

  const ranked = rankMealHistoryRecommendations({
    context: { date: '2026-07-16', slot: 'breakfast', blockId: 'breakfast', targetTime: '07:30', sequenceIndex: 0 },
    meals: [...repeated, oneOff],
    entries: [],
    foods: COMMON_FOODS,
    presets: [],
  })

  assert.equal(ranked.meals[0]?.display_name, 'Thursday oats')
})

test('history suggestions never surface synthetic planned prescriptions', () => {
  const actualFood = COMMON_FOODS[0]
  const plannedMeal = meal({
    id: 'planned-breakfast',
    local_date: '2026-07-15',
    meal_slot: 'breakfast',
    display_name: 'Breakfast · planned prescription',
    source_preset_id: null,
    logged_at: '2026-07-15T07:00:00.000Z',
  })
  const actualMeal = meal({
    id: 'actual-breakfast',
    local_date: '2026-07-14',
    meal_slot: 'breakfast',
    display_name: 'Oats and berries',
    source_preset_id: null,
    logged_at: '2026-07-14T07:00:00.000Z',
  })
  const plannedEntry = {
    ...entry(plannedMeal.id, actualFood.id),
    snapshot_name: 'Breakfast · planned prescription',
    snapshot_brand: 'APEX plan',
  }

  const ranked = rankMealHistoryRecommendations({
    context: { date: '2026-07-16', slot: 'breakfast', memoryMode: 'daily', targetTime: '07:00' },
    meals: [plannedMeal, actualMeal],
    entries: [plannedEntry, entry(actualMeal.id, actualFood.id)],
    foods: COMMON_FOODS,
    presets: [],
  })

  assert.deepEqual(ranked.meals.map((candidate) => candidate.id), [actualMeal.id])
  assert.equal(ranked.foods[0]?.id, actualFood.id)
})

test('daily memory uses recent same-meal history while weekly memory stays on the same weekday', () => {
  const chicken = COMMON_FOODS[0]
  const oats = COMMON_FOODS[1]
  const sameWeekday = meal({
    id: 'same-weekday',
    local_date: '2026-06-11',
    meal_slot: 'breakfast',
    display_name: 'Thursday oats',
    source_preset_id: null,
    logged_at: '2026-06-11T07:30:00.000Z',
    client_idempotency_key: 'breakfast|apex-meal-block=breakfast',
  })
  const recentDay = meal({
    id: 'recent-day',
    local_date: '2026-07-15',
    meal_slot: 'breakfast',
    display_name: 'Recent chicken',
    source_preset_id: null,
    logged_at: '2026-07-15T07:30:00.000Z',
    client_idempotency_key: 'breakfast|apex-meal-block=breakfast',
  })
  const commonInput = {
    meals: [sameWeekday, recentDay],
    entries: [entry(sameWeekday.id, oats.id), entry(recentDay.id, chicken.id)],
    foods: COMMON_FOODS,
    presets: [],
  }

  const daily = rankMealHistoryRecommendations({
    ...commonInput,
    context: { date: '2026-07-16', slot: 'breakfast' as const, memoryMode: 'daily' as const, blockId: 'breakfast' as const, targetTime: '07:30' },
  })
  const weekly = rankMealHistoryRecommendations({
    ...commonInput,
    context: { date: '2026-07-16', slot: 'breakfast' as const, memoryMode: 'weekly' as const, blockId: 'breakfast' as const, targetTime: '07:30' },
  })

  assert.equal(daily.meals[0]?.id, recentDay.id)
  assert.equal(daily.foods[0]?.id, chicken.id)
  assert.equal(weekly.meals[0]?.id, sameWeekday.id)
  assert.equal(weekly.foods[0]?.id, oats.id)
})

test('meal presets are composable, reviewable, subtitled and compact by default', () => {
  const source = readFileSync(new URL('../src/components/food/MealComposer.tsx', import.meta.url), 'utf8')
  assert.match(source, /useState<'compact' \| 'expanded'>\('compact'\)/)
  assert.match(source, /meal_preset_subtitles/)
  assert.match(source, /setPresetReview\(/)
  assert.match(source, /setItems\(\(current\) => \[\s*\.\.\.current,/)
  assert.match(source, /Add preset items/)
  assert.match(source, /Presets are reusable food groups/)
  assert.doesNotMatch(source, /setName\(preset\.name\)/)
})
