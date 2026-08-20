import type { ActivityLevel, Goal, Profile, RecoveryCheckin, RecoveryDataSource, WatchActivityCheckin } from './types'
import type { PersonaSlug } from './persona'

export interface PersonalCalorieProtocol {
  calories: Record<Goal, Record<ActivityLevel, number>>
  protein: Record<Goal, number>
  fat: Record<Goal, number>
  defaultGoal: Goal
  defaultActivity: ActivityLevel
  freezeLoggedDays: number
}

export interface PersonalTargetResult {
  kcal: number
  tdee: number
  proteinG: number
  fatG: number
  carbsG: number
}

const LEVELS: ActivityLevel[] = ['sedentary', 'light', 'moderate', 'very', 'extra']

function levelTable(values: [number, number, number, number, number]): Record<ActivityLevel, number> {
  return Object.fromEntries(LEVELS.map((level, index) => [level, values[index]])) as Record<ActivityLevel, number>
}

export const PERSONAL_CALORIE_PROTOCOLS: Partial<Record<PersonaSlug, PersonalCalorieProtocol>> = {
  constantine: {
    calories: {
      recomp: levelTable([2300, 2400, 2450, 2650, 2900]),
      maintain: levelTable([2400, 2500, 2550, 2750, 3000]),
      bulk: levelTable([2550, 2650, 2700, 2900, 3150]),
    },
    protein: { recomp: 150, maintain: 150, bulk: 150 },
    fat: { recomp: 75, maintain: 80, bulk: 85 },
    defaultGoal: 'recomp',
    defaultActivity: 'moderate',
    freezeLoggedDays: 14,
  },
  june: {
    calories: {
      recomp: levelTable([2200, 2200, 2200, 2350, 2550]),
      maintain: levelTable([2200, 2250, 2300, 2450, 2650]),
      bulk: levelTable([2300, 2350, 2400, 2550, 2750]),
    },
    protein: { recomp: 85, maintain: 85, bulk: 85 },
    fat: { recomp: 90, maintain: 92, bulk: 95 },
    defaultGoal: 'bulk',
    defaultActivity: 'moderate',
    freezeLoggedDays: 21,
  },
}

export function carbohydrateGrams(kcal: number, proteinG: number, fatG: number): number {
  return Math.max(0, Math.round((kcal - proteinG * 4 - fatG * 9) / 4))
}

export function personalTargetFor(profile: Pick<Profile, 'persona' | 'goal' | 'activity_level'>): PersonalTargetResult | null {
  const protocol = PERSONAL_CALORIE_PROTOCOLS[profile.persona]
  if (!protocol) return null
  const kcal = protocol.calories[profile.goal][profile.activity_level]
  const proteinG = protocol.protein[profile.goal]
  const fatG = protocol.fat[profile.goal]
  return {
    kcal,
    /* Maintenance is the closest useful TDEE estimate. Goal calories are
       displayed separately, so a surplus or deficit is never mislabeled. */
    tdee: protocol.calories.maintain[profile.activity_level],
    proteinG,
    fatG,
    carbsG: carbohydrateGrams(kcal, proteinG, fatG),
  }
}

export interface WatchActivityInput {
  steps: number
  activeCalories: number
  exerciseMinutes: number
}

export interface ActivityRecommendationContext {
  strengthCompleted?: boolean
  focusT25Completed?: boolean
  substantialWalkingOrHousework?: boolean
  massageAppointments?: number
  demandingMassageAppointments?: number
  gimbalMinutes?: number
  hardCyclingMinutes?: number
  demandingPhysicalHours?: number
}

export interface ActivityModeRecommendation {
  level: ActivityLevel
  reasons: string[]
  /* The recommendation is informational by design. The selected mode is
     changed only by an explicit user action. */
  shouldAutoApply: false
}

function highestLevel(...levels: ActivityLevel[]): ActivityLevel {
  return levels.reduce((highest, candidate) =>
    LEVELS.indexOf(candidate) > LEVELS.indexOf(highest) ? candidate : highest
  , 'sedentary' as ActivityLevel)
}

function levelFromThresholds(value: number, thresholds: [number, number, number, number]): ActivityLevel {
  if (value >= thresholds[3]) return 'extra'
  if (value >= thresholds[2]) return 'very'
  if (value >= thresholds[1]) return 'moderate'
  if (value >= thresholds[0]) return 'light'
  return 'sedentary'
}

