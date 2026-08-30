/* Day planner sheet: plan preview, Full/Lite toggle, deload, water, START. */
import { lazy, Suspense, useMemo, useState } from 'react'
import { format } from 'date-fns'
import { useNavigate } from 'react-router-dom'
import type { Accent } from '../lib/theme'
import { ACCENTS } from '../lib/theme'
import type { AppData, ProgramSlug, SessionMode, WorkoutSession } from '../lib/types'
import { preferredSessionMode, rememberSessionMode } from '../lib/sessionShape'
import { planForDate, programDaysForDate, todayIso } from '../lib/plan'
import { recommendLoad } from '../lib/progression'
import { useStore } from '../store/AppStore'
import { AccentChip, Sheet, Stepper } from './ui'
import { DropletIcon } from './Icons'
import { dailyLogId } from '../lib/ids'
import { WorkoutStatsSheet } from './workout/WorkoutStatsSheet'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { workoutLogsInPerformedOrder } from '../lib/workoutLogOrder'

const HologramStage = lazy(() =>
  import('./hologram/HologramStage').then((m) => ({ default: m.HologramStage })),
)

interface DaySheetProps {
  open: boolean
  onClose: () => void
  dateIso: string
  slug: ProgramSlug
  accent: Accent
  initialLite?: boolean
  initialProgramDayId?: string
}

function completedSessionFor(
  data: AppData,
  slug: ProgramSlug,
  dateIso: string,
  programDayId?: string,
): WorkoutSession | null {
  const program = data.programs.find((p) => p.slug === slug)
  const dayIds = new Set(data.program_days.filter((d) => d.program_id === program?.id).map((d) => d.id))
  return (
    data.workout_sessions.find(
      (s) => s.date === dateIso && s.completed && (
        programDayId
          ? s.program_day_id === programDayId || s.is_event_recovery
          : dayIds.has(s.program_day_id) || s.is_event_recovery
      ),
    ) ?? null
  )
}

