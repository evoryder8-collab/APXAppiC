import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

import { coachClientPolicy } from '../src/lib/coachPlatform.ts'

test('sponsored-only coach access cannot create custom workouts while individual access can', () => {
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

  assert.equal(sponsoredOnly.can_follow_coach_plan, true)
  assert.equal(sponsoredOnly.can_create_custom_workouts, false)
  assert.equal(individual.can_create_custom_workouts, true)
})

test('the coach workout page applies the custom-workout policy to every inline creation surface', async () => {
  const source = await readFile(new URL('../src/pages/WorkoutSection.tsx', import.meta.url), 'utf8')

  assert.match(
    source,
    /const canCreateCustomWorkouts = clientPolicyForAccount\(appAccess, coachContext\)\.can_create_custom_workouts/,
  )
  assert.match(source, /\{canCreateCustomWorkouts && \(\s*<TodayManualWorkoutCard/)
  assert.match(source, /\{canCreateCustomWorkouts && \(\s*<div className="relative overflow-hidden[\s\S]*?APEX WORKOUT STUDIO/)
  assert.match(source, /\{canCreateCustomWorkouts && \(\s*<Suspense fallback=\{null\}>\s*<CustomWorkoutBuilder/)
  assert.match(source, /\{canCreateCustomWorkouts && \(\s*<ManualWorkoutLogger/)
  assert.equal(
    [...source.matchAll(/\{canCreateCustomWorkouts && \(/g)].length,
    4,
    'each creation surface must keep its own entitlement guard',
  )
})