export function recommendActivityMode(
  persona: PersonaSlug,
  input: WatchActivityInput,
  context: ActivityRecommendationContext = {},
): ActivityModeRecommendation {
  const steps = Math.max(0, Math.round(input.steps || 0))
  const activeCalories = Math.max(0, Math.round(input.activeCalories || 0))
  const exerciseMinutes = Math.max(0, Math.round(input.exerciseMinutes || 0))
  const reasons: string[] = []
  const isJune = persona === 'june'
  let level = highestLevel(
    levelFromThresholds(steps, isJune ? [4000, 7000, 11500, 16000] : [4000, 7500, 12000, 18000]),
    levelFromThresholds(activeCalories, isJune ? [180, 350, 550, 800] : [250, 500, 750, 1100]),
  )

  if (steps > 0) reasons.push(`${steps.toLocaleString('en')} steps`)
  if (activeCalories > 0) reasons.push(`${activeCalories} active kcal`)
  if (exerciseMinutes > 0) reasons.push(`${exerciseMinutes} exercise min`)

  if (persona === 'constantine') {
    if (context.gimbalMinutes != null && context.gimbalMinutes >= 480) {
      level = highestLevel(level, 'extra')
      reasons.push('extended gimbal-camera work')
    } else if (context.gimbalMinutes != null && context.gimbalMinutes >= 180) {
      level = highestLevel(level, 'very')
      reasons.push('sustained gimbal-camera work')
    }
    if ((context.hardCyclingMinutes ?? 0) >= 120 || (context.demandingPhysicalHours ?? 0) >= 6) {
      level = highestLevel(level, 'extra')
      reasons.push('exceptional physical workload')
    } else if ((context.hardCyclingMinutes ?? 0) >= 60 || (context.demandingPhysicalHours ?? 0) >= 3) {
      level = highestLevel(level, 'very')
      reasons.push('several physically active hours')
    }
    if (context.strengthCompleted && context.focusT25Completed) {
      level = highestLevel(level, 'moderate')
      reasons.push('strength plus Focus T25')
    } else if (context.strengthCompleted) {
      level = highestLevel(level, context.substantialWalkingOrHousework ? 'moderate' : 'light')
      reasons.push(context.substantialWalkingOrHousework ? 'strength plus substantial daily movement' : 'strength session')
    }
  } else if (persona === 'june') {
    const massages = Math.max(context.massageAppointments ?? 0, context.demandingMassageAppointments ?? 0)
    if (massages >= 4 && (context.strengthCompleted || context.focusT25Completed || steps >= 12000)) {
      level = highestLevel(level, 'extra')
      reasons.push('several demanding massages plus training or long walking')
    } else if (massages >= 2 && (context.strengthCompleted || context.focusT25Completed)) {
      level = highestLevel(level, 'very')
      reasons.push('massage work plus training')
    } else if (massages >= 2) {
      level = highestLevel(level, 'moderate')
      reasons.push('two or three massage appointments')
    } else if (massages === 1) {
      level = highestLevel(level, 'light')
      reasons.push('one massage appointment')
    } else if (context.strengthCompleted || context.focusT25Completed) {
      level = highestLevel(level, 'moderate')
      reasons.push('training session')
    }
  }

  return { level, reasons: reasons.slice(0, 3), shouldAutoApply: false }
}

export type RecoveryState = 'strong' | 'normal' | 'low' | 'very_low'

export interface RecoveryAssessmentContext {
  consecutiveLowMornings?: number
  decliningPerformance?: boolean
  increasedJointDiscomfort?: boolean
  highSoreness?: boolean
  demandingMassageDay?: boolean
  recentGimbalEvent?: boolean
  repeatedShortSleep?: boolean
}

export interface RecoveryAssessment {
  state: RecoveryState
  source: RecoveryDataSource
  title: string
  guidance: string
}

function escalatorCount(context: RecoveryAssessmentContext): number {
  return [
    (context.consecutiveLowMornings ?? 0) >= 2,
    context.decliningPerformance,
    context.increasedJointDiscomfort,
    context.highSoreness,
    context.demandingMassageDay,
    context.recentGimbalEvent,
    context.repeatedShortSleep,
  ].filter(Boolean).length
}

