import assert from 'node:assert/strict'
import test from 'node:test'

import { buildFriendSeedData } from '../src/data/personaSeeds.ts'
import { buildSeedData } from '../src/data/seed.ts'
import { planForDate, programDaysForDate } from '../src/lib/plan.ts'

const mainDays = (data: ReturnType<typeof buildSeedData>) => {
  const main = data.programs.find((program) => program.slug === 'main')!
  return data.program_days.filter((day) => day.program_id === main.id)
}

test('June V8.4 exposes morning, official, and T25 sessions as separate cards', () => {
  const data = buildFriendSeedData('10000000-0000-4000-8000-000000000084', 'june')
  const days = mainDays(data)

  assert.equal(data.settings?.addons.training_protocol?.version, 84)
  assert.deepEqual(days.filter((day) => day.weekday === 2).map((day) => day.name), [
    'AM · Hip thrust',
    'Push A · Strength',
    'Focus T25 · Core',
  ])
  assert.deepEqual(days.filter((day) => day.weekday === 4).map((day) => day.name), [
    'AM · Hip thrust',
    'Recovery · Posture and wrists',
    'Focus T25 · Stretch',
  ])

  const tuesday = programDaysForDate(data, 'main', '2026-09-01')
  assert.equal(tuesday.length, 3)
  const t25 = tuesday.find((day) => day.programDay.name === 'Focus T25 · Core')!
  assert.equal(t25.exercises.length, 1)
  assert.equal(planForDate(data, 'main', '2026-09-01', false, t25.programDay.id).programDay?.id, t25.programDay.id)
})

test('Constantine V8.5 exposes the morning circle independently from official and T25 work', () => {
  const data = buildSeedData('10000000-0000-4000-8000-000000000085', 'constantine')
  const days = mainDays(data)

  assert.equal(data.settings?.addons.training_protocol?.version, 85)
  assert.deepEqual(days.filter((day) => day.weekday === 3).map((day) => day.name), [
    'AM · Morning circle',
    'Pull A · Strength',
    'Focus T25 · Lower Focus and Speed',
  ])

  const mondayMorning = days.find((day) => day.weekday === 1 && day.name === 'AM · Morning circle')!
  const exercises = data.exercises.filter((exercise) => exercise.program_day_id === mondayMorning.id && !exercise.is_lite)
  assert.deepEqual(exercises.map((exercise) => [exercise.name, exercise.sets]), [
    ['Weighted backpack push-up', 5],
    ['Dumbbell lateral raise', 5],
  ])
})
