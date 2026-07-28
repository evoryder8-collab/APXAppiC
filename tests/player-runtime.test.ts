import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { exerciseExecutionCue } from '../src/lib/exerciseGuidance.ts'
import {
  prefillSetWeight,
  reconcilePlayerElapsed,
  type Block,
} from '../src/lib/playerTimeline.ts'

const passiveRest = { kind: 'rest' } as Block
const activeSet = { kind: 'set' } as Block

test('backgrounded passive timers reconcile from wall-clock time', () => {
  const result = reconcilePlayerElapsed({
    block: passiveRest,
    elapsed: 24,
    paused: false,
    persistedAt: '2026-07-28T10:00:00.000Z',
    now: Date.parse('2026-07-28T10:02:00.000Z'),
  })
  assert.deepEqual(result, { elapsed: 144, paused: false })
})

test('backgrounded active sets never manufacture repetitions', () => {
  assert.deepEqual(reconcilePlayerElapsed({
    block: activeSet,
    elapsed: 7.5,
    paused: false,
    persistedAt: '2026-07-28T10:00:00.000Z',
    now: Date.parse('2026-07-28T10:02:00.000Z'),
  }), { elapsed: 7.5, paused: true })
})

test('the next set defaults to the most recently entered real load', () => {
  assert.equal(prefillSetWeight([17], 2, null, 2.5), 17)
  assert.equal(prefillSetWeight([17, 20], 3, null, 2.5), 20)
  assert.equal(prefillSetWeight([], 1, 12.5, 2.5), 12.5)
})

test('exercise instructions are localized and available from the player list', () => {
  assert.match(exerciseExecutionCue('Bulgarian Split Squat', 'ro'), /talpa|picior/i)
  assert.match(exerciseExecutionCue('Focus T25 · Lower Focus', 'th'), /หน้าจอ|ท่าปรับง่าย/)
  const player = readFileSync(new URL('../src/pages/Player.tsx', import.meta.url), 'utf8')
  assert.match(player, /selectedExerciseInfo/)
  assert.match(player, /exerciseExecutionCue/)
  assert.match(player, /Completed with modifier/)
})

test('Focus T25 review uses completion-specific controls instead of strength fields', () => {
  const receipt = readFileSync(new URL('../src/components/workout/WorkoutStatsSheet.tsx', import.meta.url), 'utf8')
  assert.match(receipt, /isFocusT25Name/)
  assert.match(receipt, /copy\.modifier/)
  assert.match(receipt, /weight_kg: null/)
  assert.match(receipt, /rir: null/)
})
