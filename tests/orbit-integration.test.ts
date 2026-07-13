import test from 'node:test'
import assert from 'node:assert/strict'
import { authoritativeActivityLogs, avatarContributionForRun, nutritionAdjustmentForRun, trainingAdjustmentForRun } from '../src/orbit/domain/integrations.ts'
import { recommendMission, scoreRouteCandidate } from '../src/orbit/domain/missions.ts'
import { orbitUuid } from '../src/orbit/domain/ids.ts'
import type { ActivityLog, Profile } from '../src/lib/types.ts'
import type { OrbitRun, RouteCandidate, RouteRequest } from '../src/orbit/domain/types.ts'

const userId = '00000000-0000-4000-8000-000000000001'
const profile: Profile = { id: userId, user_id: userId, persona: 'constantine', display_name: 'Constantine', sex: 'male', weight_kg: 70, body_fat_pct: 20, height_cm: 175, birthdate: '1992-07-25', activity_level: 'moderate', goal: 'recomp', target_kcal: null, target_protein_g: null, target_fat_g: null, target_carbs_g: null, training_time: '19:00', baseline_date: '2026-01-01', profile_note: '', seed_version: 1, calibration_k: 1, calibration_history: [], updated_at: '2026-07-13T00:00:00Z' }

function run(patch: Partial<OrbitRun> = {}): OrbitRun {
  return { id: '00000000-0000-4000-8000-000000000401', user_id: userId, client_idempotency_key: 'run', local_date: '2026-07-13', started_at: '2026-07-13T08:00:00Z', ended_at: '2026-07-13T10:00:00Z', mission: 'long_run', route_id: null, campaign_session_id: null, shoe_id: null, samples: [], pauses: [], manual_laps_m: [], metrics: { distance_m: 18_000, elapsed_s: 7200, moving_s: 7200, avg_pace_sec_km: 400, best_pace_sec_km: 380, elevation_gain_m: null, heart_rate_avg: null, cadence_avg: null, calories_kcal: 1260, splits: [], rejected_samples: 0, gps_confidence: 'high' }, check_in: { perceived_effort: 7, legs: 'heavy', discomfort: 'none', note: 'fuel tolerated' }, status: 'completed', sync_state: 'local', created_at: '2026-07-13T08:00:00Z', updated_at: '2026-07-13T10:00:00Z', ...patch }
}

test('completed Orbit run is authoritative and removes overlapping manual distance and watch energy', () => {
  const existing: ActivityLog[] = [
    { id: 'manual-run', user_id: userId, date: '2026-07-13', type_id: 'jog-run', quantity: 1, duration_min: 120, distance_km: 18, watch_kcal: null, computed_kcal: 1260, source: 'manual', reconciled: false, created_at: '', updated_at: '' },
    { id: 'watch', user_id: userId, date: '2026-07-13', type_id: 'watch-kcal', quantity: 1, duration_min: null, distance_km: null, watch_kcal: 1400, computed_kcal: 1120, source: 'manual', reconciled: false, created_at: '', updated_at: '' },
    { id: 'massage', user_id: userId, date: '2026-07-13', type_id: 'massage-session', quantity: 1, duration_min: 60, distance_km: null, watch_kcal: null, computed_kcal: 196, source: 'manual', reconciled: true, created_at: '', updated_at: '' },
  ]
  const result = authoritativeActivityLogs(existing, run(), profile)
  assert.deepEqual(new Set(result.removeIds), new Set(['manual-run', 'watch']))
  assert.equal(result.orbitLog.source, 'orbit')
  assert.equal(result.orbitLog.computed_kcal, 1260)
  assert.ok(!result.removeIds.includes('massage'))
})

test('cross-domain proposals are exact, optional and based only on recorded facts', () => {
  const item = run()
  const nutrition = nutritionAdjustmentForRun(item, 70)
  assert.equal(nutrition.kcal, nutrition.carbs_g * 4 + nutrition.protein_g * 4 + nutrition.fat_g * 9)
  assert.match(nutrition.explanation, /Nothing changes until you apply it/)
  const avatar = avatarContributionForRun(item)
  assert.equal(avatar.endurance_minutes, 120)
  assert.match(avatar.explanation, /one authoritative endurance record/)
  const training = trainingAdjustmentForRun(item, [], [])
  assert.equal(training.reversible, true)
  assert.notEqual(training.action, 'none')
})

test('one clear mission recommendation respects strength context and campaign prescriptions', () => {
  const base = { lowerBodyYesterday: true, lowerBodyToday: false, lowerBodyTomorrow: false, recoveryStable: true, enduranceTrend: 'stable' as const, availableMinutes: 60, recentRuns: [] }
  const recovery = recommendMission(base)
  assert.equal(recovery.mission, 'recovery')
  assert.match(recovery.reason, /lower-body/)
  const campaign = recommendMission({ ...base, campaignMission: 'marathon_pace', campaignTitle: 'Marathon pace durability', campaignDurationMin: 55 })
  assert.equal(campaign.mission, 'marathon_pace')
  assert.equal(campaign.duration_min, 55)
})

test('mission-aware route scoring prefers simple flat recovery routes and exploration novelty', () => {
  const now = '2026-07-13T00:00:00Z'
  const candidate = (patch: Partial<RouteCandidate>): RouteCandidate => ({ id: crypto.randomUUID(), user_id: userId, client_idempotency_key: crypto.randomUUID(), name: 'Route', note: '', points: [{ lat: 47, lng: 8 }, { lat: 47.01, lng: 8 }], distance_m: 5000, elevation_gain_m: 20, surface: 'path', terrain: 'flat', shape: 'loop', navigation_complexity: 'low', familiarity_pct: 80, favourite: false, rating: null, mission_tags: [], preferred_sections: [], avoided_sections: [], provider: 'test', attribution: 'test', created_at: now, updated_at: now, sync_state: 'local', score: 0, explanation: '', estimated_duration_min: 30, ...patch })
  const request: RouteRequest = { start: { lat: 47, lng: 8 }, distance_km: 5, duration_min: null, mission: 'recovery', shape: 'loop', terrain: 'flat', surface: 'path', familiarity: 'balanced', simple_navigation: true, avoid_notes: [] }
  assert.ok(scoreRouteCandidate(candidate({}), request) > scoreRouteCandidate(candidate({ terrain: 'hilly', navigation_complexity: 'high' }), request))
  assert.ok(scoreRouteCandidate(candidate({ familiarity_pct: 5 }), { ...request, mission: 'exploration', familiarity: 'exploratory' }) > scoreRouteCandidate(candidate({ familiarity_pct: 95 }), { ...request, mission: 'exploration', familiarity: 'exploratory' }))
})

test('deterministic ids and computations remain account-scoped', () => {
  const other = '00000000-0000-4000-8000-000000000002'
  assert.notEqual(orbitUuid(userId, 'route:river'), orbitUuid(other, 'route:river'))
  const otherProfile = { ...profile, user_id: other, id: other, weight_kg: 58 }
  assert.equal(authoritativeActivityLogs([], run({ user_id: other }), otherProfile).orbitLog.computed_kcal, Math.round(58 * 18))
  assert.equal(authoritativeActivityLogs([], run(), profile).orbitLog.computed_kcal, 1260)
})
