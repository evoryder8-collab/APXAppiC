import test from 'node:test'
import assert from 'node:assert/strict'
import { buildSeedData } from '../src/data/seed.ts'
import { planForDate, programDaysForDate } from '../src/lib/plan.ts'
import { buildTimeline, estimatedTimelineMinutes, plannedWorkoutDurationBreakdown } from '../src/lib/playerTimeline.ts'
import { computeEngine } from '../src/lib/rpg.ts'

const userId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
const protocolStart = '2026-07-27'

function withProtocol(persona: 'constantine' | 'june') {
  const data = buildSeedData(userId, persona)
  assert.ok(data.settings)
  data.settings = {
    ...data.settings,
    addons: {
      ...data.settings.addons,
      training_protocol: { version: 81, start_date: protocolStart },
    },
  }
  return data
}

test('Constantine V8.5 uses the prescribed official structure and a separate Focus T25 card', () => {
  const data = withProtocol('constantine')
  const monday = planForDate(data, 'main', '2026-08-03', false)
  assert.equal(monday.programDay?.name, 'Legs A · Strength')
  assert.deepEqual(
    monday.exercises.map((exercise) => [exercise.name, exercise.planned_sets, exercise.rest_sec]),
    [
      ['Bulgarian Split Squat', 5, 120],
      ['Dumbbell Romanian Deadlift', 3, 120],
      ['Sliding Leg Curl', 3, 90],
      ['Single-Leg Calf Raise', 5, 60],
    ],
  )

  const tuesday = programDaysForDate(data, 'main', '2026-08-04').find((candidate) => candidate.programDay?.name.startsWith('Focus T25'))!
  assert.ok(tuesday.exercises.some((exercise) =>
    exercise.name === 'Focus T25 · Ab Intervals' && exercise.rep_unit === 'minutes',
  ))
})

test('Friday Full and Light are explicit, distinct prescriptions in opening week', () => {
  const data = withProtocol('constantine')
  const full = planForDate(data, 'main', '2026-07-31', false)
  const light = planForDate(data, 'main', '2026-07-31', true)

  assert.equal(full.programDay?.name, 'Legs B · Strength')
  assert.deepEqual(
    full.exercises.map((exercise) => [exercise.name, exercise.planned_sets]),
    [
      ['Front Lunge', 3],
      ['Reverse Lunge', 2],
      ['Single-Leg Romanian Deadlift', 3],
      ['Single-Leg Calf Raise', 5],
    ],
  )
  assert.ok(!full.exercises.some((exercise) => exercise.name.startsWith('Focus T25')))
  assert.deepEqual(
    light.exercises.map((exercise) => [exercise.name, exercise.planned_sets]),
    [
      ['Front Lunge', 2],
      ['Single-Leg Romanian Deadlift', 2],
    ],
  )
  assert.ok(estimatedTimelineMinutes(light) > 0)
  assert.ok(estimatedTimelineMinutes(light) < (full.programDay?.est_minutes ?? 0))
})

test('Constantine Wednesday keeps strength and Focus T25 as independent durations', () => {
  const data = withProtocol('constantine')
  const wednesday = planForDate(data, 'main', '2026-07-29', false)
  const focus = programDaysForDate(data, 'main', '2026-07-29').find((candidate) => candidate.programDay?.name.startsWith('Focus T25'))!

  assert.equal(wednesday.programDay?.est_minutes, 52)
  assert.equal(focus.programDay?.est_minutes, 25)
  assert.equal(focus.exercises[0]?.rep_unit, 'minutes')
  assert.match(focus.exercises[0]?.notes ?? '', /25 min/)
  assert.deepEqual(
    plannedWorkoutDurationBreakdown(wednesday, wednesday.programDay?.est_minutes ?? 0, false),
    { total: 52, primary: 52, focusT25: 0 },
  )
})

test('deload weeks cap strength while keeping separately scheduled Focus T25 visible', () => {
  const data = withProtocol('constantine')
  const deloadWednesday = planForDate(data, 'main', '2026-08-19', false)
  assert.equal(deloadWednesday.isDeload, true)
  assert.ok(deloadWednesday.exercises.every((exercise) => exercise.rep_unit === 'check' || exercise.planned_sets <= 2))
  assert.ok(!deloadWednesday.exercises.some((exercise) => exercise.name.startsWith('Focus T25')))

  const deloadTuesday = programDaysForDate(data, 'main', '2026-08-18').find((candidate) => candidate.programDay?.name.startsWith('Focus T25'))!
  assert.ok(deloadTuesday.exercises.some((exercise) => exercise.name === 'Focus T25 · Ab Intervals'))
})

