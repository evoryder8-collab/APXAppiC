import assert from 'node:assert/strict'
import test from 'node:test'
import { MOVEMENTS, MOVEMENT_BY_ID } from '../src/data/movements.ts'
import {
  restSecondsFor,
  setSeconds,
  tempoFor,
  type TrainingIntent,
} from '../src/lib/liftingTempo.ts'
import { generateWeek, type GeneratorIntake } from '../src/lib/planGenerator.ts'

const INTENTS: TrainingIntent[] = ['rebuild', 'hypertrophy', 'strength', 'endurance', 'power']
const GYM = [...new Set(MOVEMENTS.flatMap((m) => [...m.equipment, ...m.equipmentAnyOf.flat()]))]

function intake(over: Partial<GeneratorIntake> = {}): GeneratorIntake {
  return {
    goal: 'muscle', sessionsPerWeek: 3, minutesPerSession: 50, equipment: GYM,
    painAreas: [], age: 30, experience: 'intermediate', hasRackSafeties: true, ...over,
  }
}

test('a rep is only timed where timing one means something', () => {
  for (const m of MOVEMENTS) {
    const tempo = tempoFor(m, 'hypertrophy')
    if (m.entityType === 'plyometric' || m.ballistic) {
      assert.equal(tempo, null,
        `${m.id} is ballistic or a plyometric and must not carry a rep tempo`)
    }
    if (m.entityType === 'resistance_isometric' || m.repUnit !== 'reps') {
      assert.equal(tempo, null, `${m.id} has no rep to time`)
    }
    if (tempo) {
      assert.equal(m.entityType, 'resistance_dynamic', `${m.id}`)
      assert.ok(tempo.repSeconds > 0 && tempo.repSeconds <= 10,
        `${m.id} rep duration ${tempo.repSeconds}s is outside the range the evidence supports`)
    }
  }
})

test('the pause lands where the movement actually loads the muscle', () => {
  // A hip thrust peaks at lockout, so the top is the hardest part of the lift.
  const thrust = tempoFor(MOVEMENT_BY_ID.get('hip_thrust_barbell')!, 'hypertrophy')!
  assert.equal(thrust.pausePosition, 'shortened')
  assert.match(thrust.cue, /top/)

  // A squat peaks at the bottom, where holding is work rather than rest.
  const squat = tempoFor(MOVEMENT_BY_ID.get('barbell_back_squat')!, 'hypertrophy')!
  assert.equal(squat.pausePosition, 'lengthened')
  assert.match(squat.cue, /stretch/)

  // Squeezing the top of a squat would be a pause in the rest position.
  assert.notEqual(squat.pausePosition, 'shortened')
})

test('every movement that can be timed knows where it is loaded', () => {
  for (const m of MOVEMENTS) {
    if (!m.tempoApplies) continue
    assert.notEqual(m.peakTension, 'held',
      `${m.id} carries a tempo but no loaded position for the pause`)
  }
})

test('rest is not shortened to chase hypertrophy', () => {
  // Three minutes beat one minute for both size and strength when this was
  // actually tested, so the old short-rest advice is the wrong way round.
  for (const m of MOVEMENTS.filter((x) => x.role === 'primary').slice(0, 40)) {
    const hypertrophy = restSecondsFor(m, 'hypertrophy')
    const endurance = restSecondsFor(m, 'endurance')
    assert.ok(hypertrophy >= 90,
      `${m.id} rests only ${hypertrophy}s for hypertrophy`)
    assert.ok(hypertrophy > endurance,
      `${m.id} rests no longer for hypertrophy than for work capacity`)
  }
})

test('rest scales with what the set is actually limited by', () => {
  const squat = MOVEMENT_BY_ID.get('barbell_back_squat')!
  const curl = MOVEMENT_BY_ID.get('dumbbell_curl')!
  assert.ok(restSecondsFor(squat, 'strength') > restSecondsFor(squat, 'hypertrophy'))
  assert.ok(restSecondsFor(squat, 'hypertrophy') > restSecondsFor(squat, 'endurance'))
  // A compound costs more to recover from than an isolation movement.
  assert.ok(restSecondsFor(squat, 'hypertrophy') > restSecondsFor(curl, 'hypertrophy'))
})

test('work capacity shortens rest and lengthens sets together', () => {
  const endurance = generateWeek(intake({ intent: 'endurance' }), 'gym')
  const hypertrophy = generateWeek(intake({ intent: 'hypertrophy' }), 'gym')
  const first = (w: typeof endurance) => w.sessions[0].blocks[0]
  assert.ok(first(endurance).restSeconds < first(hypertrophy).restSeconds)
  assert.ok(first(endurance).repHigh > first(hypertrophy).repHigh)
  // Shortening the rest without raising the reps would just be a worse
  // hypertrophy session, not an endurance one.
  assert.ok(first(endurance).repLow >= 12)
})

test('a slower tempo costs real time in the session estimate', () => {
  const squat = MOVEMENT_BY_ID.get('barbell_back_squat')!
  assert.ok(setSeconds(squat, 10, 'hypertrophy') > setSeconds(squat, 10, 'endurance'),
    'a three second eccentric with a pause must cost more than a one second one')
  // Unilateral work costs both sides.
  const split = MOVEMENT_BY_ID.get('split_squat')!
  assert.ok(setSeconds(split, 10, 'hypertrophy') > setSeconds(squat, 10, 'hypertrophy'))
})

test('a movement whose load cannot change keeps its own rep range', () => {
  const week = generateWeek(intake({ goal: 'strength', equipment: ['floor_space', 'mat', 'wall'] }), 'bodyweight_only')
  for (const session of week.sessions) {
    for (const block of session.blocks) {
      const m = MOVEMENT_BY_ID.get(block.movementId)!
      if (m.loadable || block.unit !== 'reps') continue
      // There is no way to make a push-up heavy enough for a set of five.
      assert.equal(block.repLow, m.repLow,
        `${m.id} cannot be loaded, so a strength rep range is not available to it`)
    }
  }
})

test('every intent produces a coherent, defensible prescription', () => {
  for (const intent of INTENTS) {
    const week = generateWeek(intake({ intent }), 'gym')
    assert.ok(week.tempoRationale.length > 40, `${intent} cannot explain its tempo`)
    for (const session of week.sessions) {
      assert.ok(session.estimatedMinutes <= session.targetMinutes, `${intent} overran`)
      for (const block of session.blocks) {
        assert.ok(block.restSeconds > 0, `${intent} ${block.movementId} has no rest`)
        assert.ok(block.repHigh >= block.repLow)
        const m = MOVEMENT_BY_ID.get(block.movementId)!
        if (m.tempoApplies) {
          assert.ok(block.tempo, `${intent} ${m.id} should carry a tempo`)
          assert.match(block.note, /second/)
        }
      }
    }
  }
})

test('the cue reads as an instruction, not as a code', () => {
  const t = tempoFor(MOVEMENT_BY_ID.get('barbell_back_squat')!, 'hypertrophy')!
  // "3-1-1-0" means nothing to most people and hides which end the pause is at.
  assert.doesNotMatch(t.cue, /\d-\d/)
  assert.match(t.cue, /second/)
  assert.doesNotMatch(t.cue, /1 seconds/)
})
