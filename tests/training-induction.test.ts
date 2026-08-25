import assert from 'node:assert/strict'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import test from 'node:test'
import { buildSeedData } from '../src/data/seed.ts'
import { planForDate } from '../src/lib/plan.ts'
import { estimatedTimelineMinutes } from '../src/lib/playerTimeline.ts'
import { repairSeedDefinitions } from '../src/lib/seedRepair.ts'
import {
  EQUIPMENT_CATALOG,
  activeTrainingProgramDays,
  archivedTrainingDayIds,
  assessTrainingInput,
  commitTrainingPlanAddons,
  generateTrainingPlan,
  invalidateTrainingPlanAddons,
  isInsideInductionWindow,
  isTrainingInductionEligible,
  markPendingTrainingPlanAddons,
  pendingTrainingDayIds,
  restoreTrainingPlanAddons,
  searchEquipment,
  trainingInputFromProfile,
  trainingGenerationRevision,
  type TrainingInductionInput,
} from '../src/lib/trainingInduction.ts'

const userId = '19191919-aaaa-4bbb-8ccc-292929292929'

const baseInput: TrainingInductionInput = {
  start_date: '2026-07-15',
  inactivity: 'one_to_three_months',
  venue: 'home',
  equipment: ['adjustable_dumbbells', 'resistance_bands'],
  pain_areas: [],
  recent_operation: false,
  chronic_lower_back_pain: false,
  sessions_per_week: 3,
  plan_weeks: 12,
  goal: 'rebuild',
}

test('predictive equipment search finds both dumbbell formats from dum', () => {
  const ids = searchEquipment('dum').map((item) => item.id)
  assert.ok(ids.includes('adjustable_dumbbells'))
  assert.ok(ids.includes('fixed_dumbbells'))
})

test('six and seven day requests remain selectable and distribute weekly load', () => {
  for (const requested of [6, 7] as const) {
    const input = { ...baseInput, sessions_per_week: requested } as unknown as TrainingInductionInput
    assert.equal(trainingInputFromProfile(input, input.start_date).sessions_per_week, requested)

    const generated = generateTrainingPlan(userId, input)
    const induction = generated.induction as typeof generated.induction & {
      weekly_load_strategy?: string
      hard_set_cap?: number
    }
    assert.equal(induction.sessions_per_week, requested)
    assert.equal(induction.weekly_load_strategy, requested === 7 ? 'distributed_with_recovery' : 'distributed')
    assert.equal(induction.hard_set_cap, 2)

    for (const program of generated.programs) {
      const days = generated.program_days
        .filter((day) => day.program_id === program.id)
        .sort((left, right) => left.sort_order - right.sort_order)
      assert.equal(days.length, requested)
      assert.deepEqual(days.map((day) => day.weekday), Array.from({ length: requested }, (_, index) => index + 1))

      const loadedExercises = generated.exercises.filter((exercise) => (
        days.some((day) => day.id === exercise.program_day_id) && exercise.increment_kg > 0 && !exercise.is_lite
      ))
      assert.ok(loadedExercises.length > 0)
      assert.ok(loadedExercises.every((exercise) => exercise.sets <= 2))
      assert.ok(days.some((day) => /Mobility|Recovery/.test(day.name)))
    }
  }
})

test('home equipment leads with wearable loads and changes the generated movements', () => {
  assert.deepEqual(
    EQUIPMENT_CATALOG.slice(0, 2).map((item) => item.id),
    ['weighted_vest', 'weighted_backpack'],
  )

  const vest = generateTrainingPlan(userId, {
    ...baseInput,
    equipment: ['weighted_vest'],
  })
  assert.ok(vest.exercises.some((exercise) => exercise.name.includes('Weighted Vest')))

  const backpack = generateTrainingPlan(userId, {
    ...baseInput,
    equipment: ['weighted_backpack'],
  })
  assert.ok(backpack.exercises.some((exercise) => exercise.name.includes('Backpack')))
})

test('web plan builder labels days explicitly and warns without banning six or seven', () => {
  const panel = readFileSync(
    join(process.cwd(), 'src/components/workout/TrainingInductionPanel.tsx'),
    'utf8',
  )
  assert.match(panel, /\[2, 3, 4, 5, 6, 7\]/)
  assert.match(panel, /days \/ week/)
  assert.match(panel, /pendingFrequency/)
  assert.match(panel, /cannot guarantee recovery or prevent overtraining/i)
  assert.match(panel, /TRAINING_PLAN_WEEK_OPTIONS/)
  assert.match(panel, /How long should your plan be\?/)
  assert.match(panel, /plan_weeks/)
  assert.doesNotMatch(panel, /<select[^>]*goal/i)
})