test('benchmark weeks replace normal push volume with the PDF max-test protocol', () => {
  const data = withProtocol('constantine')
  const plan = planForDate(data, 'main', '2026-08-25', false)
  assert.deepEqual(plan.exercises.slice(0, 2).map((exercise) => [
    exercise.name,
    exercise.planned_sets,
    exercise.rest_sec,
  ]), [
    ['Strict Push-Up Max Test', 1, 180],
    ['Weighted Push-Up Back-Off', 2, 120],
  ])
  assert.ok(!plan.exercises.some((exercise) => exercise.name.includes('Feet-Elevated')))
})

test('June V8.4 has two glute days, three separate T25 cards and a true Sunday rest', () => {
  const data = withProtocol('june')
  assert.equal(planForDate(data, 'main', '2026-08-03', false).programDay?.name, 'Glutes A · Strength')
  assert.equal(planForDate(data, 'main', '2026-08-07', false).programDay?.name, 'Glutes B · Strength')
  assert.equal(planForDate(data, 'main', '2026-08-09', false).exercises.length, 0)
  assert.equal(
    programDaysForDate(data, 'main', '2026-08-04').find((candidate) => candidate.programDay?.name.startsWith('Focus T25'))?.exercises.at(-1)?.name,
    'Focus T25 · Ab Intervals',
  )
  assert.equal(
    programDaysForDate(data, 'main', '2026-08-05').find((candidate) => candidate.programDay?.name.startsWith('Focus T25'))?.exercises.at(-1)?.name,
    'Focus T25 · Lower Focus',
  )
  assert.equal(
    programDaysForDate(data, 'main', '2026-08-06').find((candidate) => candidate.programDay?.name.startsWith('Focus T25'))?.exercises[0]?.name,
    'Focus T25 · Stretch',
  )
})

test('June Full is never silently replaced by Light and follows the V8.4 exercise order', () => {
  const june = withProtocol('june')
  const juneMonday = planForDate(june, 'main', '2026-08-03', false)
  const juneFriday = planForDate(june, 'main', '2026-07-31', false)
  const juneFridayLight = planForDate(june, 'main', '2026-07-31', true)

  assert.deepEqual(juneMonday.exercises.slice(0, 3).map((exercise) => exercise.name), [
    'Dumbbell Hip Thrust', 'Bulgarian Split Squat', 'Dumbbell Romanian Deadlift',
  ])
  assert.deepEqual(juneFriday.exercises.slice(0, 3).map((exercise) => exercise.name), [
    'Reverse Lunge', 'B-Stance or Single-Leg Hip Thrust', 'Sliding Leg Curl',
  ])
  assert.deepEqual(juneFriday.exercises.map((exercise) => exercise.planned_sets), [3, 3, 3, 1])
  assert.deepEqual(juneFridayLight.exercises.map((exercise) => exercise.planned_sets), [2, 2, 2])
  assert.ok(!juneFriday.exercises.some((exercise) => exercise.name.startsWith('Focus T25')))
  assert.ok(!juneFridayLight.exercises.some((exercise) => exercise.name.startsWith('Focus T25')))
})

test('guided timeline completes both sides and keeps the full prescribed rest', () => {
  const data = withProtocol('constantine')
  const plan = planForDate(data, 'main', '2026-08-03', false)
  const timeline = buildTimeline(plan)
  const firstSetBlocks = timeline.filter((block) =>
    block.kind === 'set' && block.exIdx === 0 && block.setNo === 1,
  )
  assert.deepEqual(
    firstSetBlocks.map((block) => block.kind === 'set' ? block.side : null),
    ['left', 'right'],
  )
  const firstRest = timeline.find((block) =>
    block.kind === 'rest' && block.exIdx === 0 && block.afterSet === 1,
  )
  assert.equal(firstRest?.kind === 'rest' ? firstRest.duration : null, 120)
})

test('a checked Focus T25 session feeds endurance even on a strength day', () => {
  const data = withProtocol('constantine')
  assert.ok(data.profile)
  data.profile = { ...data.profile, baseline_date: '2026-07-28' }
  const main = data.programs.find((program) => program.slug === 'main')
  const tuesday = data.program_days.find((day) => day.program_id === main?.id && day.weekday === 2)
  assert.ok(tuesday)
  data.workout_sessions = [{
    id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    user_id: userId,
    date: '2026-07-28',
    program_day_id: tuesday.id,
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: true,
    quality_score: 1,
    started_at: null,
    completed_at: null,
    notes: '',
  }]
  const withoutCheck = computeEngine(data, '2026-07-28').snapshots.at(-1)
  data.workout_logs = [{
    id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    user_id: userId,
    session_id: data.workout_sessions[0].id,
    exercise_id: null,
    exercise_name: 'Focus T25 · Ab Intervals',
    set_no: 1,
    weight_kg: null,
    reps: 1,
    rir: null,
    skipped: false,
    override_flag: false,
    created_at: '2026-07-28T18:00:00Z',
  }]
  const withCheck = computeEngine(data, '2026-07-28').snapshots.at(-1)
  assert.ok(withCheck && withoutCheck && withCheck.endurance > withoutCheck.endurance)
})
