import { useMemo, useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { GlassCard, GradientButton, GhostButton, BackLink } from '../components/ui'
import { ACCENTS } from '../lib/theme'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { useStore } from '../store/AppStore'
import { planForDate } from '../lib/plan'
import { recommendLoad } from '../lib/progression'
import { buildSessionRecords, sessionQuality, type ExerciseEntry, type SetEntry } from '../lib/workoutSession'
import { movementForExercise } from '../lib/sessionShape'
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
      const suggested = known ? recommendLoad(data, e).weight : null
      seed[index] = {
        exerciseId: known ? e.id : null,
        name: e.name,
        plannedSets: e.planned_sets,
        skipped: false,
        override: false,
        sets: Array.from({ length: e.planned_sets }, () => ({
          weight: suggested ?? null,
          reps: null,
          rir: null,
        })),
      }
    })
    return seed
  })

  const startedAt = useMemo(() => new Date().toISOString(), [])

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
          })),
        },
      }
    })
  }

  const list = Object.values(entries)
  const setsLogged = list.reduce(
    (sum, e) => e.skipped ? sum : sum + e.sets.filter((s) => (s.reps ?? 0) > 0).length, 0)
  const setsPlanned = list.reduce((sum, e) => sum + e.plannedSets, 0)

  const finish = (): void => {
    if (!plan.programDay || !data.profile) return
    const { session, logs } = buildSessionRecords({
      sessionId: crypto.randomUUID(),
      userId: data.profile.user_id,
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
          const target = exercise.rep_min === exercise.rep_max
            ? `${exercise.rep_min}`
            : `${exercise.rep_min}-${exercise.rep_max}`
          return (
            <GlassCard key={exercise.id} className={`p-4 ${entry.skipped ? 'opacity-50' : ''}`}>
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <h2 className="truncate text-sm font-black text-ink">{exercise.name}</h2>
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
                  <div className="mt-3 grid grid-cols-[1.6rem_1fr_1fr_1fr] items-center gap-2 text-[10px] font-bold uppercase tracking-wide text-ink-soft">
                    <span />
                    <span>{t('kg')}</span>
                    <span>{t('Reps')}</span>
                    <span>{t('RIR')}</span>
                  </div>
                  {entry.sets.map((set, setIdx) => (
                    <div key={setIdx} className="mt-1.5 grid grid-cols-[1.6rem_1fr_1fr_1fr] items-center gap-2">
                      <span className="text-[11px] font-black text-ink-soft">{setIdx + 1}</span>
                      <NumberField
                        value={set.weight}
                        step={exercise.increment_kg || 1}
                        onChange={(weight) => patchSet(exIdx, setIdx, { weight })}
                        disabled={exercise.increment_kg === 0}
                      />
                      <NumberField
                        value={set.reps}
                        step={1}
                        onChange={(reps) => patchSet(exIdx, setIdx, { reps })}
                      />
                      <NumberField
                        value={set.rir}
                        step={1}
                        onChange={(rir) => patchSet(exIdx, setIdx, { rir })}
                      />
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
          <GradientButton accent={ACCENTS.teal} onClick={finish}>
            {t('Finish session')}
          </GradientButton>
        </div>
      </div>
    </div>
  )
}

function NumberField({
  value, step, onChange, disabled = false,
}: {
  value: number | null
  step: number
  onChange: (next: number | null) => void
  disabled?: boolean
}) {
  return (
    <input
      type="number"
      inputMode="decimal"
      step={step}
      disabled={disabled}
      value={value ?? ''}
      onChange={(event) => {
        const raw = event.target.value
        onChange(raw === '' ? null : Number(raw))
      }}
      className="w-full rounded-xl border border-white/10 bg-white/60 px-2 py-2 text-center text-sm font-bold text-ink outline-none disabled:opacity-40"
    />
  )
}
