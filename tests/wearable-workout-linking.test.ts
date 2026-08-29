import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { UI_TRANSLATIONS } from '../src/lib/translations.ts'
import type { ImportedActivity, WorkoutSession } from '../src/lib/types.ts'
import {
  automaticWearableLinks,
  explicitWearableLink,
  wearableCandidatesForDay,
} from '../src/lib/wearableWorkoutLinking.ts'

function session(overrides: Partial<WorkoutSession> = {}): WorkoutSession {
  return {
    id: overrides.id ?? 'session',
    user_id: overrides.user_id ?? 'owner',
    date: overrides.date ?? '2026-08-29',
    program_day_id: overrides.program_day_id ?? 'day',
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: true,
    quality_score: 1,
    started_at: overrides.started_at ?? '2026-08-29T10:00:00.000Z',
    completed_at: overrides.completed_at ?? '2026-08-29T11:00:00.000Z',
    notes: overrides.notes ?? 'Completed in APEX',
  }
}

function activity(id: string, overrides: Partial<ImportedActivity> = {}): ImportedActivity {
  return {
    id,
    user_id: overrides.user_id ?? 'owner',
    date: overrides.date ?? '2026-08-29',
    kind: overrides.kind ?? 'strength',
    activity: overrides.activity ?? 'Traditional Strength Training',
    duration_min: overrides.duration_min ?? 60,
    source: overrides.source ?? 'Constantin’s Apple Watch',
    healthkit_workout_id: overrides.healthkit_workout_id ?? `hk-${id}`,
    started_at: overrides.started_at ?? '2026-08-29T09:55:00.000Z',
    ended_at: overrides.ended_at ?? '2026-08-29T10:55:00.000Z',
    workout_name_key: overrides.workout_name_key ?? 'health.workout.traditional_strength_training',
    source_bundle_id: overrides.source_bundle_id ?? 'com.apple.health',
    apex_workout_session_id: overrides.apex_workout_session_id ?? null,
    hidden_at: overrides.hidden_at ?? null,
  }
}

test('one overlapping wearable workout links at the inclusive five-minute boundary', () => {
  const workout = session()
  const boundary = activity('boundary')

  assert.deepEqual(
    automaticWearableLinks([workout], [boundary], 'owner').map((row) => [row.id, row.apex_workout_session_id]),
    [['boundary', 'session']],
  )

  const endedBeforeAPEX = activity('ended-before', {
    started_at: '2026-08-29T09:50:00.000Z',
    ended_at: '2026-08-29T09:59:59.000Z',
  })
  assert.deepEqual(automaticWearableLinks([workout], [endedBeforeAPEX], 'owner'), [])
})

test('automatic association refuses to guess between multiple wearable activities', () => {
  const workout = session()
  const first = activity('first', { started_at: '2026-08-29T09:58:00.000Z' })
  const second = activity('second', { started_at: '2026-08-29T10:02:00.000Z' })

  assert.deepEqual(automaticWearableLinks([workout], [first, second], 'owner'), [])
})

test('manual choices are external, owner/day scoped, unlinked, and newest first', () => {
  const rows = [
    activity('older', { started_at: '2026-08-29T07:00:00.000Z' }),
    activity('newer', { started_at: '2026-08-29T12:00:00.000Z' }),
    activity('hidden', { hidden_at: '2026-08-29T12:30:00.000Z' }),
    activity('foreign', { user_id: 'someone-else' }),
    activity('other-day', { date: '2026-08-28' }),
    activity('already-linked', { apex_workout_session_id: 'another-session' }),
    activity('apex-mirror', { source_bundle_id: 'ch.apexperformance.APEX.watchkitapp' }),
  ]

  assert.deepEqual(wearableCandidatesForDay(rows, 'owner', '2026-08-29').map((row) => row.id), ['newer', 'older'])
  assert.equal(explicitWearableLink(rows[1], session())?.apex_workout_session_id, 'session')
  assert.equal(explicitWearableLink(rows[3], session()), null)
})

test('an activity eligible for two overlapping APEX sessions remains unlinked', () => {
  const shared = activity('shared', {
    started_at: '2026-08-29T10:02:00.000Z',
    ended_at: '2026-08-29T10:45:00.000Z',
  })
  const first = session({ id: 'first', started_at: '2026-08-29T10:00:00.000Z' })
  const second = session({ id: 'second', started_at: '2026-08-29T10:01:00.000Z' })

  assert.deepEqual(automaticWearableLinks([first, second], [shared], 'owner'), [])
})

test('manual completion and linked receipts are implemented without inventing unrecorded sets', () => {
  const player = readFileSync(new URL('../src/pages/Player.tsx', import.meta.url), 'utf8')
  const receipts = readFileSync(new URL('../src/components/workout/CompletedWorkoutHistoryCards.tsx', import.meta.url), 'utf8')

  assert.match(player, /Already finished\?/)
  assert.match(player, /result\?\.finalized === true/)
  assert.match(player, /automaticWearableLinks/)
  assert.match(player, /explicitWearableLink/)
  assert.match(player, /if \(!externallyCompleted && activityType && data\.profile\)/)
  assert.match(player, /if \(!externallyCompleted && completedFocusT25/)
  assert.match(receipts, /data-linked-wearable-evidence/)
  assert.match(receipts, /Device metrics are read-only and are not added to HealthKit energy twice\./)
})

test('wearable recovery copy is authored in Romanian and Thai', () => {
  for (const key of [
    'Already finished?',
    'Did you finish this planned workout on your own?',
    'Choose the wearable activity that matches this workout',
    'Finish without a wearable',
    'Linked wearable effort',
    'Device metrics are read-only and are not added to HealthKit energy twice.',
    'That wearable activity is no longer available. Choose it again.',
    'Completed externally from the APEX guided player',
  ]) {
    assert.ok(UI_TRANSLATIONS[key]?.ro)
    assert.ok(UI_TRANSLATIONS[key]?.th)
    assert.notEqual(UI_TRANSLATIONS[key]?.ro, key)
    assert.notEqual(UI_TRANSLATIONS[key]?.th, key)
  }
})