export function assessRecovery(
  entry: RecoveryCheckin,
  context: RecoveryAssessmentContext = {},
): RecoveryAssessment {
  const mainScore = entry.source === 'apple' ? entry.sleep_score : entry.recovery_pct
  const score = Math.max(0, Math.min(100, mainScore ?? 0))
  let state: RecoveryState
  if (entry.source === 'apple') {
    /* Apple watchOS 26 classifications: 0-40 Very Low, 41-60 Low,
       61-80 OK, 81-95 High and 96+ Very High. Sleep Score is not HRV. */
    state = score <= 40 ? 'very_low' : score <= 60 ? 'low' : score <= 80 ? 'normal' : 'strong'
  } else {
    /* Recovery score is the readiness input. Sleep is supporting context.
       0-33, 34-66 and 67-100 follow its red, yellow and green presentation. */
    state = score <= 20 ? 'very_low' : score <= 33 ? 'low' : score <= 66 ? 'normal' : 'strong'
    if ((entry.sleep_pct ?? 100) <= 40 && state === 'strong') state = 'normal'
  }

  const escalation = escalatorCount(context)
  if (state === 'low' && escalation >= 2) state = 'very_low'
  if (state === 'normal' && escalation >= 3) state = 'low'

  if (state === 'strong') {
    return { state, source: entry.source, title: 'Ready for the planned session', guidance: 'Follow the planned session normally.' }
  }
  if (state === 'normal') {
    return { state, source: entry.source, title: 'Normal training readiness', guidance: 'Follow the plan and keep the prescribed repetitions in reserve.' }
  }
  if (state === 'low') {
    return { state, source: entry.source, title: 'Protect the priority work', guidance: 'Keep the priority strength work, reduce optional volume and prefer Stretch over optional conditioning.' }
  }
  return { state, source: entry.source, title: 'Recovery first today', guidance: 'Use reduced volume, Stretch or rest. Avoid adding extra training.' }
}

export function normalizeRecoverySource(value: unknown): RecoveryDataSource {
  return value === 'other' ? 'other' : 'apple'
}

function validPercent(value: unknown): number | null {
  if (value == null || value === '') return null
  const number = Number(value)
  return Number.isFinite(number) ? Math.max(0, Math.min(100, Math.round(number))) : null
}

export function normalizeRecoveryHistory(value: unknown): RecoveryCheckin[] {
  if (!Array.isArray(value)) return []
  return value.flatMap((candidate) => {
    if (!candidate || typeof candidate !== 'object') return []
    const raw = candidate as Partial<RecoveryCheckin>
    if (typeof raw.date !== 'string' || typeof raw.updated_at !== 'string') return []
    const source = normalizeRecoverySource(raw.source)
    const sleepScore = validPercent(raw.sleep_score)
    const sleepPct = validPercent(raw.sleep_pct)
    const recoveryPct = validPercent(raw.recovery_pct)
    if (source === 'apple' && sleepScore == null) return []
    if (source === 'other' && (sleepPct == null || recoveryPct == null)) return []
    return [{
      date: raw.date,
      source,
      sleep_score: source === 'apple' ? sleepScore : null,
      sleep_pct: source === 'other' ? sleepPct : null,
      recovery_pct: source === 'other' ? recoveryPct : null,
      updated_at: raw.updated_at,
    }]
  }).sort((left, right) => right.date.localeCompare(left.date)).slice(0, 730)
}

export function normalizeWatchActivityHistory(value: unknown): WatchActivityCheckin[] {
  if (!Array.isArray(value)) return []
  return value.flatMap((candidate) => {
    if (!candidate || typeof candidate !== 'object') return []
    const raw = candidate as Partial<WatchActivityCheckin>
    if (typeof raw.date !== 'string' || typeof raw.updated_at !== 'string') return []
    return [{
      date: raw.date,
      steps: Math.max(0, Math.round(Number(raw.steps) || 0)),
      active_calories: Math.max(0, Math.round(Number(raw.active_calories) || 0)),
      exercise_minutes: Math.max(0, Math.round(Number(raw.exercise_minutes) || 0)),
      suggested_level: LEVELS.includes(raw.suggested_level as ActivityLevel) ? raw.suggested_level! : 'sedentary',
      selected_level: LEVELS.includes(raw.selected_level as ActivityLevel) ? raw.selected_level! : 'sedentary',
      updated_at: raw.updated_at,
    }]
  }).sort((left, right) => right.date.localeCompare(left.date)).slice(0, 730)
}

