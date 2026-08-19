/*
 * Golden parity fixtures for the native HealthImport merge policy.
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-health-import-fixtures.mts
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { buildImportRows, type ParsedHealth } from '../../../src/lib/healthImport.ts'
import type { AppData } from '../../../src/lib/types.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = join(HERE, '..', 'APEXTests', 'Fixtures', 'health-import-parity.json')

const USER = '99999999-0000-4000-8000-000000000001'

/* The day APEX already knows about by hand, the day it half knows, and the
   day it has never seen. Each exercises a different branch of the policy. */
const existingDailyLogs = [
  {
    id: 'aaaa1111-0000-4000-8000-000000000001', user_id: USER, date: '2026-08-10',
    kcal: 2100, protein_g: 170, fat_g: 60, carbs_g: 210, water_l: 2.5,
    estimated_tdee: null, computed_pal: null, activity_mode: 'quick', weight_kg: null,
  },
  {
    id: 'aaaa1111-0000-4000-8000-000000000002', user_id: USER, date: '2026-08-11',
    kcal: null, protein_g: 99, fat_g: null, carbs_g: null, water_l: 0.5,
    estimated_tdee: null, computed_pal: null, activity_mode: 'quick', weight_kg: null,
  },
]

const existingMetrics = [
  { id: 'bbbb1111-0000-4000-8000-000000000001', user_id: USER, date: '2026-08-10', weight_kg: 72.4, vo2max: null, resting_hr: 52 },
]

const existingActivities = [
  { id: 'cccc1111-0000-4000-8000-000000000001', user_id: USER, date: '2026-08-10', kind: 'strength', activity: 'TraditionalStrengthTraining', duration_min: 55, source: 'Apple Watch' },
]

const parsed: ParsedHealth = {
  nutrition: new Map([
    // A day already logged by hand: the import must not overwrite it.
    ['2026-08-10', { kcal: 1800, protein: 120, fat: 50, carbs: 190 }],
    // Half logged: kcal is empty so it fills, protein is not so it stays.
    ['2026-08-11', { kcal: 2400, protein: 180, fat: 70, carbs: 250 }],
    // Never seen.
    ['2026-08-12', { kcal: 2200, protein: 165, fat: 62, carbs: 230 }],
    // Zero energy is not a meal and must not create a row.
    ['2026-08-13', { kcal: 0, protein: 0, fat: 0, carbs: 0 }],
  ]),
  water: new Map([
    // Lower than the manual figure: water must not fall.
    ['2026-08-10', 1.2],
    // Higher: it rises, rounded to the quarter litre.
    ['2026-08-11', 2.13],
    ['2026-08-12', 3.0],
  ]),
  weight: new Map([['2026-08-10', 72.1], ['2026-08-12', 71.9]]),
  vo2max: new Map([['2026-08-12', 48.5]]),
  restingHr: new Map([['2026-08-12', 49]]),
  workouts: [
    // Already recorded: same date, kind and duration.
    { date: '2026-08-10', activity: 'TraditionalStrengthTraining', kind: 'strength', durationMin: 55, source: 'Apple Watch' },
    { date: '2026-08-12', activity: 'Running', kind: 'endurance', durationMin: 42, source: 'Apple Watch' },
    // Same day and kind, different length: a genuinely separate session.
    { date: '2026-08-12', activity: 'Yoga', kind: 'mobility', durationMin: 20, source: 'iPhone' },
  ],
  linesScanned: 0,
}

const data = {
  profile: { user_id: USER },
  daily_logs: existingDailyLogs,
  health_metrics: existingMetrics,
  imported_activities: existingActivities,
} as unknown as AppData

const built = buildImportRows(data, parsed)

mkdirSync(dirname(OUT), { recursive: true })
writeFileSync(OUT, `${JSON.stringify({
  user_id: USER,
  existing: { daily_logs: existingDailyLogs, metrics: existingMetrics, activities: existingActivities },
  parsed: {
    nutrition: [...parsed.nutrition.entries()].map(([date, value]) => ({ date, ...value })),
    water: [...parsed.water.entries()].map(([date, litres]) => ({ date, litres })),
    weight: [...parsed.weight.entries()].map(([date, kg]) => ({ date, kg })),
    vo2max: [...parsed.vo2max.entries()].map(([date, value]) => ({ date, value })),
    resting_hr: [...parsed.restingHr.entries()].map(([date, value]) => ({ date, value })),
    workouts: parsed.workouts,
  },
  expected: {
    daily_logs: built.dailyLogs.map((row) => ({
      date: row.date, kcal: row.kcal, protein_g: row.protein_g,
      fat_g: row.fat_g, carbs_g: row.carbs_g, water_l: row.water_l,
    })).sort((a, b) => a.date.localeCompare(b.date)),
    metrics: built.metrics.map((row) => ({
      date: row.date, weight_kg: row.weight_kg, vo2max: row.vo2max, resting_hr: row.resting_hr,
    })).sort((a, b) => a.date.localeCompare(b.date)),
    activities: built.activities.map((row) => ({
      date: row.date, kind: row.kind, activity: row.activity, duration_min: row.duration_min, source: row.source,
    })).sort((a, b) => a.date.localeCompare(b.date) || a.activity.localeCompare(b.activity)),
    result: built.result,
  },
}, null, 2)}\n`)
console.log(`wrote ${OUT}`)
