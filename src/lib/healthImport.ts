/*
 * Apple Health export.xml importer. The file can be close to a gigabyte, so
 * it is stream-parsed line by line, never loaded whole. Import policy for
 * days without the watch or phone: absence of data never penalizes anything.
 * Imports are positive signals only, and manual entries in APEX always win
 * over imported values.
 */
import type {
  AppData,
  DailyLog,
  HealthMetric,
  ImportedActivity,
  ImportedActivityKind,
} from './types'
import { dailyLogId, healthMetricId } from './ids'

export interface ParsedHealth {
  nutrition: Map<string, { kcal: number; protein: number; fat: number; carbs: number }>
  water: Map<string, number> // liters per date
  weight: Map<string, number> // kg, last of day
  vo2max: Map<string, number>
  restingHr: Map<string, number>
  workouts: Array<{ date: string; activity: string; kind: ImportedActivityKind; durationMin: number; source: string }>
  linesScanned: number
}

const ACTIVITY_KIND: Record<string, ImportedActivityKind> = {
  TraditionalStrengthTraining: 'strength',
  FunctionalStrengthTraining: 'strength',
  CoreTraining: 'strength',
  HighIntensityIntervalTraining: 'endurance',
  Running: 'endurance',
  Cycling: 'endurance',
  Swimming: 'endurance',
  Rowing: 'endurance',
  Elliptical: 'endurance',
  StairClimbing: 'endurance',
  JumpRope: 'endurance',
  CrossTraining: 'endurance',
  MixedCardio: 'endurance',
  Hiking: 'endurance',
  WaterSports: 'endurance',
  Yoga: 'mobility',
  Flexibility: 'mobility',
  MindAndBody: 'mobility',
  Pilates: 'mobility',
}

const MIN_WORKOUT_MIN = 8

function attr(line: string, name: string): string | null {
  const i = line.indexOf(name + '="')
  if (i < 0) return null
  const start = i + name.length + 2
  const end = line.indexOf('"', start)
  return end < 0 ? null : line.slice(start, end)
}

function litersOf(value: number, unit: string | null): number {
  if (unit === 'mL' || unit === 'ml') return value / 1000
  if (unit === 'fl_oz_us') return value * 0.0295735
  return value // assume L
}

function kgOf(value: number, unit: string | null): number {
  if (unit === 'lb') return value * 0.453592
  return value
}

/* Needles checked with indexOf before any parsing, for throughput. */
const NEEDLES = [
  'DietaryEnergyConsumed',
  'DietaryProtein',
  'DietaryFatTotal',
  'DietaryCarbohydrates',
  'DietaryWater',
  'BodyMass"',
  'VO2Max',
  'RestingHeartRate',
  '<Workout ',
] as const

export function createHealthParser(): {
  feed: (chunk: string) => void
  finish: () => ParsedHealth
} {
  const out: ParsedHealth = {
    nutrition: new Map(),
    water: new Map(),
    weight: new Map(),
    vo2max: new Map(),
    restingHr: new Map(),
    workouts: [],
    linesScanned: 0,
  }
  let carry = ''

  const nut = (date: string) => {
    let n = out.nutrition.get(date)
    if (!n) {
      n = { kcal: 0, protein: 0, fat: 0, carbs: 0 }
      out.nutrition.set(date, n)
    }
    return n
  }

  const handleLine = (line: string): void => {
    out.linesScanned += 1
    let matched: (typeof NEEDLES)[number] | null = null
    for (const needle of NEEDLES) {
      if (line.includes(needle)) {
        matched = needle
        break
      }
    }
    if (!matched) return

    const date = attr(line, 'startDate')?.slice(0, 10)
    if (!date) return

    if (matched === '<Workout ') {
      const raw = attr(line, 'workoutActivityType')?.replace('HKWorkoutActivityType', '') ?? ''
      const kind = ACTIVITY_KIND[raw]
      if (!kind) return
      const dur = parseFloat(attr(line, 'duration') ?? '0')
      const unit = attr(line, 'durationUnit')
      const minutes = unit === 'min' ? dur : unit === 's' ? dur / 60 : unit === 'hr' ? dur * 60 : dur
      if (!(minutes >= MIN_WORKOUT_MIN)) return
      out.workouts.push({
        date,
        activity: raw,
        kind,
        durationMin: Math.round(minutes),
        source: attr(line, 'sourceName') ?? 'Apple Health',
      })
      return
    }

    const value = parseFloat(attr(line, 'value') ?? '')
    if (!Number.isFinite(value)) return
    const unit = attr(line, 'unit')

    switch (matched) {
      case 'DietaryEnergyConsumed':
        nut(date).kcal += value
        break
      case 'DietaryProtein':
        nut(date).protein += value
        break
      case 'DietaryFatTotal':
        nut(date).fat += value
        break
      case 'DietaryCarbohydrates':
        nut(date).carbs += value
        break
      case 'DietaryWater':
        out.water.set(date, (out.water.get(date) ?? 0) + litersOf(value, unit))
        break
      case 'BodyMass"':
        out.weight.set(date, kgOf(value, unit))
        break
      case 'VO2Max':
        out.vo2max.set(date, value)
        break
      case 'RestingHeartRate':
        out.restingHr.set(date, value)
        break
    }
  }

  return {
    feed(chunk: string) {
      const text = carry + chunk
      const lines = text.split('\n')
      carry = lines.pop() ?? ''
      for (const line of lines) handleLine(line)
    },
    finish() {
      if (carry) handleLine(carry)
      carry = ''
      return out
    },
  }
}

