import {
  CARDIO_MODALITIES,
  CARDIO_ALIASES,
  MOVEMENTS,
  MOVEMENT_ALIASES,
  type Movement,
} from '../data/movements.ts'
import { resolveMovement } from './liftingTempo.ts'
import type { WorkoutLog } from './types.ts'

export type ExerciseLoggingKind =
  | 'strength'
  | 'bodyweight'
  | 'isometric'
  | 'carry'
  | 'cardio'
  | 'mobility'
  | 'interval'
  | 'circuit'

export type ExerciseLoggingField =
  | 'reps'
  | 'signedLoad'
  | 'rir'
  | 'duration'
  | 'distance'
  | 'contacts'
  | 'completion'
  | 'rounds'
  | 'work'
  | 'recovery'

export interface ExerciseLoggingDescriptor {
  kind: ExerciseLoggingKind
  fields: ExerciseLoggingField[]
  supported: boolean
  movementId: string | null
}

export interface ExerciseLoggingFacts {
  weight: number | null
  reps: number | null
  rir: number | null
  durationSeconds?: number | null
  distanceMeters?: number | null
  contacts?: number | null
  rounds?: number | null
  workSeconds?: number | null
  recoverySeconds?: number | null
}

const MOVEMENT_BY_ID = new Map(MOVEMENTS.map((movement) => [movement.id, movement]))
const CARDIO_BY_ID = new Map(CARDIO_MODALITIES.map((modality) => [modality.id, modality]))

function normalized(value: string): string {
  return value
    .replace(/\([^)]*\)/g, '')
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLocaleLowerCase('en')
    .replace(/[^\p{Letter}\p{Number}]+/gu, '')
}

const CARDIO_BY_NAME = new Map(CARDIO_MODALITIES.map((modality) => [normalized(modality.name), modality]))
const MOVEMENT_ALIAS_BY_NAME = new Map(Object.entries(MOVEMENT_ALIASES).map(([name, movementID]) => [
  normalized(name),
  MOVEMENT_BY_ID.get(movementID) ?? null,
]))
const CARDIO_ALIAS_BY_NAME = new Map(Object.entries(CARDIO_ALIASES).map(([name, value]) => [
  normalized(name),
  CARDIO_BY_ID.get(value.modality) ?? null,
]))

function kindForMovement(movement: Movement): ExerciseLoggingKind {
  switch (movement.entityType) {
    case 'movement_sequence': return 'circuit'
    case 'conditioning_complex': return 'interval'
    case 'balance_drill':
    case 'mobility_drill':
    case 'skill_drill':
    case 'yoga_pose': return 'mobility'
    case 'resistance_isometric': return movement.prescriptionMode === 'carry' ? 'carry' : 'isometric'
    case 'plyometric': return 'bodyweight'
    case 'resistance_dynamic':
      return !movement.loadable
        || movement.disciplines.includes('calisthenics')
        || movement.id === 'assisted_pull_up_machine'
        ? 'bodyweight'
        : 'strength'
    default: return 'strength'
  }
}

function fieldsFor(kind: ExerciseLoggingKind, movement: Movement | null): ExerciseLoggingField[] {
  if (movement?.prescriptionMode === 'contacts') return ['contacts']
  switch (kind) {
    case 'strength':
    case 'bodyweight': return ['reps', 'signedLoad', 'rir']
    case 'isometric': return ['duration', 'signedLoad']
    case 'carry': return ['duration', 'distance', 'signedLoad']
    case 'cardio': return ['duration', 'distance']
    case 'mobility': return ['duration', 'completion']
    case 'interval': return ['rounds', 'work', 'recovery']
    case 'circuit': return []
  }
}

/** Resolve on every read. Neither the row nor the database stores a logging kind. */
export function descriptorForExercise(exercise: {
  name: string
  movement_id?: string | null
}): ExerciseLoggingDescriptor {
  const movement = exercise.movement_id ? MOVEMENT_BY_ID.get(exercise.movement_id) ?? null : null
  const cardio = exercise.movement_id ? CARDIO_BY_ID.get(exercise.movement_id) ?? null : null
  const resolvedMovement = movement
    ?? MOVEMENT_ALIAS_BY_NAME.get(normalized(exercise.name))
    ?? resolveMovement(exercise.name, MOVEMENTS, MOVEMENT_ALIASES)
  const resolvedCardio = cardio
    ?? CARDIO_BY_NAME.get(normalized(exercise.name))
    ?? CARDIO_ALIAS_BY_NAME.get(normalized(exercise.name))
    ?? null

  if (resolvedCardio) {
    return { kind: 'cardio', fields: fieldsFor('cardio', null), supported: true, movementId: resolvedCardio.id }
  }
  const kind = resolvedMovement ? kindForMovement(resolvedMovement) : 'strength'
  return {
    kind,
    fields: fieldsFor(kind, resolvedMovement),
    supported: kind !== 'circuit',
    movementId: resolvedMovement?.id ?? exercise.movement_id ?? null,
  }
}

const emptyFacts = (): Required<ExerciseLoggingFacts> => ({
  weight: null,
  reps: null,
  rir: null,
  durationSeconds: null,
  distanceMeters: null,
  contacts: null,
  rounds: null,
  workSeconds: null,
  recoverySeconds: null,
})

