import type { LoggedFoodEntry, LoggedMeal, MealSlot } from './food'
import type { Settings, WorkoutSession } from './types'

export const DAYLINE_START_MINUTE = 3 * 60
export const DAYLINE_DURATION_MINUTES = 24 * 60
export const DAYLINE_END_MINUTE = DAYLINE_START_MINUTE + DAYLINE_DURATION_MINUTES
export const QUIET_HOURS_START_MINUTE = 22 * 60 + 30
export const QUIET_HOURS_END_MINUTE = 5 * 60

export type MealComfortZone = 'settling' | 'transition' | 'ready'
export type MealLoadKind = 'light' | 'standard' | 'substantial' | 'large'

export interface MealComfortWindow {
  load: MealLoadKind
  transitionAfterMinutes: number
  readyAfterMinutes: number
  fibreG: number
}

export interface ZonedClock {
  date: string
  time: string
  minute: number
}

export interface TimedMeal {
  meal: LoggedMeal
  time: string
  minute: number
  lineMinute: number
  recorded: boolean
  window: MealComfortWindow
}

export interface WorkoutMealTiming {
  sessionId: string
  date: string
  startedAt: string
  mealId: string | null
  mealName: string | null
  waitedMinutes: number | null
  zone: MealComfortZone | null
}

export type RecoveryNutritionLog = NonNullable<Settings['addons']['recovery_nutrition']>[string]

export interface TimedWorkout {
  session: WorkoutSession
  startedTime: string | null
  completedTime: string
  completedMinute: number
  completedLineMinute: number
}

export interface PostWorkoutNutritionTiming {
  sessionId: string
  date: string
  completedAt: string
  mealId: string | null
  mealName: string | null
  mealStartedAt: string | null
  gapMinutes: number | null
  timingScore: number | null
  source: 'recorded_start' | 'inferred_finish' | 'missing'
}

export interface MealTimingAnalysis {
  recordedMeals: number
  estimatedMeals: number
  workoutsWithContext: number
  readyStarts: number
  transitionStarts: number
  settlingStarts: number
  averageWaitMinutes: number | null
  rhythmScore: number | null
  typicalVariationMinutes: number | null
  workoutRelations: WorkoutMealTiming[]
  completedWorkouts: number
  recoveryMealsRecorded: number
  averageRecoveryGapMinutes: number | null
  recoveryTimingScore: number | null
  postWorkoutRelations: PostWorkoutNutritionTiming[]
}

export function normalizeRecoveryNutrition(value: unknown): Record<string, RecoveryNutritionLog> {
  if (!value || typeof value !== 'object') return {}
  const normalized: Record<string, RecoveryNutritionLog> = {}
  for (const [sessionId, candidate] of Object.entries(value)) {
    if (!sessionId || !candidate || typeof candidate !== 'object') continue
    const record = candidate as Partial<RecoveryNutritionLog>
    if (typeof record.started_at !== 'string' || !Number.isFinite(Date.parse(record.started_at))) continue
    const updatedAt = typeof record.updated_at === 'string' && Number.isFinite(Date.parse(record.updated_at))
      ? record.updated_at
      : record.started_at
    normalized[sessionId] = {
      meal_id: typeof record.meal_id === 'string' && record.meal_id ? record.meal_id : null,
      started_at: new Date(record.started_at).toISOString(),
      updated_at: new Date(updatedAt).toISOString(),
    }
  }
  return Object.fromEntries(Object.entries(normalized)
    .sort((left, right) => right[1].updated_at.localeCompare(left[1].updated_at))
    .slice(0, 365))
}

const DEFAULT_SLOT_CLOCK: Record<MealSlot, string> = {
  breakfast: '07:00',
  lunch: '13:00',
  dinner: '19:00',
  snack: '16:00',
}

function pad(value: number): string {
  return String(value).padStart(2, '0')
}

export function validTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat('en', { timeZone: value }).format(new Date())
    return true
  } catch {
    return false
  }
}