export async function parseHealthFile(
  file: File,
  onProgress?: (fraction: number) => void,
): Promise<ParsedHealth> {
  const parser = createHealthParser()
  const reader = file.stream().getReader()
  const decoder = new TextDecoder()
  let read = 0
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    read += value.byteLength
    parser.feed(decoder.decode(value, { stream: true }))
    onProgress?.(Math.min(0.99, read / file.size))
    /* yield to the UI thread between chunks */
    await new Promise((r) => setTimeout(r, 0))
  }
  parser.feed(decoder.decode())
  onProgress?.(1)
  return parser.finish()
}

/* ---------------- merge into the store ---------------- */

export interface ImportResult {
  dailyLogsTouched: number
  metricsTouched: number
  workoutsAdded: number
  latestWeight: number | null
  latestVo2max: number | null
  dateRange: [string, string] | null
}

export function buildImportRows(
  data: AppData,
  parsed: ParsedHealth,
): {
  dailyLogs: DailyLog[]
  metrics: HealthMetric[]
  activities: ImportedActivity[]
  result: ImportResult
} {
  const userId = data.profile?.user_id ?? ''
  const byDate = new Map(data.daily_logs.map((d) => [d.date, d]))
  const dailyLogs: DailyLog[] = []

  const dates = new Set<string>([...parsed.nutrition.keys(), ...parsed.water.keys()])
  for (const date of dates) {
    const existing = byDate.get(date)
    const n = parsed.nutrition.get(date)
    const w = parsed.water.get(date)
    const next: DailyLog = existing
      ? { ...existing }
      : {
          id: dailyLogId(date, userId),
          user_id: userId,
          date,
          kcal: null,
          protein_g: null,
          fat_g: null,
          carbs_g: null,
          water_l: 0,
        }
    let changed = false
    /* manual entries always win: only fill fields that are still empty */
    if (n && n.kcal > 0 && next.kcal == null) {
      next.kcal = Math.round(n.kcal)
      next.protein_g = next.protein_g ?? Math.round(n.protein)
      next.fat_g = next.fat_g ?? Math.round(n.fat)
      next.carbs_g = next.carbs_g ?? Math.round(n.carbs)
      changed = true
    }
    if (w != null && w > next.water_l) {
      next.water_l = Math.round(w * 4) / 4
      changed = true
    }
    if (changed) dailyLogs.push(next)
  }

  const metricDates = new Set<string>([
    ...parsed.weight.keys(),
    ...parsed.vo2max.keys(),
    ...parsed.restingHr.keys(),
  ])
  const existingMetrics = new Map(data.health_metrics.map((m) => [m.date, m]))
  const metrics: HealthMetric[] = []
  for (const date of metricDates) {
    const prev = existingMetrics.get(date)
    const row: HealthMetric = {
      id: prev?.id ?? healthMetricId(date, userId),
      user_id: userId,
      date,
      weight_kg: parsed.weight.get(date) ?? prev?.weight_kg ?? null,
      vo2max: parsed.vo2max.get(date) ?? prev?.vo2max ?? null,
      resting_hr: parsed.restingHr.get(date) ?? prev?.resting_hr ?? null,
    }
    if (
      !prev ||
      prev.weight_kg !== row.weight_kg ||
      prev.vo2max !== row.vo2max ||
      prev.resting_hr !== row.resting_hr
    ) {
      metrics.push(row)
    }
  }

  /* re-import safe: skip workouts already present (same date + kind + duration) */
  const seen = new Set(
    data.imported_activities.map((a) => `${a.date}|${a.kind}|${a.duration_min}`),
  )
  const activities: ImportedActivity[] = []
  for (const w of parsed.workouts) {
    const key = `${w.date}|${w.kind}|${w.durationMin}`
    if (seen.has(key)) continue
    seen.add(key)
    activities.push({
      id: crypto.randomUUID(),
      user_id: userId,
      date: w.date,
      kind: w.kind,
      activity: w.activity,
      duration_min: w.durationMin,
      source: w.source,
    })
  }

  const weightDates = [...parsed.weight.keys()].sort()
  const voDates = [...parsed.vo2max.keys()].sort()
  const allDates = [...dates, ...metricDates].sort()
  return {
    dailyLogs,
    metrics,
    activities,
    result: {
      dailyLogsTouched: dailyLogs.length,
      metricsTouched: metrics.length,
      workoutsAdded: activities.length,
      latestWeight: weightDates.length ? (parsed.weight.get(weightDates[weightDates.length - 1]) ?? null) : null,
      latestVo2max: voDates.length ? (parsed.vo2max.get(voDates[voDates.length - 1]) ?? null) : null,
      dateRange: allDates.length ? [allDates[0], allDates[allDates.length - 1]] : null,
    },
  }
}