test('every profile can explicitly enable the beginner induction without replacing bespoke plans by default', () => {
  assert.equal(isTrainingInductionEligible('constantine'), true)
  assert.equal(isTrainingInductionEligible('june'), true)
  assert.equal(isTrainingInductionEligible('matthew'), true)
  assert.equal(isTrainingInductionEligible('iulian'), true)
})

test('recent operations receive a clearance-first plan and reduced frequency', () => {
  const assessment = assessTrainingInput({ ...baseInput, recent_operation: true, sessions_per_week: 4 })
  assert.equal(assessment.caution, 'clearance')
  assert.equal(assessment.sessions_per_week, 2)
  const generated = generateTrainingPlan(userId, { ...baseInput, recent_operation: true, sessions_per_week: 4 })
  assert.equal(generated.induction.sessions_per_week, 2)
  assert.match(generated.exercises[0].notes + generated.program_days[0].warmup_note, /clinician|pain-free/i)
})

test('generated foundation occupies the selected 12 weeks and then stops', () => {
  const seeded = buildSeedData(userId, 'matthew')
  const generated = generateTrainingPlan(userId, baseInput, seeded.programs, '2026-07-15T08:00:00.000Z')
  const data = {
    ...seeded,
    settings: {
      ...seeded.settings!,
      addons: { ...seeded.settings!.addons, newbie_mode: true, training_induction: generated.induction },
    },
    programs: generated.programs,
    program_days: [...seeded.program_days, ...generated.program_days],
    exercises: [...seeded.exercises, ...generated.exercises],
  }
  assert.equal(generated.induction.main_start_date, '2026-10-07')
  assert.equal(generated.induction.transition_day_ids.length, 3)
  assert.equal(generated.induction.main_day_ids.length, 3)
  assert.ok(planForDate(data, 'transition', '2026-07-15', false).exercises.length > 0)
  assert.ok(planForDate(data, 'transition', '2026-10-12', false).exercises.length === 0)
  assert.ok(planForDate(data, 'main', '2026-10-12', false).exercises.length === 0)
  assert.ok(planForDate(data, 'main', '2026-07-20', false).exercises.length === 0)
})

test('the selected plan length bounds both generated phases instead of running forever', () => {
  const fourWeek = generateTrainingPlan(userId, {
    ...baseInput,
    plan_weeks: 4,
  } as TrainingInductionInput)
  assert.equal(fourWeek.induction.plan_weeks, 4)
  assert.equal(fourWeek.induction.transition_weeks, 4)
  assert.equal(fourWeek.induction.main_start_date, '2026-08-12')
  assert.equal(fourWeek.induction.end_date, '2026-08-12')
  assert.equal(isInsideInductionWindow(fourWeek.induction, 'transition', '2026-08-11'), true)
  assert.equal(isInsideInductionWindow(fourWeek.induction, 'transition', '2026-08-12'), false)
  assert.equal(isInsideInductionWindow(fourWeek.induction, 'main', '2026-08-12'), false)

  const sixMonth = generateTrainingPlan(userId, {
    ...baseInput,
    plan_weeks: 26,
  } as TrainingInductionInput)
  assert.equal(sixMonth.induction.plan_weeks, 26)
  assert.equal(sixMonth.induction.transition_weeks, 12)
  assert.equal(sixMonth.induction.main_start_date, '2026-10-07')
  assert.equal(sixMonth.induction.end_date, '2027-01-13')
  assert.equal(isInsideInductionWindow(sixMonth.induction, 'main', '2026-10-07'), true)
  assert.equal(isInsideInductionWindow(sixMonth.induction, 'main', '2027-01-12'), true)
  assert.equal(isInsideInductionWindow(sixMonth.induction, 'main', '2027-01-13'), false)
})

