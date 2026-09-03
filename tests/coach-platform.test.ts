import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'
import {
  COACH_CONSENT_SCOPES,
  coachClientPolicy,
  coachRosterAttention,
  validateCoachPlan,
  type CoachPlanDraft,
} from '../src/lib/coachPlatform.ts'

const completePlan = (): CoachPlanDraft => ({
  title: 'Foundation strength',
  objective: 'Build pain-free strength and repeatable training rhythm.',
  coach_note: 'Keep two good reps in reserve during the first week.',
  review_date: '2026-09-15',
  checklist: {
    nutrition: true,
    workouts: true,
    supplements: true,
    hydration: true,
    schedule: true,
    review_date: true,
  },
  sessions: [{
    id: '11111111-1111-4111-8111-111111111111',
    weekday: 1,
    name: 'Monday foundation',
    session_mode: 'guided',
    estimated_minutes: 38,
    warmup_note: 'Five minutes of pain-free joint preparation.',
    exercises: [{
      id: '22222222-2222-4222-8222-222222222222',
      movement_id: 'bodyweight-squat',
      name: 'Bodyweight squat',
      sets: 3,
      target_min: 10,
      target_max: 12,
      unit: 'reps',
      per_side: false,
      rest_seconds: 75,
      tempo_up_seconds: 1,
      tempo_down_seconds: 2,
      tempo_pause_seconds: 0,
      notes: 'Stop if knee pain appears.',
      optional: false,
      group_id: null,
      group_position: null,
    }],
  }],
})

test('consent is explicit and visual progress is never included by default', () => {
  assert.deepEqual(COACH_CONSENT_SCOPES, [
    'nutrition', 'workouts', 'activity', 'hydration', 'supplements',
    'avatar', 'measurements', 'notes', 'recovery', 'visual_progress',
  ])
  const policy = coachClientPolicy({
    relationship_status: 'active',
    seat_state: 'active',
    consented_scopes: ['nutrition', 'workouts', 'avatar'],
    individual_access: false,
  })
  assert.equal(policy.can_use_sponsored_app, true)
  assert.equal(policy.can_follow_coach_plan, true)
  assert.equal(policy.can_create_custom_workouts, false)
  assert.equal(policy.can_rebuild_fitness_plan, false)
  assert.equal(policy.can_use_orbit, false)
  assert.equal(policy.can_view_visual_progress, false)
  assert.equal(policy.can_use_nutrition, true)
  assert.equal(policy.can_use_avatar, true)
})

test('individual access survives sponsorship and grace is visibly read-only', () => {
  const grace = coachClientPolicy({
    relationship_status: 'grace',
    seat_state: 'grace',
    consented_scopes: ['workouts'],
    individual_access: false,
  })
  assert.equal(grace.can_use_sponsored_app, false)
  assert.equal(grace.can_follow_coach_plan, false)
  assert.equal(grace.coach_plan_read_only, true)

  const subscribed = coachClientPolicy({
    relationship_status: 'grace',
    seat_state: 'grace',
    consented_scopes: ['workouts'],
    individual_access: true,
  })
  assert.equal(subscribed.can_create_custom_workouts, true)
  assert.equal(subscribed.can_rebuild_fitness_plan, true)
})

test('a complete typed plan is publishable', () => {
  const result = validateCoachPlan(completePlan(), {
    publishing: true,
    known_movement_ids: new Set(['bodyweight-squat']),
  })
  assert.deepEqual(result.issues, [])
  assert.equal(result.publishable, true)
})

test('publication rejects unknown structure, catalogue gaps, duplicates, and unsafe prescriptions', () => {
  const plan = completePlan() as CoachPlanDraft & { surprise?: string }
  plan.surprise = 'not part of the contract'
  plan.sessions.push({
    ...plan.sessions[0],
    name: 'Duplicate identifier',
    weekday: 9,
    exercises: [{
      ...plan.sessions[0].exercises[0],
      movement_id: 'invented-movement',
      sets: 99,
      target_min: 20,
      target_max: 4,
    }],
  })
  plan.checklist.hydration = false
  const result = validateCoachPlan(plan, {
    publishing: true,
    known_movement_ids: new Set(['bodyweight-squat']),
  })
  assert.equal(result.publishable, false)
  assert.ok(result.issues.some((issue) => issue.code === 'unknown_field'))
  assert.ok(result.issues.some((issue) => issue.code === 'duplicate_id'))
  assert.ok(result.issues.some((issue) => issue.code === 'weekday'))
  assert.ok(result.issues.some((issue) => issue.code === 'movement'))
  assert.ok(result.issues.some((issue) => issue.code === 'sets'))
  assert.ok(result.issues.some((issue) => issue.code === 'target_order'))
  assert.ok(result.issues.some((issue) => issue.code === 'checklist'))
})

