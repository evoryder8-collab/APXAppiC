import test from 'node:test'
import assert from 'node:assert/strict'
import { buildSeedData } from '../src/data/seed.ts'
import { CURRENT_SEED_VERSION, repairSeedDefinitions } from '../src/lib/seedRepair.ts'

const userId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'

test('Constantine seed ids stay deterministic across repeated builds', () => {
  const first = buildSeedData(userId, 'constantine')
  const second = buildSeedData(userId, 'constantine')

  assert.deepEqual(first.meals.map((row) => row.id), second.meals.map((row) => row.id))
  assert.deepEqual(first.supplements.map((row) => row.id), second.supplements.map((row) => row.id))
  assert.deepEqual(first.program_days.map((row) => row.id), second.program_days.map((row) => row.id))
  assert.deepEqual(first.exercises.map((row) => row.id), second.exercises.map((row) => row.id))
})

test('versioned repair completes a partial seed without replacing existing rows', () => {
  const seeded = buildSeedData(userId, 'constantine')
  assert.ok(seeded.profile)
  const editedBreakfast = { ...seeded.meals[0], foods: 'User-edited breakfast' }
  const legacyTaurine = { ...seeded.supplements[0], id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' }
  const legacyProgram = { ...seeded.programs[0], id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' }
  const partial = {
    ...seeded,
    profile: { ...seeded.profile, seed_version: 0 },
    meals: [editedBreakfast],
    supplements: [legacyTaurine],
    programs: [legacyProgram],
    program_days: [],
    exercises: [],
  }

  const repair = repairSeedDefinitions(partial, buildSeedData(userId, 'constantine'))

  assert.equal(repair.needsRepair, true)
  assert.equal(repair.data.profile?.seed_version, CURRENT_SEED_VERSION)
  assert.equal(repair.data.meals.length, seeded.meals.length)
  assert.equal(repair.data.supplements.length, seeded.supplements.length)
  assert.equal(repair.data.programs.length, seeded.programs.length)
  assert.equal(repair.data.program_days.length, seeded.program_days.length)
  assert.equal(repair.data.exercises.length, seeded.exercises.length)
  assert.equal(repair.data.meals[0].foods, 'User-edited breakfast')
  assert.equal(repair.data.supplements[0].id, legacyTaurine.id)
  assert.equal(repair.data.programs[0].id, legacyProgram.id)
  assert.equal(
    repair.data.program_days.filter((row) => row.program_id === legacyProgram.id).length,
    seeded.program_days.filter((row) => row.program_id === seeded.programs[0].id).length,
  )
  assert.equal(repair.missing.meals.length, seeded.meals.length - 1)
  assert.equal(repair.missing.supplements.length, seeded.supplements.length - 1)
})

test('completed seed versions do not recreate intentionally removed definitions', () => {
  const seeded = buildSeedData(userId, 'constantine')
  assert.ok(seeded.profile)
  const completed = {
    ...seeded,
    profile: { ...seeded.profile, seed_version: CURRENT_SEED_VERSION },
    meals: seeded.meals.slice(0, -1),
  }
  const repair = repairSeedDefinitions(completed, seeded)

  assert.equal(repair.needsRepair, false)
  assert.equal(repair.data.meals.length, seeded.meals.length - 1)
  assert.equal(repair.missing.meals.length, 0)
})

test('V8.1 repair replaces the bespoke main plan while preserving historical day ids', () => {
  const seeded = buildSeedData(userId, 'constantine')
  assert.ok(seeded.profile)
  const main = seeded.programs.find((row) => row.slug === 'main')
  assert.ok(main)
  const tuesday = seeded.program_days.find((row) => row.program_id === main.id && row.weekday === 2)
  assert.ok(tuesday)
  const obsoleteExercise = {
    ...seeded.exercises.find((row) => row.program_day_id === tuesday.id)!,
    id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    name: 'Obsolete programme exercise',
    sort_order: 99,
  }
  const current = {
    ...seeded,
    profile: { ...seeded.profile, seed_version: 2 },
    settings: seeded.settings ? {
      ...seeded.settings,
      addons: { ...seeded.settings.addons, training_protocol: undefined },
    } : null,
    program_days: seeded.program_days.map((row) =>
      row.id === tuesday.id ? { ...row, name: 'Legacy Push Day' } : row,
    ),
    exercises: [
      ...seeded.exercises.map((row) =>
        row.program_day_id === tuesday.id && row.sort_order === 0
          ? { ...row, name: 'Legacy Weighted Pushups' }
          : row,
      ),
      obsoleteExercise,
    ],
    workout_sessions: [{
      id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      user_id: userId,
      date: '2026-07-21',
      program_day_id: tuesday.id,
      is_lite: false,
      is_deload: false,
      is_event_recovery: false,
      completed: true,
      quality_score: 1,
      started_at: null,
      completed_at: null,
      notes: '',
    }],
  }

  const repair = repairSeedDefinitions(current, seeded)
  const repairedTuesday = repair.data.program_days.find((row) => row.program_id === main.id && row.weekday === 2)
  assert.equal(repairedTuesday?.id, tuesday.id)
  assert.equal(repairedTuesday?.name, 'Push A + Focus T25 Core')
  assert.equal(repair.data.workout_sessions[0].program_day_id, tuesday.id)
  assert.ok(repair.data.exercises.some((row) => row.program_day_id === tuesday.id && row.rep_unit === 'check'))
  assert.ok(!repair.data.exercises.some((row) => row.name === 'Obsolete programme exercise'))
  assert.deepEqual(repair.removed.exercises, [obsoleteExercise.id])
  assert.equal(repair.data.settings?.addons.training_protocol?.version, 81)
  assert.equal(repair.missing.program_days.length, 7)
})
