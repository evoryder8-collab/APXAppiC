import assert from 'node:assert/strict'
import test from 'node:test'

import { buildFriendSeedData } from '../src/data/personaSeeds.ts'
import { buildSeedData } from '../src/data/seed.ts'
import { planForDate, programDaysForDate } from '../src/lib/plan.ts'
import { buildWorkSequence } from '../src/lib/workGrouping.ts'
import { buildTimeline } from '../src/lib/playerTimeline.ts'

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

test('all seven morning rotations exclude the official targets and run one set per movement per round', () => {
  const data = buildSeedData('10000000-0000-4000-8000-000000000085', 'constantine')
  const expected = [
    ['chest', 'side delts'],
    ['side delts', 'quads', 'hamstrings', 'calves'],
    ['chest', 'side delts', 'quads', 'hamstrings', 'calves'],
    ['chest', 'side delts', 'quads', 'hamstrings', 'calves'],
    ['chest', 'side delts'],
    ['quads', 'hamstrings', 'calves'],
    ['chest', 'side delts', 'quads', 'hamstrings', 'calves'],
  ]
  for (const [index, targets] of expected.entries()) {
    const day = mainDays(data).find(row => row.weekday === index + 1 && row.name === 'AM · Morning circle')!
    const rows = data.exercises.filter(row => row.program_day_id === day.id && !row.is_lite)
    assert.deepEqual(rows.map(row => row.notes.replace('Morning circle · ', '')), targets)
    assert.ok(rows.every(row => row.sets === 5))
    const sequence = buildWorkSequence(rows)
    assert.equal(sequence.length, targets.length * 5)
    assert.deepEqual(sequence.slice(0, targets.length).map(row => [row.exIdx, row.setNo]),
      targets.map((_, i) => [i, 1]), `weekday ${index + 1} must alternate targets, not finish all sets of one target`)
  }
})

test('the morning circle keeps prescribed strength rest instead of a rushed superset transition', () => {
  const data = buildSeedData('10000000-0000-4000-8000-000000000085', 'constantine')
  data.settings!.addons.training_protocol = { version: 85, start_date: '2026-09-07' }
  const day = mainDays(data).find(row => row.weekday === 1 && row.name === 'AM · Morning circle')!
  const plan = planForDate(data, 'main', '2026-09-14', false, day.id)
  const rest = buildTimeline(plan).find(row => row.kind === 'rest')
  assert.equal(rest?.duration, 90)
})
