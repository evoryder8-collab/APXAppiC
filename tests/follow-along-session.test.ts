import assert from 'node:assert/strict'
import test from 'node:test'
import { buildTimeline, estimatedTimelineMinutes, type Block } from '../src/lib/playerTimeline.ts'
import { generateTrainingPlan } from '../src/lib/trainingInduction.ts'
import {
  estimateSessionSeconds,
  followAlongFields,
  movementForExercise,
  sideSwitchSeconds,
  suggestedRestSeconds,
  transitionSeconds,
} from '../src/lib/sessionShape.ts'
import { MOVEMENT_BY_ID } from '../src/data/movements.ts'
import type { PlannedDay, PlannedExercise } from '../src/lib/plan.ts'
import { buildSessionRecords, sessionQuality } from '../src/lib/workoutSession.ts'
import type { Exercise, TrainingGoal, TrainingInductionInput } from '../src/lib/types.ts'

function planFrom(exercises: Exercise[]): PlannedDay {
  return {
    programDay: null,
    exercises: exercises.map((e) => ({ ...e, planned_sets: e.sets, swapped: false })) as PlannedExercise[],
    warmup: 'Warm up', warmupDuration: 180, badges: [], isDeload: false,
    isEventDay: false, isRecoveryMicro: false, taperFactor: 1,
    legsBlocked: false, layoffDeload: false,
  }
}

function intake(goal: TrainingGoal, over: Partial<TrainingInductionInput> = {}): TrainingInductionInput {
  return {
    start_date: '2026-08-19', inactivity: 'under_1_month', venue: 'gym',
    equipment: [], pain_areas: [], recent_operation: false,
    chronic_lower_back_pain: false, sessions_per_week: 3, goal, ...over,
  }
}

/** Every wait in a guided session has to be a real number of seconds. */
function assertWellFormed(blocks: Block[], where: string): void {
  for (const block of blocks) {
    if (block.kind === 'rest' || block.kind === 'side_switch' || block.kind === 'warmup') {
      assert.ok(Number.isFinite(block.duration) && block.duration > 0,
        `${where}: a ${block.kind} block waits ${block.duration}s`)
      assert.ok(block.duration <= 600, `${where}: a ${block.kind} block waits ${block.duration}s`)
    }
    if (block.kind === 'set') {
      assert.ok(block.resultKey.length > 0, `${where}: a set cannot be recorded against anything`)
      if (block.timed == null) {
        assert.ok(block.repDuration >= 1.6, `${where}: rep cadence of ${block.repDuration}s`)
        assert.ok(block.targetReps === null || block.targetReps > 0, where)
      }
    }
  }
  assert.equal(blocks.at(-1)?.kind, 'done', `${where}: the session never finishes`)
}

test('a plan generated from the questionnaire is ready to follow along with', () => {
  for (const goal of ['rebuild', 'muscle', 'strength'] as TrainingGoal[]) {
    for (const venue of ['home', 'gym'] as const) {
      const plan = generateTrainingPlan('user-1', intake(goal, { venue }))
      assert.ok(plan.exercises.length > 0, `${goal}/${venue} generated nothing`)

      for (const day of plan.program_days) {
        const forDay = plan.exercises.filter((e) => e.program_day_id === day.id && !e.is_lite)
        if (forDay.length === 0) continue
        const blocks = buildTimeline(planFrom(forDay))
        assertWellFormed(blocks, `${goal}/${venue}/${day.name}`)

        // Every set can report what was done: reps against a result key, and
        // kilograms wherever the movement is loadable.
        const weighted = forDay.filter((e) => e.increment_kg > 0)
        if (weighted.length > 0) {
          const capture = blocks.filter((b) => b.kind === 'rest' && b.captureLoad)
          assert.ok(capture.length > 0,
            `${goal}/${venue}/${day.name} never asks what was lifted`)
        }
      }
    }
  }
})

test('a generated plan is paced by its movements, not by one default', () => {
  const plan = generateTrainingPlan('user-1', intake('muscle', { venue: 'gym' }))
  const cadences = new Set(plan.exercises.map(
    (e) => `${e.tempo_down_s}-${e.tempo_pause_s}-${e.tempo_up_s}`))
  const rests = new Set(plan.exercises.map((e) => e.rest_sec))
  assert.ok(cadences.size > 1, 'every generated exercise shares one cadence')
  assert.ok(rests.size > 1, 'every generated exercise shares one rest interval')
  // And it knows which movement each row is, so the player can find its cues.
  const resolved = plan.exercises.filter((e) => e.movement_id)
  assert.ok(resolved.length / plan.exercises.length > 0.6,
    `only ${resolved.length} of ${plan.exercises.length} generated rows resolve to a movement`)
})

test('someone training under caution is paced accordingly', () => {
  const standard = generateTrainingPlan('u', intake('strength', { venue: 'gym' }))
  const cautious = generateTrainingPlan('u', intake('strength', {
    venue: 'gym', chronic_lower_back_pain: true, inactivity: 'over_one_year',
  }))
  const avgDown = (p: typeof standard) =>
    p.exercises.reduce((sum, e) => sum + e.tempo_down_s, 0) / p.exercises.length
  assert.ok(avgDown(cautious) >= avgDown(standard),
    'a cautious plan is not lowered any more slowly than a standard one')
})

