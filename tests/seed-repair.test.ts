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
