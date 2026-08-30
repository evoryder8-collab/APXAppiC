import type { AppData } from './types'

export const CURRENT_SEED_VERSION = 8

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
    meals: string[]
    supplements: string[]
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

export function shouldRepairSeedDefinitions(current: AppData): boolean {
  const addons = current.settings?.addons
  const hasSettingsOnlyTrainingState = Boolean(addons && (
    addons.training_induction_skipped === true ||
    (addons.training_induction != null && typeof addons.training_induction === 'object') ||
    addons.newbie_mode === true ||
    Array.isArray(addons.training_induction_pending_day_ids) ||
    Array.isArray(addons.training_induction_archived_day_ids) ||
    typeof addons.training_induction_generation_revision === 'number'
  ))
  /* Skip, an installed plan, an interrupted install and a restored plan are
   * explicit profileless account states. Preserve those facts, while still
   * repairing an ordinary persona seed interrupted after its settings insert. */
  if (!current.profile && hasSettingsOnlyTrainingState) return false
  return !current.profile || Number(current.profile.seed_version ?? 0) < CURRENT_SEED_VERSION
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

  const sessionKind = (name: string): 'morning' | 't25' | 'official' => {
    if (name.startsWith('AM ·')) return 'morning'
    if (name.toLocaleLowerCase('en').startsWith('focus t25')) return 't25'
    return 'official'
  }
  const dayKey = (row: { weekday: number; name: string }) => `${row.weekday}|${sessionKind(row.name)}`
  const currentDays = current.program_days.filter((row) => row.program_id === currentProgram.id)
  const currentDayByKey = new Map(currentDays.map((row) => [dayKey(row), row]))
  const seededDays = seeded.program_days.filter((row) => row.program_id === seededProgram.id)
  const seededDayByKey = new Map(seededDays.map((row) => [dayKey(row), row]))
  const mappedDays = seededDays.map((row) => {
    const kind = sessionKind(row.name)
    const existing = currentDayByKey.get(dayKey(row))
    return {
      ...row,
      id: existing?.id ?? stableUpgradeId(currentProgram.user_id, `main-day:${row.weekday}:${kind}`),
      program_id: currentProgram.id,
    }
  })

  const mappedExercises = mappedDays.flatMap((mappedDay) => {
    const kind = sessionKind(mappedDay.name)
    const seededDay = seededDayByKey.get(dayKey(mappedDay))
    if (!seededDay) return []
    const existingDay = currentDayByKey.get(dayKey(mappedDay))
    const currentRows = existingDay
      ? current.exercises.filter((row) => row.program_day_id === existingDay.id)
      : []
    const currentByIdentity = new Map(currentRows.map((row) => [`${row.is_lite}|${row.name.toLocaleLowerCase('en')}`, row]))
    return seeded.exercises
      .filter((row) => row.program_day_id === seededDay.id)
      .map((row) => {
        const slot = `${row.is_lite}|${row.sort_order}`
        /* Preserve an exercise id only when the exercise itself still matches.
           Reusing ids by visual slot would attach old strength history to a
           different movement after a partner-sync reorder. */
        const existing = currentByIdentity.get(`${row.is_lite}|${row.name.toLocaleLowerCase('en')}`)
        return {
          ...row,
          id: existing?.id ?? stableUpgradeId(currentProgram.user_id, `main-exercise:${mappedDay.weekday}:${kind}:${slot}`),
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

function upgradeV3Nutrition(
  current: AppData,
  seeded: AppData,
): {
  data: AppData
  rows: Pick<AppData, 'meals' | 'supplements'>
  removedMeals: string[]
  removedSupplements: string[]
} {
  const removedMeals = current.meals.map((row) => row.id)
  const removedSupplements = current.supplements.map((row) => row.id)
  const removedMealIds = new Set(removedMeals)
  const removedSupplementIds = new Set(removedSupplements)
  return {
    data: {
      ...current,
      meals: [...seeded.meals],
      meal_logs: current.meal_logs.filter((row) => !removedMealIds.has(row.meal_id)),
      supplements: [...seeded.supplements],
      supplement_logs: current.supplement_logs.filter((row) => !removedSupplementIds.has(row.supplement_id)),
    },
    rows: {
      meals: seeded.meals,
      supplements: seeded.supplements,
    },
    removedMeals,
    removedSupplements,
  }
}

function upgradeV5PersonalProtocol(
  current: AppData,
  seeded: AppData,
): {
  data: AppData
  profileChanged: boolean
  settingsChanged: boolean
  supplementRows: AppData['supplements']
} {
  const persona = current.profile?.persona
  if ((persona !== 'constantine' && persona !== 'june') || !current.profile || !seeded.profile) {
    return { data: current, profileChanged: false, settingsChanged: false, supplementRows: [] }
  }

  const profile = persona === 'constantine'
    ? {
        ...current.profile,
        weight_kg: 71,
        body_fat_pct: 22.5,
        height_cm: 177,
        custom_bmr: 1680,
        target_kcal: 2450,
        target_protein_g: 150,
        target_fat_g: 75,
        target_carbs_g: 294,
        profile_note: seeded.profile.profile_note,
      }
    : {
        ...current.profile,
        weight_kg: 41,
        /* Extra active was June's previous seeded default. Preserve every
           other explicitly selected mode while correcting that old default. */
        activity_level: current.profile.activity_level === 'extra'
          ? seeded.profile.activity_level
          : current.profile.activity_level,
        target_kcal: 2400,
        target_protein_g: 85,
        target_fat_g: 95,
        target_carbs_g: 301,
        profile_note: seeded.profile.profile_note,
      }

  const currentSettings = current.settings
  const settings = currentSettings && seeded.settings
    ? {
        ...currentSettings,
        addons: {
          ...currentSettings.addons,
          recovery_data_source: currentSettings.addons.recovery_data_source ?? 'apple',
          recovery_history: currentSettings.addons.recovery_history ?? [],
          watch_activity_history: currentSettings.addons.watch_activity_history ?? [],
          meal_blocks: currentSettings.addons.meal_blocks ?? seeded.settings.addons.meal_blocks,
        },
      }
    : currentSettings ?? seeded.settings

  /* Update the requested protocol supplements in place so existing logs keep
     their foreign keys. Custom supplements remain untouched. */
  const seededByKey = new Map(
    seeded.supplements.map((row) => [`${row.group_label}|${row.name}`.toLocaleLowerCase(), row]),
  )
  const currentKeys = new Set(
    current.supplements.map((row) => `${row.group_label}|${row.name}`.toLocaleLowerCase()),
  )
  const mappedExisting = current.supplements.map((row) => {
    const seededRow = seededByKey.get(`${row.group_label}|${row.name}`.toLocaleLowerCase())
    return seededRow ? { ...seededRow, id: row.id, user_id: row.user_id } : row
  })
  const newRows = seeded.supplements.filter(
    (row) => !currentKeys.has(`${row.group_label}|${row.name}`.toLocaleLowerCase()),
  )
  const supplements = [...mappedExisting, ...newRows]
  const updatedRows = supplements.filter((row) =>
    seededByKey.has(`${row.group_label}|${row.name}`.toLocaleLowerCase()),
  )

  return {
    data: { ...current, profile, settings, supplements },
    profileChanged: true,
    settingsChanged: Boolean(settings),
    supplementRows: updatedRows,
  }
}

/* Seed completion is deliberately versioned. It repairs interrupted first
   syncs once, while preserving every row that already exists and avoiding
   the permanent re-creation of definitions a user may later remove. */
export function repairSeedDefinitions(current: AppData, seeded: AppData): SeedRepairResult {
  const currentVersion = Number(current.profile?.seed_version ?? 0)
  const needsRepair = shouldRepairSeedDefinitions(current)
  if (!needsRepair) {
    return {
      data: current,
      needsRepair: false,
      profileChanged: false,
      settingsChanged: false,
      missing: emptyMissing(),
      removed: { meals: [], supplements: [], exercises: [] },
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
  /* Version 8 installs June V8.4 and Constantine V8.5. Morning, official and
     Focus T25 work become distinct follow-along sessions. The mapper preserves
     the existing official day ids and movement ids whenever identity still
     matches, while assigning stable ids to the new cards. */
  const upgradesV81Programme =
    ((current.profile?.persona === 'constantine' && currentVersion < 8) ||
     (current.profile?.persona === 'june' && currentVersion < 8))
      ? upgradeBespokeMainProgramme(iulianWorking, seeded)
      : null
  const programmeWorking = upgradesV81Programme?.data ?? iulianWorking
  const upgradesNutrition =
    currentVersion < 4 &&
    (current.profile?.persona === 'constantine' || current.profile?.persona === 'june')
      ? upgradeV3Nutrition(programmeWorking, seeded)
      : null
  const nutritionWorking = upgradesNutrition?.data ?? programmeWorking
  const upgradesPersonalProtocol =
    currentVersion < 5
      ? upgradeV5PersonalProtocol(nutritionWorking, seeded)
      : { data: nutritionWorking, profileChanged: false, settingsChanged: false, supplementRows: [] }
  const working = upgradesPersonalProtocol.data

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
  const missing: Pick<AppData, SeedDefinitionTable> = {
    ...genuinelyMissing,
    ...(upgradesNutrition
      ? {
          meals: upgradesNutrition.rows.meals,
          supplements: upgradesNutrition.rows.supplements,
        }
      : {}),
    ...(upgradesPersonalProtocol.supplementRows.length > 0
      ? { supplements: upgradesPersonalProtocol.supplementRows }
      : {}),
    ...(upgradesV81Programme
      ? {
          programs: upgradesV81Programme.rows.programs,
          program_days: upgradesV81Programme.rows.program_days,
          exercises: upgradesV81Programme.rows.exercises,
        }
      : upgradesIulianProgramme
        ? {
            programs: seeded.programs,
            program_days: remappedDays,
            exercises: remappedExercises,
          }
        : {}),
  }

  const profile = current.profile
    ? {
        ...current.profile,
        ...(upgradesNutrition && seeded.profile
          ? {
              target_kcal: seeded.profile.target_kcal,
              target_protein_g: seeded.profile.target_protein_g,
              target_fat_g: seeded.profile.target_fat_g,
              target_carbs_g: seeded.profile.target_carbs_g,
            }
          : {}),
        ...(upgradesPersonalProtocol.profileChanged && working.profile
          ? working.profile
          : {}),
        seed_version: CURRENT_SEED_VERSION,
      }
    : seeded.profile
      ? { ...seeded.profile, seed_version: CURRENT_SEED_VERSION }
      : null
  const seededProtocol = seeded.settings?.addons.training_protocol
  const currentProtocol = current.settings?.addons.training_protocol
  const protocolWasAdded = !!seededProtocol && !currentProtocol
  const protocolNeedsUpgrade = !!seededProtocol && Number(currentProtocol?.version ?? 0) < Number(seededProtocol.version)
  const settingsBase = upgradesPersonalProtocol.settingsChanged ? working.settings : current.settings
  const settings = settingsBase
    ? {
        ...settingsBase,
        addons: {
          ...settingsBase.addons,
          ...(protocolWasAdded || protocolNeedsUpgrade
            ? {
                training_protocol: {
                  ...seededProtocol,
                  start_date: currentProtocol?.start_date ?? seededProtocol.start_date,
                },
              }
            : {}),
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
    profileChanged: !current.profile || currentVersion !== CURRENT_SEED_VERSION || upgradesPersonalProtocol.profileChanged,
    settingsChanged: (!current.settings && !!settings) || protocolWasAdded || protocolNeedsUpgrade || upgradesPersonalProtocol.settingsChanged,
    missing,
    removed: {
      meals: upgradesNutrition?.removedMeals ?? [],
      supplements: upgradesNutrition?.removedSupplements ?? [],
      exercises: upgradesV81Programme?.removedExercises ?? [],
    },
  }
}
