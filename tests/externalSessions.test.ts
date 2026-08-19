import { strict as assert } from 'node:assert'
import { test } from 'node:test'
import {
  EXTERNAL_SESSION_TYPES,
  creditForSession,
  recallLabel,
  rememberLabel,
} from '../src/lib/externalSessions.ts'

test('the catalogue ships no third-party programme or session names', () => {
  /* The whole point of the generic catalogue: APEX distributes no marks it
     has no right to. A brand name appearing here would defeat it. */
  const text = JSON.stringify(EXTERNAL_SESSION_TYPES).toLowerCase()
  const marks = [
    'beachbody', 'insanity', 'p90x', 'focus t25', 'shaun t', 'peloton',
    'les mills', 'zumba', 'crossfit', 'orangetheory', 'barry', 'f45',
  ]
  for (const mark of marks) {
    assert.equal(text.includes(mark), false, `catalogue must not ship "${mark}"`)
  }
})

test('a session shapes its credit by type, not just by length', () => {
  const hiit = creditForSession({ label: 'my cardio thing', type: 'hiit', minutes: 30 })
  const yoga = creditForSession({ label: 'evening stretch', type: 'yoga_restorative', minutes: 30 })

  assert.ok(hiit.endurance > yoga.endurance * 5, 'HIIT builds far more endurance')
  assert.ok(yoga.flexibility > hiit.flexibility * 5, 'restorative yoga builds far more flexibility')
  assert.ok(hiit.fatigue > yoga.fatigue * 5, 'and costs far more')
})

test('effort scales the credit, but cannot rewrite a week', () => {
  const normal = creditForSession({ label: 'x', type: 'run', minutes: 30, effort: 7 })
  const brutal = creditForSession({ label: 'x', type: 'run', minutes: 30, effort: 10 })
  const easy = creditForSession({ label: 'x', type: 'run', minutes: 30, effort: 3 })

  assert.ok(brutal.endurance > normal.endurance)
  assert.ok(easy.endurance < normal.endurance)
  /* Deliberately narrow: a maximal self-report is worth about half again as
     much as a normal one, not triple. */
  assert.ok(brutal.endurance < normal.endurance * 1.6, 'one heroic self-report cannot dominate')
  assert.ok(easy.endurance > 0, 'and an easy session still counts for something')
})

test('resistance exposure and impact are tracked separately from credit', () => {
  const circuit = creditForSession({ label: 'weights class', type: 'circuit_resistance', minutes: 40 })
  assert.equal(circuit.resistanceExposure, true, 'a weights circuit is a resistance exposure')

  const swim = creditForSession({ label: 'pool', type: 'swim', minutes: 40 })
  assert.equal(swim.resistanceExposure, false)
  assert.equal(swim.impactMinutes, 0, 'swimming carries no impact load')

  const run = creditForSession({ label: 'park', type: 'run', minutes: 40 })
  assert.equal(run.impactMinutes, 40, 'running is all impact, which the knee rules need')
})

test('a missing or absurd duration falls back rather than distorting', () => {
  const missing = creditForSession({ label: 'x', type: 'hiit', minutes: 0 })
  assert.ok(missing.endurance > 0, 'falls back to the typical length for the type')
  const absurd = creditForSession({ label: 'x', type: 'run', minutes: 5000 })
  const capped = creditForSession({ label: 'x', type: 'run', minutes: 240 })
  assert.equal(absurd.endurance, capped.endurance, 'capped at four hours')
})

test('the app learns what a person calls their own sessions', () => {
  let memory: Record<string, ReturnType<typeof recallLabel> extends null ? never : any> = {}
  assert.equal(recallLabel(memory, 'Pure Cardio'), null, 'nothing is known on the first log')

  memory = rememberLabel(memory, 'Pure Cardio', 'hiit')
  assert.equal(recallLabel(memory, 'Pure Cardio'), 'hiit')
  assert.equal(recallLabel(memory, 'pure cardio'), 'hiit', 'case does not matter')
  assert.equal(recallLabel(memory, 'Pure Cardio 2'), 'hiit', 'a near match is offered')
  assert.equal(recallLabel(memory, 'Morning swim'), null, 'an unrelated label is not guessed')
})

test('every type declares a complete contribution', () => {
  for (const type of EXTERNAL_SESSION_TYPES) {
    const c = type.contribution
    for (const [key, value] of Object.entries(c)) {
      assert.ok(value >= 0 && value <= 1, `${type.id}.${key} out of range: ${value}`)
    }
    assert.ok(type.typicalMinutes > 0 && type.typicalMinutes <= 120, type.id)
    assert.ok(type.label.length > 0 && type.hint.length > 0, type.id)
  }
})
