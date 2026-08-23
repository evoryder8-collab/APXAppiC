import assert from 'node:assert/strict'
import test from 'node:test'
import { buildSessionRecords, type SessionDraft } from '../src/lib/workoutSession.ts'
import { buildWorkSequence } from '../src/lib/workGrouping.ts'

test('the same round model scales from a pair to a three-member circuit', () => {
  const sequence = buildWorkSequence([
    { sets: 2, rep_unit: 'reps', work_group_id: 'group', work_group_position: 1 },
    { sets: 2, rep_unit: 'reps', work_group_id: 'group', work_group_position: 2 },
    { sets: 2, rep_unit: 'reps', work_group_id: 'group', work_group_position: 3 },
  ])

  assert.deepEqual(
    sequence.map(({ exIdx, setNo, groupLabel }) => `${groupLabel}:${exIdx}:${setNo}`),
    ['A1:0:1', 'A2:1:1', 'A3:2:1', 'A1:0:2', 'A2:1:2', 'A3:2:2'],
  )
})

test('linked work persists in the round-major order it was performed', () => {
  const draft = {
    sessionId: 'session',
    userId: 'user',
    date: '2026-08-23',
    programDayId: 'day',
    isLite: false,
    isDeload: false,
    isEventRecovery: false,
    qualityScore: 1,
    startedAt: '2026-08-23T10:00:00.000Z',
    completedAt: '2026-08-23T10:10:00.000Z',
    exercises: [
      {
        exerciseId: 'push', movementId: null, name: 'Bench Press', plannedSets: 2,
        workGroupId: 'upper-pair', workGroupPosition: 1, repUnit: 'reps',
        skipped: false, override: false,
        sets: [
          { weight: 60, reps: 8, rir: 2 },
          { weight: 60, reps: 7, rir: 1 },
        ],
      },
      {
        exerciseId: 'pull', movementId: null, name: 'Seated Row', plannedSets: 2,
        workGroupId: 'upper-pair', workGroupPosition: 2, repUnit: 'reps',
        skipped: false, override: false,
        sets: [
          { weight: 50, reps: 10, rir: 2 },
          { weight: 50, reps: 9, rir: 1 },
        ],
      },
    ],
  } as SessionDraft

  const records = buildSessionRecords(draft, (() => {
    let next = 0
    return () => `log-${next++}`
  })())

  assert.deepEqual(
    records.logs.map((log) => `${log.exercise_id}:${log.set_no}`),
    ['push:1', 'pull:1', 'push:2', 'pull:2'],
  )
  assert.deepEqual(
    records.logs.map((log) => log.created_at),
    [
      '2026-08-23T10:10:00.000Z',
      '2026-08-23T10:10:00.001Z',
      '2026-08-23T10:10:00.002Z',
      '2026-08-23T10:10:00.003Z',
    ],
  )
})