function positiveOrNull(value: number | null | undefined): number | null {
  return value != null && Number.isFinite(value) && value > 0 ? value : null
}

/** Clear irrelevant observations and make unassisted bodyweight an explicit zero. */
export function normalizeExerciseFacts(
  facts: ExerciseLoggingFacts,
  descriptor: ExerciseLoggingDescriptor,
  skipped: boolean,
): Required<ExerciseLoggingFacts> {
  if (skipped || !descriptor.supported) return emptyFacts()
  const has = (field: ExerciseLoggingField): boolean => descriptor.fields.includes(field)
  const load = has('signedLoad') && facts.weight != null && Number.isFinite(facts.weight)
    ? facts.weight
    : has('signedLoad') && descriptor.kind === 'bodyweight' ? 0 : null
  const rir = has('rir') && facts.rir != null && Number.isFinite(facts.rir)
    && facts.rir >= 0 && facts.rir <= 5 ? Math.round(facts.rir) : null
  return {
    weight: load,
    reps: has('reps') ? positiveOrNull(facts.reps) : null,
    rir,
    durationSeconds: has('duration') ? positiveOrNull(facts.durationSeconds) : null,
    distanceMeters: has('distance') ? positiveOrNull(facts.distanceMeters) : null,
    contacts: has('contacts') ? positiveOrNull(facts.contacts) : null,
    rounds: has('rounds') ? positiveOrNull(facts.rounds) : null,
    workSeconds: has('work') ? positiveOrNull(facts.workSeconds) : null,
    recoverySeconds: has('recovery') ? positiveOrNull(facts.recoverySeconds) : null,
  }
}

/** A completed row is valid only when its kind's measured facts are complete. */
export function isValidExerciseFacts(
  facts: ExerciseLoggingFacts,
  descriptor: ExerciseLoggingDescriptor,
): boolean {
  if (!descriptor.supported) return false
  const value = normalizeExerciseFacts(facts, descriptor, false)
  switch (descriptor.kind) {
    case 'strength':
    case 'bodyweight':
      return descriptor.fields.includes('contacts')
        ? value.contacts != null
        : value.reps != null
    case 'isometric': return value.durationSeconds != null
    case 'carry': return (value.durationSeconds != null) !== (value.distanceMeters != null)
    case 'cardio': return value.durationSeconds != null && value.distanceMeters != null
    case 'mobility': return true
    case 'interval': return value.rounds != null && value.workSeconds != null && value.recoverySeconds != null
    case 'circuit': return false
  }
}

export function derivePaceSecondsPerKilometre(
  distanceMeters: number,
  durationSeconds: number,
): number | null {
  if (!(distanceMeters > 0) || !(durationSeconds > 0)) return null
  return durationSeconds * 1_000 / distanceMeters
}

export function workoutLogFactSummary(log: WorkoutLog): string[] {
  const descriptor = descriptorForExercise({ name: log.exercise_name, movement_id: log.movement_id })
  if (log.skipped) return ['Not completed']
  const facts: string[] = []
  if (descriptor.fields.includes('reps') && log.reps != null) facts.push(`${log.reps} reps`)
  if (descriptor.fields.includes('signedLoad') && log.weight_kg != null) facts.push(`${log.weight_kg} kg`)
  if (descriptor.fields.includes('rir') && log.rir != null) facts.push(`RIR ${log.rir}`)
  if (descriptor.fields.includes('duration') && log.duration_seconds != null) facts.push(`${log.duration_seconds} sec`)
  if (descriptor.fields.includes('distance') && log.distance_meters != null) facts.push(`${log.distance_meters} m`)
  if (descriptor.fields.includes('contacts') && log.contacts != null) facts.push(`${log.contacts} contacts`)
  if (descriptor.fields.includes('rounds') && log.rounds != null) facts.push(`${log.rounds} rounds`)
  if (descriptor.fields.includes('work') && log.work_seconds != null) facts.push(`${log.work_seconds} sec work`)
  if (descriptor.fields.includes('recovery') && log.recovery_seconds != null) facts.push(`${log.recovery_seconds} sec recovery`)
  if (descriptor.fields.includes('completion') && facts.length === 0) facts.push('Completed')
  if (descriptor.kind === 'cardio' && log.distance_meters != null && log.duration_seconds != null) {
    const pace = derivePaceSecondsPerKilometre(log.distance_meters, log.duration_seconds)
    if (pace != null) {
      const rounded = Math.round(pace)
      facts.push(`${Math.floor(rounded / 60)}:${String(rounded % 60).padStart(2, '0')} /km`)
    }
  }
  return facts
}

/** Positive external kg × reps, including added load on bodyweight movements. */
export function loadedStrengthVolume(logs: WorkoutLog[]): number {
  return logs.reduce((total, log) => {
    const descriptor = descriptorForExercise({ name: log.exercise_name, movement_id: log.movement_id })
    if (log.skipped || (descriptor.kind !== 'strength' && descriptor.kind !== 'bodyweight')) return total
    return total + Math.max(0, log.weight_kg ?? 0) * Math.max(0, log.reps ?? 0)
  }, 0)
}
