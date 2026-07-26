import assert from 'node:assert/strict'
import test from 'node:test'
import { buildSeedData } from '../src/data/seed.ts'
import type { LoggedMeal } from '../src/lib/food.ts'
import { mealBlockIdempotencyKey } from '../src/lib/mealBlocks.ts'
import { buildMealRhythmDay, mealRhythmRefreshDates, normalizeMealRhythmHistory } from '../src/lib/mealRhythm.ts'
import { searchTimeZoneOptions, zonedDateTimeToIso } from '../src/lib/mealTiming.ts'
import { computeEngine } from '../src/lib/rpg.ts'

const userId = '51515151-aaaa-4bbb-8ccc-515151515151'

function meal(input: {
  id: string
  date: string
  block: 'breakfast' | 'lunch' | 'dinner' | 'snack' | 'post_workout'
  time: string
}): LoggedMeal {
  const slot = input.block === 'post_workout' ? 'snack' : input.block
  const loggedAt = zonedDateTimeToIso(input.date, input.time, 'Europe/Zurich')
  return {
    id: input.id,
    user_id: userId,
    local_date: input.date,
    meal_slot: slot,
    display_name: input.block,
    source_preset_id: null,
    source_planned_meal_id: null,
    logged_at: loggedAt,
    client_idempotency_key: mealBlockIdempotencyKey(input.id, input.block),
    logged_as: 'custom',
    total_kcal: 500,
    total_protein_g: 30,
    total_carbs_g: 60,
    total_fat_g: 15,
    created_at: loggedAt,
    updated_at: loggedAt,
  }
}

test('timezone picker searches country, localized country, city, and IANA name', () => {
  assert.equal(searchTimeZoneOptions('Thailand', 'en')[0]?.zone, 'Asia/Bangkok')
  assert.equal(searchTimeZoneOptions('Bangkok', 'en')[0]?.zone, 'Asia/Bangkok')
  assert.equal(searchTimeZoneOptions('Asia/Bangkok', 'en')[0]?.zone, 'Asia/Bangkok')
  assert.equal(searchTimeZoneOptions('România', 'ro')[0]?.zone, 'Europe/Bucharest')
  assert.equal(searchTimeZoneOptions('Switzerland', 'en')[0]?.zone, 'Europe/Zurich')
})

test('a closed day with no meals receives a final no-meals verdict while today stays open', () => {
  const seeded = buildSeedData(userId, 'constantine')
  const settings = {
    ...seeded.settings!,
    addons: { ...seeded.settings!.addons, time_zone: 'Europe/Zurich' },
  }
  const closed = buildMealRhythmDay({
    date: '2026-07-25',
    meals: [],
    settings,
    today: '2026-07-26',
  })
  assert.equal(closed.finalized, true)
  assert.equal(closed.verdict, 'no_meals')
  assert.equal(closed.completion_score, 0)

  const open = buildMealRhythmDay({
    date: '2026-07-26',
    meals: [],
    settings,
    today: '2026-07-26',
  })
  assert.equal(open.finalized, false)
  assert.equal(open.verdict, 'open')
})

test('reopening after several days rebuilds every missing midnight verdict since baseline', () => {
  assert.deepEqual(
    mealRhythmRefreshDates({
      today: '2026-07-30',
      baselineDate: '2026-07-26',
      knownDates: ['2026-07-26', '2026-07-29'],
    }),
    ['2026-07-26', '2026-07-27', '2026-07-28', '2026-07-29', '2026-07-30'],
  )
})

test('a breakfast finished at 15:40 is recorded as the first meal but receives a low timing score', () => {
  const seeded = buildSeedData(userId, 'constantine')
  const settings = {
    ...seeded.settings!,
    addons: { ...seeded.settings!.addons, time_zone: 'Europe/Zurich' },
  }
  const day = buildMealRhythmDay({
    date: '2026-07-25',
    meals: [meal({ id: 'late-breakfast', date: '2026-07-25', block: 'breakfast', time: '15:40' })],
    settings,
    today: '2026-07-26',
  })
  assert.equal(day.first_meal_at, '15:40')
  assert.equal(day.logged_meals, 1)
  assert.equal(day.verdict, 'missed_meals')
  assert.ok((day.timing_score ?? 100) < 20)
})

test('correcting a past day replaces its rhythm verdict and deterministic Avatar replay', () => {
  const seeded = buildSeedData(userId, 'constantine')
  seeded.profile = { ...seeded.profile!, baseline_date: '2026-07-24' }
  const settings = {
    ...seeded.settings!,
    addons: { ...seeded.settings!.addons, time_zone: 'Europe/Zurich' },
  }
  const empty = buildMealRhythmDay({
    date: '2026-07-25',
    meals: [],
    settings,
    today: '2026-07-26',
  })
  const completedMeals = [
    meal({ id: 'b', date: '2026-07-25', block: 'breakfast', time: '07:05' }),
    meal({ id: 'l', date: '2026-07-25', block: 'lunch', time: '13:05' }),
    meal({ id: 's', date: '2026-07-25', block: 'snack', time: '15:35' }),
    meal({ id: 'd', date: '2026-07-25', block: 'dinner', time: '19:20' }),
    meal({ id: 'p', date: '2026-07-25', block: 'post_workout', time: '21:05' }),
  ]
  const corrected = buildMealRhythmDay({
    date: '2026-07-25',
    meals: completedMeals,
    settings,
    today: '2026-07-26',
    existing: empty,
  })
  assert.equal(corrected.verdict, 'complete_on_time')
  assert.equal(corrected.completion_score, 100)
  assert.ok(corrected.rhythm_score >= 95)

  const withoutCorrection = {
    ...seeded,
    settings: {
      ...settings,
      addons: { ...settings.addons, meal_rhythm_history: { '2026-07-25': empty } },
    },
  }
  const withCorrection = {
    ...seeded,
    settings: {
      ...settings,
      addons: { ...settings.addons, meal_rhythm_history: { '2026-07-25': corrected } },
    },
  }
  const before = computeEngine(withoutCorrection, '2026-07-26').snapshots.at(-1)!
  const after = computeEngine(withCorrection, '2026-07-26').snapshots.at(-1)!
  assert.ok(after.health > before.health)
  assert.equal(normalizeMealRhythmHistory(withCorrection.settings.addons.meal_rhythm_history)['2026-07-25'].verdict, 'complete_on_time')
})
