import type { LoggedMeal, MealSlot } from './food.ts'
import {
  mealMomentIdFromIdempotencyKey,
  mealSlotForBlock,
  normalizeMealBlockSettings,
  resolveMealBlockStatuses,
} from './mealBlocks.ts'
import { clockToMinute, timeZoneFromSettings, zonedClock } from './mealTiming.ts'
import type { Settings } from './types.ts'

export type MealRhythmVerdict =
  | 'open'
  | 'complete_on_time'
  | 'complete_irregular'
  | 'missed_meals'
  | 'no_meals'

export interface MealRhythmSchedule {
  id: string
  slot: MealSlot
  time: string
}

export interface MealRhythmDay {
  date: string
  time_zone: string
  finalized: boolean
  expected_meals: number
  logged_meals: number
  scheduled_times: MealRhythmSchedule[]
  meal_times: string[]
  first_meal_at: string | null
  last_meal_at: string | null
  completion_score: number
  timing_score: number | null
  rhythm_score: number
  verdict: MealRhythmVerdict
  updated_at: string
}

export type MealRhythmHistory = Record<string, MealRhythmDay>

function round(value: number): number {
  return Math.round(value)
}

function clockDistance(left: string, right: string): number {
  const distance = Math.abs(clockToMinute(left) - clockToMinute(right))
  return Math.min(distance, 24 * 60 - distance)
}

function validDate(value: unknown): value is string {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
}

function validClock(value: unknown): value is string {
  if (typeof value !== 'string' || !/^\d{2}:\d{2}$/.test(value)) return false
  const [hour, minute] = value.split(':').map(Number)
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
}

function semanticRecord(record: MealRhythmDay): Omit<MealRhythmDay, 'updated_at'> {
  const { updated_at: _updatedAt, ...semantic } = record
  return semantic
}

function sameSemanticRecord(left: MealRhythmDay | undefined, right: MealRhythmDay): boolean {
  return Boolean(left && JSON.stringify(semanticRecord(left)) === JSON.stringify(semanticRecord(right)))
}

export function normalizeMealRhythmHistory(value: unknown): MealRhythmHistory {
  if (!value || typeof value !== 'object') return {}
  const normalized: MealRhythmHistory = {}
  for (const [key, candidate] of Object.entries(value)) {
    if (!validDate(key) || !candidate || typeof candidate !== 'object') continue
    const record = candidate as Partial<MealRhythmDay>
    const scheduledTimes = Array.isArray(record.scheduled_times)
      ? record.scheduled_times.flatMap((entry) => (
          entry
          && typeof entry.id === 'string'
          && typeof entry.slot === 'string'
          && ['breakfast', 'lunch', 'dinner', 'snack'].includes(entry.slot)
          && validClock(entry.time)
            ? [{ id: entry.id, slot: entry.slot as MealSlot, time: entry.time }]
            : []
        )).slice(0, 20)
      : []
    const mealTimes = Array.isArray(record.meal_times)
      ? record.meal_times.filter(validClock).slice(0, 30)
      : []
    const expected = Math.max(0, Math.min(20, Math.round(Number(record.expected_meals) || scheduledTimes.length)))
    const logged = Math.max(0, Math.min(30, Math.round(Number(record.logged_meals) || mealTimes.length)))
    const completion = Math.max(0, Math.min(100, Math.round(Number(record.completion_score) || 0)))
    const timing = record.timing_score == null || !Number.isFinite(Number(record.timing_score))
      ? null
      : Math.max(0, Math.min(100, Math.round(Number(record.timing_score))))
    const rhythm = Math.max(0, Math.min(100, Math.round(Number(record.rhythm_score) || 0)))
    const verdict = ['open', 'complete_on_time', 'complete_irregular', 'missed_meals', 'no_meals'].includes(record.verdict ?? '')
      ? record.verdict as MealRhythmVerdict
      : record.finalized ? (logged === 0 ? 'no_meals' : logged < expected ? 'missed_meals' : 'complete_irregular') : 'open'
    normalized[key] = {
      date: key,
      time_zone: typeof record.time_zone === 'string' ? record.time_zone : 'UTC',
      finalized: record.finalized === true,
      expected_meals: expected,
      logged_meals: logged,
      scheduled_times: scheduledTimes,
      meal_times: mealTimes,
      first_meal_at: validClock(record.first_meal_at) ? record.first_meal_at : mealTimes[0] ?? null,
      last_meal_at: validClock(record.last_meal_at) ? record.last_meal_at : mealTimes.at(-1) ?? null,
      completion_score: completion,
      timing_score: timing,
      rhythm_score: rhythm,
      verdict,
      updated_at: typeof record.updated_at === 'string' && Number.isFinite(Date.parse(record.updated_at))
        ? new Date(record.updated_at).toISOString()
        : new Date(0).toISOString(),
    }
  }
  return Object.fromEntries(Object.entries(normalized).sort(([left], [right]) => right.localeCompare(left)).slice(0, 730))
}

