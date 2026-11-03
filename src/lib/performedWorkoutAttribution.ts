import { withoutWorkoutTimingMetadata } from './workoutTimingMetadata.ts'
import { CARDIO_MODALITIES, MOVEMENTS } from '../data/movements.ts'
import type { WorkoutLog, WorkoutSession } from './types.ts'

/** These are game-index activity domains, never measured physical capacity. */
export type PerformedWorkoutType = 'upper' | 'legs_a' | 'mobility' | 'cardio'

const movements = new Map(MOVEMENTS.map((movement) => [movement.id, movement]))
const cardioIDs = new Set(CARDIO_MODALITIES.map((movement) => movement.id))
const lowerMuscles = new Set(['hamstrings', 'glutes', 'quadriceps', 'glute_medius', 'calves', 'soleus', 'adductors', 'hip_flexors', 'tibialis'])
const upperMuscles = new Set(['chest', 'front_delts', 'triceps', 'lats', 'upper_back', 'biceps', 'forearms', 'lower_traps', 'traps', 'side_delts', 'rear_delts', 'rotator_cuff', 'mid_traps'])

function positive(value: number | null | undefined): boolean {
  return value != null && Number.isFinite(value) && value > 0
}

export function hasPerformedWorkoutFacts(log: WorkoutLog): boolean {
  return !log.skipped && (positive(log.reps) || positive(log.duration_seconds)
    || positive(log.distance_meters) || positive(log.contacts)
    || (positive(log.rounds) && positive(log.work_seconds)))
}

/** Resolve only a stored catalogue ID. A familiar-looking free-text name is not evidence. */
export function performedWorkoutTypes(log: WorkoutLog): PerformedWorkoutType[] {
  if (log.skipped || !log.movement_id) return []
  if (cardioIDs.has(log.movement_id)) {
    return positive(log.duration_seconds) && positive(log.distance_meters) ? ['cardio'] : []
  }
  const movement = movements.get(log.movement_id)
  if (!movement) return []
  if (movement.entityType === 'mobility_drill' || movement.entityType === 'yoga_pose') {
    // These catalogue modes explicitly support a completed checkmark instead
    // of measured time. Retain that evidence without inventing any duration.
    return ['mobility']
  }
  if (movement.entityType === 'conditioning_complex') {
    return positive(log.rounds) && positive(log.work_seconds) ? ['cardio'] : []
  }
  const performed = movement.entityType === 'resistance_dynamic' ? positive(log.reps)
    : movement.entityType === 'resistance_isometric'
      ? positive(log.duration_seconds) || positive(log.distance_meters)
      : movement.entityType === 'plyometric' ? positive(log.contacts) || positive(log.reps) : false
  if (!performed) return []
  const types: PerformedWorkoutType[] = []
  if (movement.primaryMuscles.some((muscle) => upperMuscles.has(muscle))) types.push('upper')
  if (movement.primaryMuscles.some((muscle) => lowerMuscles.has(muscle))) types.push('legs_a')
  return types
}

/** Distinguish missing historical detail from explicit evidence of no work. */
export function recordedWorkoutQuality(session: WorkoutSession, logs: WorkoutLog[]): number {
  if (!session.completed) return 0
  const notes = withoutWorkoutTimingMetadata(session.notes)
  const external = notes === 'Completed externally from the APEX guided player'
    || notes === 'Completed externally from the FITR MAX guided player'
  if (logs.length > 0 && !external
    && !logs.some((log) => hasPerformedWorkoutFacts(log) || performedWorkoutTypes(log).length > 0)) return 0
  const quality = session.quality_score
  if (!Number.isFinite(quality) || quality < 0) return 0
  if (quality === 0 && (logs.length === 0 || external)) return 1
  return Math.min(1, quality)
}

export function workoutActivityDomain(type: string): PerformedWorkoutType | null {
  if (['push', 'pull', 'upper'].includes(type)) return 'upper'
  if (['legs_a', 'legs_b'].includes(type)) return 'legs_a'
  if (['mobility', 'fix'].includes(type)) return 'mobility'
  if (['t25', 'cardio'].includes(type)) return 'cardio'
  return null
}