test('every single-sided exercise gets a switch, sized to what it takes', () => {
  // A rear foot on a bench is not swapped over as quickly as a dumbbell is.
  const split = sideSwitchSeconds(MOVEMENT_BY_ID.get('bulgarian_split_squat')!)
  const carry = sideSwitchSeconds(MOVEMENT_BY_ID.get('suitcase_carry')!)
  assert.ok(split > carry, `split squat ${split}s vs suitcase carry ${carry}s`)
  assert.ok(split <= 30 && carry >= 4)
  // And nothing gets the old fixed three seconds.
  for (const id of ['bulgarian_split_squat', 'one_arm_dumbbell_row', 'split_squat',
    'single_leg_romanian_deadlift', 'suitcase_carry', 'side_plank']) {
    assert.ok(sideSwitchSeconds(MOVEMENT_BY_ID.get(id)!) > 3, id)
  }
})

test('moving between exercises allows for setting the next one up', () => {
  const hipThrust = MOVEMENT_BY_ID.get('hip_thrust_barbell')!   // 90s to set up
  const pushUp = MOVEMENT_BY_ID.get('push_up')!                 // 5s
  // A ninety second setup is not covered by a sixty second rest.
  assert.ok(transitionSeconds(pushUp, hipThrust, 60) >= hipThrust.setupSeconds)
  // But setting up happens during the rest rather than after it, so the two
  // overlap instead of stacking.
  assert.equal(transitionSeconds(pushUp, pushUp, 150), 150)
  // Walking away from something brutal is never instant.
  assert.ok(transitionSeconds(MOVEMENT_BY_ID.get('conventional_deadlift')!, pushUp, 30) >= 90)
})

test('a hand-built workout is shaped like a generated one', () => {
  // A trainer picking exercises should not produce a worse-paced session than
  // the questionnaire does.
  const built = followAlongFields('Barbell Hip Thrust', 'hypertrophy', {
    rest_sec: 60, per_side: false, increment_kg: 0,
  })
  assert.equal(built.movement_id, 'hip_thrust_barbell')
  assert.equal(built.tempo_pause_s, 2)
  assert.match(built.tempo_note, /top/)
  assert.ok(built.increment_kg > 0, 'a loadable movement got no increment')

  // The trainer's own choices survive.
  const kept = followAlongFields('Barbell Hip Thrust', 'hypertrophy',
    { rest_sec: 45 }, { keepAuthoredRest: true })
  assert.equal(kept.rest_sec, 45)

  // The picker still opens on something sensible rather than a flat default.
  assert.ok((suggestedRestSeconds('Barbell Back Squat', 'hypertrophy') ?? 0)
    > (suggestedRestSeconds('Cable External Rotation', 'hypertrophy') ?? 0))
})

test('a single-sided movement is treated as such even if the box was missed', () => {
  const fields = followAlongFields('Bulgarian Split Squat', 'hypertrophy', { per_side: false })
  assert.equal(fields.per_side, true)
})

test('an unknown exercise keeps what it was given rather than being guessed at', () => {
  const fields = followAlongFields('Interpretive Dance', 'hypertrophy',
    { rest_sec: 75, per_side: true, increment_kg: 5 })
  assert.equal(fields.movement_id, null)
  assert.equal(fields.rest_sec, 75)
  assert.equal(fields.per_side, true)
  assert.equal(fields.increment_kg, 5)
})

test('a session estimate reflects the waits it actually contains', () => {
  const plan = generateTrainingPlan('user-1', intake('muscle', { venue: 'gym' }))
  const day = plan.program_days[0]
  const forDay = plan.exercises.filter((e) => e.program_day_id === day.id && !e.is_lite)
  const blocks = buildTimeline(planFrom(forDay))
  const waits = blocks.reduce((sum, b) =>
    b.kind === 'rest' || b.kind === 'side_switch' ? sum + b.duration : sum, 0)
  assert.ok(waits > 0, 'a session with no waits in it')
  const minutes = estimatedTimelineMinutes(planFrom(forDay))
  assert.ok(minutes >= Math.round(waits / 60),
    'the estimate is shorter than the resting alone')
  assert.ok(minutes < 180, `a generated session estimated at ${minutes} minutes`)
})

test('the movement behind a row is found by id or by its authored name', () => {
  assert.equal(movementForExercise({ name: 'anything', movement_id: 'pull_up' })?.id, 'pull_up')
  assert.equal(movementForExercise({ name: 'Pull-Ups (different grip than Wed)' })?.id, 'pull_up')
  assert.equal(movementForExercise({ name: 'Interpretive Dance' }), null)
})