export interface ProtocolMeal {
  time: string
  name: string
  foods: string[]
}

export interface AthleteSupportProtocol {
  meals: ProtocolMeal[]
  clusterDextrin: {
    incrementG: 5
    normalG: [number, number]
    proteinAndCarbProteinG: [number, number]
  }
  heavyCaseinProteinG: [40, 45]
  supplements: string[]
  healthyFatNote?: string
}

export const ATHLETE_SUPPORT_PROTOCOLS: Partial<Record<PersonaSlug, AthleteSupportProtocol>> = {
  constantine: {
    meals: [
      { time: '07:00', name: 'Overnight oat jar', foods: ['70 g organic whole-grain oats', '250 ml Migros Oh! protein-rich milk', '20 g LeeSport unflavoured whey isolate', '100 g berries', '1 kiwi', '15 g walnuts', '10-15 g seed blend', '5 g coconut flakes', 'Optional boiled egg'] },
      { time: '13:00', name: 'Lunch', foods: ['70 g dry bulgur', '10 g EVOO', 'Cherry tomatoes', 'Raw spring onion', 'Vegetables', '150 g saved protein or whey providing 35-40 g protein'] },
      { time: '15:30', name: 'Snack', foods: ['1 banana or another saved fruit'] },
      { time: '19:15', name: 'Dinner', foods: ['300 g sweet potato, cooked', '150 g chicken breast, cooked', '100 g mixed vegetables, cooked', '10 g extra virgin olive oil', 'Iodized salt'] },
    ],
    clusterDextrin: { incrementG: 5, normalG: [25, 40], proteinAndCarbProteinG: [25, 30] },
    heavyCaseinProteinG: [40, 45],
    supplements: ['Creatine monohydrate 3-5 g with breakfast', 'Collagen 10-15 g plus vitamin C before tendon-focused training', 'Citrulline malate 6-8 g before hard sessions when enabled', 'Cluster dextrin 25-40 g when workload or remaining carbohydrate requires it'],
  },
  june: {
    meals: [
      { time: '07:00', name: 'Overnight oat jar', foods: ['65 g oats', '250 ml Migros Oh! protein-rich milk', '10 g whey isolate when useful', '100 g berries', '1 kiwi', '15 g walnuts', '15 g seed blend'] },
      { time: '13:00', name: 'Lunch', foods: ['75 g dry bulgur', '10-15 g EVOO', 'Tomatoes', 'Spring onion', 'Vegetables', '100-120 g saved protein or whey providing 25-30 g protein', 'Optional half avocado with a lean protein'] },
      { time: '15:30', name: 'Snack', foods: ['1 banana or another saved fruit'] },
      { time: '19:15', name: 'Dinner', foods: ['300 g sweet potato, cooked', '110 g salmon fillet, cooked', '100 g mixed vegetables, cooked', '10 g extra virgin olive oil', '70 g avocado with a lean protein'] },
    ],
    clusterDextrin: { incrementG: 5, normalG: [20, 25], proteinAndCarbProteinG: [20, 25] },
    heavyCaseinProteinG: [40, 45],
    supplements: ['Creatine monohydrate 3 g with breakfast', 'Cluster dextrin 20-25 g when workload or remaining carbohydrate requires it', 'Water and iodized salt according to heat, duration and sweating'],
    healthyFatNote: 'Prioritize EVOO, avocado, nuts, seeds and oily fish as calorie-dense foods.',
  },
}

export function powderGramsForProtein(proteinPer100G: number, targetProteinG: number): number | null {
  if (!Number.isFinite(proteinPer100G) || proteinPer100G <= 0 || !Number.isFinite(targetProteinG) || targetProteinG <= 0) return null
  return Math.round((targetProteinG / proteinPer100G) * 100)
}

export interface PostWorkoutMealTarget {
  proteinG: [number, number] | null
  carbsG: [number, number] | null
  normalBalancedMeal: boolean
}

const NORMAL_MEAL: PostWorkoutMealTarget = {
  proteinG: null,
  carbsG: null,
  normalBalancedMeal: true,
}

