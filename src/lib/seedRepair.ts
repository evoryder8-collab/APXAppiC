import type { AppData } from './types'

export const CURRENT_SEED_VERSION = 3

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
  removed: {
    exercises: string[]
  }
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

function hash32(value: string, seed: number): number {
  let hash = seed >>> 0
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  hash ^= hash >>> 16
  hash = Math.imul(hash, 0x7feb352d)
  hash ^= hash >>> 15
  return hash >>> 0
}

function stableUpgradeId(userId: string, label: string): string {
  const input = `${userId}:seed-upgrade:${label}`
  const raw = [
    hash32(input, 0x811c9dc5),
    hash32(input, 0x9e3779b9),
    hash32(input, 0x85ebca6b),
    hash32(input, 0xc2b2ae35),
  ].map((part) => part.toString(16).padStart(8, '0')).join('')
  const variant = ((parseInt(raw[16], 16) & 0x3) | 0x8).toString(16)
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-4${raw.slice(13, 16)}-${variant}${raw.slice(17, 20)}-${raw.slice(20, 32)}`
}

function upgradeBespokeMainProgramme(
  current: AppData,
  seeded: AppData,
): {
  data: AppData
  rows: Pick<AppData, 'programs' | 'program_days' | 'exercises'>
  removedExercises: string[]
} | null {
  const currentProgram = current.programs.find((row) => row.slug === 'main')
  const seededProgram = seeded.programs.find((row) => row.slug === 'main')
  if (!currentProgram || !seededProgram || !current.profile) return null

  const currentDays = current.program_days.filter((row) => row.program_id === currentProgram.id)
  const currentDayByWeekday = new Map(currentDays.map((row) => [row.weekday, row]))
  const seededDays = seeded.program_days.filter((row) => row.program_id === seededProgram.id)
  const mappedDays = seededDays.map((row) => {
    const existing = currentDayByWeekday.get(row.weekday)
    return {
      ...row,
      id: existing?.id ?? stableUpgradeId(currentProgram.user_id, `main-day:${row.weekday}`),
      program_id: currentProgram.id,
    }
  })

  const mappedExercises = mappedDays.flatMap((mappedDay) => {
    const seededDay = seededDays.find((row) => row.weekday === mappedDay.weekday)
    if (!seededDay) return []
    const existingDay = currentDayByWeekday.get(mappedDay.weekday)
    const currentRows = existingDay
      ? current.exercises.filter((row) => row.program_day_id === existingDay.id)
      : []
    const currentBySlot = new Map(currentRows.map((row) => [`${row.is_lite}|${row.sort_order}`, row]))
    return seeded.exercises
      .filter((row) => row.program_day_id === seededDay.id)
      .map((row) => {
        const slot = `${row.is_lite}|${row.sort_order}`
        const existing = currentBySlot.get(slot)
        return {
          ...row,
          id: existing?.id ?? stableUpgradeId(currentProgram.user_id, `main-exercise:${mappedDay.weekday}:${slot}`),
          program_day_id: mappedDay.id,
        }
      })
  })

  const mappedExerciseIds = new Set(mappedExercises.map((row) => row.id))
  const currentDayIds = new Set(currentDays.map((row) => row.id))
  const removedExercises = current.exercises
    .filter((row) => currentDayIds.has(row.program_day_id) && !mappedExerciseIds.has(row.id))
    .map((row) => row.id)
  const mappedProgram = { ...seededProgram, id: currentProgram.id }
  const currentProgramDayIds = new Set(currentDays.map((row) => row.id))

  return {
    data: {
      ...current,
      programs: current.programs.map((row) => row.id === currentProgram.id ? mappedProgram : row),
      program_days: [
        ...current.program_days.filter((row) => !currentProgramDayIds.has(row.id)),
        ...mappedDays,
      ],
      exercises: [
        ...current.exercises.filter((row) => !currentDayIds.has(row.program_day_id)),
        ...mappedExercises,
      ],
    },
    rows: {
      programs: [mappedProgram],
      program_days: mappedDays,
      exercises: mappedExercises,
    },
    removedExercises,
  }
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
      removed: { exercises: [] },
    }
  }

  /* Version 2 corrects Iulian-Andrei's inherited home/calisthenics rows to a
     gym-only bodybuilding programme. IDs stay stable so workout history keeps
     its references while the definitions are upgraded in place. */
  const upgradesIulianProgramme = currentVersion === 1 && current.profile?.persona === 'iulian'
  const iulianWorking = upgradesIulianProgramme
    ? {
        ...current,
        programs: replaceRowsBySeedId(current.programs, seeded.programs),
        program_days: replaceRowsBySeedId(current.program_days, seeded.program_days),
        exercises: replaceRowsBySeedId(current.exercises, seeded.exercises),
      }
    : current
  const upgradesV81Programme =
    currentVersion < 3 &&
    (current.profile?.persona === 'constantine' || current.profile?.persona === 'june')
      ? upgradeBespokeMainProgramme(iulianWorking, seeded)
      : null
  const working = upgradesV81Programme?.data ?? iulianWorking

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
  const missing: Pick<AppData, SeedDefinitionTable> = upgradesV81Programme
    ? {
        ...genuinelyMissing,
        programs: upgradesV81Programme.rows.programs,
        program_days: upgradesV81Programme.rows.program_days,
        exercises: upgradesV81Programme.rows.exercises,
      }
    : upgradesIulianProgramme
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
  const seededProtocol = seeded.settings?.addons.training_protocol
  const protocolWasAdded = !!seededProtocol && !current.settings?.addons.training_protocol
  const settings = current.settings
    ? {
        ...current.settings,
        addons: {
          ...current.settings.addons,
          ...(protocolWasAdded ? { training_protocol: seededProtocol } : {}),
        },
      }
    : seeded.settings

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
    settingsChanged: (!current.settings && !!settings) || protocolWasAdded,
    missing,
    removed: { exercises: upgradesV81Programme?.removedExercises ?? [] },
  }
}