export function detectedTimeZone(): string {
  const detected = Intl.DateTimeFormat().resolvedOptions().timeZone
  return detected && validTimeZone(detected) ? detected : 'UTC'
}

export function timeZoneFromSettings(settings: Settings | null | undefined): string {
  const configured = settings?.addons.time_zone
  return configured && validTimeZone(configured) ? configured : detectedTimeZone()
}

export function supportedTimeZones(): string[] {
  const intl = Intl as typeof Intl & { supportedValuesOf?: (key: 'timeZone') => string[] }
  if (typeof intl.supportedValuesOf === 'function') return intl.supportedValuesOf('timeZone')
  return [
    'Europe/Zurich',
    'Europe/Bucharest',
    'Europe/London',
    'Asia/Bangkok',
    'Asia/Singapore',
    'America/New_York',
    'America/Los_Angeles',
    'Australia/Sydney',
    'UTC',
  ]
}

function zonedParts(value: Date | string, timeZone: string): Record<string, string> {
  const date = value instanceof Date ? value : new Date(value)
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  })
  return Object.fromEntries(
    formatter.formatToParts(date)
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  )
}

export function zonedClock(value: Date | string, timeZone: string): ZonedClock {
  const parts = zonedParts(value, timeZone)
  const hour = Number(parts.hour)
  const minute = Number(parts.minute)
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    time: `${pad(hour)}:${pad(minute)}`,
    minute: hour * 60 + minute,
  }
}

/**
 * Converts an editable wall-clock value to an instant in an IANA timezone.
 * Iterating the offset handles daylight-saving boundaries without shipping a
 * second timezone database to the client.
 */
export function zonedDateTimeToIso(date: string, time: string, timeZone: string): string {
  const [year, month, day] = date.split('-').map(Number)
  const [hour, minute] = time.split(':').map(Number)
  const desired = Date.UTC(year, month - 1, day, hour, minute, 0, 0)
  let guess = desired
  for (let iteration = 0; iteration < 4; iteration += 1) {
    const parts = zonedParts(new Date(guess), timeZone)
    const represented = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour),
      Number(parts.minute),
      Number(parts.second),
    )
    const offset = represented - guess
    const next = desired - offset
    if (Math.abs(next - guess) < 1_000) {
      guess = next
      break
    }
    guess = next
  }
  return new Date(guess).toISOString()
}

export function clockToMinute(time: string): number {
  const match = /^(\d{1,2}):(\d{2})$/.exec(time)
  if (!match) return 0
  const hour = Math.min(23, Math.max(0, Number(match[1])))
  const minute = Math.min(59, Math.max(0, Number(match[2])))
  return hour * 60 + minute
}

export function minuteToClock(minute: number): string {
  const normalized = ((Math.round(minute) % (24 * 60)) + 24 * 60) % (24 * 60)
  return `${pad(Math.floor(normalized / 60))}:${pad(normalized % 60)}`
}

export function toDaylineMinute(clockMinute: number): number {
  const normalized = ((clockMinute % (24 * 60)) + 24 * 60) % (24 * 60)
  return normalized < DAYLINE_START_MINUTE ? normalized + 24 * 60 : normalized
}

export function daylineRatio(clockMinute: number): number {
  const lineMinute = toDaylineMinute(clockMinute)
  return Math.min(1, Math.max(0, (lineMinute - DAYLINE_START_MINUTE) / DAYLINE_DURATION_MINUTES))
}

export function isQuietClock(clockMinute: number): boolean {
  return clockMinute >= QUIET_HOURS_START_MINUTE || clockMinute < QUIET_HOURS_END_MINUTE
}

export function fallbackMealTime(meal: LoggedMeal): string {
  return DEFAULT_SLOT_CLOCK[meal.meal_slot]
}

