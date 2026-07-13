import test from 'node:test'
import assert from 'node:assert/strict'
import { adaptAfterMissedSession, adaptAfterRun, assessInduction, coordinateCampaignWithEvents, createCampaign, EMPTY_INDUCTION_ANSWERS, generateCampaignSessions, preserveUserOverride } from '../src/orbit/domain/campaign.ts'
import type { CalendarEvent } from '../src/lib/types.ts'
import type { MarathonInduction, MarathonInductionAnswers, OrbitRun } from '../src/orbit/domain/types.ts'

const userId = '00000000-0000-4000-8000-000000000001'

function answers(patch: Partial<MarathonInductionAnswers> = {}): MarathonInductionAnswers {
  return {
    ...EMPTY_INDUCTION_ANSWERS,
    race_name: 'Zurich Marathon', race_date: '2027-05-09', race_goal: 'finish_comfortably', course_profile: 'rolling', course_surface: 'road', climate_familiar: 'yes',
    running_frequency: 'three', weekly_distance: '20_35', longest_run: '10_15', consistency: 'three_six_months', race_experience: 'half', marathon_experience: 'never',
    structured_plan: 'completed_one', running_style: 'continuous', available_days: 'four', long_run_day: 'sunday', previous_issue: 'none', previous_surgery: 'no', issue_status: 'resolved', medication: 'none',
    strength_days_per_week: 3,
    ...patch,
  }
}

function induction(value: MarathonInductionAnswers): MarathonInduction {
  return { id: '00000000-0000-4000-8000-000000000201', user_id: userId, answers: value, current_step: 20, completed: true, outcome: null, outcome_reason: '', created_at: '2026-07-13T08:00:00Z', updated_at: '2026-07-13T08:00:00Z', sync_state: 'local' }
}

test('readiness gate assigns a credible base without using an arbitrary age penalty', () => {
  const assessment = assessInduction(answers(), '2026-07-13')
  assert.equal(assessment.outcome, 'ready')
  assert.equal(assessment.credible_base, true)
  const experienced = assessInduction(answers({ running_frequency: 'five_plus', weekly_distance: 'over_50', longest_run: 'over_21', consistency: 'over_six_months', marathon_experience: 'five_plus' }), '2026-07-13')
  assert.equal(experienced.outcome, 'ready')
})

test('a beginner receives Foundation and a race that is too close is not compressed', () => {
  const beginner = assessInduction(answers({ running_frequency: 'none', weekly_distance: 'under_10', longest_run: 'under_5', consistency: 'none' }), '2026-07-13')
  assert.equal(beginner.outcome, 'foundation')
  assert.match(beginner.reason, /Foundation to First Marathon/)
  const tooClose = assessInduction(answers({ race_date: '2026-09-01' }), '2026-07-13')
  assert.equal(tooClose.outcome, 'more_information')
  assert.match(tooClose.reason, /shorter than Orbit’s 12-week/)
})

test('current concerning status recommends professional review while resolved history does not block', () => {
  assert.equal(assessInduction(answers({ previous_issue: 'knee', previous_surgery: 'over_three_years', issue_status: 'resolved' }), '2026-07-13').outcome, 'ready')
  const current = assessInduction(answers({ previous_issue: 'knee', issue_status: 'changes_movement', pain_changes_movement: true }), '2026-07-13')
  assert.equal(current.outcome, 'professional_review')
  assert.doesNotMatch(current.reason, /medical clearance/i)
})

test('campaign generation is strength-aware, phased and preserves original prescriptions', () => {
  const item = induction(answers())
  const campaign = createCampaign(item, '2026-07-13')
  const sessions = generateCampaignSessions(campaign, item.answers, [1, 5], '2026-07-13')
  assert.ok(sessions.length > 30)
  assert.ok(new Set(sessions.map((session) => session.phase)).size >= 4)
  assert.ok(sessions.every((session) => session.prescribed_date === session.date))
  const quality = sessions.filter((session) => session.adapted.demanding && session.adapted.mission !== 'long_run')
  assert.ok(quality.every((session) => ![1, 5].includes(new Date(`${session.date}T12:00:00`).getDay())))
})

test('calendar event movement affects only the owning user and records the original date', () => {
  const item = induction(answers())
  const campaign = createCampaign(item, '2026-07-13')
  const sessions = generateCampaignSessions(campaign, item.answers, [], '2026-07-13')
  const demanding = sessions.find((session) => session.adapted.demanding)!
  const events: CalendarEvent[] = [
    { id: 'event-owner', user_id: userId, name: 'Championship filming', type: 'filming_championship', start_date: demanding.date, end_date: demanding.date, notes: '' },
    { id: 'event-other', user_id: '00000000-0000-4000-8000-000000000002', name: 'Other account travel', type: 'travel', start_date: sessions[0].date, end_date: sessions[0].date, notes: '' },
  ]
  const coordinated = coordinateCampaignWithEvents(campaign, sessions, events)
  const moved = coordinated.sessions.find((session) => session.id === demanding.id)!
  assert.notEqual(moved.date, demanding.date)
  assert.equal(moved.prescribed_date, demanding.date)
  assert.match(moved.adaptation_reason, /Championship filming/)
  assert.ok(coordinated.campaign.adaptations.some((adaptation) => adaptation.session_id === moved.id))
})

function completedRun(sessionId: string, effort = 9): OrbitRun {
  return {
    id: '00000000-0000-4000-8000-000000000301', user_id: userId, client_idempotency_key: 'run', local_date: '2026-07-15', started_at: '2026-07-15T08:00:00Z', ended_at: '2026-07-15T09:00:00Z',
    mission: 'tempo', route_id: null, campaign_session_id: sessionId, shoe_id: null, samples: [], pauses: [], manual_laps_m: [],
    metrics: { distance_m: 10_000, elapsed_s: 3600, moving_s: 3600, avg_pace_sec_km: 360, best_pace_sec_km: 350, elevation_gain_m: null, heart_rate_avg: null, cadence_avg: null, calories_kcal: 700, splits: [], rejected_samples: 0, gps_confidence: 'high' },
    check_in: { perceived_effort: effort, legs: 'very_heavy', discomfort: 'none', note: '' }, status: 'completed', sync_state: 'local', created_at: '2026-07-15T08:00:00Z', updated_at: '2026-07-15T09:00:00Z',
  }
}

test('hard and missed sessions adapt forward without stacking catch-up work', () => {
  const item = induction(answers())
  const campaign = createCampaign(item, '2026-07-13')
  const sessions = generateCampaignSessions(campaign, item.answers, [], '2026-07-13')
  const completed = sessions.find((session) => session.adapted.demanding)!
  const afterHard = adaptAfterRun(campaign, sessions, completedRun(completed.id))
  const reduced = afterHard.sessions.find((session) => session.adaptation_reason.includes('harder than intended'))
  assert.ok(reduced)
  assert.equal(reduced.original.demanding, true)
  assert.equal(reduced.adapted.demanding, false)
  const override = preserveUserOverride(reduced, true)
  assert.equal(override.adapted.mission, reduced.original.mission)
  assert.equal(override.user_override, true)

  const missedTarget = sessions.find((session) => session.adapted.demanding)!
  const afterMissed = adaptAfterMissedSession(campaign, sessions, missedTarget.id)
  assert.equal(afterMissed.sessions.find((session) => session.id === missedTarget.id)?.status, 'missed')
  assert.ok(afterMissed.campaign.adaptations.some((adaptation) => adaptation.reason.includes('not stacked')))
})