test('the duration on the card is the duration the session runs', () => {
  // It used to be a number typed into the template: a plan could advertise
  // thirty-eight minutes and take twenty-seven, which is the kind of thing
  // that stops people trusting the rest of it.
  for (const goal of ['rebuild', 'muscle', 'strength'] as TrainingGoal[]) {
    for (const venue of ['home', 'gym'] as const) {
      const plan = generateTrainingPlan('u', intake(goal, { venue }))
      for (const day of plan.program_days) {
        const forDay = plan.exercises.filter((e) => e.program_day_id === day.id && !e.is_lite)
        if (forDay.length === 0) continue
        const player = estimatedTimelineMinutes(planFrom(forDay))
        assert.equal(day.est_minutes, player,
          `${goal}/${venue}/${day.name}: card says ${day.est_minutes}, player runs ${player}`)
      }
    }
  }
})

test('the shared estimator and the player agree on the same session', () => {
  // Two implementations of the same arithmetic drift apart unless something
  // checks. The estimator lives outside the timeline only because the plan
  // module and the induction generator already import each other.
  const plan = generateTrainingPlan('u', intake('muscle', { venue: 'gym' }))
  for (const day of plan.program_days) {
    const forDay = plan.exercises.filter((e) => e.program_day_id === day.id && !e.is_lite)
    if (forDay.length === 0) continue
    const shared = Math.round(estimateSessionSeconds(forDay, 180) / 60)
    const player = estimatedTimelineMinutes(planFrom(forDay))
    assert.ok(Math.abs(shared - player) <= 1,
      `${day.name}: estimator says ${shared}, player says ${player}`)
  }
})

test('both ways of training write identical history', () => {
  // A set counted by the guided player and a set typed into the tracked list
  // must be indistinguishable afterwards, or progressive overload, the workout
  // receipt and every strength comparison quietly depend on which screen
  // somebody happened to open.
  const draft = {
    sessionId: 'session-1', userId: 'user-1', date: '2026-08-19',
    programDayId: 'day-1', isLite: false, isDeload: false, isEventRecovery: false,
    qualityScore: 0.8333333, startedAt: '2026-08-19T09:00:00.000Z',
    completedAt: '2026-08-19T10:00:00.000Z',
    exercises: [
      {
        exerciseId: 'ex-1', name: 'Barbell Back Squat', plannedSets: 3,
        skipped: false, override: false,
        sets: [
          { weight: 80, reps: 10, rir: 2 },
          { weight: 80, reps: 9, rir: 1 },
          { weight: 80, reps: 8, rir: 0 },
        ],
      },
      {
        exerciseId: null, name: 'Push-Up', plannedSets: 2,
        skipped: true, override: false, sets: [],
      },
    ],
  }
  let counter = 0
  const ids = () => `log-${counter++}`
  const first = buildSessionRecords(draft, ids)
  counter = 0
  const second = buildSessionRecords(draft, ids)
  assert.deepEqual(first, second)

  // Every planned set is written even when the exercise was skipped, because
  // an absent row and a skipped row mean different things.
  assert.equal(first.logs.length, 5)
  const skipped = first.logs.filter((l) => l.exercise_name === 'Push-Up')
  assert.equal(skipped.length, 2)
  assert.ok(skipped.every((l) => l.skipped && l.reps === null && l.weight_kg === null))

  // Reps in reserve survives, which is the number progressive overload runs on.
  assert.deepEqual(first.logs.slice(0, 3).map((l) => l.rir), [2, 1, 0])
  // And the stored order is pinned rather than left to the database.
  const times = first.logs.map((l) => Date.parse(l.created_at))
  assert.deepEqual(times, [...times].sort((a, b) => a - b))
  assert.equal(new Set(times).size, times.length)
})

test('session quality means the same thing in both modes', () => {
  const full = sessionQuality([
    { exerciseId: null, name: 'a', plannedSets: 3, skipped: false, override: false,
      sets: [{ weight: 1, reps: 8, rir: 1 }, { weight: 1, reps: 8, rir: 1 }, { weight: 1, reps: 8, rir: 1 }] },
  ])
  assert.equal(full, 1)
  const half = sessionQuality([
    { exerciseId: null, name: 'a', plannedSets: 4, skipped: false, override: false,
      sets: [{ weight: 1, reps: 8, rir: 1 }, { weight: 1, reps: 8, rir: 1 }] },
  ])
  assert.equal(half, 0.5)
  // A skipped exercise counts as planned but not performed.
  assert.equal(sessionQuality([
    { exerciseId: null, name: 'a', plannedSets: 2, skipped: true, override: false, sets: [] },
  ]), 0)
})

test('the questionnaire picks a starting mode that suits the person', () => {
  const trained = generateTrainingPlan('u', intake('muscle', { inactivity: 'currently_training' }))
  const returning = generateTrainingPlan('u', intake('muscle', { inactivity: 'over_one_year' }))
  // Somebody already training and chasing size runs their own overload.
  assert.ok(trained.program_days.every((d) => d.session_mode === 'tracked'))
  // Somebody coming back after a year needs the pacing more than the autonomy.
  assert.ok(returning.program_days.every((d) => d.session_mode === 'guided'))
  // Rebuilding is guided regardless, because that is what the mode is for.
  const rebuilding = generateTrainingPlan('u', intake('rebuild', { inactivity: 'currently_training' }))
  assert.ok(rebuilding.program_days.every((d) => d.session_mode === 'guided'))
})
