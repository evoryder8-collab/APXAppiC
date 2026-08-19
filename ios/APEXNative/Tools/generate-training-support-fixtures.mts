/*
 * Golden parity fixtures for WeightTrend and ExerciseGuidance.
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-training-support-fixtures.mts
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { buildWeightTrend, weightTrendChange, type WeightTrendRange } from '../../../src/lib/weightTrend.ts'
import { exerciseExecutionCue } from '../../../src/lib/exerciseGuidance.ts'
import type { IntroLanguage } from '../../../src/lib/introLanguage.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = join(HERE, '..', 'APEXTests', 'Fixtures', 'training-support-parity.json')

/* A month of weigh-ins with the awkward cases in it: a duplicate date, a
   value below the plausible band, one above it, and a gap. */
const logs = [
  { date: '2026-07-05', weight_kg: 74.4 },
  { date: '2026-07-12', weight_kg: 74.0 },
  { date: '2026-07-20', weight_kg: 3 },
  { date: '2026-07-21', weight_kg: 402 },
  { date: '2026-07-26', weight_kg: 73.55 },
  { date: '2026-08-02', weight_kg: 73.2 },
  { date: '2026-08-02', weight_kg: 73.1 },
  { date: '2026-08-09', weight_kg: 72.85 },
  { date: '2026-08-16', weight_kg: 72.6 },
  { date: '2026-08-20', weight_kg: 72.4 },
]

const ranges: WeightTrendRange[] = [7, 30, 90, 365]
const anchor = '2026-08-19'

/* Names chosen for the ordering traps: each of these contains a word that an
   earlier, more general entry would otherwise swallow. */
const exercises = [
  'Leg curl', 'Seated leg curl', 'Biceps curl', 'Hammer curl',
  'Bulgarian split squat', 'Back squat', 'Goblet squat',
  'Romanian deadlift', 'RDL', 'Conventional deadlift',
  'Hip thrust', 'Walking lunge', 'Standing calf raise',
  'Pull-up', 'Chin up', 'Barbell row', 'Push-up', 'Overhead press',
  'Face pull', 'Side plank', 'Focus T25 Alpha Cardio',
  'Something entirely unlisted',
]
const languages: IntroLanguage[] = ['en', 'ro', 'th']

mkdirSync(dirname(OUT), { recursive: true })
writeFileSync(OUT, `${JSON.stringify({
  weight: {
    anchor,
    logs,
    ranges: ranges.map((range) => {
      const points = buildWeightTrend(logs, anchor, range)
      return {
        range,
        points: points.map((point) => ({ date: point.date, weight_kg: point.weightKg })),
        change: weightTrendChange(points),
      }
    }),
  },
  cues: exercises.map((name) => ({
    name,
    en: exerciseExecutionCue(name, 'en'),
    ro: exerciseExecutionCue(name, 'ro'),
    th: exerciseExecutionCue(name, 'th'),
  })),
  languages,
}, null, 2)}\n`)
console.log(`wrote ${OUT}`)
