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

export interface TimeZoneOption {
  zone: string
  city: string
  countries: string[]
  label: string
  offset: string
  searchText: string
}

export interface DaylineLabelAnchor {
  key: string
  minute: number
  height: number
}

export interface TimedMeal {
  meal: LoggedMeal
  time: string
  minute: number
  lineMinute: number
  recorded: boolean
  timingSource: 'recorded_finish' | 'scheduled'
  finishedAt: string | null
  comfortMinute: number
  comfortLineMinute: number
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
export type MealStartLog = NonNullable<Settings['addons']['meal_start_times']>[string]
export type MealTimelineSnapMinutes = NonNullable<Settings['addons']['meal_timeline_snap_minutes']>
export type MealDaylineDensity = NonNullable<Settings['addons']['meal_dayline_density']>

export const MEAL_TIMELINE_SNAP_OPTIONS = [5, 15, 30, 60] as const
export const MEAL_DAYLINE_DENSITY_OPTIONS = ['compact', 'medium', 'long'] as const

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
  mealFinishedAt: string | null
  gapMinutes: number | null
  timingScore: number | null
  source: 'recorded_finish' | 'missing'
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

export function normalizeMealStartTimes(value: unknown): Record<string, MealStartLog> {
  if (!value || typeof value !== 'object') return {}
  const normalized: Record<string, MealStartLog> = {}
  for (const [mealId, candidate] of Object.entries(value)) {
    if (!mealId || !candidate || typeof candidate !== 'object') continue
    const record = candidate as Partial<MealStartLog>
    if (typeof record.started_at !== 'string' || !Number.isFinite(Date.parse(record.started_at))) continue
    const updatedAt = typeof record.updated_at === 'string' && Number.isFinite(Date.parse(record.updated_at))
      ? record.updated_at
      : record.started_at
    normalized[mealId] = {
      started_at: new Date(record.started_at).toISOString(),
      updated_at: new Date(updatedAt).toISOString(),
    }
  }
  return Object.fromEntries(Object.entries(normalized)
    .sort((left, right) => right[1].updated_at.localeCompare(left[1].updated_at))
    .slice(0, 730))
}

export function normalizeMealTimelineSnap(value: unknown): MealTimelineSnapMinutes {
  const parsed = Number(value)
  return MEAL_TIMELINE_SNAP_OPTIONS.includes(parsed as MealTimelineSnapMinutes)
    ? parsed as MealTimelineSnapMinutes
    : 30
}

export function normalizeMealDaylineDensity(value: unknown): MealDaylineDensity {
  return MEAL_DAYLINE_DENSITY_OPTIONS.includes(value as MealDaylineDensity)
    ? value as MealDaylineDensity
    : 'medium'
}

/**
 * A full 24-hour line needs enough physical distance for a two-hour guidance
 * band to remain legible on a phone. `compactPresentation` only trims the
 * surrounding card chrome; density remains a user preference in both views.
 */
export function mealDaylineHeight(
  density: MealDaylineDensity,
  compactPresentation: boolean,
  itemCount: number,
): number {
  const resolved = normalizeMealDaylineDensity(density)
  const base = compactPresentation
    ? { compact: 560, medium: 780, long: 1_040 }[resolved]
    : { compact: 640, medium: 860, long: 1_140 }[resolved]
  const itemGap = { compact: 72, medium: 80, long: 90 }[resolved]
  return Math.max(base, Math.max(0, itemCount) * itemGap)
}

export function mealStartStorageKey(meal: Pick<
  LoggedMeal,
  'id' | 'local_date' | 'meal_slot' | 'client_idempotency_key' | 'source_planned_meal_id' | 'source_preset_id'
>): string {
  const marker = 'apex-meal-block='
  const markerIndex = meal.client_idempotency_key.lastIndexOf(marker)
  const moment = markerIndex >= 0
    ? meal.client_idempotency_key.slice(markerIndex + marker.length).split('|')[0]
    : ''
  if (moment) return `${meal.local_date}|moment:${moment}`
  if (meal.source_planned_meal_id) return `${meal.local_date}|planned:${meal.source_planned_meal_id}`
  if (meal.source_preset_id) return `${meal.local_date}|${meal.meal_slot}|preset:${meal.source_preset_id}`
  return `meal:${meal.id}`
}

export function snapDaylineMinute(
  lineMinute: number,
  increment: MealTimelineSnapMinutes,
): number {
  const bounded = Math.max(DAYLINE_START_MINUTE, Math.min(DAYLINE_END_MINUTE - 1, lineMinute))
  const snapped = Math.round(bounded / increment) * increment
  const lastStep = Math.floor((DAYLINE_END_MINUTE - 1) / increment) * increment
  return Math.max(DAYLINE_START_MINUTE, Math.min(lastStep, snapped))
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

const FALLBACK_REGION_ZONES: Record<string, string[]> = {
  CH: ['Europe/Zurich'],
  RO: ['Europe/Bucharest'],
  TH: ['Asia/Bangkok'],
  GB: ['Europe/London'],
  IE: ['Europe/Dublin'],
  US: ['America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles', 'America/Phoenix', 'Pacific/Honolulu', 'America/Anchorage'],
  CA: ['America/Toronto', 'America/Vancouver', 'America/Edmonton', 'America/Halifax', 'America/Winnipeg', 'America/St_Johns'],
  AU: ['Australia/Sydney', 'Australia/Melbourne', 'Australia/Brisbane', 'Australia/Adelaide', 'Australia/Perth'],
  NZ: ['Pacific/Auckland'],
  DE: ['Europe/Berlin'],
  AT: ['Europe/Vienna'],
  FR: ['Europe/Paris'],
  IT: ['Europe/Rome'],
  ES: ['Europe/Madrid', 'Atlantic/Canary'],
  PT: ['Europe/Lisbon', 'Atlantic/Azores'],
  NL: ['Europe/Amsterdam'],
  BE: ['Europe/Brussels'],
  DK: ['Europe/Copenhagen'],
  SE: ['Europe/Stockholm'],
  NO: ['Europe/Oslo'],
  FI: ['Europe/Helsinki'],
  PL: ['Europe/Warsaw'],
  GR: ['Europe/Athens'],
  TR: ['Europe/Istanbul'],
  UA: ['Europe/Kyiv'],
  AE: ['Asia/Dubai'],
  IN: ['Asia/Calcutta'],
  SG: ['Asia/Singapore'],
  MY: ['Asia/Kuala_Lumpur'],
  ID: ['Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura'],
  PH: ['Asia/Manila'],
  VN: ['Asia/Ho_Chi_Minh'],
  JP: ['Asia/Tokyo'],
  KR: ['Asia/Seoul'],
  CN: ['Asia/Shanghai'],
  HK: ['Asia/Hong_Kong'],
  TW: ['Asia/Taipei'],
  ZA: ['Africa/Johannesburg'],
  EG: ['Africa/Cairo'],
  BR: ['America/Sao_Paulo', 'America/Manaus', 'America/Belem'],
  MX: ['America/Mexico_City', 'America/Tijuana', 'America/Cancun'],
  AR: ['America/Buenos_Aires'],
}

const timeZoneOptionCache = new Map<string, TimeZoneOption[]>()

function normalizedSearchText(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase()
    .replace(/[._/()-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

function countryZones(): Map<string, string[]> {
  const byRegion = new Map<string, string[]>()
  for (const [region, zones] of Object.entries(FALLBACK_REGION_ZONES)) byRegion.set(region, zones)
  for (let first = 65; first <= 90; first += 1) {
    for (let second = 65; second <= 90; second += 1) {
      const region = String.fromCharCode(first, second)
      try {
        const locale = new Intl.Locale(`und-${region}`) as Intl.Locale & { timeZones?: readonly string[] }
        const zones = locale.timeZones
        if (zones?.length) byRegion.set(region, [...zones])
      } catch {
        // Reserved two-letter combinations are intentionally skipped.
      }
    }
  }
  return byRegion
}

function timeZoneOffset(zone: string, locale: string): string {
  try {
    const part = new Intl.DateTimeFormat(locale, {
      timeZone: zone,
      timeZoneName: 'shortOffset',
    }).formatToParts(new Date()).find((candidate) => candidate.type === 'timeZoneName')
    return part?.value ?? ''
  } catch {
    return ''
  }
}

/**
 * Builds a searchable catalogue from the runtime's complete IANA database.
 * Where supported, Intl.Locale supplies the country-to-timezone relationship,
 * so users can search "Thailand", "România", "ประเทศไทย", a city, or an IANA
 * identifier without shipping a second timezone database.
 */
export function supportedTimeZoneOptions(locale = 'en'): TimeZoneOption[] {
  const localeKey = locale === 'ro' || locale === 'th' ? locale : 'en'
  const cached = timeZoneOptionCache.get(localeKey)
  if (cached) return cached
  const zones = supportedTimeZones()
  const zoneSet = new Set(zones)
  const localizedNames = new Intl.DisplayNames([localeKey], { type: 'region' })
  const englishNames = new Intl.DisplayNames(['en'], { type: 'region' })
  const namesByZone = new Map<string, Set<string>>()
  const searchNamesByZone = new Map<string, Set<string>>()

  for (const [region, regionZones] of countryZones()) {
    const localized = localizedNames.of(region)
    const english = englishNames.of(region)
    if (!localized || !english || localized === region || english === region) continue
    for (const zone of regionZones) {
      if (!zoneSet.has(zone)) continue
      const visible = namesByZone.get(zone) ?? new Set<string>()
      visible.add(localized)
      namesByZone.set(zone, visible)
      const searchable = searchNamesByZone.get(zone) ?? new Set<string>()
      searchable.add(localized)
      searchable.add(english)
      searchable.add(region)
      searchNamesByZone.set(zone, searchable)
    }
  }

  const options = zones.map((zone): TimeZoneOption => {
    const pieces = zone.split('/')
    const city = (pieces.at(-1) ?? zone).replaceAll('_', ' ')
    const area = pieces.slice(0, -1).join(' ').replaceAll('_', ' ')
    const countries = [...(namesByZone.get(zone) ?? [])].sort((left, right) => left.localeCompare(right, localeKey))
    const countryLabel = countries.slice(0, 2).join(' / ')
    const label = countryLabel ? `${city}, ${countryLabel}` : `${city}, ${area}`
    const searchText = normalizedSearchText([
      zone,
      city,
      area,
      ...countries,
      ...(searchNamesByZone.get(zone) ?? []),
    ].join(' '))
    return {
      zone,
      city,
      countries,
      label,
      offset: timeZoneOffset(zone, localeKey),
      searchText,
    }
  }).sort((left, right) => left.label.localeCompare(right.label, localeKey))

  timeZoneOptionCache.set(localeKey, options)
  return options
}

export function searchTimeZoneOptions(
  query: string,
  locale = 'en',
  limit = 18,
): TimeZoneOption[] {
  const needle = normalizedSearchText(query)
  const options = supportedTimeZoneOptions(locale)
  if (!needle) {
    const preferred = new Set([
      detectedTimeZone(),
      'Europe/Zurich',
      'Europe/Bucharest',
      'Asia/Bangkok',
      'Europe/London',
      'America/New_York',
      'America/Los_Angeles',
      'Australia/Sydney',
    ])
    return [
      ...options.filter((option) => preferred.has(option.zone)),
      ...options.filter((option) => !preferred.has(option.zone)),
    ].slice(0, limit)
  }
  return options
    .map((option) => {
      const zone = normalizedSearchText(option.zone)
      const label = normalizedSearchText(option.label)
      const exact = zone === needle || label === needle
      const starts = zone.startsWith(needle) || label.startsWith(needle)
        || option.searchText.split(' ').some((token) => token.startsWith(needle))
      const contains = option.searchText.includes(needle)
      return { option, rank: exact ? 0 : starts ? 1 : contains ? 2 : 3 }
    })
    .filter((candidate) => candidate.rank < 3)
    .sort((left, right) => left.rank - right.rank || left.option.label.localeCompare(right.option.label, locale))
    .slice(0, Math.max(1, limit))
    .map((candidate) => candidate.option)
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

function shiftIsoDate(date: string, days: number): string {
  const [year, month, day] = date.split('-').map(Number)
  const shifted = new Date(Date.UTC(year, month - 1, day + days, 12, 0, 0, 0))
  return shifted.toISOString().slice(0, 10)
}

/**
 * A Dayline belongs to the date on which its 03:00 rail starts. Times from
 * midnight through 02:59 therefore live on the following calendar date while
 * remaining part of the selected training/nutrition day.
 */
export function daylineClockDate(date: string, time: string): string {
  return clockToMinute(time) < DAYLINE_START_MINUTE ? shiftIsoDate(date, 1) : date
}

export function daylineDateTimeToIso(date: string, time: string, timeZone: string): string {
  return zonedDateTimeToIso(daylineClockDate(date, time), time, timeZone)
}

export function daylineDateForInstant(value: Date | string, timeZone: string): string {
  const clock = zonedClock(value, timeZone)
  return clock.minute < DAYLINE_START_MINUTE ? shiftIsoDate(clock.date, -1) : clock.date
}

export function instantBelongsToDaylineDate(date: string, value: Date | string, timeZone: string): boolean {
  return daylineDateForInstant(value, timeZone) === date
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

/**
 * Meal cards and workout labels share the same side of the Dayline. Lay them
 * out as one collision group while their connector lines preserve the exact
 * event time on the rail.
 */
export function layoutDaylineLabels(
  anchors: readonly DaylineLabelAnchor[],
  height: number,
  compactPresentation = false,
): Map<string, number> {
  if (!anchors.length || height <= 0) return new Map()
  const edgeGap = compactPresentation ? 8 : 10
  const collisionGap = compactPresentation ? 8 : 10
  const ordered = anchors
    .map((anchor) => {
      const labelHeight = Math.max(20, anchor.height)
      return {
        ...anchor,
        height: labelHeight,
        half: labelHeight / 2,
        actual: daylineRatio(anchor.minute) * height,
      }
    })
    .sort((left, right) => left.actual - right.actual || left.key.localeCompare(right.key))
  const positions = ordered.map((anchor) => (
    Math.max(edgeGap + anchor.half, Math.min(height - edgeGap - anchor.half, anchor.actual))
  ))

  for (let index = 1; index < positions.length; index += 1) {
    const previous = ordered[index - 1]
    const current = ordered[index]
    positions[index] = Math.max(
      positions[index],
      positions[index - 1] + previous.half + current.half + collisionGap,
    )
  }

  const last = ordered.length - 1
  const lastLimit = height - edgeGap - ordered[last].half
  if (positions[last] > lastLimit) {
    positions[last] = lastLimit
    for (let index = last - 1; index >= 0; index -= 1) {
      const current = ordered[index]
      const next = ordered[index + 1]
      positions[index] = Math.min(
        positions[index],
        positions[index + 1] - current.half - next.half - collisionGap,
      )
    }
  }

  const firstLimit = edgeGap + ordered[0].half
  if (positions[0] < firstLimit) {
    positions[0] = firstLimit
    for (let index = 1; index < positions.length; index += 1) {
      const previous = ordered[index - 1]
      const current = ordered[index]
      positions[index] = Math.max(
        positions[index],
        positions[index - 1] + previous.half + current.half + collisionGap,
      )
    }
  }

  return new Map(ordered.map((anchor, index) => [anchor.key, positions[index]]))
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
  const finishedClock = zonedClock(meal.logged_at, timeZone)
  const finishedAt = instantBelongsToDaylineDate(meal.local_date, meal.logged_at, timeZone) ? meal.logged_at : null
  const timingSource = finishedAt ? 'recorded_finish' : 'scheduled'
  const time = finishedAt ? finishedClock.time : fallbackTime
  const minute = clockToMinute(time)
  const comfortMinute = minute
  return {
    meal,
    time,
    minute,
    lineMinute: toDaylineMinute(minute),
    recorded: timingSource !== 'scheduled',
    timingSource,
    finishedAt,
    comfortMinute,
    comfortLineMinute: toDaylineMinute(comfortMinute),
    window: mealComfortWindow(meal, mealFibre(meal.id, entries)),
  }
}

export function timedWorkout(session: WorkoutSession, timeZone: string): TimedWorkout | null {
  if (!session.completed || !session.completed_at) return null
  const completed = zonedClock(session.completed_at, timeZone)
  if (!instantBelongsToDaylineDate(session.date, session.completed_at, timeZone)) return null
  const started = session.started_at ? zonedClock(session.started_at, timeZone) : null
  return {
    session,
    startedTime: session.started_at && instantBelongsToDaylineDate(session.date, session.started_at, timeZone)
      ? started?.time ?? null
      : null,
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

export function resolvePostWorkoutNutrition(input: {
  sessions: readonly WorkoutSession[]
  meals: readonly LoggedMeal[]
  timeZone: string
  /** @deprecated Meal finish is now the only user-recorded timing signal. */
  recoveryNutrition?: Readonly<Record<string, RecoveryNutritionLog>>
  /** @deprecated Meal finish is now the only user-recorded timing signal. */
  mealStartTimes?: Readonly<Record<string, MealStartLog>>
}): PostWorkoutNutritionTiming[] {
  const { sessions, meals, timeZone } = input
  const completed = sessions
    .flatMap((session) => timedWorkout(session, timeZone) ? [session] : [])
    .sort((left, right) => Date.parse(left.completed_at ?? '') - Date.parse(right.completed_at ?? ''))

  return completed.map((session) => {
    const completedAt = session.completed_at!
    const finishedMeal = meals
      .filter((meal) => meal.local_date === session.date)
      .filter((meal) => {
        const gap = Date.parse(meal.logged_at) - Date.parse(completedAt)
        return gap >= 0 && gap <= 6 * 60 * 60 * 1_000
      })
      .sort((left, right) => Date.parse(left.logged_at) - Date.parse(right.logged_at))[0] ?? null
    if (finishedMeal) {
      const gapMinutes = Math.max(0, Math.round((Date.parse(finishedMeal.logged_at) - Date.parse(completedAt)) / 60_000))
      return {
        sessionId: session.id,
        date: session.date,
        completedAt,
        mealId: finishedMeal.id,
        mealName: finishedMeal.display_name,
        mealFinishedAt: finishedMeal.logged_at,
        gapMinutes,
        timingScore: recoveryTimingScore(gapMinutes),
        source: 'recorded_finish' as const,
      }
    }
    return {
      sessionId: session.id,
      date: session.date,
      completedAt,
      mealId: null,
      mealName: null,
      mealFinishedAt: null,
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

export function analyzeMealTiming(input: {
  meals: readonly LoggedMeal[]
  entries: readonly LoggedFoodEntry[]
  sessions: readonly WorkoutSession[]
  timeZone: string
  fallbackTimes?: Readonly<Record<string, string>>
  /** @deprecated Meal finish is now the only user-recorded timing signal. */
  recoveryNutrition?: Readonly<Record<string, RecoveryNutritionLog>>
  /** @deprecated Meal finish is now the only user-recorded timing signal. */
  mealStartTimes?: Readonly<Record<string, MealStartLog>>
}): MealTimingAnalysis {
  const {
    meals,
    entries,
    sessions,
    timeZone,
    fallbackTimes = {},
  } = input
  const timed = meals.map((meal) => timedMeal(
    meal,
    entries,
    timeZone,
    fallbackTimes[meal.id] ?? fallbackMealTime(meal),
  ))
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
  })
  const recordedRecovery = postWorkoutRelations.filter((relation) => relation.source === 'recorded_finish')
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