test('short generated sessions persist one generic work group for each paired movement', () => {
  const generated = generateTrainingPlan(userId, baseInput)
  const transitionDay = generated.program_days.find((day) => (
    generated.induction.transition_day_ids.includes(day.id) && day.name.includes('Full Body A')
  ))
  assert.ok(transitionDay)
  const rows = generated.exercises
    .filter((exercise) => exercise.program_day_id === transitionDay.id && !exercise.is_lite)
    .map((exercise) => exercise as typeof exercise & {
      work_group_id?: string | null
      work_group_position?: number | null
    })
  const grouped = rows.filter((exercise) => exercise.work_group_id != null)

  assert.equal(grouped.length, 2)
  assert.equal(new Set(grouped.map((exercise) => exercise.work_group_id)).size, 1)
  assert.deepEqual(grouped.map((exercise) => exercise.work_group_position), [1, 2])
  assert.deepEqual(grouped.map((exercise) => exercise.name), ['Dumbbell Floor Press', 'One-Arm Dumbbell Row'])
})

test('every generated work group position is unique inside its day and full-or-lite mode', () => {
  for (const venue of ['home', 'gym', 'outdoors'] as const) {
    for (let sessions = 2; sessions <= 7; sessions += 1) {
      const generated = generateTrainingPlan(userId, {
        ...baseInput,
        venue,
        sessions_per_week: sessions,
      })
      const keys = generated.exercises.flatMap((exercise) => (
        exercise.work_group_id && exercise.work_group_position
          ? [`${exercise.program_day_id}:${exercise.is_lite}:${exercise.work_group_id}:${exercise.work_group_position}`]
          : []
      ))
      assert.equal(
        new Set(keys).size,
        keys.length,
        `${venue}/${sessions} generated duplicate (day, mode, group, position) rows`,
      )
    }
  }
})

test('a generated grouped day advertises the duration its runnable timeline actually uses', () => {
  const seeded = buildSeedData(userId, 'matthew')
  const generated = generateTrainingPlan(userId, baseInput, seeded.programs)
  const data = {
    ...seeded,
    settings: { ...seeded.settings!, addons: { ...seeded.settings!.addons, training_induction: generated.induction } },
    programs: generated.programs,
    program_days: generated.program_days,
    exercises: generated.exercises,
  }
  const day = planForDate(data, 'transition', baseInput.start_date, false)

  assert.ok(day.exercises.some((exercise) => exercise.work_group_id != null))
  assert.equal(day.programDay?.est_minutes, estimatedTimelineMinutes(day))
})

test('native and web rebuild metadata archives history and activates only the committed revision', () => {
  const seeded = buildSeedData(userId, 'matthew')
  const first = generateTrainingPlan(userId, baseInput, seeded.programs, '2026-07-15T08:00:00.000Z')
  let addons = commitTrainingPlanAddons(seeded.settings!.addons, first)
  let data = {
    ...seeded,
    settings: { ...seeded.settings!, addons },
    programs: first.programs,
    program_days: [...seeded.program_days, ...first.program_days],
    exercises: [...seeded.exercises, ...first.exercises],
  }

  addons = invalidateTrainingPlanAddons(addons)
  assert.deepEqual(
    [...archivedTrainingDayIds(addons)].sort(),
    first.program_days.map((day) => day.id).sort(),
  )
  assert.equal(trainingGenerationRevision(addons), 1)

  const second = generateTrainingPlan(
    userId,
    { ...baseInput, venue: 'outdoors' },
    data.programs,
    '2026-08-22T08:00:00.000Z',
    trainingGenerationRevision(addons),
  )
  assert.equal(
    second.program_days.some((day) => first.program_days.some((old) => old.id === day.id)),
    false,
  )
  addons = markPendingTrainingPlanAddons(addons, second)
  data = {
    ...data,
    settings: { ...data.settings, addons },
    programs: second.programs,
    program_days: [...data.program_days, ...second.program_days],
    exercises: [...data.exercises, ...second.exercises],
  }
  assert.deepEqual([...pendingTrainingDayIds(addons)].sort(), second.program_days.map((day) => day.id).sort())
  assert.equal(
    activeTrainingProgramDays(data).some((day) => second.program_days.some((pending) => pending.id === day.id)),
    false,
  )

  addons = commitTrainingPlanAddons(addons, second)
  data = { ...data, settings: { ...data.settings, addons } }
  assert.equal(
    activeTrainingProgramDays(data).every((day) => !first.program_days.some((old) => old.id === day.id)),
    true,
  )
  assert.equal(
    second.program_days.every((day) => activeTrainingProgramDays(data).some((active) => active.id === day.id)),
    true,
  )
  const planned = planForDate(data, 'transition', '2026-08-24', false)
  assert.equal(second.program_days.some((day) => day.id === planned.programDay?.id), true)

  const restored = restoreTrainingPlanAddons(data)
  assert.ok(restored)
  data = { ...data, settings: { ...data.settings, addons: restored } }
  assert.equal(
    activeTrainingProgramDays(data).some((day) =>
      [...first.program_days, ...second.program_days].some((generated) => generated.id === day.id)),
    false,
  )
  const restoredPlan = planForDate(data, 'transition', '2026-08-24', false)
  assert.ok(restoredPlan.programDay)
  assert.equal(
    [...first.program_days, ...second.program_days].some((day) => day.id === restoredPlan.programDay?.id),
    false,
  )
})

