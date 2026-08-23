import { useMemo, useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { GlassCard, GradientButton, GhostButton, BackLink } from '../components/ui'
import { ACCENTS } from '../lib/theme'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { useStore } from '../store/AppStore'
import { planForDate } from '../lib/plan'
import { recommendLoad } from '../lib/progression'
import { buildSessionRecords, sessionQuality, type ExerciseEntry, type SetEntry } from '../lib/workoutSession'
import { hasLoggedFact } from '../lib/workoutSession'
import { descriptorForExercise, isValidExerciseFacts } from '../lib/exerciseLogging'
import { ExerciseFactFields } from '../components/workout/ExerciseFactFields'
import { movementForExercise } from '../lib/sessionShape'
import { buildWorkSequence } from '../lib/playerTimeline'
import type { ProgramSlug } from '../lib/types'

/**
 * The tracked session: a list, not a follow-along.
 *
 * Anyone running their own progressive overload does not want to be paced.
 * They want to see what is on today, do it at their own rhythm, and write down
 * what actually happened -- weight, reps, and reps in reserve, which is the
 * number that decides whether the next session goes up.
 *
 * It writes exactly the same records as the guided player, through the same
 * function, so history does not depend on which screen was used.
 */
export function TrackedSession() {
  const { slug, date } = useParams()
  const [params] = useSearchParams()
  const lite = params.get('lite') === '1'
  const navigate = useNavigate()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const { data, upsert, bulkUpsert } = useStore()
  const ownerId = data.profile?.user_id ?? data.settings?.user_id

  const plan = useMemo(
    () => planForDate(data, slug as ProgramSlug, date ?? '', lite),
    [data, slug, date, lite],
  )

  /* Last session's numbers are the only sensible starting point: nobody wants
   * to retype 80 kg every week to discover whether it moved. */
  const [entries, setEntries] = useState<Record<number, ExerciseEntry>>(() => {
    const seed: Record<number, ExerciseEntry> = {}
    plan.exercises.forEach((e, index) => {
      const known = data.exercises.some((x) => x.id === e.id)
      const descriptor = descriptorForExercise({ name: e.name, movement_id: e.movement_id })
      const suggested = known ? recommendLoad(data, e).weight : null
      seed[index] = {
        exerciseId: known ? e.id : null,
        movementId: e.movement_id ?? movementForExercise(e)?.id ?? null,
        name: e.name,
        plannedSets: e.planned_sets,
        repUnit: e.rep_unit,
        workGroupId: e.work_group_id,
        workGroupPosition: e.work_group_position,
        skipped: false,
        override: false,
        sets: Array.from({ length: e.planned_sets }, () => ({
          weight: suggested ?? (descriptor.kind === 'bodyweight' && descriptor.fields.includes('signedLoad') ? 0 : null),
          reps: null,
          rir: null,
          durationSeconds: null,
          distanceMeters: null,
          contacts: null,
          rounds: null,
          workSeconds: null,
          recoverySeconds: null,
        })),
      }
    })
    return seed
  })

  const startedAt = useMemo(() => new Date().toISOString(), [])
  const groupLabels = useMemo(() => {
    const labels = new Map<number, string>()
    buildWorkSequence(plan.exercises).forEach((position) => {
      if (position.groupLabel && !labels.has(position.exIdx)) labels.set(position.exIdx, position.groupLabel)
    })
    return labels
  }, [plan.exercises])

  const patchSet = (exIdx: number, setIdx: number, patch: Partial<SetEntry>): void => {
    setEntries((current) => {
      const entry = current[exIdx]
      const sets = entry.sets.map((s, i) => (i === setIdx ? { ...s, ...patch } : s))
      return { ...current, [exIdx]: { ...entry, sets } }
    })
  }

  const toggleSkipped = (exIdx: number): void => {
    setEntries((current) => ({
      ...current,
      [exIdx]: { ...current[exIdx], skipped: !current[exIdx].skipped },
    }))
  }

  /* Carrying the first set's weight down the column is what people do by hand
   * anyway, and it makes a five-set exercise two taps instead of ten. */
  const fillDown = (exIdx: number): void => {
    setEntries((current) => {
      const entry = current[exIdx]
      const first = entry.sets[0]
      return {
        ...current,
        [exIdx]: {
          ...entry,
          sets: entry.sets.map((s, i) => (i === 0 ? s : {
            weight: s.weight ?? first.weight,
            reps: s.reps ?? first.reps,
            rir: s.rir ?? first.rir,
            durationSeconds: s.durationSeconds ?? first.durationSeconds,
            distanceMeters: s.distanceMeters ?? first.distanceMeters,
            contacts: s.contacts ?? first.contacts,
            rounds: s.rounds ?? first.rounds,
            workSeconds: s.workSeconds ?? first.workSeconds,
            recoverySeconds: s.recoverySeconds ?? first.recoverySeconds,
          })),
        },
      }
    })
  }

  const list = Object.values(entries)
  const setsLogged = list.reduce((sum, entry) => {
    if (entry.skipped) return sum
    const descriptor = descriptorForExercise({ name: entry.name, movement_id: entry.movementId })
    return sum + entry.sets.filter((set) => hasLoggedFact(set, descriptor)).length
  }, 0)
  const setsPlanned = list.reduce((sum, e) => sum + e.plannedSets, 0)
  const canFinish = list.every((entry) => {
    if (entry.skipped) return true
    const descriptor = descriptorForExercise({ name: entry.name, movement_id: entry.movementId })
    return entry.sets.length === entry.plannedSets
      && entry.sets.every((set) => isValidExerciseFacts(set, descriptor))
  })

  const finish = (): void => {
    if (!plan.programDay || !ownerId || !canFinish) return
    const { session, logs } = buildSessionRecords({
      sessionId: crypto.randomUUID(),
      userId: ownerId,
      date: date ?? '',
      programDayId: plan.programDay.id,
      isLite: lite,
      isDeload: plan.isDeload,
      isEventRecovery: plan.isRecoveryMicro,
      qualityScore: sessionQuality(list),
      startedAt,
      completedAt: new Date().toISOString(),
      exercises: list,
    })
    upsert('workout_sessions', session)
    bulkUpsert('workout_logs', logs)
    navigate('/')
  }

  if (!plan.programDay) {
    return (
      <div className="mx-auto w-full max-w-2xl px-4 py-6">
        <BackLink />
        <GlassCard className="mt-4 p-6 text-sm text-ink-soft">
          {t('Nothing is scheduled for this day.')}
        </GlassCard>
      </div>
    )
  }

  return (
    <div className="mx-auto w-full max-w-2xl px-4 py-6 pb-32">
      <BackLink />
      <header className="mt-4">
        <p className="text-[10px] font-black uppercase tracking-[0.2em] text-ink-soft">
          {t('Tracked session')}
        </p>
        <h1 className="text-2xl font-black text-ink">{plan.programDay.name}</h1>
        <p className="mt-1 text-xs text-ink-soft">
          {t('Log what you actually did. Nothing here is timed.')}
        </p>
      </header>

      <div className="mt-5 space-y-3">
        {plan.exercises.map((exercise, exIdx) => {
          const entry = entries[exIdx]
          const movement = movementForExercise(exercise)
          const descriptor = descriptorForExercise({ name: exercise.name, movement_id: exercise.movement_id })
          const groupLabel = groupLabels.get(exIdx)
          const target = exercise.rep_min === exercise.rep_max
            ? `${exercise.rep_min}`
            : `${exercise.rep_min}-${exercise.rep_max}`
          return (
            <GlassCard key={exercise.id} className={`p-4 ${entry.skipped ? 'opacity-50' : ''}`}>
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    {groupLabel ? <span className="rounded-full bg-teal-500/10 px-2 py-1 font-mono text-[10px] font-black text-teal-800">{groupLabel}</span> : null}
                    <h2 className="truncate text-sm font-black text-ink">{exercise.name}</h2>
                  </div>
                  <p className="mt-0.5 text-[11px] text-ink-soft">
                    {entry.plannedSets} × {target} {exercise.rep_unit}
                    {exercise.per_side ? ` · ${t('per side')}` : ''}
                  </p>
                  {movement?.notes ? (
                    <p className="mt-1 text-[11px] leading-snug text-ink-soft/80">{movement.notes}</p>
                  ) : null}
                </div>
                <GhostButton onClick={() => toggleSkipped(exIdx)}>
                  {entry.skipped ? t('Undo') : t('Skip')}
                </GhostButton>
              </div>

              {!entry.skipped && (
                <>
                  {entry.sets.map((set, setIdx) => (
                    <div key={setIdx} className="mt-2 grid grid-cols-[1.6rem_minmax(0,1fr)] items-center gap-2">
                      <span className="text-[11px] font-black text-ink-soft" aria-label={groupLabel ? `${t('Round')} ${setIdx + 1}` : `${t('Set')} ${setIdx + 1}`}>
                        {groupLabel ? `R${setIdx + 1}` : setIdx + 1}
                      </span>
                      <ExerciseFactFields descriptor={descriptor} value={set} onChange={(patch) => patchSet(exIdx, setIdx, patch)} />
                    </div>
                  ))}
                  {entry.plannedSets > 1 && (
                    <button
                      type="button"
                      onClick={() => fillDown(exIdx)}
                      className="mt-2 text-[11px] font-bold text-ink-soft underline underline-offset-2"
                    >
                      {t('Copy set 1 to the rest')}
                    </button>
                  )}
                </>
              )}
            </GlassCard>
          )
        })}
      </div>

      <div className="fixed inset-x-0 bottom-0 border-t border-white/10 bg-surface/90 px-4 py-3 backdrop-blur">
        <div className="mx-auto flex w-full max-w-2xl items-center justify-between gap-3">
          <p className="text-[11px] font-bold text-ink-soft">
            {setsLogged}/{setsPlanned} {t('sets logged')}
          </p>
          <GradientButton accent={ACCENTS.teal} onClick={finish} disabled={!canFinish}>
            {t('Finish session')}
          </GradientButton>
        </div>
      </div>
    </div>
  )
}
