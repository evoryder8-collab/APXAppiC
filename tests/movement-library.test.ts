import assert from 'node:assert/strict'
import test from 'node:test'
import {
  MOVEMENTS,
  MOVEMENT_BY_ID,
  MOVEMENT_ALIASES,
  CARDIO_MODALITIES,
  CARDIO_PRESCRIPTIONS,
  CARDIO_ALIASES,
  KIT_LIMITATIONS,
  TRAINING_PILLARS,
} from '../src/data/movements.ts'

/**
 * Every kit the intake questionnaire can produce, including the awkward ones.
 * The library is not complete at a movement count, it is complete when each of
 * these yields a balanced week or says honestly why it cannot.
 */
const KITS: Record<string, string[] | null> = {
  bodyweight_only: ['floor_space', 'mat', 'wall'],
  bodyweight_plus_bar: ['floor_space', 'mat', 'pull_up_bar', 'wall'],
  bands_only: ['bands', 'floor_space', 'mat', 'wall'],
  bands_plus_anchor: ['bands', 'floor_space', 'mat', 'anchor_point', 'door_anchor'],
  dumbbells_only: ['dumbbells', 'floor_space', 'mat'],
  dumbbells_plus_bench: ['dumbbells', 'floor_space', 'mat', 'bench', 'adjustable_bench'],
  kettlebell_only: ['kettlebell', 'floor_space', 'mat'],
  hotel_room: ['floor_space', 'mat', 'chair', 'towel', 'wall', 'backpack'],
  commercial_gym: null,
}

const ALL_EQUIPMENT = [
  ...new Set(MOVEMENTS.flatMap((m) => [...m.equipment, ...m.equipmentAnyOf.flat()])),
]

function available(m: (typeof MOVEMENTS)[number], owned: Set<string>): boolean {
  if (!m.equipment.every((e) => owned.has(e))) return false
  return m.equipmentAnyOf.every((group) => group.some((e) => owned.has(e)))
}

const SELECTABLE = new Set(['resistance_dynamic', 'resistance_isometric', 'balance_drill'])

function fill(pillar: string, owned: Set<string>, youth: boolean) {
  const patterns = TRAINING_PILLARS[pillar]
  return MOVEMENTS.filter(
    (m) =>
      patterns.includes(m.pattern) &&
      SELECTABLE.has(m.entityType) &&
      available(m, owned) &&
      (youth ? m.youthAutoAssignable : m.adultAutoAssignable),
  )
}

for (const youth of [false, true]) {
  const who = youth ? 'a 16-17 year old training unsupervised' : 'an adult'
  test(`every intake kit yields a balanced week for ${who}`, () => {
    for (const [kit, equipment] of Object.entries(KITS)) {
      const owned = new Set(equipment ?? ALL_EQUIPMENT)
      const declared = KIT_LIMITATIONS[kit] ?? {}
      for (const pillar of Object.keys(TRAINING_PILLARS)) {
        const found = fill(pillar, owned, youth)
        if (found.length > 0) continue
        assert.ok(
          declared[pillar],
          `kit "${kit}" cannot fill "${pillar}" and does not declare why. ` +
            `Add a movement or declare the limitation so the user is told.`,
        )
      }
    }
  })
}

test('a declared limitation explains the gap rather than hiding it', () => {
  for (const [kit, gaps] of Object.entries(KIT_LIMITATIONS)) {
    assert.ok(KITS[kit] !== undefined, `limitation declared for unknown kit ${kit}`)
    for (const [pillar, message] of Object.entries(gaps)) {
      assert.ok(TRAINING_PILLARS[pillar], `limitation names unknown pillar ${pillar}`)
      assert.ok(message.length > 40, `limitation for ${kit}/${pillar} is too terse to be useful`)
    }
  }
})

test('substitutions, prerequisites and sequences all resolve', () => {
  for (const m of MOVEMENTS) {
    for (const id of [...m.substitutions, ...m.prerequisites, ...m.sequenceSteps]) {
      assert.ok(MOVEMENT_BY_ID.has(id), `${m.id} references unknown movement ${id}`)
    }
    assert.notEqual(m.substitutions.includes(m.id), true, `${m.id} substitutes itself`)
  }
  for (const [alias, id] of Object.entries(MOVEMENT_ALIASES)) {
    assert.ok(MOVEMENT_BY_ID.has(id), `alias "${alias}" points at unknown movement ${id}`)
  }
})

test('a prerequisite is never harder than the movement that requires it', () => {
  for (const m of MOVEMENTS) {
    for (const id of m.prerequisites) {
      const pre = MOVEMENT_BY_ID.get(id)!
      assert.ok(
        pre.technicalComplexity <= m.technicalComplexity,
        `${m.id} requires ${id}, which is harder than it is`,
      )
    }
  }
})

test('youth eligibility follows one rule rather than 300 opinions', () => {
  for (const m of MOVEMENTS) {
    const canBeMadeSafe = m.canFailSafely || m.failSafeConditions.length > 0
    const expected =
      m.technicalComplexity <= 3 &&
      !(m.requiresBailSkill && !canBeMadeSafe) &&
      !(m.ballistic && m.technicalComplexity >= 4) &&
      !(m.axialLoad && !m.loadable) &&
      !(m.axialLoad && m.minIncrementKg !== null && m.minIncrementKg >= 10)
    assert.equal(
      m.youthAutoAssignable,
      expected,
      `${m.id} youth eligibility does not follow the derivation`,
    )
  }
  // Under-18s are never given maximal singles, whatever the movement.
  for (const m of MOVEMENTS) {
    if (m.loadable) assert.equal(m.youthRepFloor, 6, `${m.id} has no youth rep floor`)
  }
})

