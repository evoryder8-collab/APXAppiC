import assert from 'node:assert/strict'
import test from 'node:test'
import type { LoggedFoodEntry, LoggedMeal } from '../src/lib/food.ts'
import {
  analyzeMealTiming,
  comfortZone,
  daylineRatio,
  isQuietClock,
  mealComfortWindow,
  timedMeal,
  zonedClock,
  zonedDateTimeToIso,
} from '../src/lib/mealTiming.ts'
import type { WorkoutSession } from '../src/lib/types.ts'

function meal(patch: Partial<LoggedMeal> = {}): LoggedMeal {
  return {
    id: 'meal-1',
    user_id: 'user-1',
    local_date: '2026-07-25',
    meal_slot: 'lunch',
    display_name: 'Lunch',
    source_preset_id: null,
    source_planned_meal_id: null,
    logged_at: '2026-07-25T13:00:00.000Z',
    client_idempotency_key: 'meal-1',
    logged_as: 'custom',
    total_kcal: 520,
    total_protein_g: 40,
    total_carbs_g: 62,
    total_fat_g: 17,
    created_at: '2026-07-25T13:00:00.000Z',
    updated_at: '2026-07-25T13:00:00.000Z',
    ...patch,
  }
}

function fibreEntry(mealId: string, fibreG: number): LoggedFoodEntry {
  return {
    id: `entry-${mealId}`,
    meal_id: mealId,
    user_id: 'user-1',
    food_id: null,
    sort_order: 0,
    snapshot_name: 'Food',
    snapshot_brand: null,
    snapshot_preparation_state: 'prepared',
    snapshot_nutrition_basis: 'per_100g',
    snapshot_kcal_100: 100,
    snapshot_protein_100: 10,
    snapshot_carbs_100: 10,
    snapshot_fat_100: 2,
    snapshot_fibre_100: fibreG,
    snapshot_sugar_100: null,
    snapshot_saturated_fat_100: null,
    snapshot_salt_100: null,
    quantity: 100,
    unit: 'g',
    equivalent_amount: 100,
    kcal: 100,
    protein_g: 10,
    carbs_g: 10,
    fat_g: 2,
    fibre_g: fibreG,
    sugar_g: null,
    saturated_fat_g: null,
    salt_g: null,
    created_at: '2026-07-25T13:00:00.000Z',
  }
}

function session(patch: Partial<WorkoutSession> = {}): WorkoutSession {
  return {
    id: 'session-1',
    user_id: 'user-1',
    date: '2026-07-25',
    program_day_id: 'day-1',
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: true,
    quality_score: 1,
    started_at: '2026-07-25T15:30:00.000Z',
    completed_at: '2026-07-25T16:30:00.000Z',
    notes: '',
    ...patch,
  }
}

test('the dayline spans 03:00 through the next quiet hours and preserves night context', () => {
  assert.equal(daylineRatio(3 * 60), 0)
  assert.equal(daylineRatio(2 * 60), 23 / 24)
  assert.equal(isQuietClock(22 * 60 + 30), true)
  assert.equal(isQuietClock(4 * 60 + 59), true)
  assert.equal(isQuietClock(5 * 60), false)
})

test('IANA timezone conversion round-trips a Zurich summer clock', () => {
  const instant = zonedDateTimeToIso('2026-07-25', '14:30', 'Europe/Zurich')
  assert.equal(instant, '2026-07-25T12:30:00.000Z')
  assert.deepEqual(zonedClock(instant, 'Europe/Zurich'), {
    date: '2026-07-25',
    time: '14:30',
    minute: 14 * 60 + 30,
  })
})

test('meal comfort bands expand with actual energy, fat and fibre load', () => {
  const light = mealComfortWindow({ total_kcal: 180, total_fat_g: 4 }, 3)
  const standard = mealComfortWindow({ total_kcal: 500, total_fat_g: 14 }, 8)
  const substantial = mealComfortWindow({ total_kcal: 700, total_fat_g: 26 }, 10)
  const large = mealComfortWindow({ total_kcal: 1_000, total_fat_g: 20 }, 8)
  assert.deepEqual(
    [light.readyAfterMinutes, standard.readyAfterMinutes, substantial.readyAfterMinutes, large.readyAfterMinutes],
    [60, 120, 180, 240],
  )
  assert.equal(comfortZone(20, standard), 'settling')
  assert.equal(comfortZone(70, standard), 'transition')
  assert.equal(comfortZone(130, standard), 'ready')
})

test('meal timestamps are recorded only when they belong to the selected nutrition date', () => {
  const recorded = timedMeal(meal(), [], 'UTC', '13:00')
  const estimated = timedMeal(meal({ logged_at: '2026-07-24T13:00:00.000Z' }), [], 'UTC', '12:45')
  assert.equal(recorded.recorded, true)
  assert.equal(recorded.time, '13:00')
  assert.equal(estimated.recorded, false)
  assert.equal(estimated.time, '12:45')
})

test('Avatar and AI timing analysis joins workout starts to the latest completed meal', () => {
  const lunch = meal()
  const analysis = analyzeMealTiming({
    meals: [lunch],
    entries: [fibreEntry(lunch.id, 8)],
    sessions: [session()],
    timeZone: 'UTC',
  })
  assert.equal(analysis.recordedMeals, 1)
  assert.equal(analysis.workoutsWithContext, 1)
  assert.equal(analysis.readyStarts, 1)
  assert.equal(analysis.workoutRelations[0].waitedMinutes, 150)
  assert.equal(analysis.workoutRelations[0].mealName, 'Lunch')
})

