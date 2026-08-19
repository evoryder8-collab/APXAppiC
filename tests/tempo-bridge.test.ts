import assert from 'node:assert/strict'
import test from 'node:test'
import { MOVEMENTS, MOVEMENT_ALIASES, MOVEMENT_BY_ID } from '../src/data/movements.ts'
import { resolveMovement, tempoFieldsFor } from '../src/lib/liftingTempo.ts'
import { EXERCISE_CATALOG } from '../src/data/exerciseCatalog.ts'

test('the cadence engine is given a per-movement tempo, not one default', () => {
  const cadences = new Set<string>()
  for (const m of MOVEMENTS.filter((x) => x.prescriptionMode === 'tempo_reps')) {
    const t = tempoFieldsFor(m, 'hypertrophy')
    cadences.add(`${t.tempo_down_s}-${t.tempo_pause_s}-${t.tempo_up_s}`)
    assert.ok(t.tempo_down_s > 0 && t.tempo_up_s > 0, `${m.id} has no countable phases`)
  }
  // 301 of 439 live exercises shared 2-0-1 across 78 movements before this.
  assert.ok(cadences.size >= 4, `only ${cadences.size} distinct cadences reach the player`)
})

test('a movement with no rep to time is not given a cadence to count', () => {
  for (const id of ['plank', 'farmers_carry', 'box_jump', 'power_clean', 'downward_dog']) {
    const m = MOVEMENT_BY_ID.get(id)!
    const t = tempoFieldsFor(m, 'hypertrophy')
    assert.equal(t.tempo_down_s, 0, `${id} would have its phases counted`)
    assert.equal(t.tempo_pause_s, 0, id)
    assert.equal(t.tempo_up_s, 0, id)
    // But it still tells the follower what governs the set.
    assert.ok(t.tempo_note.length > 0, `${id} says nothing about how to perform it`)
  }
})

test('the spoken note names where the pause is, not just that there is one', () => {
  const thrust = tempoFieldsFor(MOVEMENT_BY_ID.get('hip_thrust_barbell')!, 'hypertrophy')
  assert.match(thrust.tempo_note, /top/)
  const squat = tempoFieldsFor(MOVEMENT_BY_ID.get('barbell_back_squat')!, 'hypertrophy')
  assert.match(squat.tempo_note, /stretch/)
  // Short enough to read mid-set or say aloud between reps.
  for (const m of MOVEMENTS.filter((x) => x.prescriptionMode === 'tempo_reps')) {
    assert.ok(tempoFieldsFor(m, 'hypertrophy').tempo_note.length <= 40, m.id)
  }
})

test('authored programme names still resolve to their movement', () => {
  // Programme rows carry their own names, so resolution has to survive the
  // parenthetical the coach wrote for the person following along.
  const cases: [string, string][] = [
    ['Pull-Ups (different grip than Wed)', 'pull_up'],
    ['Bulgarian Split Squat (backpack)', 'bulgarian_split_squat'],
    ['Romanian Deadlift', 'barbell_romanian_deadlift'],
    ['Seated Dumbbell Press', 'dumbbell_overhead_press'],
  ]
  for (const [name, expected] of cases) {
    const m = resolveMovement(name, MOVEMENTS, MOVEMENT_ALIASES)
    assert.equal(m?.id, expected, `"${name}" resolved to ${m?.id ?? 'nothing'}`)
  }
  // And an unknown name resolves to nothing rather than to something wrong.
  assert.equal(resolveMovement('Interpretive Dance', MOVEMENTS, MOVEMENT_ALIASES), null)
})

test('most of what a custom workout can contain gets a real tempo', () => {
  const resolved = EXERCISE_CATALOG.filter(
    (item) => resolveMovement(item.name, MOVEMENTS, MOVEMENT_ALIASES) !== null)
  const share = resolved.length / EXERCISE_CATALOG.length
  // Anything unresolved falls back to the old default rather than guessing,
  // so this is a coverage measure and not a correctness one -- but a custom
  // workout that mostly falls back has not gained anything.
  assert.ok(share > 0.5,
    `only ${Math.round(share * 100)}% of the custom catalogue maps onto a movement`)
})