export const POST_WORKOUT_MEAL_TARGETS: Partial<Record<PersonaSlug, Record<number, PostWorkoutMealTarget>>> = {
  constantine: {
    1: { proteinG: [35, 45], carbsG: [70, 100], normalBalancedMeal: false },
    2: { proteinG: [30, 40], carbsG: [60, 90], normalBalancedMeal: false },
    3: { proteinG: [30, 40], carbsG: [70, 100], normalBalancedMeal: false },
    4: NORMAL_MEAL,
    5: { proteinG: [35, 45], carbsG: [80, 110], normalBalancedMeal: false },
    6: { proteinG: [30, 40], carbsG: [50, 80], normalBalancedMeal: false },
    7: { proteinG: [30, 40], carbsG: [40, 70], normalBalancedMeal: false },
  },
  june: {
    1: { proteinG: [20, 30], carbsG: [60, 90], normalBalancedMeal: false },
    2: { proteinG: [20, 30], carbsG: [40, 70], normalBalancedMeal: false },
    3: { proteinG: [20, 30], carbsG: [50, 80], normalBalancedMeal: false },
    4: NORMAL_MEAL,
    5: { proteinG: [20, 30], carbsG: [60, 90], normalBalancedMeal: false },
    6: { proteinG: [20, 30], carbsG: [40, 70], normalBalancedMeal: false },
    7: NORMAL_MEAL,
  },
}

export function postWorkoutMealTargetFor(persona: PersonaSlug, weekday: number): PostWorkoutMealTarget | null {
  return POST_WORKOUT_MEAL_TARGETS[persona]?.[weekday] ?? null
}

export interface CalibrationInput {
  persona: PersonaSlug
  sufficientlyLoggedDays: number
  weeklyWeightChangeKg: number
  monthlyWeightChangeKg?: number
  waistTrend?: 'down' | 'stable' | 'up' | 'rapid_up'
  performanceTrend: 'down' | 'stable' | 'up'
  sleepOrRecoveryDeclining?: boolean
  highHunger?: boolean
  earlyCreatineChangeSettled?: boolean
  exceptionalActivityOnly?: boolean
}

export interface CalibrationRecommendation {
  eligible: boolean
  deltaKcal: number
  label: string
}

export function recommendTargetCalibration(input: CalibrationInput): CalibrationRecommendation {
  if (input.persona === 'june') {
    if (input.sufficientlyLoggedDays < 21) return { eligible: false, deltaKcal: 0, label: 'Keep the initial targets stable for 21 sufficiently logged days.' }
    const monthly = input.monthlyWeightChangeKg ?? input.weeklyWeightChangeKg * 4.345
    if (monthly < 0) return { eligible: true, deltaKcal: monthly <= -0.25 ? 250 : 150, label: 'Weight is falling. Confirm a calorie increase across every activity mode.' }
    if (monthly > 0.75 && input.earlyCreatineChangeSettled && (input.waistTrend === 'up' || input.waistTrend === 'rapid_up')) {
      return { eligible: true, deltaKcal: -100, label: 'Weight and waist are rising faster than planned. Confirm a small reduction.' }
    }
    if (Math.abs(monthly) < 0.1 && input.performanceTrend === 'stable') {
      return { eligible: true, deltaKcal: 100, label: 'Weight and glute performance are both flat. Confirm a 100 kcal increase.' }
    }
    return { eligible: true, deltaKcal: 0, label: 'Keep the current targets and review the next two weeks.' }
  }
  if (input.persona === 'constantine') {
    if (input.sufficientlyLoggedDays < 14) return { eligible: false, deltaKcal: 0, label: 'Collect at least 14 sufficiently logged days before calibration.' }
    if (input.exceptionalActivityOnly) return { eligible: true, deltaKcal: 0, label: 'Use event-specific fuel instead of changing every normal target.' }
    if (input.weeklyWeightChangeKg < -0.25 || input.performanceTrend === 'down' || input.sleepOrRecoveryDeclining || input.highHunger) {
      return { eligible: true, deltaKcal: 150, label: 'Confirm a 150 kcal increase across every activity mode.' }
    }
    if ((input.waistTrend === 'up' || input.waistTrend === 'rapid_up') && input.weeklyWeightChangeKg > 0 && input.performanceTrend !== 'up') {
      return { eligible: true, deltaKcal: -125, label: 'Confirm a 100-150 kcal reduction across every activity mode.' }
    }
    return { eligible: true, deltaKcal: 0, label: 'Current weight, waist and performance trends support keeping the targets.' }
  }
  return { eligible: false, deltaKcal: 0, label: 'Personal trend calibration is not configured for this profile.' }
}