test('native-shaped induction metadata is canonical before the web form or generator uses it', () => {
  const nativeMetadata = {
    start_date: '2026-08-22',
    inactivity: 'under_three_months',
    venue: 'outdoors',
    equipment: ['resistance_bands'],
    pain_areas: ['knee', 'shoulder'],
    recent_operation: false,
    chronic_lower_back_pain: true,
    sessions_per_week: 5,
    goal: 'general',
  }
  const input = trainingInputFromProfile(nativeMetadata, '2026-01-01')

  assert.deepEqual(input, {
    ...nativeMetadata,
    inactivity: 'one_to_three_months',
    pain_areas: ['knees', 'shoulders'],
    plan_weeks: 12,
    goal: 'rebuild',
  })
  const generated = generateTrainingPlan(userId, nativeMetadata as unknown as TrainingInductionInput)
  assert.equal(generated.induction.goal, 'rebuild')
  assert.equal(generated.exercises.every((exercise) => Number.isFinite(exercise.rest_sec)), true)
})

test('native fat-loss and endurance goals remain honest through a web rebuild', () => {
  for (const goal of ['fat_loss', 'endurance'] as const) {
    const input = trainingInputFromProfile({ ...baseInput, goal }, '2026-01-01')
    assert.equal(input.goal, goal)
    assert.equal(generateTrainingPlan(userId, input).induction.goal, goal)
  }

  const panel = readFileSync(
    join(process.cwd(), 'src/components/workout/TrainingInductionPanel.tsx'),
    'utf8',
  )
  assert.match(panel, /fat_loss: copy\.fatLoss/)
  assert.match(panel, /endurance: copy\.endurance/)
})

test('a skipped settings-only account can build without becoming another persona', () => {
  const seeded = buildSeedData(userId, 'constantine')
  const generated = generateTrainingPlan(userId, baseInput, [])
  const committed = commitTrainingPlanAddons({
    ...seeded.settings!.addons,
    newbie_mode: false,
    training_induction: null,
    training_induction_skipped: true,
  }, generated)
  assert.equal(committed.training_induction_skipped, undefined)

  const reloaded = repairSeedDefinitions({
    ...seeded,
    profile: null,
    settings: { ...seeded.settings!, addons: committed },
    meals: [],
    supplements: [],
    programs: generated.programs,
    program_days: generated.program_days,
    exercises: generated.exercises,
    snapshots: [],
  }, seeded)
  assert.equal(reloaded.needsRepair, false)
  assert.equal(reloaded.data.profile, null)
  assert.deepEqual(reloaded.data.programs, generated.programs)
  assert.deepEqual(reloaded.data.program_days, generated.program_days)

  const panel = readFileSync(
    join(process.cwd(), 'src/components/workout/TrainingInductionPanel.tsx'),
    'utf8',
  )
  assert.match(panel, /data\.profile\?\.user_id \?\? data\.settings\?\.user_id/)
  const workout = readFileSync(join(process.cwd(), 'src/pages/WorkoutSection.tsx'), 'utf8')
  assert.match(workout, /training_induction_skipped/)
  const app = readFileSync(join(process.cwd(), 'src/App.tsx'), 'utf8')
  assert.match(app, /data\.profile\?\.user_id \?\? data\.settings\?\.user_id \?\? 'signed-out'/)
  assert.match(app, /settingsOnly \? <WorkoutSection/)
})