test('drafts may be incomplete but remain bounded', () => {
  const plan = completePlan()
  plan.sessions = []
  plan.title = ''
  const draft = validateCoachPlan(plan, { publishing: false })
  assert.equal(draft.publishable, false)
  assert.ok(!draft.issues.some((issue) => issue.code === 'sessions_required'))
  assert.ok(!draft.issues.some((issue) => issue.code === 'title_required'))

  plan.coach_note = 'x'.repeat(4_001)
  assert.ok(validateCoachPlan(plan, { publishing: false }).issues.some((issue) => issue.code === 'too_long'))
})

test('roster attention is deterministic and does not invent health judgements', () => {
  assert.deepEqual(coachRosterAttention({
    relationship_status: 'active',
    plan_version: null,
    plan_published_at: null,
    acknowledged_at: null,
    review_date: null,
    today: '2026-09-01',
  }), ['plan_missing'])

  assert.deepEqual(coachRosterAttention({
    relationship_status: 'active',
    plan_version: 4,
    plan_published_at: '2026-08-30T08:00:00Z',
    acknowledged_at: null,
    review_date: '2026-09-05',
    today: '2026-09-01',
  }), ['review_due', 'awaiting_acknowledgement'])
})

test('server contract is RLS isolated, token hashed, client activated, versioned, and append only', async () => {
  const sql = await readFile(new URL('../supabase/migrations/045_coach_platform_foundation.sql', import.meta.url), 'utf8')
  for (const table of [
    'coach_profiles', 'coach_invitations', 'coach_relationships', 'coach_plan_versions',
    'coach_plan_acknowledgements', 'coach_plan_installations', 'coach_audit_log',
  ]) {
    assert.match(sql, new RegExp(`alter table public\\.${table}[\\s\\S]*?enable row level security`, 'i'))
  }
  assert.match(sql, /digest\(v_token,\s*'sha256'\)/i)
  assert.match(sql, /auth\.jwt\(\)\s*->>\s*'email'/i)
  assert.match(sql, /visual_progress[^\n]+false/i)
  assert.match(sql, /create or replace function public\.coach_create_invitation/i)
  assert.match(sql, /create or replace function public\.coach_accept_invitation/i)
  assert.match(sql, /create or replace function public\.coach_publish_plan/i)
  assert.match(sql, /create or replace function public\.client_activate_coach_plan/i)
  assert.match(sql, /select\s+relationship\.\*\s+into\s+v_relationship/i)
  assert.match(sql, /select\s+plan\.\*\s+into\s+v_plan/i)
  assert.doesNotMatch(sql, /select\s+relationship\.\*,\s*plan\.\*/i)
  assert.match(sql, /is_active\s*=\s*false/i)
  assert.doesNotMatch(sql, /delete\s+from\s+public\.program_days/i)
  assert.match(sql, /prevent_coach_audit_mutation/i)
  assert.match(sql, /'grace_released'/i)
  assert.ok(sql.includes("p_plan ->> 'review_date', '') !~ '^\\d{4}-\\d{2}-\\d{2}$'"))
  assert.match(sql, /revoke\s+all[\s\S]+coach_audit_log/i)
  assert.match(sql, /9a0fffbc-bb02-40ac-834a-d4e339b32574/i)

  const overviewUpgrade = await readFile(new URL('../supabase/migrations/046_coach_overview_current_plan.sql', import.meta.url), 'utf8')
  assert.match(overviewUpgrade, /'current_plan',\s*v_current_plan/i)
  assert.match(overviewUpgrade, /order by plan\.version desc/i)
  assert.match(overviewUpgrade, /coach_preview_invitation/i)
  assert.match(overviewUpgrade, /v_email\s*<>\s*v_invitation\.invitee_email/i)
  assert.match(overviewUpgrade, /'offered_scopes',\s*to_jsonb\(relationship\.offered_scopes\)/i)
})

