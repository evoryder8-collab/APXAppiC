import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { EXERCISE_CATALOG } from '../src/data/exerciseCatalog.ts'
import { MOVEMENTS } from '../src/data/movements.ts'
import { parseExerciseImportCsv } from '../tools/exercise-import-review.mjs'

type ResearchedMovement = (typeof MOVEMENTS)[number] & {
  evidenceSourceIds?: string[]
  importSourceName?: string | null
}

type ResearchSource = {
  id: string
  url: string
}

const importRows = parseExerciseImportCsv(readFileSync(
  new URL('../data/imports/exercise_extra_encyclopedia_with_sport_tags.csv', import.meta.url),
  'utf8',
))

const alreadyCanonical = new Set([
  'Kettlebell Clean',
  'Wall Sit',
  'Shrimp Squat',
  'Frog Pump',
  'Archer Push-up',
  'Bear Crawl',
  'Landmine Squat',
  'Smith Machine Split Squat',
  'Smith Machine Hip Thrust',
  'Cable Pull-through',
])

const pendingRows = importRows.filter((row) => !alreadyCanonical.has(row.name))
const evidenceSources = JSON.parse(readFileSync(
  new URL('../data/research/exercise-enrichment-sources.json', import.meta.url),
  'utf8',
)) as ResearchSource[]
const knownSourceIDs = new Set(evidenceSources.map((source) => source.id))

const maceIDs = [
  'steel_mace_360',
  'steel_mace_10_to_2',
  'steel_mace_uppercut',
  'steel_mace_offset_press',
  'steel_mace_offset_squat',
  'steel_mace_rotational_lunge',
  'steel_mace_single_arm_swing',
  'steel_mace_overhead_carry',
]

test('all 209 queued owner rows become distinct, source-backed canonical movements', () => {
  assert.equal(importRows.length, 219)
  assert.equal(pendingRows.length, 209)

  const researched = MOVEMENTS as ResearchedMovement[]
  for (const row of pendingRows) {
    const matches = researched.filter((movement) => movement.name === row.name)
    assert.equal(matches.length, 1, `${row.name} must resolve exactly once`)
    assert.equal(matches[0].importSourceName, row.name)
    assert.ok((matches[0].evidenceSourceIds?.length ?? 0) > 0, `${row.name} has no evidence source`)
    for (const sourceID of matches[0].evidenceSourceIds ?? []) {
      assert.ok(knownSourceIDs.has(sourceID), `${row.name} cites unknown source ${sourceID}`)
    }
  }
})

test('the researched mace family is selectable under Street workout and never given a fake tempo', () => {
  const byID = new Map(MOVEMENTS.map((movement) => [movement.id, movement]))
  for (const id of maceIDs) {
    const movement = byID.get(id) as ResearchedMovement | undefined
    assert.ok(movement, `${id} is missing`)
    assert.ok(movement.equipment.includes('steel_mace'))
    assert.ok(movement.disciplines.includes('street_workout'))
    assert.ok((movement.evidenceSourceIds?.length ?? 0) >= 2)
    if (movement.ballistic) assert.equal(movement.tempoApplies, false)

    const catalogued = EXERCISE_CATALOG.find((item) => item.id === id)
    assert.ok(catalogued, `${id} is not selectable`)
    assert.ok(catalogued.categories.includes('street'))
  }
})

test('the expanded catalogue count is checkable and every identifier remains unique', () => {
  assert.equal(MOVEMENTS.length, 534)
  assert.equal(new Set(MOVEMENTS.map((movement) => movement.id)).size, 534)
  assert.equal(EXERCISE_CATALOG.length, 549)
  assert.equal(new Set(EXERCISE_CATALOG.map((item) => item.id)).size, 549)
})

test('high consequence additions are coached-only and use the right prescription facts', () => {
  const byName = new Map(MOVEMENTS.map((movement) => [movement.name, movement]))
  const coachedOnly = [
    'Planche Push-up',
    'Ring Fly',
    'Rope Climb (Feet Clamp)',
    'Rope Climb (Legless)',
    'Behind-the-Neck Pull-up',
    'Jefferson Curl',
    'Skin-the-Cat',
    'German Hang',
    'Back Lever Full Hold',
    'Barbell Split Jerk',
    'Barbell Push Jerk',
    'Barbell Power Jerk',
    'Sandbag Over-the-Shoulder Throw',
    'Atlas Stone to Platform',
  ]
  for (const name of coachedOnly) {
    assert.equal(byName.get(name)?.coachedOnly, true, `${name} must require coaching`)
  }

  for (const row of pendingRows) {
    const movement = byName.get(row.name)!
    if (row.exerciseType === 'Plyometric') {
      assert.equal(movement.prescriptionMode, 'contacts', row.name)
      assert.equal(movement.tempoApplies, false, row.name)
    }
    if (row.movementPattern === 'Carry') {
      assert.equal(movement.prescriptionMode, 'carry', row.name)
      assert.ok(['metres', 'seconds'].includes(movement.repUnit), row.name)
    }
    if (row.exerciseType === 'Mobility') {
      assert.ok(['quality', 'hold'].includes(movement.prescriptionMode), row.name)
    }
    if (movement.ballistic) assert.equal(movement.tempoApplies, false, row.name)
  }
})

test('enrichment does not infer load from support equipment or invent anatomy keys', () => {
  const researched = (MOVEMENTS as ResearchedMovement[]).filter((movement) => movement.importSourceName)
  const loadedMobility = researched
    .filter((movement) => movement.entityType === 'mobility_drill' && movement.loadable)
    .map((movement) => movement.name)
    .sort()
  assert.deepEqual(loadedMobility, ['Jefferson Curl', 'Kettlebell Armbar', 'Kettlebell Halo'])

  const anatomy = new Set([
    'adductors', 'ankle_stabilisers', 'biceps', 'calves', 'chest', 'core',
    'erectors', 'foot_intrinsics', 'forearms', 'front_delts', 'full_body',
    'glute_medius', 'glutes', 'hamstrings', 'hip_flexors', 'hips', 'lats',
    'lower_traps', 'mid_traps', 'obliques', 'quadriceps', 'rear_delts',
    'rotator_cuff', 'side_delts', 'soleus', 'spinal_erectors',
    'thoracic_spine', 'traps', 'triceps', 'upper_back', 'upper_chest',
  ])
  for (const movement of researched) {
    for (const muscle of [
      ...movement.primaryMuscles,
      ...movement.secondaryMuscles,
      ...movement.stabilizerMuscles,
    ]) assert.ok(anatomy.has(muscle), `${movement.name} invents anatomy key ${muscle}`)
  }
})

test('complex ballistic mace work remains selectable but cannot be auto-programmed', () => {
  for (const movement of MOVEMENTS.filter((item) => item.id.startsWith('steel_mace_') && item.ballistic)) {
    assert.equal(movement.coachedOnly, true, movement.name)
    assert.equal(movement.tempoApplies, false, movement.name)
  }
})

test('research sources are unique, secure, and fully described', () => {
  assert.ok(evidenceSources.length >= 15)
  assert.equal(knownSourceIDs.size, evidenceSources.length)
  for (const source of evidenceSources) {
    assert.match(source.id, /^[a-z0-9_]+$/)
    assert.match(source.url, /^https:\/\//)
  }
})