test('a profileless installed plan remains followable without weight-derived activity', () => {
  const tracked = readFileSync(join(process.cwd(), 'src/pages/TrackedSession.tsx'), 'utf8')
  assert.match(tracked, /const ownerId = data\.profile\?\.user_id \?\? data\.settings\?\.user_id/)
  assert.match(tracked, /if \([^\n]*!ownerId[^\n]*\) return/)
  assert.match(tracked, /userId: ownerId/)
  assert.doesNotMatch(tracked, /!data\.profile\) return/)

  const player = readFileSync(join(process.cwd(), 'src/pages/Player.tsx'), 'utf8')
  assert.match(player, /const ownerId = data\.profile\?\.user_id \?\? data\.settings\?\.user_id/)
  assert.match(player, /if \(!finished \|\| savedRef\.current \|\| !plan\.programDay \|\| !ownerId\) return/)
  assert.match(player, /userId: ownerId/)
  assert.match(player, /if \(activityType && data\.profile\)/)

  for (const relativePath of ['src/components/DaySheet.tsx', 'src/pages/WorkoutSection.tsx']) {
    const source = readFileSync(join(process.cwd(), relativePath), 'utf8')
    assert.match(source, /const ownerId = data\.profile\?\.user_id \?\? data\.settings\?\.user_id/)
    assert.doesNotMatch(source, /user_id: data\.profile\?\.user_id \?\? ''/)
  }
})

test('web generation matches the shared native revision fixture', () => {
  const fixture = JSON.parse(readFileSync(
    join(process.cwd(), 'tests/fixtures/training-induction-revision.json'),
    'utf8',
  )) as {
    user_id: string
    generation_revision: number
    input: unknown
    expected: { first_day_id: string; first_exercise_id: string }
  }
  const generated = generateTrainingPlan(
    fixture.user_id,
    fixture.input as TrainingInductionInput,
    [],
    '2026-08-22T08:00:00.000Z',
    fixture.generation_revision,
  )

  assert.equal(generated.program_days[0].id, fixture.expected.first_day_id)
  assert.equal(generated.exercises[0].id, fixture.expected.first_exercise_id)
})

test('an empty legacy induction marker remains safely restorable', () => {
  const seeded = buildSeedData(userId, 'matthew')
  const data = {
    ...seeded,
    program_days: [],
    settings: {
      ...seeded.settings!,
      addons: {
        ...seeded.settings!.addons,
        newbie_mode: false,
        training_induction: {} as never,
      },
    },
  }

  const restored = restoreTrainingPlanAddons(data)
  assert.ok(restored)
  assert.equal(restored.training_induction, null)
})

test('Iulian-Andrei receives concise gym bodybuilding definitions and versioned upgrades rewrite inherited rows', () => {
  const seeded = buildSeedData(userId, 'iulian')
  assert.equal(seeded.programs.find((program) => program.slug === 'main')?.name, 'Main Training')
  assert.equal(seeded.programs.find((program) => program.slug === 'main')?.description, 'Bodybuilding')
  assert.equal(seeded.programs.find((program) => program.slug === 'transition')?.name, 'Transitional Training')
  assert.equal(seeded.programs.find((program) => program.slug === 'transition')?.description, 'For beginners')
  const names = seeded.exercises.map((exercise) => exercise.name).join('|')
  assert.match(names, /Smith Machine|Cable|Hack Squat/)
  assert.doesNotMatch(names, /SkiErg|Team Calisthenics|Big Hammer Loop/)

  const legacy = {
    ...seeded,
    profile: { ...seeded.profile!, seed_version: 1 },
    programs: seeded.programs.map((program) => ({ ...program, name: 'Inherited home plan' })),
    exercises: seeded.exercises.map((exercise, index) => index === 0 ? { ...exercise, name: 'Push-Up' } : exercise),
  }
  const repaired = repairSeedDefinitions(legacy, seeded)
  assert.equal(repaired.data.programs.find((program) => program.slug === 'main')?.name, 'Main Training')
  assert.equal(repaired.data.exercises.find((exercise) => exercise.id === seeded.exercises[0].id)?.name, seeded.exercises[0].name)
  assert.ok(repaired.missing.programs.length > 0)
})

function filesBelow(directory: string): string[] {
  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name)
    return statSync(path).isDirectory() ? filesBelow(path) : [path]
  })
}

test('website source contains no em dash characters or entities', () => {
  for (const path of filesBelow(new URL('../src', import.meta.url).pathname)) {
    const source = readFileSync(path, 'utf8')
    assert.equal(source.includes('—'), false, `em dash in ${path}`)
    assert.equal(/&mdash;|&#8212;/.test(source), false, `em dash entity in ${path}`)
  }
})