export function buildMealRhythmDay(input: {
  date: string
  meals: LoggedMeal[]
  settings: Settings
  today: string
  existing?: MealRhythmDay
  now?: string
}): MealRhythmDay {
  const timeZone = timeZoneFromSettings(input.settings)
  const mealBlocks = normalizeMealBlockSettings(input.settings.addons.meal_blocks)
  const meals = input.meals
    .filter((meal) => meal.local_date === input.date)
    .slice()
    .sort((left, right) => left.logged_at.localeCompare(right.logged_at))
  const standardStatuses = resolveMealBlockStatuses({
    settings: mealBlocks,
    loggedMeals: meals,
  })
  const schedule: MealRhythmSchedule[] = [
    ...standardStatuses.map((status) => ({
      id: status.block.id,
      slot: mealSlotForBlock(status.block.kind),
      time: status.block.time,
    })),
    ...mealBlocks.custom_blocks.filter((block) => block.enabled).map((block) => ({
      id: block.id,
      slot: block.slot,
      time: block.time,
    })),
  ].sort((left, right) => left.time.localeCompare(right.time))

  const matched: Array<{ expected: MealRhythmSchedule; meal: LoggedMeal }> = []
  for (const status of standardStatuses) {
    if (!status.loggedMeal) continue
    matched.push({
      expected: {
        id: status.block.id,
        slot: mealSlotForBlock(status.block.kind),
        time: status.block.time,
      },
      meal: status.loggedMeal,
    })
  }
  for (const block of mealBlocks.custom_blocks.filter((candidate) => candidate.enabled)) {
    const meal = meals.find((candidate) => mealMomentIdFromIdempotencyKey(candidate.client_idempotency_key) === block.id)
    if (meal) matched.push({ expected: { id: block.id, slot: block.slot, time: block.time }, meal })
  }

  const mealTimes = meals.map((meal) => zonedClock(meal.logged_at, timeZone).time).sort()
  const expectedMeals = schedule.length
  const loggedMeals = Math.min(expectedMeals, matched.length)
  const completionScore = expectedMeals === 0 ? 100 : round((loggedMeals / expectedMeals) * 100)
  const deviations = matched.map(({ expected, meal }) => (
    clockDistance(expected.time, zonedClock(meal.logged_at, timeZone).time)
  ))
  const timingScore = deviations.length
    ? round(deviations.reduce((sum, minutes) => sum + Math.max(0, 100 - minutes / 1.2), 0) / deviations.length)
    : null
  const rhythmScore = round(completionScore * 0.72 + (timingScore ?? 0) * 0.28)
  const finalized = input.date < input.today
  const verdict: MealRhythmVerdict = !finalized
    ? 'open'
    : loggedMeals === 0
      ? 'no_meals'
      : loggedMeals < expectedMeals
        ? 'missed_meals'
        : (timingScore ?? 0) >= 70
          ? 'complete_on_time'
          : 'complete_irregular'
  const next: MealRhythmDay = {
    date: input.date,
    time_zone: timeZone,
    finalized,
    expected_meals: expectedMeals,
    logged_meals: loggedMeals,
    scheduled_times: schedule,
    meal_times: mealTimes,
    first_meal_at: mealTimes[0] ?? null,
    last_meal_at: mealTimes.at(-1) ?? null,
    completion_score: completionScore,
    timing_score: timingScore,
    rhythm_score: rhythmScore,
    verdict,
    updated_at: input.now ?? new Date().toISOString(),
  }
  return sameSemanticRecord(input.existing, next) ? input.existing! : next
}

export function mealRhythmRefreshDates(input: {
  today: string
  baselineDate?: string | null
  knownDates?: string[]
  maximumDays?: number
}): string[] {
  if (!validDate(input.today)) return []
  const maximumDays = Math.max(1, Math.min(730, Math.round(input.maximumDays ?? 730)))
  const cutoff = new Date(`${input.today}T12:00:00Z`)
  cutoff.setUTCDate(cutoff.getUTCDate() - (maximumDays - 1))
  const cutoffDate = cutoff.toISOString().slice(0, 10)
  const candidates = [
    input.baselineDate,
    ...(input.knownDates ?? []),
  ].filter((date): date is string => validDate(date) && date <= input.today)
  const earliest = candidates.sort()[0] ?? input.today
  const start = earliest < cutoffDate ? cutoffDate : earliest
  const dates: string[] = []
  const cursor = new Date(`${start}T12:00:00Z`)
  const end = new Date(`${input.today}T12:00:00Z`)
  while (cursor <= end && dates.length < maximumDays) {
    dates.push(cursor.toISOString().slice(0, 10))
    cursor.setUTCDate(cursor.getUTCDate() + 1)
  }
  return dates
}

export function averageClosedMealRhythm(history: unknown, fromDate: string): number | null {
  const days = Object.values(normalizeMealRhythmHistory(history))
    .filter((day) => day.finalized && day.date >= fromDate)
  if (!days.length) return null
  return round(days.reduce((sum, day) => sum + day.rhythm_score, 0) / days.length)
}
