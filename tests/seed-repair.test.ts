import test from 'node:test'
import assert from 'node:assert/strict'
import { buildSeedData } from '../src/data/seed.ts'
import {
  CURRENT_SEED_VERSION,
  repairSeedDefinitions,
  shouldRepairSeedDefinitions,
} from '../src/lib/seedRepair.ts'

const userId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'

test('Constantine seed ids stay deterministic across repeated builds', () => {
  const first = buildSeedData(userId, 'constantine')
  const second = buildSeedData(userId, 'constantine')

  assert.deepEqual(first.meals.map((row) => row.id), second.meals.map((row) => row.id))
  assert.deepEqual(first.supplements.map((row) => row.id), second.supplements.map((row) => row.id))
  assert.deepEqual(first.program_days.map((row) => row.id), second.program_days.map((row) => row.id))
  assert.deepEqual(first.exercises.map((row) => row.id), second.exercises.map((row) => row.id))
})

test('personal protocol seed installs exact defaults, empty meal canvas and evidence-limited supplement modules', () => {
  const constantine = buildSeedData(userId, 'constantine')
  const june = buildSeedData(userId, 'june')

  assert.deepEqual(
    {
      kcal: constantine.profile?.target_kcal,
      protein: constantine.profile?.target_protein_g,
      fat: constantine.profile?.target_fat_g,
      carbs: constantine.profile?.target_carbs_g,
    },
    { kcal: 2450, protein: 150, fat: 75, carbs: 294 },
  )
  assert.deepEqual(
    {
      kcal: june.profile?.target_kcal,
      protein: june.profile?.target_protein_g,
      fat: june.profile?.target_fat_g,
      carbs: june.profile?.target_carbs_g,
    },
    { kcal: 2400, protein: 85, fat: 95, carbs: 301 },
  )
  assert.deepEqual(constantine.meals, [])
  assert.deepEqual(june.meals, [])
  assert.deepEqual(constantine.supplements.map((row) => row.name), [
    'Creatine monohydrate',
    'Iodised salt',
    'Whey isolate',
    'Casein',
    'Citrulline malate',
    'Cluster Dextrin',
    'Collagen + Vitamin C',
  ])
  assert.deepEqual(june.supplements.map((row) => row.name), [
    'Creatine monohydrate',
    'Iodised salt',
    'Whey isolate',
    'Casein',
    'Cluster Dextrin',
    'Electrolytes',
  ])
})

