import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { activeDateStorageKey, calendarDayState, isIsoDate, resolveActiveDate } from '../src/lib/activeDate.ts'

test('active date context prefers an explicit route date, then the saved per-user date', () => {
  assert.equal(resolveActiveDate({
    today: '2026-08-02',
    requestedDate: '2026-08-01',
    storedDate: '2026-07-31',
  }), '2026-08-01')
  assert.equal(resolveActiveDate({ today: '2026-08-02', storedDate: '2026-08-01' }), '2026-08-01')
  assert.equal(resolveActiveDate({ today: '2026-08-02', storedDate: 'not-a-date' }), '2026-08-02')
  assert.equal(activeDateStorageKey('user-1'), 'apex-active-date:user-1')
  assert.equal(isIsoDate('2026-02-29'), false)
})

test('Simple and Nutrition share the same per-profile active date context', () => {
  const simple = readFileSync(new URL('../src/pages/SimpleHome.tsx', import.meta.url), 'utf8')
  const nutrition = readFileSync(new URL('../src/pages/Nutrition.tsx', import.meta.url), 'utf8')
  assert.match(simple, /loadActiveDate\(profile\?\.user_id, today\)/)
  assert.match(simple, /rememberActiveDate\(profile\?\.user_id, selectedDate\)/)
  assert.match(nutrition, /loadActiveDate\(data\.profile\?\.user_id, today, requestedDate\)/)
  assert.match(nutrition, /rememberActiveDate\(profile\?\.user_id, selectedLogDate\)/)
})

test('completed Simple Mode training opens summaries and editable stats', () => {
  const simple = readFileSync(new URL('../src/pages/SimpleHome.tsx', import.meta.url), 'utf8')
  assert.match(simple, /completedWorkoutSessions\.map/)
  assert.match(simple, /setWorkoutStatsSessionId\(session\.id\)/)
  assert.match(simple, /daylineDateTimeToIso\(selectedDate, completedWorkoutTimeDraft, mealTimeZone\)/)
  assert.match(simple, /<WorkoutStatsSheet/)
})

test('the real current day stays identified when another calendar day is selected', () => {
  assert.deepEqual(calendarDayState({
    date: '2026-08-26',
    selectedDate: '2026-08-01',
    today: '2026-08-26',
  }), {
    isSelected: false,
    isToday: true,
    ariaCurrent: 'date',
  })

  assert.deepEqual(calendarDayState({
    date: '2026-08-01',
    selectedDate: '2026-08-01',
    today: '2026-08-26',
  }), {
    isSelected: true,
    isToday: false,
    ariaCurrent: undefined,
  })
})
