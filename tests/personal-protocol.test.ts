import test from 'node:test'
import assert from 'node:assert/strict'
import {
  PERSONAL_CALORIE_PROTOCOLS,
  assessRecovery,
  carbohydrateGrams,
  normalizeRecoveryHistory,
  normalizeWatchActivityHistory,
  personalTargetFor,
  postWorkoutMealTargetFor,
  powderGramsForProtein,
  recommendActivityMode,
  recommendTargetCalibration,
} from '../src/lib/personalProtocol.ts'
import type { ActivityLevel, Goal } from '../src/lib/types.ts'

const levels: ActivityLevel[] = ['sedentary', 'light', 'moderate', 'very', 'extra']
const goals: Goal[] = ['recomp', 'maintain', 'bulk']

const expected = {
  constantine: {
    calories: {
      recomp: [2300, 2400, 2450, 2650, 2900],
      maintain: [2400, 2500, 2550, 2750, 3000],
      bulk: [2550, 2650, 2700, 2900, 3150],
    },
    protein: { recomp: 150, maintain: 150, bulk: 150 },
    fat: { recomp: 75, maintain: 80, bulk: 85 },
  },
  june: {
    calories: {
      recomp: [2200, 2200, 2200, 2350, 2550],
      maintain: [2200, 2250, 2300, 2450, 2650],
      bulk: [2300, 2350, 2400, 2550, 2750],
    },
    protein: { recomp: 85, maintain: 85, bulk: 85 },
    fat: { recomp: 90, maintain: 92, bulk: 95 },
  },
} as const

test('all 30 personalized goal and activity combinations use the exact tables and carbohydrate formula', () => {
  for (const persona of ['constantine', 'june'] as const) {
    for (const goal of goals) {
      for (const [index, activity_level] of levels.entries()) {
        const result = personalTargetFor({ persona, goal, activity_level })
        assert.ok(result)
        const kcal = expected[persona].calories[goal][index]
        const protein = expected[persona].protein[goal]
        const fat = expected[persona].fat[goal]
        assert.deepEqual(
          { kcal: result.kcal, protein: result.proteinG, fat: result.fatG, carbs: result.carbsG },
          { kcal, protein, fat, carbs: carbohydrateGrams(kcal, protein, fat) },
          `${persona} ${goal} ${activity_level}`,
        )
        assert.equal(result.tdee, expected[persona].calories.maintain[index])
      }
    }
  }
  assert.deepEqual(
    personalTargetFor({ persona: 'constantine', goal: 'recomp', activity_level: 'moderate' }),
    { kcal: 2450, tdee: 2550, proteinG: 150, fatG: 75, carbsG: 294 },
  )
  assert.deepEqual(
    personalTargetFor({ persona: 'june', goal: 'bulk', activity_level: 'moderate' }),
    { kcal: 2400, tdee: 2300, proteinG: 85, fatG: 95, carbsG: 301 },
  )
})

test('protocol metadata preserves the requested defaults and 14/21-day gates', () => {
  assert.deepEqual(
    {
      goal: PERSONAL_CALORIE_PROTOCOLS.constantine?.defaultGoal,
      activity: PERSONAL_CALORIE_PROTOCOLS.constantine?.defaultActivity,
      gate: PERSONAL_CALORIE_PROTOCOLS.constantine?.freezeLoggedDays,
    },
    { goal: 'recomp', activity: 'moderate', gate: 14 },
  )
  assert.deepEqual(
    {
      goal: PERSONAL_CALORIE_PROTOCOLS.june?.defaultGoal,
      activity: PERSONAL_CALORIE_PROTOCOLS.june?.defaultActivity,
      gate: PERSONAL_CALORIE_PROTOCOLS.june?.freezeLoggedDays,
    },
    { goal: 'bulk', activity: 'moderate', gate: 21 },
  )
})