test('versioned repair completes a partial seed without replacing existing rows', () => {
  const seeded = buildSeedData(userId, 'matthew')
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

  const repair = repairSeedDefinitions(partial, buildSeedData(userId, 'matthew'))

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

test('a skipped settings-only account is never expanded into fabricated seed facts', () => {
  const seeded = buildSeedData(userId, 'constantine')
  const skipped = {
    ...seeded,
    profile: null,
    settings: {
      ...seeded.settings!,
      addons: {
        ...seeded.settings!.addons,
        newbie_mode: false,
        training_induction: null,
        training_induction_skipped: true,
      },
    },
    meals: [],
    supplements: [],
    programs: [],
    program_days: [],
    exercises: [],
  }

  assert.equal(shouldRepairSeedDefinitions(skipped), false)
  const repair = repairSeedDefinitions(skipped, seeded)
  assert.equal(repair.needsRepair, false)
  assert.equal(repair.data.profile, null)
  assert.deepEqual(repair.data.programs, [])
  assert.deepEqual(repair.data.program_days, [])
  assert.deepEqual(repair.data.exercises, [])
})

test('an interrupted ordinary seed with settings but no onboarding state is still repaired', () => {
  const seeded = buildSeedData(userId, 'constantine')
  const addons = { ...seeded.settings!.addons }
  delete addons.training_induction_skipped
  delete addons.training_induction
  delete addons.training_induction_pending_day_ids
  delete addons.training_induction_archived_day_ids
  delete addons.training_induction_generation_revision
  delete addons.newbie_mode
  const interrupted = {
    ...seeded,
    profile: null,
    settings: { ...seeded.settings!, addons },
  }

  assert.equal(shouldRepairSeedDefinitions(interrupted), true)
  assert.equal(repairSeedDefinitions(interrupted, seeded).needsRepair, true)
})

test('V3 nutrition upgrade clears prescriptions and installs only the PDF supplement core', () => {
  for (const persona of ['constantine', 'june'] as const) {
    const seeded = buildSeedData(userId, persona)
    assert.ok(seeded.profile)
    assert.ok(seeded.supplements.length > 0)
    const legacyMeal = {
      id: 'abababab-abab-4aba-8aba-abababababab',
      user_id: userId,
      time: '07:00',
      name: 'Legacy prescribed meal',
      foods: 'Old prescription',
      kcal: 500,
      protein_g: 30,
      fat_g: 20,
      carbs_g: 40,
      full_days_only: false,
      sort_order: 0,
    }
    const legacySupplement = {
      ...seeded.supplements[0],
      id: 'cdcdcdcd-cdcd-4cdc-8dcd-cdcdcdcdcdcd',
      name: 'Legacy automatic stack',
    }
    const current = {
      ...seeded,
      profile: {
        ...seeded.profile,
        seed_version: 3,
        target_kcal: null,
        target_protein_g: null,
        target_fat_g: null,
        target_carbs_g: null,
      },
      meals: [legacyMeal],
      supplements: [legacySupplement],
    }

    const repair = repairSeedDefinitions(current, seeded)
    assert.deepEqual(repair.data.meals, [])
    assert.deepEqual(repair.removed.meals, [legacyMeal.id])
    assert.deepEqual(repair.removed.supplements, [legacySupplement.id])
    assert.deepEqual(repair.data.supplements.map((row) => row.name), seeded.supplements.map((row) => row.name))
    assert.deepEqual(repair.missing.supplements.map((row) => row.name), seeded.supplements.map((row) => row.name))
    assert.equal(repair.data.profile?.target_kcal, seeded.profile.target_kcal)
    assert.equal(repair.data.profile?.target_protein_g, seeded.profile.target_protein_g)
    assert.equal(repair.data.profile?.target_fat_g, seeded.profile.target_fat_g)
    assert.equal(repair.data.profile?.target_carbs_g, seeded.profile.target_carbs_g)
  }
})

test('V5 protocol repair corrects defaults without deleting logged meals or custom activity choices', () => {
  const seededJune = buildSeedData(userId, 'june')
  assert.ok(seededJune.profile)
  assert.ok(seededJune.settings)
  const legacySupplements = seededJune.supplements
    .filter((row) => row.name !== 'Casein')
    .map((row, index) => ({
      ...row,
      id: `10000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
      sort_order: index,
      dose: row.name === 'Cluster Dextrin' ? 'Legacy dose' : row.dose,
    }))
  const customMeal = {
    id: '20000000-0000-4000-8000-000000000001',
    user_id: userId,
    time: '10:45',
    name: 'User meal',
    foods: 'User food',
    kcal: 410,
    protein_g: 25,
    fat_g: 14,
    carbs_g: 45,
    full_days_only: false,
    sort_order: 0,
  }
  const current = {
    ...seededJune,
    profile: {
      ...seededJune.profile,
      seed_version: 4,
      weight_kg: 41.5,
      activity_level: 'very' as const,
    },
    settings: {
      ...seededJune.settings,
      addons: {
        ...seededJune.settings.addons,
        recovery_data_source: undefined,
        recovery_history: undefined,
        watch_activity_history: undefined,
      },
    },
    meals: [customMeal],
    supplements: legacySupplements,
  }

  const repair = repairSeedDefinitions(current, seededJune)
  assert.equal(repair.data.profile?.weight_kg, 41)
  assert.equal(repair.data.profile?.activity_level, 'very')
  assert.equal(repair.data.profile?.seed_version, CURRENT_SEED_VERSION)
  assert.deepEqual(repair.data.meals, [customMeal])
  assert.equal(repair.data.settings?.addons.recovery_data_source, 'apple')
  assert.deepEqual(repair.data.settings?.addons.recovery_history, [])
  assert.deepEqual(repair.data.settings?.addons.watch_activity_history, [])
  assert.equal(repair.data.supplements.filter((row) => row.name === 'Casein').length, 1)
  assert.equal(
    repair.data.supplements.find((row) => row.name === 'Cluster Dextrin')?.id,
    legacySupplements.find((row) => row.name === 'Cluster Dextrin')?.id,
  )
  assert.notEqual(repair.data.supplements.find((row) => row.name === 'Cluster Dextrin')?.dose, 'Legacy dose')
  assert.equal(repair.settingsChanged, true)
  assert.equal(repair.profileChanged, true)

  const oldSeedDefault = {
    ...current,
    profile: { ...current.profile, activity_level: 'extra' as const },
  }
  assert.equal(repairSeedDefinitions(oldSeedDefault, seededJune).data.profile?.activity_level, 'moderate')
})

test('completed seed versions do not recreate intentionally removed definitions', () => {
  const seeded = buildSeedData(userId, 'constantine')
  assert.ok(seeded.profile)
  const completed = {
    ...seeded,
    profile: { ...seeded.profile, seed_version: CURRENT_SEED_VERSION },
    supplements: seeded.supplements.slice(0, -1),
  }
  const repair = repairSeedDefinitions(completed, seeded)

  assert.equal(repair.needsRepair, false)
  assert.equal(repair.data.supplements.length, seeded.supplements.length - 1)
  assert.equal(repair.missing.supplements.length, 0)
})

test('V8.5 repair replaces the bespoke main plan while preserving historical day ids', () => {
  const seeded = buildSeedData(userId, 'constantine')
  assert.ok(seeded.profile)
  const main = seeded.programs.find((row) => row.slug === 'main')
  assert.ok(main)
  const tuesday = seeded.program_days.find(
    (row) => row.program_id === main.id && row.weekday === 2 && row.name === 'Push A · Strength',
  )
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
  const repairedTuesday = repair.data.program_days.find(
    (row) => row.program_id === main.id && row.weekday === 2 && row.name === 'Push A · Strength',
  )
  assert.equal(repairedTuesday?.id, tuesday.id)
  assert.equal(repairedTuesday?.name, 'Push A · Strength')
  assert.equal(repair.data.workout_sessions[0].program_day_id, tuesday.id)
  assert.ok(repair.data.exercises.some(
    (row) => row.program_day_id === tuesday.id && row.name === 'Strict Bodyweight Push-Up',
  ))
  assert.ok(!repair.data.exercises.some((row) => row.name === 'Obsolete programme exercise'))
  assert.ok(repair.removed.exercises.includes(obsoleteExercise.id))
  assert.ok(repair.removed.exercises.length >= 1)
  assert.equal(repair.data.settings?.addons.training_protocol?.version, 85)
  assert.ok(repair.missing.program_days.length >= 14)
})

test('V8.5 repairs existing Full and Light rows without crossing strength history', () => {
  const seeded = buildSeedData(userId, 'constantine')
  assert.ok(seeded.profile)
  const main = seeded.programs.find((row) => row.slug === 'main')
  assert.ok(main)
  const friday = seeded.program_days.find(
    (row) => row.program_id === main.id && row.weekday === 5 && row.name === 'Legs B · Strength',
  )
  assert.ok(friday)
  const fridayRows = seeded.exercises.filter((row) => row.program_day_id === friday.id)
  const byName = (name: string, isLite: boolean) => {
    const row = fridayRows.find((candidate) => candidate.name === name && candidate.is_lite === isLite)
    assert.ok(row)
    return row
  }
  const oldFullFocus = {
    ...byName('Front Lunge', true),
    id: '61000000-0000-4000-8000-000000000001',
    name: 'Focus T25 · Friday conditioning',
    is_lite: false,
    sort_order: 4,
  }
  const oldFullFront = {
    ...byName('Front Lunge', false),
    id: '61000000-0000-4000-8000-000000000002',
  }
  const oldLightFront = {
    ...byName('Front Lunge', true),
    id: '61000000-0000-4000-8000-000000000003',
    sets: 2,
  }
  const legacyFridayRows = [
    oldFullFront,
    byName('Reverse Lunge', false),
    byName('Single-Leg Romanian Deadlift', false),
    byName('Single-Leg Calf Raise', false),
    oldFullFocus,
    oldLightFront,
    byName('Single-Leg Romanian Deadlift', true),
  ]
  const current = {
    ...seeded,
    profile: { ...seeded.profile, seed_version: 5 },
    exercises: [
      ...seeded.exercises.filter((row) => row.program_day_id !== friday.id),
      ...legacyFridayRows,
    ],
    workout_sessions: [{
      id: '62000000-0000-4000-8000-000000000001',
      user_id: userId,
      date: '2026-07-24',
      program_day_id: friday.id,
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
  const repairedFriday = repair.data.program_days.find(
    (row) => row.program_id === main.id && row.weekday === 5 && row.name === 'Legs B · Strength',
  )
  const repairedRows = repair.data.exercises.filter((row) => row.program_day_id === repairedFriday?.id)

  assert.equal(repair.needsRepair, true)
  /* Reference the constant so a protocol revision does not fail this test
     for the wrong reason. What matters here is that Friday's rows were
     repaired without crossing strength history. */
  assert.equal(repair.data.profile?.seed_version, CURRENT_SEED_VERSION)
  assert.equal(repairedFriday?.id, friday.id)
  assert.equal(repair.data.workout_sessions[0].program_day_id, friday.id)
  assert.equal(
    repairedRows.find((row) => row.name === 'Front Lunge' && !row.is_lite)?.id,
    oldFullFront.id,
  )
  assert.equal(
    repairedRows.find((row) => row.name === 'Front Lunge' && row.is_lite)?.id,
    oldLightFront.id,
  )
  assert.ok(!repairedRows.some((row) => row.name.startsWith('Focus T25') && !row.is_lite))
  assert.ok(repairedRows.some((row) => row.name === 'Single-Leg Romanian Deadlift' && row.is_lite))
  assert.ok(repair.removed.exercises.includes(oldFullFocus.id))
})