export function mealFibre(mealId: string, entries: readonly LoggedFoodEntry[]): number {
  return Math.round(entries
    .filter((entry) => entry.meal_id === mealId)
    .reduce((sum, entry) => sum + (entry.fibre_g ?? 0), 0) * 10) / 10
}

/**
 * These bands are deliberately conservative comfort estimates, not a safety
 * clearance. Meal energy, fat and fibre extend the settling window because
 * they commonly increase gastric load and/or slow emptying.
 */
export function mealComfortWindow(
  meal: Pick<LoggedMeal, 'total_kcal' | 'total_fat_g'>,
  fibreG = 0,
): MealComfortWindow {
  if (meal.total_kcal >= 900 || meal.total_fat_g >= 35 || fibreG >= 18) {
    return { load: 'large', transitionAfterMinutes: 120, readyAfterMinutes: 240, fibreG }
  }
  if (meal.total_kcal >= 600 || meal.total_fat_g >= 24 || fibreG >= 13) {
    return { load: 'substantial', transitionAfterMinutes: 90, readyAfterMinutes: 180, fibreG }
  }
  if (meal.total_kcal >= 250 || meal.total_fat_g >= 10 || fibreG >= 7) {
    return { load: 'standard', transitionAfterMinutes: 45, readyAfterMinutes: 120, fibreG }
  }
  return { load: 'light', transitionAfterMinutes: 25, readyAfterMinutes: 60, fibreG }
}

export function comfortZone(minutesSinceMeal: number, window: MealComfortWindow): MealComfortZone {
  if (minutesSinceMeal < window.transitionAfterMinutes) return 'settling'
  if (minutesSinceMeal < window.readyAfterMinutes) return 'transition'
  return 'ready'
}

export function timedMeal(
  meal: LoggedMeal,
  entries: readonly LoggedFoodEntry[],
  timeZone: string,
  fallbackTime = fallbackMealTime(meal),
): TimedMeal {
  const loggedClock = zonedClock(meal.logged_at, timeZone)
  const recorded = loggedClock.date === meal.local_date
  const time = recorded ? loggedClock.time : fallbackTime
  const minute = clockToMinute(time)
  return {
    meal,
    time,
    minute,
    lineMinute: toDaylineMinute(minute),
    recorded,
    window: mealComfortWindow(meal, mealFibre(meal.id, entries)),
  }
}

export function timedWorkout(session: WorkoutSession, timeZone: string): TimedWorkout | null {
  if (!session.completed || !session.completed_at) return null
  const completed = zonedClock(session.completed_at, timeZone)
  if (completed.date !== session.date) return null
  const started = session.started_at ? zonedClock(session.started_at, timeZone) : null
  return {
    session,
    startedTime: started?.date === session.date ? started.time : null,
    completedTime: completed.time,
    completedMinute: completed.minute,
    completedLineMinute: toDaylineMinute(completed.minute),
  }
}

/**
 * There is no minute-by-minute anabolic cliff. The first two hours are one
 * broad, high-value band; the score tapers only after that. This keeps the
 * signal useful without rewarding anxiety or claiming that eating at minute
 * five is superior to eating at minute sixty.
 */
export function recoveryTimingScore(gapMinutes: number | null): number | null {
  if (gapMinutes == null || !Number.isFinite(gapMinutes) || gapMinutes < 0) return null
  if (gapMinutes <= 120) return 100
  if (gapMinutes <= 180) return Math.round(100 - (gapMinutes - 120) * 0.25)
  if (gapMinutes <= 240) return Math.round(85 - (gapMinutes - 180) * 0.25)
  return Math.max(0, Math.round(70 - (gapMinutes - 240) * 0.2))
}