export function DaySheet({ open, onClose, dateIso, slug, accent, initialLite = false, initialProgramDayId }: DaySheetProps) {
  const { data, upsert, remove } = useStore()
  const ownerId = data.profile?.user_id ?? data.settings?.user_id
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const navigate = useNavigate()
  const [lite, setLite] = useState(initialLite)
  const [statsOpen, setStatsOpen] = useState(false)
  const [selectedProgramDayId, setSelectedProgramDayId] = useState(initialProgramDayId)

  const plans = useMemo(() => programDaysForDate(data, slug, dateIso, lite), [data, slug, dateIso, lite])
  const plan = plans.find((candidate) => candidate.programDay?.id === selectedProgramDayId)
    ?? plans[0]
    ?? planForDate(data, slug, dateIso, lite, selectedProgramDayId)
  const done = useMemo(
    () => completedSessionFor(data, slug, dateIso, plan.programDay?.id),
    [data, slug, dateIso, plan.programDay?.id],
  )
  const deloadMark = data.deload_marks.find((m) => m.date === dateIso)

  const dayLog = data.daily_logs.find((d) => d.date === dateIso)
  const water = dayLog?.water_l ?? 0
  const setWater = (v: number): void => {
    if (!ownerId) return
    upsert('daily_logs', {
      id: dayLog?.id ?? dailyLogId(dateIso, ownerId),
      user_id: ownerId,
      date: dateIso,
      kcal: dayLog?.kcal ?? null,
      protein_g: dayLog?.protein_g ?? null,
      fat_g: dayLog?.fat_g ?? null,
      carbs_g: dayLog?.carbs_g ?? null,
      water_l: v,
      estimated_tdee: dayLog?.estimated_tdee ?? null,
      computed_pal: dayLog?.computed_pal ?? null,
      activity_mode: dayLog?.activity_mode ?? 'quick',
      weight_kg: dayLog?.weight_kg ?? null,
    })
  }

  const toggleDeload = (): void => {
    if (!ownerId) return
    if (deloadMark) remove('deload_marks', deloadMark.id)
    else
      upsert('deload_marks', {
        id: crypto.randomUUID(),
        user_id: ownerId,
        date: dateIso,
      })
  }

  const logsForDone = done
    ? workoutLogsInPerformedOrder(data, done.id)
    : []

  const d = new Date(dateIso + 'T12:00:00')
  const isPastOrToday = dateIso <= todayIso()

  return (
    <>
    <Sheet open={open} onClose={onClose} wide>
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">
            {format(d, 'EEEE, d MMMM')}
          </p>
          <h2 className="font-display text-2xl font-bold text-ink">
            {plan.isRecoveryMicro ? 'Recovery micro-session' : (plan.programDay?.name ?? 'Rest')}
          </h2>
          {plan.programDay && !plan.isRecoveryMicro && (
            <p className="text-xs font-semibold text-ink-soft">~{plan.programDay.est_minutes} min</p>
          )}
        </div>
        <button
          type="button"
          onClick={onClose}
          className="glass flex h-9 w-9 items-center justify-center rounded-full text-lg font-bold text-ink-soft"
          aria-label="Close"
        >
          ×
        </button>
      </div>

      {plans.length > 1 && (
        <div className="mt-4 grid gap-2" aria-label={t('Sessions planned for this day')}>
          {plans.map((candidate, index) => {
            const active = candidate.programDay?.id === plan.programDay?.id
            return (
              <button
                key={candidate.programDay?.id ?? index}
                type="button"
                onClick={() => setSelectedProgramDayId(candidate.programDay?.id)}
                className={`rounded-2xl border px-3.5 py-3 text-left transition ${active ? 'border-white/90 bg-white/85 shadow-sm' : 'border-white/45 bg-white/45'}`}
              >
                <span className="block break-words text-sm font-black text-ink">{t(candidate.programDay?.name ?? 'Rest')}</span>
                <span className="mt-0.5 block text-[10px] font-semibold text-ink-soft">
                  {t(`~${candidate.programDay?.est_minutes ?? 0} min · ${candidate.exercises.length} exercises`)}
                </span>
              </button>
            )
          })}
        </div>
      )}

      {plan.badges.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {plan.badges.map((b) => (
            <AccentChip
              key={b}
              accent={b.startsWith('Deload') || b.startsWith('Return') ? ACCENTS.teal : b.includes('Taper') || b.includes('Championship') || b.includes('recovery') ? ACCENTS.amber : accent}
            >
              {b.toUpperCase()}
            </AccentChip>
          ))}
        </div>
      )}

      {/* Hologram: muscles for this day light up */}
      {plan.programDay && (
        <div className="mt-4">
          <Suspense
            fallback={
              <div className="glass skeleton h-56 w-full rounded-3xl" aria-label="Loading body" />
            }
          >
            <HologramStage dayType={plan.programDay.day_type} accent={accent} height={260} exerciseNames={plan.exercises.map((exercise) => exercise.name)} />
          </Suspense>
        </div>
      )}

      {/* Full / Lite toggle */}
      {!plan.isRecoveryMicro && (
        <div className="mt-4 flex gap-2">
          {(['Full', 'Lite'] as const).map((mode) => {
            const active = (mode === 'Lite') === lite
            return (
              <button
                key={mode}
                type="button"
                onClick={() => setLite(mode === 'Lite')}
                className="flex-1 rounded-2xl px-4 py-2.5 text-sm font-bold transition-all"
                style={
                  active
                    ? { background: accent.gradient, color: '#fff', boxShadow: `0 8px 20px -8px ${accent.glowStrong}` }
                    : { background: 'rgba(255,255,255,0.6)', color: '#55555f', border: '1px solid rgba(26,26,34,0.08)' }
                }
              >
                {mode}
                {mode === 'Lite' && <span className="ml-1 text-[10px] font-semibold opacity-80">0-1 RIR</span>}
              </button>
            )
          })}
        </div>
      )}

      {/* Warmup + exercises */}
      {plan.exercises.length > 0 && (
        <div className="mt-4 space-y-2">
          {plan.warmup && <div className="rounded-2xl px-3.5 py-2.5 text-[13px] font-semibold" style={{ background: accent.wash, color: accent.deep }}>
            {t('Warm-up')}: {t(plan.warmup)}
          </div>}
          {plan.exercises.map((e) => {
            const rec = e.increment_kg > 0 ? recommendLoad(data, e) : null
            const reps =
              e.rep_unit === 'check'
                ? t('Check')
                : e.rep_unit === 'max'
                ? 'max'
                : e.rep_unit === 'seconds'
                  ? `${e.rep_min}-${e.rep_max}s`
                  : e.rep_unit === 'minutes'
                    ? `${e.rep_min}-${e.rep_max} min`
                    : e.rep_min === e.rep_max
                      ? `${e.rep_min}`
                      : `${e.rep_min}-${e.rep_max}`
            return (
              <div key={e.id} className="glass rounded-2xl p-3.5">
                <div className="flex items-baseline justify-between gap-2">
                  <p className="text-[14px] leading-snug font-bold text-ink">
                    {e.name}
                    {e.optional && <span className="ml-1.5 text-[10px] font-semibold text-ink-faint">OPTIONAL</span>}
                    {e.swapped && <span className="ml-1.5 text-[10px] font-semibold" style={{ color: ACCENTS.amber.deep }}>SWAP</span>}
                  </p>
                  <p className="shrink-0 font-mono text-sm font-bold" style={{ color: accent.deep }}>
                    {e.rep_unit === 'check' ? reps : `${e.planned_sets}x${reps}`}
                    {e.per_side ? '/side' : ''}
                  </p>
                </div>
                <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 text-[11px] font-semibold text-ink-soft">
                  {e.rest_sec > 0 && <span>rest {e.rest_sec}s</span>}
                  {e.tempo_note && <span>{e.tempo_note}</span>}
                  {e.notes && <span className="text-ink-faint">{e.notes}</span>}
                </div>
                {rec?.weight != null && (
                  <div className="mt-1.5 inline-block rounded-full px-2.5 py-0.5 font-mono text-[11px] font-bold" style={{ background: accent.wash, color: accent.deep }}>
                    Recommended: {rec.weight} kg
                    {rec.previous && rec.weight > rec.previous.weight ? ` (was ${rec.previous.weight} kg)` : ''}
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}

      {/* Completed summary */}
      {done && (
        <div className="mt-4 rounded-2xl p-4" style={{ background: accent.wash }}>
          <div className="flex items-center justify-between">
            <p className="font-display text-sm font-bold text-ink">Completed</p>
            <AccentChip accent={accent} solid>
              QUALITY {(done.quality_score * 100).toFixed(0)}%
            </AccentChip>
          </div>
          <div className="mt-2 space-y-0.5 font-mono text-[12px] font-semibold text-ink-soft">
            {logsForDone.slice(0, 14).map((l) => (
              <p key={l.id}>
                {l.exercise_name} · set {l.set_no}:{' '}
                {l.skipped
                  ? 'skipped'
                  : `${l.weight_kg != null ? `${l.weight_kg} kg × ` : ''}${l.reps ?? '?'} reps${l.rir != null ? `, RIR ${l.rir}` : ''}`}
              </p>
            ))}
            {logsForDone.length > 14 && <p>… {logsForDone.length - 14} more sets</p>}
          </div>
          <button type="button" onClick={() => setStatsOpen(true)} className="mt-3 w-full rounded-2xl bg-white/75 px-4 py-3 text-sm font-black shadow-sm" style={{ color: accent.deep }}>{t('Workout stats at a glance')}</button>
        </div>
      )}

      {/* Water + deload + start */}
      <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-ink/8 pt-4">
        <div>
          <p className="flex items-center gap-1 text-xs font-bold" style={{ color: ACCENTS.ice.deep }}>
            <DropletIcon className="h-3.5 w-3.5" />
            Water · one record with Nutrition
          </p>
          <div className="mt-1">
            <Stepper accent={ACCENTS.ice} value={water} step={0.25} unit="L" onChange={setWater} />
          </div>
        </div>
        <button
          type="button"
          onClick={toggleDeload}
          className="rounded-2xl px-4 py-2.5 text-sm font-bold transition-all"
          style={
            deloadMark
              ? { background: 'linear-gradient(135deg,#38bdf8,#7dd3fc)', color: '#fff' }
              : { background: 'rgba(255,255,255,0.6)', color: '#0369a1', border: '1px solid rgba(56,189,248,0.35)' }
          }
        >
          {deloadMark ? 'Deload day ✓' : 'Mark deload'}
        </button>
      </div>

      {!done && plan.exercises.length > 0 && isPastOrToday && (() => {
        /* Both ways of training the same session, shown as what they are.
         * Neither is a fallback hidden under the other, and neither is picked
         * for the user by anything they answered in a questionnaire. The one
         * they chose last time is marked so the choice is predictable rather
         * than merely available. */
        const query = new URLSearchParams()
        if (lite) query.set('lite', '1')
        if (plan.programDay?.id) query.set('day', plan.programDay.id)
        const suffix = query.size > 0 ? `?${query.toString()}` : ''
        const preferred = preferredSessionMode(plan.programDay?.session_mode)
        const go = (mode: SessionMode): void => {
          rememberSessionMode(mode)
          onClose()
          navigate(mode === 'tracked'
            ? `/log/${slug}/${dateIso}${suffix}`
            : `/player/${slug}/${dateIso}${suffix}`)
        }
        const options: Array<[SessionMode, string, string]> = [
          ['guided', plan.isRecoveryMicro ? 'Follow recovery' : 'Follow along',
            'Paced, counts your reps'],
          ['tracked', 'Track it', 'A list you fill in'],
        ]
        return (
          <div className="mt-4 grid grid-cols-2 gap-2">
            {options.map(([mode, label, hint]) => {
              const active = preferred === mode
              return (
                <button
                  key={mode}
                  type="button"
                  onClick={() => go(mode)}
                  className={`rounded-2xl border px-3 py-3.5 text-left transition active:scale-[.98] ${
                    active
                      ? 'border-white/40 bg-white/80 shadow-[0_12px_26px_-16px_rgba(0,0,0,.55)]'
                      : 'border-white/15 bg-white/35'
                  }`}
                >
                  <span className="block text-sm font-black tracking-wide text-ink">{label}</span>
                  <span className="mt-0.5 block text-[10px] font-semibold text-ink-soft">{hint}</span>
                  {active && (
                    <span className="mt-1.5 block text-[9px] font-black uppercase tracking-[0.14em] text-ink-soft/70">
                      Last used
                    </span>
                  )}
                </button>
              )
            })}
          </div>
        )
      })()}
    </Sheet>
    <WorkoutStatsSheet open={statsOpen} onClose={() => setStatsOpen(false)} sessionId={done?.id ?? null} accent={accent} />
    </>
  )
}
