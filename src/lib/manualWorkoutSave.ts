import { timeZoneFromSettings, zonedClock, zonedDateTimeToIso } from './mealTiming.ts'
import { descriptorForExercise, normalizeExerciseFacts } from './exerciseLogging.ts'
import { scopedUuid } from './ids.ts'
import { manualWorkoutNotes, manualWorkoutTitle, reconcileManualWorkoutLogs, type ManualExerciseDraft } from './manualWorkout.ts'
import type { OwnerBoundMutationWrite } from './ownerBoundMutation.ts'
import type { AppData, Program, ProgramDay, WorkoutLog, WorkoutSession } from './types.ts'
import { hasLoggedFact } from './workoutSession.ts'
import { isWorkoutDate } from './workoutTimingMetadata.ts'

export function stageManualWorkoutSave(current: AppData, input: {
  ownerID: string; sessionID: string; editing: boolean; date: string; title: string
  exercises: ManualExerciseDraft[]; now: Date
}): { data: AppData; writes: OwnerBoundMutationWrite[]; result: void } {
  const { ownerID, sessionID, date, now } = input
  if (current.profile?.user_id !== ownerID) throw new Error('Your account changed. Reopen this workout.')
  const timeZone = timeZoneFromSettings(current.settings)
  const clock = zonedClock(now, timeZone)
  if (!isWorkoutDate(date) || date > clock.date) throw new Error('Choose today or an earlier date.')
  if (!input.exercises.length) throw new Error('Add at least one exercise.')
  const existing = current.workout_sessions.find((row) => row.id === sessionID)
  if ((input.editing && !existing) || (existing && (existing.user_id !== ownerID || manualWorkoutTitle(existing.notes) == null))) {
    throw new Error('This workout could not be reopened.')
  }
  const existingLogs = current.workout_logs.filter((row) => row.user_id === ownerID && row.session_id === sessionID)
  const existingProgram = current.programs.find((row) => row.user_id === ownerID && row.slug === 'custom')
  const program: Program = existingProgram ?? {
    id: scopedUuid('custom-workout-program', 'custom', ownerID.toLowerCase()),
    user_id: ownerID, slug: 'custom', name: 'Custom workouts', description: 'Your searchable exercise studio, saved privately.',
  }
  const dayID = scopedUuid('quick-log-day', program.id.toLowerCase(), ownerID.toLowerCase())
  const day: ProgramDay = {
    id: dayID, user_id: ownerID, program_id: program.id, weekday: 1, name: 'Quick Log',
    day_type: 'custom', est_minutes: 0, warmup_note: '', sort_order: 0, is_active: false,
  }
  const performed = new Date(date === clock.date ? now : zonedDateTimeToIso(date, clock.time, timeZone))
  const session: WorkoutSession = {
    is_lite: false, is_deload: false, is_event_recovery: false, quality_score: 1, started_at: null,
    completed_at: performed.toISOString(), ...existing, id: sessionID, user_id: ownerID, date,
    completed: true, program_day_id: existing?.program_day_id ?? dayID, notes: manualWorkoutNotes(input.title, existing?.notes),
  }
  const existingTimes = existingLogs.map((row) => Date.parse(row.created_at)).filter(Number.isFinite)
  const start = existingTimes.length ? Math.min(...existingTimes) : performed.getTime()
  const nextLogs = input.exercises.flatMap<WorkoutLog>((exercise, index) => {
    const descriptor = descriptorForExercise({ name: exercise.canonicalName, movement_id: exercise.movementId })
    if (!descriptor.supported || !exercise.sets.length) throw new Error('Complete each set or remove it before saving.')
    return exercise.sets.map((set, position) => {
      const entry = { ...set, weight: set.weightKg, rir: set.rir ?? null }
      if (!hasLoggedFact(entry, descriptor)) throw new Error('Complete each set or remove it before saving.')
      const facts = normalizeExerciseFacts(entry, descriptor, false)
      return {
        id: scopedUuid('quick-log-set', [sessionID, exercise.id, set.id].join(':'), ownerID.toLowerCase()),
        user_id: ownerID, session_id: sessionID, exercise_id: null, exercise_name: exercise.canonicalName, set_no: position + 1,
        movement_id: exercise.movementId ?? descriptor.movementId, weight_kg: facts.weight, reps: facts.reps, rir: facts.rir,
        duration_seconds: facts.durationSeconds, distance_meters: facts.distanceMeters, contacts: facts.contacts,
        rounds: facts.rounds, work_seconds: facts.workSeconds, recovery_seconds: facts.recoverySeconds,
        skipped: false, override_flag: false, created_at: new Date(start + index * 60_000 + position * 100).toISOString(),
      }
    })
  })
  const { logs, staleIds } = reconcileManualWorkoutLogs(existingLogs, nextLogs)
  const writes: OwnerBoundMutationWrite[] = []
  const addProgram = !existing && !existingProgram
  const addDay = !existing && !current.program_days.some((row) => row.id === dayID && row.user_id === ownerID)
  if (addProgram) writes.push({ ownerID, table: 'programs', type: 'upsert', payload: { ...program } })
  if (addDay) writes.push({ ownerID, table: 'program_days', type: 'upsert', payload: { ...day } })
  writes.push({ ownerID, table: 'workout_sessions', type: 'upsert', payload: { ...session } })
  writes.push({ ownerID, table: 'workout_logs', type: 'upsert', payload: logs.map((row) => ({ ...row })) })
  for (const id of staleIds) writes.push({ ownerID, table: 'workout_logs', type: 'delete', payload: { id, user_id: ownerID } })
  return { data: { ...current,
    programs: addProgram ? [...current.programs, program] : current.programs,
    program_days: addDay ? [...current.program_days, day] : current.program_days,
    workout_sessions: [...current.workout_sessions.filter((row) => row.id !== sessionID), session],
    workout_logs: [...current.workout_logs.filter((row) => row.user_id !== ownerID || row.session_id !== sessionID), ...logs],
  }, writes, result: undefined }
}