export function resolvePostWorkoutNutrition({
  sessions,
  meals,
  timeZone,
  recoveryNutrition = {},
}: {
  sessions: readonly WorkoutSession[]
  meals: readonly LoggedMeal[]
  timeZone: string
  recoveryNutrition?: Readonly<Record<string, RecoveryNutritionLog>>
}): PostWorkoutNutritionTiming[] {
  const completed = sessions
    .flatMap((session) => timedWorkout(session, timeZone) ? [session] : [])
    .sort((left, right) => Date.parse(left.completed_at ?? '') - Date.parse(right.completed_at ?? ''))

  return completed.map((session) => {
    const completedAt = session.completed_at!
    const explicit = recoveryNutrition[session.id]
    const explicitStarted = explicit && Number.isFinite(Date.parse(explicit.started_at))
      ? explicit.started_at
      : null
    const explicitMeal = explicit?.meal_id
      ? meals.find((meal) => meal.id === explicit.meal_id) ?? null
      : null
    if (explicitStarted) {
      const gapMinutes = Math.max(0, Math.round((Date.parse(explicitStarted) - Date.parse(completedAt)) / 60_000))
      const linkedMeal = explicitMeal ?? meals
        .filter((meal) => meal.local_date === session.date)
        .filter((meal) => {
          const gap = Date.parse(meal.logged_at) - Date.parse(explicitStarted)
          return gap >= 0 && gap <= 6 * 60 * 60 * 1_000
        })
        .sort((left, right) => Date.parse(left.logged_at) - Date.parse(right.logged_at))[0] ?? null
      return {
        sessionId: session.id,
        date: session.date,
        completedAt,
        mealId: linkedMeal?.id ?? explicit?.meal_id ?? null,
        mealName: linkedMeal?.display_name ?? null,
        mealStartedAt: explicitStarted,
        gapMinutes,
        timingScore: recoveryTimingScore(gapMinutes),
        source: 'recorded_start' as const,
      }
    }

    /* A meal finish is a useful fallback for historical sessions, but it is
       deliberately labelled as inferred and never presented as a recorded
       eating start. Keep the horizon short enough to avoid linking breakfast
       the next morning to the previous evening's session. */
    const inferred = meals
      .filter((meal) => meal.local_date === session.date)
      .filter((meal) => {
        const gap = Date.parse(meal.logged_at) - Date.parse(completedAt)
        return gap >= 0 && gap <= 6 * 60 * 60 * 1_000
      })
      .sort((left, right) => Date.parse(left.logged_at) - Date.parse(right.logged_at))[0] ?? null
    if (inferred) {
      const gapMinutes = Math.max(0, Math.round((Date.parse(inferred.logged_at) - Date.parse(completedAt)) / 60_000))
      return {
        sessionId: session.id,
        date: session.date,
        completedAt,
        mealId: inferred.id,
        mealName: inferred.display_name,
        mealStartedAt: inferred.logged_at,
        gapMinutes,
        timingScore: recoveryTimingScore(gapMinutes),
        source: 'inferred_finish' as const,
      }
    }
    return {
      sessionId: session.id,
      date: session.date,
      completedAt,
      mealId: null,
      mealName: null,
      mealStartedAt: null,
      gapMinutes: null,
      timingScore: null,
      source: 'missing' as const,
    }
  })
}

function standardDeviation(values: number[]): number | null {
  if (values.length < 2) return null
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length
  const variance = values.reduce((sum, value) => sum + (value - mean) ** 2, 0) / values.length
  return Math.sqrt(variance)
}

function sessionStart(session: WorkoutSession): string | null {
  return session.started_at
}

