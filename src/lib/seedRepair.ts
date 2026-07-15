import type { AppData } from './types'

export const CURRENT_SEED_VERSION = 2

export type SeedDefinitionTable =
  | 'meals'
  | 'supplements'
  | 'programs'
  | 'program_days'
  | 'exercises'

export interface SeedRepairResult {
  data: AppData
  needsRepair: boolean
  profileChanged: boolean
  settingsChanged: boolean
  missing: Pick<AppData, SeedDefinitionTable>
}

function reconcileRows<T extends { id: string }>(
  current: T[],
  seeded: T[],
  naturalKey: (row: T) => string,
): { missing: T[]; idMap: Map<string, string> } {
  const currentById = new Map(current.map((row) => [row.id, row]))
  const currentByKey = new Map(current.map((row) => [naturalKey(row), row]))
  const missing: T[] = []
  const idMap = new Map<string, string>()

  for (const row of seeded) {
    const match = currentById.get(row.id) ?? currentByKey.get(naturalKey(row))
    if (match) idMap.set(row.id, match.id)
    else {
      missing.push(row)
      idMap.set(row.id, row.id)
    }
  }
  return { missing, idMap }
}

function emptyMissing(): Pick<AppData, SeedDefinitionTable> {
  return {
    meals: [],
    supplements: [],
    programs: [],
    program_days: [],
    exercises: [],
  }
}

function replaceRowsBySeedId<T extends { id: string }>(current: T[], seeded: T[]): T[] {
  const seededById = new Map(seeded.map((row) => [row.id, row]))
  const replaced = current.map((row) => seededById.get(row.id) ?? row)
  const currentIds = new Set(current.map((row) => row.id))
  return [...replaced, ...seeded.filter((row) => !currentIds.has(row.id))]
}

/* Seed completion is deliberately versioned. It repairs interrupted first
   syncs once, while preserving every row that already exists and avoiding
   the permanent re-creation of definitions a user may later remove. */
export function repairSeedDefinitions(current: AppData, seeded: AppData): SeedRepairResult {
  const currentVersion = Number(current.profile?.seed_version ?? 0)
  const needsRepair = !current.profile || currentVersion < CURRENT_SEED_VERSION
  if (!needsRepair) {
    return {
      data: current,
      needsRepair: false,
      profileChanged: false,
      settingsChanged: false,
      missing: emptyMissing(),
    }
  }

  /* Version 2 corrects Iulian-Andrei's inherited home/calisthenics rows to a
     gym-only bodybuilding programme. IDs stay stable so workout history keeps
     its references while the definitions are upgraded in place. */
  const upgradesIulianProgramme = currentVersion === 1 && current.profile?.persona === 'iulian'
  const working = upgradesIulianProgramme
    ? {
        ...current,
        programs: replaceRowsBySeedId(current.programs, seeded.programs),
        program_days: replaceRowsBySeedId(current.program_days, seeded.program_days),
        exercises: replaceRowsBySeedId(current.exercises, seeded.exercises),
      }
    : current

  const mealRepair = reconcileRows(working.meals, seeded.meals, (row) => `${row.time}|${row.name}`)
  const supplementRepair = reconcileRows(
    working.supplements,
    seeded.supplements,
    (row) => `${row.group_label}|${row.name}|${row.sort_order}`,
  )
  const programRepair = reconcileRows(working.programs, seeded.programs, (row) => row.slug)

  const remappedDays = seeded.program_days.map((row) => ({
    ...row,
    program_id: programRepair.idMap.get(row.program_id) ?? row.program_id,
  }))
  const dayRepair = reconcileRows(
    working.program_days,
    remappedDays,
    (row) => `${row.program_id}|${row.weekday}|${row.name}`,
  )

  const remappedExercises = seeded.exercises.map((row) => ({
    ...row,
    program_day_id: dayRepair.idMap.get(row.program_day_id) ?? row.program_day_id,
  }))
  const exerciseRepair = reconcileRows(
    working.exercises,
    remappedExercises,
    (row) => `${row.program_day_id}|${row.is_lite}|${row.sort_order}|${row.name}`,
  )

  const genuinelyMissing: Pick<AppData, SeedDefinitionTable> = {
    meals: mealRepair.missing,
    supplements: supplementRepair.missing,
    programs: programRepair.missing,
    program_days: dayRepair.missing,
    exercises: exerciseRepair.missing,
  }
  const missing: Pick<AppData, SeedDefinitionTable> = upgradesIulianProgramme
    ? {
        ...genuinelyMissing,
        programs: seeded.programs,
        program_days: remappedDays,
        exercises: remappedExercises,
      }
    : genuinelyMissing

  const profile = current.profile
    ? { ...current.profile, seed_version: CURRENT_SEED_VERSION }
    : seeded.profile
      ? { ...seeded.profile, seed_version: CURRENT_SEED_VERSION }
      : null
  const settings = current.settings ?? seeded.settings

  return {
    data: {
      ...working,
      profile,
      settings,
      meals: [...working.meals, ...genuinelyMissing.meals],
      supplements: [...working.supplements, ...genuinelyMissing.supplements],
      programs: [...working.programs, ...genuinelyMissing.programs],
      program_days: [...working.program_days, ...genuinelyMissing.program_days],
      exercises: [...working.exercises, ...genuinelyMissing.exercises],
    },
    needsRepair: true,
    profileChanged: !current.profile || currentVersion !== CURRENT_SEED_VERSION,
    settingsChanged: !current.settings && !!settings,
    missing,
  }
}
