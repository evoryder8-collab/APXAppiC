import assert from 'node:assert/strict'
import test from 'node:test'
import type { LoggedFoodEntry, LoggedMeal } from '../src/lib/food.ts'
import {
  analyzeMealTiming,
  comfortZone,
  daylineRatio,
  isQuietClock,
  mealDaylineHeight,
  mealComfortWindow,
  normalizeMealDaylineDensity,
  normalizeMealStartTimes,
  normalizeMealTimelineSnap,
  normalizeRecoveryNutrition,
  recoveryTimingScore,
  resolvePostWorkoutNutrition,
  snapDaylineMinute,
  timedMeal,
  timedWorkout,
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

test('meal finish is the sole recorded timing signal and anchors the comfort window', () => {
  const event = timedMeal(meal({
    logged_at: '2026-07-25T13:25:00.000Z',
  }), [], 'UTC', '13:00')
  assert.equal(event.time, '13:25')
  assert.equal(event.timingSource, 'recorded_finish')
  assert.equal(event.comfortMinute, 13 * 60 + 25)
  assert.equal(event.finishedAt, '2026-07-25T13:25:00.000Z')
})

test('meal finish movement snaps across the full 03:00 to 02:59 dayline', () => {
  assert.equal(normalizeMealTimelineSnap(15), 15)
  assert.equal(normalizeMealTimelineSnap(17), 30)
  assert.equal(snapDaylineMinute(13 * 60 + 8, 15), 13 * 60 + 15)
  assert.equal(snapDaylineMinute(2 * 60 + 58 + 1440, 60), 26 * 60)
})

test('dayline density defaults to spacious medium and grows predictably', () => {
  assert.equal(normalizeMealDaylineDensity(undefined), 'medium')
  assert.equal(normalizeMealDaylineDensity('long'), 'long')
  assert.equal(normalizeMealDaylineDensity('invalid'), 'medium')
  const compact = mealDaylineHeight('compact', true, 5)
  const medium = mealDaylineHeight('medium', true, 5)
  const long = mealDaylineHeight('long', true, 5)
  assert.ok(compact < medium)
  assert.ok(medium < long)
  assert.ok(medium >= 780)
  assert.ok(long >= 1_040)
})

test('meal start records reject invalid timestamps and remain bounded sync data', () => {
  assert.deepEqual(normalizeMealStartTimes({
    valid: { started_at: '2026-07-25T12:00:00.000Z', updated_at: '2026-07-25T12:05:00.000Z' },
    invalid: { started_at: 'not-a-date', updated_at: 'not-a-date' },
  }), {
    valid: { started_at: '2026-07-25T12:00:00.000Z', updated_at: '2026-07-25T12:05:00.000Z' },
  })
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

test('completed workouts become exact dayline events in the selected timezone', () => {
  const event = timedWorkout(session(), 'UTC')
  assert.ok(event)
  assert.equal(event.completedTime, '16:30')
  assert.equal(event.completedMinute, 16 * 60 + 30)
  assert.equal(timedWorkout(session({ completed: false }), 'UTC'), null)
})

test('post-workout scoring uses a broad two-hour plateau rather than an artificial minute cliff', () => {
  assert.equal(recoveryTimingScore(5), 100)
  assert.equal(recoveryTimingScore(60), 100)
  assert.equal(recoveryTimingScore(120), 100)
  assert.equal(recoveryTimingScore(180), 85)
  assert.equal(recoveryTimingScore(240), 70)
  assert.equal(recoveryTimingScore(-1), null)
})

test('legacy post-workout start data cannot override the recorded meal finish', () => {
  const recovery = resolvePostWorkoutNutrition({
    sessions: [session()],
    meals: [meal({ id: 'recovery-meal', logged_at: '2026-07-25T18:00:00.000Z' })],
    timeZone: 'UTC',
    recoveryNutrition: {
      'session-1': {
        meal_id: 'recovery-meal',
        started_at: '2026-07-25T17:15:00.000Z',
        updated_at: '2026-07-25T17:15:00.000Z',
      },
    },
  })
  assert.equal(recovery[0].source, 'recorded_finish')
  assert.equal(recovery[0].gapMinutes, 90)
  assert.equal(recovery[0].timingScore, 100)
  assert.equal(recovery[0].mealName, 'Lunch')
})

test('legacy meal-start records are ignored in post-workout timing', () => {
  const recoveryMeal = meal({
    id: 'recovery-meal',
    client_idempotency_key: 'write|apex-meal-block=post_workout',
    logged_at: '2026-07-25T17:45:00.000Z',
  })
  const recovery = resolvePostWorkoutNutrition({
    sessions: [session()],
    meals: [recoveryMeal],
    timeZone: 'UTC',
    mealStartTimes: {
      legacy: {
        started_at: '2026-07-25T17:10:00.000Z',
        updated_at: '2026-07-25T17:10:00.000Z',
      },
    },
  })
  assert.equal(recovery[0].source, 'recorded_finish')
  assert.equal(recovery[0].gapMinutes, 75)
  assert.equal(recovery[0].mealName, 'Lunch')
})

test('legacy recovery-start records are ignored and the next finish is linked', () => {
  const recovery = resolvePostWorkoutNutrition({
    sessions: [session()],
    meals: [meal({
      id: 'meal-added-after-start',
      display_name: 'Recovery shake',
      logged_at: '2026-07-25T17:20:00.000Z',
    })],
    timeZone: 'UTC',
    recoveryNutrition: {
      'session-1': {
        meal_id: null,
        started_at: '2026-07-25T17:15:00.000Z',
        updated_at: '2026-07-25T17:15:00.000Z',
      },
    },
  })
  assert.equal(recovery[0].source, 'recorded_finish')
  assert.equal(recovery[0].gapMinutes, 50)
  assert.equal(recovery[0].mealId, 'meal-added-after-start')
  assert.equal(recovery[0].mealName, 'Recovery shake')
})

test('recovery timing settings discard malformed records and cap persisted history', () => {
  const normalized = normalizeRecoveryNutrition({
    valid: {
      meal_id: '',
      started_at: '2026-07-25T17:15:00.000Z',
      updated_at: 'bad',
    },
    invalid: {
      meal_id: null,
      started_at: 'not-a-date',
      updated_at: 'not-a-date',
    },
  })
  assert.deepEqual(normalized, {
    valid: {
      meal_id: null,
      started_at: '2026-07-25T17:15:00.000Z',
      updated_at: '2026-07-25T17:15:00.000Z',
    },
  })
})
