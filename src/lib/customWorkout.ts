import { EXERCISE_CATALOG, catalogExerciseByName } from '../data/exerciseCatalog.ts'
import type { AppData, Exercise, Program, ProgramDay, SessionMode } from './types.ts'
import type { OwnerBoundMutationWrite } from './ownerBoundMutation.ts'

export interface CustomWorkoutSelection {
  id: string
  sets: number
  target: number
  rest: number
  /** The boundary after this row belongs to the same repeated round. */
  linkedToNext: boolean
}

export interface CustomWorkoutDraft {
  name: string
  weekday: number
  sessionMode: SessionMode
  selected: CustomWorkoutSelection[]
  omittedExerciseCount: number
}

export class CustomWorkoutReplacementRequiredError extends Error {
  readonly replacingDayIDs: string[]

  constructor(replacingDayIDs: string[]) {
    super('Confirm the exact custom workouts that will be replaced.')
    this.name = 'CustomWorkoutReplacementRequiredError'
    this.replacingDayIDs = replacingDayIDs
  }
}

/**
 * Remote rows are deliberately ordered parent → active/archive days → new
 * prescription → stale deletes. One sync group prevents any destructive tail
 * operation from overtaking a failed replacement row.
 */
export function customWorkoutSyncWrites(input: {
  program: Program
  days: readonly ProgramDay[]
  exercises: readonly Exercise[]
  staleExerciseIDs: readonly string[]
}): OwnerBoundMutationWrite[] {
  const writes: OwnerBoundMutationWrite[] = [
    {
      ownerID: input.program.user_id,
      table: 'programs',
      type: 'upsert',
      payload: input.program as unknown as Record<string, unknown>,
    },
    {
      ownerID: input.program.user_id,
      table: 'program_days',
      type: 'upsert',
      payload: input.days as unknown as Array<Record<string, unknown>>,
    },
    {
      ownerID: input.program.user_id,
      table: 'exercises',
      type: 'upsert',
      payload: input.exercises as unknown as Array<Record<string, unknown>>,
    },
  ]
  const replacementIDs = new Set(input.exercises.map((exercise) => exercise.id))
  for (const exerciseID of input.staleExerciseIDs) {
    if (replacementIDs.has(exerciseID)) continue
    writes.push({
      ownerID: input.program.user_id,
      table: 'exercises',
      type: 'delete',
      payload: { id: exerciseID, user_id: input.program.user_id },
    })
  }
  return writes
}

/** Revalidate the draft against the latest store inside the shared save lease. */
export function stageCustomWorkoutSave(current: AppData, input: {
  program: Program
  day: ProgramDay
  exercises: Exercise[]
  editingDayID: string | null
  confirmedReplacementDayIDs: readonly string[]
}): { data: AppData; writes: OwnerBoundMutationWrite[]; result: void } {
  const ownerID = input.program.user_id
  const program = current.programs.find((row) => row.user_id === ownerID && row.slug === 'custom') ?? input.program
  const activeDays = activeCustomWorkoutDays(current.program_days, ownerID, program.id)
  if (input.editingDayID && !activeDays.some((row) => row.id === input.editingDayID)) {
    throw new Error('This workout is no longer available.')
  }
  if (
    program.slug !== 'custom'
    || input.day.user_id !== ownerID
    || (input.editingDayID !== null && input.day.id !== input.editingDayID)
    || input.exercises.some((row) => row.user_id !== ownerID || row.program_day_id !== input.day.id)
  ) throw new Error('Invalid custom workout owner or prescription.')
  const replacement = customWorkoutReplacementDecision(current.program_days, {
    ownerID, programID: program.id, weekday: input.day.weekday,
    editingDayID: input.editingDayID,
    confirmedReplacementDayIDs: input.confirmedReplacementDayIDs,
  })
  if (replacement.kind === 'confirmation-required') {
    throw new CustomWorkoutReplacementRequiredError(replacement.replacingDayIDs)
  }
  const savedDay = { ...input.day, program_id: program.id, is_active: true }
  const days = [...customWorkoutArchiveRows(current.program_days, {
    ownerID, programID: program.id, dayIDs: replacement.replacingDayIDs,
  }), savedDay]
  const dayByID = new Map(days.map((row) => [row.id, row]))
  const staleExerciseIDs = customWorkoutStaleExerciseIDs(current.exercises, ownerID, input.editingDayID)
  const staleIDs = new Set(staleExerciseIDs)
  return {
    data: {
      ...current,
      programs: current.programs.some((row) => row.id === program.id)
        ? current.programs : [...current.programs, program],
      program_days: [
        ...current.program_days.map((row) => row.user_id === ownerID ? dayByID.get(row.id) ?? row : row),
        ...days.filter((row) => !current.program_days.some((existing) => existing.id === row.id)),
      ],
      exercises: [...current.exercises.filter((row) => !staleIDs.has(row.id)), ...input.exercises],
    },
    writes: customWorkoutSyncWrites({ program, days, exercises: input.exercises, staleExerciseIDs }),
    result: undefined,
  }
}