test('a movement that cannot be failed alone says what would make it safe', () => {
  for (const m of MOVEMENTS) {
    if (m.canFailSafely) continue
    assert.ok(
      m.failSafeConditions.length > 0 || m.needsSpotter || m.coachedOnly,
      `${m.id} cannot be failed alone and offers no condition that changes that`,
    )
  }
})

test('barbell safety facts distinguish controlled pulls from high-consequence failures', () => {
  for (const id of ['barbell_romanian_deadlift', 'conventional_deadlift', 'barbell_row']) {
    assert.equal(MOVEMENT_BY_ID.get(id)?.canFailSafely, true, `${id} can be returned to the floor`)
  }

  const goodMorning = MOVEMENT_BY_ID.get('good_morning')!
  assert.equal(goodMorning.canFailSafely, false)
  assert.equal(goodMorning.needsSafeties, true)
  assert.ok(goodMorning.failSafeConditions.includes('rack_safeties_set'))

  for (const id of ['barbell_overhead_press', 'thruster', 'push_press']) {
    const movement = MOVEMENT_BY_ID.get(id)!
    assert.equal(movement.canFailSafely, false, id)
    assert.ok(movement.failSafeConditions.includes('clear_lifting_platform'), id)
  }

  for (const id of ['power_clean', 'power_snatch', 'clean_and_jerk', 'overhead_squat']) {
    const movement = MOVEMENT_BY_ID.get(id)!
    assert.equal(movement.canFailSafely, false, id)
    assert.equal(movement.coachedOnly, true, id)
    assert.ok(movement.failSafeConditions.includes('qualified_coach_present'), id)
    assert.ok(movement.failSafeConditions.includes('clear_lifting_platform'), id)
  }

  for (const id of ['landmine_press', 'landmine_squat', 'single_arm_landmine_press']) {
    assert.equal(MOVEMENT_BY_ID.get(id)?.requiresBailSkill, false, `${id} is anchored, not a free bar`)
  }

  const snatchGripRDL = MOVEMENT_BY_ID.get('snatch_grip_romanian_deadlift')!
  assert.equal(snatchGripRDL.ballistic, false)
  assert.equal(snatchGripRDL.overhead, false)
  assert.equal(snatchGripRDL.requiresBailSkill, false)
  assert.equal(snatchGripRDL.tempoApplies, true)
  assert.equal(snatchGripRDL.prescriptionMode, 'tempo_reps')
})

test('every entity type carries a prescription it can actually take', () => {
  const schemas: Record<string, string> = {
    resistance_dynamic: 'sets_reps_load',
    resistance_isometric: 'sets_duration_load',
    plyometric: 'sets_reps_quality',
    power_throw: 'sets_reps_quality',
    conditioning_complex: 'rounds_work_rest',
    skill_drill: 'sets_duration_quality',
    mobility_drill: 'sets_duration_or_reps',
    yoga_pose: 'hold_breaths_or_duration',
    movement_sequence: 'rounds_duration',
    breathing_recovery: 'duration',
    balance_drill: 'sets_duration_or_reps',
    cardio_modality: 'requires_prescription',
  }
  for (const m of MOVEMENTS) {
    assert.equal(m.prescription, schemas[m.entityType], `${m.id} has the wrong prescription`)
  }
})

test('a sequence names its steps', () => {
  for (const m of MOVEMENTS) {
    if (m.entityType !== 'movement_sequence') continue
    assert.ok(m.sequenceSteps.length > 1, `${m.id} is a sequence with nothing in it`)
  }
})

test('cardio is a modality and a prescription, never one fused record', () => {
  const modalities = new Set(CARDIO_MODALITIES.map((c) => c.id))
  const prescriptions = new Set(CARDIO_PRESCRIPTIONS.map((c) => c.id))
  for (const [alias, pair] of Object.entries(CARDIO_ALIASES)) {
    assert.ok(modalities.has(pair.modality), `${alias} names unknown modality ${pair.modality}`)
    assert.ok(
      prescriptions.has(pair.prescription),
      `${alias} names unknown prescription ${pair.prescription}`,
    )
  }
  // No movement should have crept back in carrying an intensity in its name.
  for (const m of MOVEMENTS) {
    assert.doesNotMatch(
      m.name,
      /zone ?2|interval|tempo run|threshold/i,
      `${m.id} fuses a cardio prescription into a movement name`,
    )
  }
})

test('a modality only claims the zones it can actually deliver', () => {
  for (const c of CARDIO_MODALITIES) {
    assert.ok(c.supportsZones.length > 0, `${c.id} supports no zone at all`)
    assert.ok(
      Math.abs(c.upperShare + c.lowerShare - 1) < 1e-9,
      `${c.id} work shares do not add up`,
    )
  }
  // Hard prescriptions are capped per week no matter what the goal asks for.
  for (const p of CARDIO_PRESCRIPTIONS) {
    if (p.rpe !== null && p.rpe >= 8) {
      assert.ok(p.weeklyCap !== null, `${p.id} is very hard and has no weekly cap`)
      assert.ok(p.prereqBaseWeeks > 0, `${p.id} is very hard and needs no aerobic base`)
    }
  }
})

test('no two movements are the same movement wearing different kit', () => {
  const seen = new Map<string, string>()
  for (const m of MOVEMENTS) {
    const key = m.name.toLowerCase().replace(/[^a-z]/g, '')
    const prior = seen.get(key)
    assert.equal(prior, undefined, `${m.id} duplicates ${prior}`)
    seen.set(key, m.id)
  }
})
