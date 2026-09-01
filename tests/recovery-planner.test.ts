import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

import type { Program, ProgramDay, Settings } from '../src/lib/types.ts'
import {
  buildRecoveryPlan,
  recoveryDayMatchesDate,
  scheduledRecoveryDates,
} from '../src/lib/recoveryPlanner.ts'

const owner = '10000000-0000-4000-8000-000000000001'
const main: Program = {
  id: '20000000-0000-4000-8000-000000000001',
  user_id: owner,
  slug: 'main',
  name: 'Main',
  description: '',
}

function day(id: string, weekday: number, dayType: ProgramDay['day_type']): ProgramDay {
  return {
    id,
    user_id: owner,
    program_id: main.id,
    weekday,
    name: id,
    day_type: dayType,
    est_minutes: 45,
    warmup_note: '',
    sort_order: weekday,
    session_mode: 'guided',
    is_active: true,
  }
}

const settings: Settings = {
  user_id: owner,
  locale: 'en',
  units: 'metric',
  meal_timezone: 'Europe/Zurich',
  addons: {
    training_induction: {
      version: 1,
      completed_at: '2026-08-01T08:00:00Z',
      start_date: '2026-08-01',
      main_start_date: '2026-08-15',
      end_date: '2026-12-31',
      transition_weeks: 2,
      inactivity: 'currently_training',
      venue: 'gym',
      equipment: [],
      pain_areas: [],
      recent_operation: false,
      chronic_lower_back_pain: false,
      sessions_per_week: 3,
      goal: 'rebuild',
      caution: 'standard',
      transition_day_ids: [],
      main_day_ids: [],
    },
  },
}

test('recovery scheduling creates two low-load exact dates in each of four weeks', () => {
  const existing = [day('heavy-monday', 1, 'legs_a'), day('heavy-thursday', 4, 'push')]
  const dates = scheduledRecoveryDates('2026-09-01', existing, 4, 2)
  assert.equal(dates.length, 8)
  assert.equal(new Set(dates).size, 8)
  for (let week = 0; week < 4; week += 1) {
    const pair = dates.slice(week * 2, week * 2 + 2)
    assert.equal(pair.length, 2)
    assert.notEqual(pair[0], pair[1])
  }
  assert.equal(dates.some((date) => new Date(`${date}T12:00:00Z`).getUTCDay() === 1), false)
})

test('guided recovery rows are account-owned, exact-date, grouped, and catalogue-backed', () => {
  let sequence = 0
  const result = buildRecoveryPlan({
    ownerId: owner,
    startDate: '2026-09-01',
    target: 'joint',
    source: 'guided',
    programs: [main],
    settings,
    existingDays: [day('heavy-monday', 1, 'legs_a')],
    makeId: () => `30000000-0000-4000-8000-${String(++sequence).padStart(12, '0')}`,
  })
  assert.equal(result.days.length, 8)
  assert.equal(result.days.every((row) => row.user_id === owner), true)
  assert.equal(result.days.every((row) => row.scheduled_date != null), true)
  assert.equal(result.days.every((row) => row.recovery_plan_id === result.planId), true)
  assert.equal(result.days.every((row) => row.recovery_target === 'joint' && row.recovery_source === 'guided'), true)
  assert.equal(result.exercises.length > result.days.length, true)
  assert.equal(result.exercises.some((row) => row.name === 'Wall Slide'), true)
  assert.equal(result.exercises.some((row) => row.name === 'Ankle Mobility Rock'), true)
})

test('own-session fallback schedules one honest mobility receipt per date', () => {
  const result = buildRecoveryPlan({
    ownerId: owner,
    startDate: '2026-09-01',
    target: 'flexibility',
    source: 'external',
    programs: [main],
    settings,
    existingDays: [],
  })
  assert.equal(result.days.length, 8)
  assert.equal(result.exercises.length, 8)
  assert.equal(result.exercises.every((row) => row.name === 'Mobility Flow'), true)
  assert.equal(result.exercises.every((row) => row.rep_unit === 'minutes'), true)
})

test('an exact recovery day never repeats on the same weekday', () => {
  const scheduled = { ...day('scheduled', 3, 'mobility'), scheduled_date: '2026-09-09' }
  assert.equal(recoveryDayMatchesDate(scheduled, '2026-09-09'), true)
  assert.equal(recoveryDayMatchesDate(scheduled, '2026-09-16'), false)
  assert.equal(recoveryDayMatchesDate(day('weekly', 3, 'mobility'), '2026-09-16'), true)
})

test('Plan it opens the recovery planner and the database metadata stays owner-scoped', () => {
  const avatar = readFileSync(new URL('../src/pages/AvatarPage.tsx', import.meta.url), 'utf8')
  const migration = readFileSync(new URL('../supabase/migrations/047_recovery_plan_scheduling.sql', import.meta.url), 'utf8')
  assert.match(avatar, /setRecoveryTarget/)
  assert.match(avatar, /RecoveryPlannerDialog/)
  assert.match(migration, /scheduled_date date/)
  assert.match(migration, /recovery_target.*joint.*flexibility/s)
  assert.match(migration, /program_days_user_scheduled_date_idx/)
})

test('the Zürich-city Swiss German pass remains an explicit deferred whole-locale project', () => {
  const roadmap = readFileSync(new URL('../docs/ROADMAP.md', import.meta.url), 'utf8')
  assert.match(roadmap, /Deferred project — Zürich-city Swiss German/)
  assert.match(roadmap, /Bernese, St Gallen, Zürich and standard-German/)
  assert.match(roadmap, /no half-dialect release/)
})
