import assert from 'node:assert/strict'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import test from 'node:test'
import { buildSeedData } from '../src/data/seed.ts'
import { planForDate } from '../src/lib/plan.ts'
import { repairSeedDefinitions } from '../src/lib/seedRepair.ts'
import {
  assessTrainingInput,
  generateTrainingPlan,
  isTrainingInductionEligible,
  searchEquipment,
  type TrainingInductionInput,
} from '../src/lib/trainingInduction.ts'

const userId = '19191919-aaaa-4bbb-8ccc-292929292929'

const baseInput: TrainingInductionInput = {
  start_date: '2026-07-15',
  inactivity: 'one_to_three_months',
  venue: 'home',
  equipment: ['adjustable_dumbbells', 'resistance_bands'],
  pain_areas: [],
  recent_operation: false,
  chronic_lower_back_pain: false,
  sessions_per_week: 3,
  goal: 'rebuild',
}

test('predictive equipment search finds both dumbbell formats from dum', () => {
  const ids = searchEquipment('dum').map((item) => item.id)
  assert.ok(ids.includes('adjustable_dumbbells'))
  assert.ok(ids.includes('fixed_dumbbells'))
})

test('bespoke profiles keep their programmes while future profiles can enable induction', () => {
  assert.equal(isTrainingInductionEligible('constantine'), false)
  assert.equal(isTrainingInductionEligible('june'), false)
  assert.equal(isTrainingInductionEligible('matthew'), true)
  assert.equal(isTrainingInductionEligible('iulian'), true)
})

test('recent operations receive a clearance-first plan and reduced frequency', () => {
  const assessment = assessTrainingInput({ ...baseInput, recent_operation: true, sessions_per_week: 4 })
  assert.equal(assessment.caution, 'clearance')
  assert.equal(assessment.sessions_per_week, 2)
  const generated = generateTrainingPlan(userId, { ...baseInput, recent_operation: true, sessions_per_week: 4 })
  assert.equal(generated.induction.sessions_per_week, 2)
  assert.match(generated.exercises[0].notes + generated.program_days[0].warmup_note, /clinician|pain-free/i)
})

test('generated foundation occupies 12 dated weeks before its main phase takes over', () => {
  const seeded = buildSeedData(userId, 'matthew')
  const generated = generateTrainingPlan(userId, baseInput, seeded.programs, '2026-07-15T08:00:00.000Z')
  const data = {
    ...seeded,
    settings: {
      ...seeded.settings!,
      addons: { ...seeded.settings!.addons, newbie_mode: true, training_induction: generated.induction },
    },
    programs: generated.programs,
    program_days: [...seeded.program_days, ...generated.program_days],
    exercises: [...seeded.exercises, ...generated.exercises],
  }
  assert.equal(generated.induction.main_start_date, '2026-10-07')
  assert.equal(generated.induction.transition_day_ids.length, 3)
  assert.equal(generated.induction.main_day_ids.length, 3)
  assert.ok(planForDate(data, 'transition', '2026-07-15', false).exercises.length > 0)
  assert.ok(planForDate(data, 'transition', '2026-10-12', false).exercises.length === 0)
  assert.ok(planForDate(data, 'main', '2026-10-12', false).exercises.length > 0)
  assert.ok(planForDate(data, 'main', '2026-07-20', false).exercises.length === 0)
})

test('Iulian-Andrei receives gym-only bodybuilding definitions and versioned upgrades rewrite inherited rows', () => {
  const seeded = buildSeedData(userId, 'iulian')
  assert.equal(seeded.programs.find((program) => program.slug === 'main')?.name, 'Natural Bodybuilding')
  const names = seeded.exercises.map((exercise) => exercise.name).join('|')
  assert.match(names, /Smith Machine|Cable|Hack Squat/)
  assert.doesNotMatch(names, /SkiErg|Team Calisthenics|Big Hammer Loop/)

  const legacy = {
    ...seeded,
    profile: { ...seeded.profile!, seed_version: 1 },
    programs: seeded.programs.map((program) => ({ ...program, name: 'Inherited home plan' })),
    exercises: seeded.exercises.map((exercise, index) => index === 0 ? { ...exercise, name: 'Push-Up' } : exercise),
  }
  const repaired = repairSeedDefinitions(legacy, seeded)
  assert.equal(repaired.data.programs.find((program) => program.slug === 'main')?.name, 'Natural Bodybuilding')
  assert.equal(repaired.data.exercises.find((exercise) => exercise.id === seeded.exercises[0].id)?.name, seeded.exercises[0].name)
  assert.ok(repaired.missing.programs.length > 0)
})

function filesBelow(directory: string): string[] {
  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name)
    return statSync(path).isDirectory() ? filesBelow(path) : [path]
  })
}

test('website source contains no em dash characters or entities', () => {
  for (const path of filesBelow(new URL('../src', import.meta.url).pathname)) {
    const source = readFileSync(path, 'utf8')
    assert.equal(source.includes('—'), false, `em dash in ${path}`)
    assert.equal(/&mdash;|&#8212;/.test(source), false, `em dash entity in ${path}`)
  }
})