export function stageCustomWorkoutArchive(current: AppData, input: {
  ownerID: string; programID: string; dayID: string
}): { data: AppData; writes: OwnerBoundMutationWrite[]; result: void } {
  if (!current.programs.some((row) => row.id === input.programID && row.user_id === input.ownerID && row.slug === 'custom')) {
    throw new Error('This workout is no longer available.')
  }
  const archivedDay = customWorkoutArchiveRows(current.program_days, {
    ...input, dayIDs: [input.dayID],
  })[0]
  if (!archivedDay) throw new Error('This workout is no longer available.')
  return {
    data: {
      ...current,
      program_days: current.program_days.map((row) => row.id === archivedDay.id && row.user_id === input.ownerID ? archivedDay : row),
    },
    writes: [{ ownerID: input.ownerID, table: 'program_days', type: 'upsert', payload: { ...archivedDay } }],
    result: undefined,
  }
}

export function activeCustomWorkoutDays(
  days: readonly ProgramDay[],
  ownerID: string,
  programID: string,
): ProgramDay[] {
  return days.filter((day) =>
    day.user_id === ownerID &&
    day.program_id === programID &&
    day.is_active !== false,
  )
}

export function customWorkoutArchiveRows(
  days: readonly ProgramDay[],
  input: {
    ownerID: string
    programID: string
    dayIDs: readonly string[]
  },
): ProgramDay[] {
  const requested = new Set(input.dayIDs)
  return activeCustomWorkoutDays(days, input.ownerID, input.programID)
    .filter((day) => requested.has(day.id))
    .map((day) => ({ ...day, is_active: false }))
}

export function customWorkoutSaveDayID(
  editingDayID: string | null,
  makeID: () => string = () => crypto.randomUUID(),
): string {
  return editingDayID ?? makeID()
}

export function customWorkoutStaleExerciseIDs(
  exercises: readonly Exercise[],
  ownerID: string,
  editingDayID: string | null,
): string[] {
  if (!editingDayID) return []
  return exercises
    .filter((exercise) => exercise.user_id === ownerID && exercise.program_day_id === editingDayID)
    .map((exercise) => exercise.id)
}

export type CustomWorkoutReplacementDecision =
  | { kind: 'save'; replacingDayIDs: string[] }
  | { kind: 'confirmation-required'; replacingDayIDs: string[] }

/**
 * Rebuild the exact authoring draft behind a persisted custom day. A saved
 * row resolves by canonical movement first and localized/legacy name second,
 * so changing the interface language never breaks editability.
 */
export function customWorkoutDraftForDay(
  day: ProgramDay,
  exercises: readonly Exercise[],
): CustomWorkoutDraft {
  const rows = exercises
    .filter((exercise) => exercise.user_id === day.user_id && exercise.program_day_id === day.id)
    .slice()
    .sort((left, right) => left.sort_order - right.sort_order || left.id.localeCompare(right.id))
  const resolved = rows.flatMap((exercise, index) => {
    const item = (exercise.movement_id
      ? EXERCISE_CATALOG.find((candidate) => candidate.movementID === exercise.movement_id)
      : null) ?? catalogExerciseByName(exercise.name)
    if (!item) return []
    const next = rows[index + 1]
    const nextItem = next
      ? ((next.movement_id
          ? EXERCISE_CATALOG.find((candidate) => candidate.movementID === next.movement_id)
          : null) ?? catalogExerciseByName(next.name))
      : null
    return [{
      id: item.id,
      sets: exercise.sets,
      target: exercise.rep_max,
      rest: exercise.rest_sec,
      linkedToNext: Boolean(
        exercise.work_group_id &&
        nextItem &&
        next?.work_group_id === exercise.work_group_id &&
        (next.work_group_position ?? 0) > (exercise.work_group_position ?? 0),
      ),
    }]
  })

  return {
    name: day.name,
    weekday: day.weekday,
    sessionMode: day.session_mode === 'tracked' ? 'tracked' : 'guided',
    selected: resolved,
    omittedExerciseCount: rows.length - resolved.length,
  }
}