export function analyzeMealTiming({
  meals,
  entries,
  sessions,
  timeZone,
  fallbackTimes = {},
  recoveryNutrition = {},
}: {
  meals: readonly LoggedMeal[]
  entries: readonly LoggedFoodEntry[]
  sessions: readonly WorkoutSession[]
  timeZone: string
  fallbackTimes?: Readonly<Record<string, string>>
  recoveryNutrition?: Readonly<Record<string, RecoveryNutritionLog>>
}): MealTimingAnalysis {
  const timed = meals.map((meal) => timedMeal(meal, entries, timeZone, fallbackTimes[meal.id] ?? fallbackMealTime(meal)))
  const recorded = timed.filter((item) => item.recorded)
  const byDate = new Map<string, TimedMeal[]>()
  for (const item of recorded) {
    const list = byDate.get(item.meal.local_date) ?? []
    list.push(item)
    byDate.set(item.meal.local_date, list)
  }
  for (const list of byDate.values()) list.sort((left, right) => Date.parse(left.meal.logged_at) - Date.parse(right.meal.logged_at))

  const workoutRelations: WorkoutMealTiming[] = []
  for (const session of sessions) {
    const start = sessionStart(session)
    if (!start) continue
    const startClock = zonedClock(start, timeZone)
    const candidates = (byDate.get(session.date) ?? [])
      .filter((item) => Date.parse(item.meal.logged_at) <= Date.parse(start))
    const latest = candidates.at(-1) ?? null
    if (!latest || startClock.date !== session.date) {
      workoutRelations.push({
        sessionId: session.id,
        date: session.date,
        startedAt: start,
        mealId: null,
        mealName: null,
        waitedMinutes: null,
        zone: null,
      })
      continue
    }
    const waitedMinutes = Math.max(0, Math.round((Date.parse(start) - Date.parse(latest.meal.logged_at)) / 60_000))
    workoutRelations.push({
      sessionId: session.id,
      date: session.date,
      startedAt: start,
      mealId: latest.meal.id,
      mealName: latest.meal.display_name,
      waitedMinutes,
      zone: comfortZone(waitedMinutes, latest.window),
    })
  }

  const contextual = workoutRelations.filter((relation) => relation.zone != null)
  const variations = (['breakfast', 'lunch', 'dinner', 'snack'] as const)
    .map((slot) => standardDeviation(recorded.filter((item) => item.meal.meal_slot === slot).map((item) => item.minute)))
    .filter((value): value is number => value != null)
  const typicalVariationMinutes = variations.length
    ? Math.round(variations.reduce((sum, value) => sum + value, 0) / variations.length)
    : null
  const rhythmScore = typicalVariationMinutes == null
    ? null
    : Math.round(Math.max(0, Math.min(100, 100 - typicalVariationMinutes * 0.9)))
  const waits = contextual.flatMap((relation) => relation.waitedMinutes == null ? [] : [relation.waitedMinutes])
  const postWorkoutRelations = resolvePostWorkoutNutrition({
    sessions,
    meals,
    timeZone,
    recoveryNutrition,
  })
  const recordedRecovery = postWorkoutRelations.filter((relation) => relation.source === 'recorded_start')
  const recoveryGaps = recordedRecovery.flatMap((relation) => relation.gapMinutes == null ? [] : [relation.gapMinutes])
  const recoveryScores = recordedRecovery.flatMap((relation) => relation.timingScore == null ? [] : [relation.timingScore])

  return {
    recordedMeals: recorded.length,
    estimatedMeals: timed.length - recorded.length,
    workoutsWithContext: contextual.length,
    readyStarts: contextual.filter((relation) => relation.zone === 'ready').length,
    transitionStarts: contextual.filter((relation) => relation.zone === 'transition').length,
    settlingStarts: contextual.filter((relation) => relation.zone === 'settling').length,
    averageWaitMinutes: waits.length ? Math.round(waits.reduce((sum, value) => sum + value, 0) / waits.length) : null,
    rhythmScore,
    typicalVariationMinutes,
    workoutRelations,
    completedWorkouts: postWorkoutRelations.length,
    recoveryMealsRecorded: recordedRecovery.length,
    averageRecoveryGapMinutes: recoveryGaps.length
      ? Math.round(recoveryGaps.reduce((sum, value) => sum + value, 0) / recoveryGaps.length)
      : null,
    recoveryTimingScore: recoveryScores.length
      ? Math.round(recoveryScores.reduce((sum, value) => sum + value, 0) / recoveryScores.length)
      : null,
    postWorkoutRelations,
  }
}