test('Watch activity thresholds recommend a whole-day mode and never auto-apply it', () => {
  const constantineCases: Array<[number, number, ActivityLevel]> = [
    [3999, 249, 'sedentary'],
    [4000, 250, 'light'],
    [7500, 500, 'moderate'],
    [12000, 750, 'very'],
    [18000, 1100, 'extra'],
  ]
  for (const [steps, activeCalories, level] of constantineCases) {
    const recommendation = recommendActivityMode('constantine', { steps, activeCalories, exerciseMinutes: 0 })
    assert.equal(recommendation.level, level)
    assert.equal(recommendation.shouldAutoApply, false)
  }

  const juneCases: Array<[number, number, ActivityLevel]> = [
    [3999, 179, 'sedentary'],
    [4000, 180, 'light'],
    [7000, 350, 'moderate'],
    [11500, 550, 'very'],
    [16000, 800, 'extra'],
  ]
  for (const [steps, activeCalories, level] of juneCases) {
    const recommendation = recommendActivityMode('june', { steps, activeCalories, exerciseMinutes: 0 })
    assert.equal(recommendation.level, level)
    assert.equal(recommendation.shouldAutoApply, false)
  }

  assert.equal(
    recommendActivityMode('constantine', { steps: 3000, activeCalories: 200, exerciseMinutes: 0 }, { gimbalMinutes: 480 }).level,
    'extra',
  )
  assert.equal(
    recommendActivityMode('june', { steps: 3000, activeCalories: 150, exerciseMinutes: 0 }, { massageAppointments: 3 }).level,
    'moderate',
  )
  assert.equal(
    recommendActivityMode('constantine', { steps: 0, activeCalories: 0, exerciseMinutes: 25 }).level,
    'moderate',
  )
})

test('source-tagged recovery history remains valid across source changes', () => {
  const history = normalizeRecoveryHistory([
    { date: '2026-07-25', source: 'apple', sleep_score: 86, sleep_pct: null, recovery_pct: null, updated_at: '2026-07-25T07:00:00Z' },
    { date: '2026-07-26', source: 'other', sleep_score: null, sleep_pct: 91, recovery_pct: 74, updated_at: '2026-07-26T07:00:00Z' },
    { date: 'bad', source: 'other', sleep_pct: 80, recovery_pct: null, updated_at: '2026-07-26T07:00:00Z' },
  ])
  assert.equal(history.length, 2)
  assert.equal(history[0].source, 'other')
  assert.equal(history[1].source, 'apple')
  assert.equal(assessRecovery(history[1]).state, 'strong')
  assert.equal(assessRecovery(history[0]).state, 'strong')
  assert.equal(
    assessRecovery(
      { date: '2026-07-27', source: 'apple', sleep_score: 55, sleep_pct: null, recovery_pct: null, updated_at: '2026-07-27T07:00:00Z' },
      { consecutiveLowMornings: 2, decliningPerformance: true },
    ).state,
    'very_low',
  )
})

test('Watch history normalization retains the recommendation and explicit user selection separately', () => {
  const rows = normalizeWatchActivityHistory([
    {
      date: '2026-07-26',
      steps: 9000,
      active_calories: 600,
      exercise_minutes: 55,
      suggested_level: 'moderate',
      selected_level: 'light',
      updated_at: '2026-07-26T18:00:00Z',
    },
  ])
  assert.deepEqual(rows[0], {
    date: '2026-07-26',
    steps: 9000,
    active_calories: 600,
    exercise_minutes: 55,
    suggested_level: 'moderate',
    selected_level: 'light',
    updated_at: '2026-07-26T18:00:00Z',
  })
})

test('trend calibration is recommendation-only and June keeps the first 21 logged days stable', () => {
  assert.deepEqual(
    recommendTargetCalibration({
      persona: 'june',
      sufficientlyLoggedDays: 20,
      weeklyWeightChangeKg: -0.2,
      performanceTrend: 'stable',
    }),
    { eligible: false, deltaKcal: 0, label: 'Keep the initial targets stable for 21 sufficiently logged days.' },
  )
  assert.equal(
    recommendTargetCalibration({
      persona: 'june',
      sufficientlyLoggedDays: 21,
      weeklyWeightChangeKg: 0,
      monthlyWeightChangeKg: 0,
      performanceTrend: 'stable',
    }).deltaKcal,
    100,
  )
  assert.equal(
    recommendTargetCalibration({
      persona: 'constantine',
      sufficientlyLoggedDays: 14,
      weeklyWeightChangeKg: -0.3,
      performanceTrend: 'stable',
    }).deltaKcal,
    150,
  )
})

test('weekday post-workout targets and saved-label powder conversion are deterministic', () => {
  assert.deepEqual(postWorkoutMealTargetFor('constantine', 1), {
    proteinG: [35, 45],
    carbsG: [70, 100],
    normalBalancedMeal: false,
  })
  assert.equal(postWorkoutMealTargetFor('june', 4)?.normalBalancedMeal, true)
  assert.equal(powderGramsForProtein(90, 27), 30)
  assert.equal(powderGramsForProtein(0, 27), null)
})