test('coach and sponsored-client surfaces expose the complete consented workflow', async () => {
  const [app, workspace, clientPlan, portal, nativeWorkspace, nativePlan, nativeShell] = await Promise.all([
    readFile(new URL('../src/App.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/CoachWorkspace.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/CoachPlan.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/Portal.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../ios/APEXNative/APEX/Features/Coach/CoachWorkspaceView.swift', import.meta.url), 'utf8'),
    readFile(new URL('../ios/APEXNative/APEX/Features/Coach/CoachPlanView.swift', import.meta.url), 'utf8'),
    readFile(new URL('../ios/APEXNative/APEX/Features/Portal/PortalShellView.swift', import.meta.url), 'utf8'),
  ])

  assert.match(app, /path="\/coach"/)
  assert.match(app, /path="\/coach\/invite\/:token"/)
  assert.match(app, /path="\/coach-plan"/)
  assert.match(workspace, /coachAPI\.createInvitation/)
  assert.match(workspace, /visual_progress/)
  assert.match(workspace, /validateCoachPlan/)
  assert.match(workspace, /coachAPI\.publishPlan/)
  assert.match(clientPlan, /coachAPI\.acknowledgePlan/)
  assert.match(clientPlan, /coachAPI\.activatePlan/)
  assert.match(clientPlan, /coachAPI\.updateScopes/)
  assert.match(clientPlan, /coachAPI\.endRelationship/)
  assert.match(portal, /capabilities\.coach_workspace[\s\S]*to="\/coach"/)
  assert.match(portal, /const sponsoredAccess = accountAccessHasSponsoredAccess\(appAccess\)/)
  assert.match(portal, /const showCoachPlan = sponsoredAccess \|\| coachPolicy\.coach_plan_read_only[\s\S]*\{showCoachPlan && \([\s\S]*to="\/coach-plan"/)
  assert.match(nativeWorkspace, /createCoachInvitation/)
  assert.match(nativeWorkspace, /publishCoachPlan/)
  assert.match(nativePlan, /acknowledgeCoachPlan/)
  assert.match(nativePlan, /activateCoachPlan/)
  assert.match(nativePlan, /updateCoachScopes/)
  assert.match(nativePlan, /endCoachRelationship/)
  assert.match(
    nativeShell,
    /case \.coachWorkspace:\s+if session\.coachContext\.capabilities\.coachWorkspace \{ CoachWorkspaceView\(\) \}\s+else \{ CoachFeatureLockedView\(\) \}/,
  )
  assert.match(nativeShell, /case \.coachPlan: CoachPlanView\(\)/)
  assert.match(nativeShell, /case \.coachWorkouts:[\s\S]*canFollowCoachPlan/)
})

test('simple mode keeps every manual-workout entry behind the custom-workout policy', async () => {
  const simpleHome = await readFile(new URL('../src/pages/SimpleHome.tsx', import.meta.url), 'utf8')
  const sponsoredOnly = coachClientPolicy({
    relationship_status: 'active',
    seat_state: 'active',
    consented_scopes: ['workouts'],
    individual_access: false,
  })
  const individual = coachClientPolicy({
    relationship_status: 'active',
    seat_state: 'active',
    consented_scopes: ['workouts'],
    individual_access: true,
  })

  assert.equal(sponsoredOnly.can_create_custom_workouts, false)
  assert.equal(individual.can_create_custom_workouts, true)
  assert.match(simpleHome, /const canCreateManualWorkouts = coachPolicy\.can_create_custom_workouts/)
  assert.match(simpleHome, /const sponsoredOnlyAccess = sponsoredAccess && !canCreateManualWorkouts/)
  assert.match(simpleHome, /const guidedProgramSlug: ProgramSlug = sponsoredOnlyAccess[\s\S]*?\? 'coach'/)
  assert.match(simpleHome, /canCreateManualWorkouts && <QuickWorkoutLauncher/)
  assert.match(simpleHome, /canCreateManualWorkouts && hasManualWorkout[\s\S]*?<TodayManualWorkoutCard/)
  assert.match(simpleHome, /canCreateManualWorkouts && \(\s*<ManualWorkoutLogger/)
})