/**
 * A weekday collision is replacement, never an implicit save. Rows belonging
 * to another account are intentionally invisible to the decision.
 */
export function customWorkoutReplacementDecision(
  days: readonly ProgramDay[],
  input: {
    ownerID: string
    programID: string
    weekday: number
    editingDayID: string | null
    confirmedReplacementDayIDs: readonly string[]
  },
): CustomWorkoutReplacementDecision {
  const replacingDayIDs = activeCustomWorkoutDays(days, input.ownerID, input.programID)
    .filter((day) =>
      day.weekday === input.weekday &&
      day.id !== input.editingDayID,
    )
    .map((day) => day.id)
    .sort()
  if (replacingDayIDs.length === 0) return { kind: 'save', replacingDayIDs }

  const confirmed = [...new Set(input.confirmedReplacementDayIDs)].sort()
  const confirmsExactSet = confirmed.length === replacingDayIDs.length
    && confirmed.every((dayID, index) => dayID === replacingDayIDs[index])
  return confirmsExactSet
    ? { kind: 'save', replacingDayIDs }
    : { kind: 'confirmation-required', replacingDayIDs }
}

export interface CustomWorkoutGroupAssignment {
  workGroupId: string | null
  workGroupPosition: number | null
  label: string | null
}

export function customWorkoutTargetLabel(unit: string): string {
  switch (unit) {
    case 'seconds': return 'Seconds'
    case 'minutes': return 'Minutes'
    case 'metres': return 'Distance (m)'
    case 'steps': return 'Steps'
    case 'rounds': return 'Rounds'
    default: return 'Repetitions'
  }
}

export function moveCustomWorkoutSelection(
  items: CustomWorkoutSelection[],
  index: number,
  offset: number,
): CustomWorkoutSelection[] {
  const destination = index + offset
  if (index < 0 || index >= items.length || destination < 0 || destination >= items.length) return items

  const moved = [...items]
  ;[moved[index], moved[destination]] = [moved[destination], moved[index]]
  return moved
}

export function removeCustomWorkoutSelection(
  items: CustomWorkoutSelection[],
  id: string,
): CustomWorkoutSelection[] {
  const index = items.findIndex((item) => item.id === id)
  if (index < 0) return items
  const remaining = items.filter((item) => item.id !== id)
  if (index > 0) {
    remaining[index - 1] = { ...remaining[index - 1], linkedToNext: false }
  }
  return remaining
}

function groupLabel(groupIndex: number, position: number): string {
  const letter = groupIndex < 26 ? String.fromCharCode(65 + groupIndex) : `G${groupIndex + 1}`
  return `${letter}${position}`
}

export function customWorkoutGroupAssignments(
  items: CustomWorkoutSelection[],
  makeId: () => string = () => crypto.randomUUID(),
): CustomWorkoutGroupAssignment[] {
  const assignments = items.map<CustomWorkoutGroupAssignment>(() => ({
    workGroupId: null,
    workGroupPosition: null,
    label: null,
  }))
  let groupIndex = 0
  let index = 0

  while (index < items.length - 1) {
    if (!items[index].linkedToNext) {
      index += 1
      continue
    }

    const start = index
    let end = index + 1
    while (end < items.length - 1 && items[end].linkedToNext) end += 1

    const workGroupId = makeId()
    for (let member = start; member <= end; member += 1) {
      const position = member - start + 1
      assignments[member] = {
        workGroupId,
        workGroupPosition: position,
        label: groupLabel(groupIndex, position),
      }
    }
    groupIndex += 1
    index = end + 1
  }

  return assignments
}
