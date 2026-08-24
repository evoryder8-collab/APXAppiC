import test from 'node:test'
import assert from 'node:assert/strict'
import { buildSeedData } from '../src/data/seed.ts'
import { planForDate } from '../src/lib/plan.ts'
import { isProtocolPushupTestWeek } from '../src/lib/focusT25.ts'

/*
 * Constantin Training V8.2, the two revisions against V8.1.
 *
 * Tuesday returns to bodyweight rep capacity: the weighted and feet-elevated
 * push-up work moves out, because tracked push-up load belongs to Saturday
 * ("Weighted push-up load, every Saturday") while bodyweight maximum is
 * tested on weeks 1, 5, 9 and 13. Saturday's pike volume rises to three sets.
 *
 * The benchmark cadence itself is unchanged and is asserted here so the two
 * are never confused again: the fresh maximum set is periodic, not weekly.
 */

const userId = '00000000-0000-4000-8000-000000000001'
const data = (() => {
  const seeded = buildSeedData(userId, 'constantine')
  const settings = seeded.settings!
  return {
    ...seeded,
    settings: {
      ...settings,
      addons: { ...settings.addons, training_protocol: { version: 82, start_date: '2026-07-27' } },
    },
  }
})()

test('a normal Tuesday is bodyweight rep capacity, not weighted volume', () => {
  /* Week 2 of the block: 2026-08-04 */
  const tuesday = planForDate(data, 'main', '2026-08-04', false)
  const names = tuesday.exercises.map((exercise) => exercise.name)

  assert.ok(names.includes('Strict Bodyweight Push-Up'))
  assert.ok(!names.some((name) => name.includes('Weighted Push-Up')), 'weighted work belongs to Saturday')
  assert.ok(!names.some((name) => name.includes('Feet-Elevated')), 'V8.2 drops the feet-elevated block')

  const strict = tuesday.exercises.find((exercise) => exercise.name === 'Strict Bodyweight Push-Up')!
  assert.equal(strict.planned_sets, 4)
  assert.equal(strict.rest_sec, 90)
  assert.match(strict.notes, /2 clean reps available/)
  assert.match(strict.notes, /one total repetition/)

  /* Diamonds stay on normal Tuesdays */
  assert.ok(names.some((name) => name.startsWith('Diamond')))
})

test('the fresh maximum set is periodic, on weeks 1, 5, 9 and 13', () => {
  assert.equal(isProtocolPushupTestWeek(1), true)
  assert.equal(isProtocolPushupTestWeek(5), true)
  assert.equal(isProtocolPushupTestWeek(9), true)
  assert.equal(isProtocolPushupTestWeek(13), true)
  for (const week of [2, 3, 4, 6, 7, 8, 10, 11, 12]) {
    assert.equal(isProtocolPushupTestWeek(week), false, `week ${week} is a normal Tuesday`)
  }
})

test('a benchmark Tuesday replaces the work sets with the test protocol', () => {
  /* Week 1 of the block starting 2026-07-27 */
  const tuesday = planForDate(data, 'main', '2026-07-28', false)
  const names = tuesday.exercises.map((exercise) => exercise.name)
  assert.ok(names.includes('Strict Push-Up Max Test'))
  assert.ok(!names.some((name) => name.startsWith('Diamond')), 'the PDF says skip diamonds on testing Tuesdays')
})

test('Saturday keeps the weighted work and gains a third pike set', () => {
  const saturday = planForDate(data, 'main', '2026-08-08', false)
  const weighted = saturday.exercises.find((exercise) => exercise.name === 'Weighted Push-Up')!
  assert.equal(weighted.planned_sets, 4)
  assert.match(weighted.notes, /1-2 kg only after 10, 10, 10/)

  const pike = saturday.exercises.find((exercise) => exercise.name === 'Pike Push-Up')!
  assert.equal(pike.planned_sets, 3, 'V8.2 raises pike volume from two sets to three')
})

test('Saturday stays protected from Focus T25', () => {
  const saturday = planForDate(data, 'main', '2026-08-08', false)
  assert.ok(!saturday.exercises.some((exercise) => exercise.name.startsWith('Focus T25')))
})

test('bespoke plan badge reflects the account protocol version', () => {
  const withVersion = (version: number) => ({
    ...data,
    settings: {
      ...data.settings!,
      addons: {
        ...data.settings!.addons,
        training_protocol: { version, start_date: '2026-07-27' },
      },
    },
  })

  assert.ok(planForDate(withVersion(83), 'main', '2026-08-04', false).badges.includes('V8.3 · week 2'))
  assert.ok(planForDate(withVersion(80), 'main', '2026-08-04', false).badges.includes('V8 · week 2'))
})

test('V8.3 Friday Focus T25 guidance works for the full prescription', () => {
  const main = data.programs.find((program) => program.slug === 'main')!
  const friday = data.program_days.find((day) => day.program_id === main.id && day.weekday === 5)!
  const lightFocus = data.exercises.find((exercise) =>
    exercise.program_day_id === friday.id && exercise.name === 'Focus T25 · Friday conditioning',
  )!
  const v83 = {
    ...data,
    exercises: [
      ...data.exercises.filter((exercise) => exercise.id !== lightFocus.id),
      { ...lightFocus, id: '83000000-0000-4000-8000-000000000001', is_lite: false, sort_order: 4 },
    ],
    settings: {
      ...data.settings!,
      addons: {
        ...data.settings!.addons,
        training_protocol: { version: 83, start_date: '2026-07-27' },
      },
    },
  }

  const focus = planForDate(v83, 'main', '2026-08-07', false).exercises.find((exercise) =>
    exercise.name.startsWith('Focus T25'),
  )!
  assert.ok(focus)
  assert.doesNotMatch(focus.notes, /light option only/i)
  assert.match(focus.notes, /strength first/i)
})
