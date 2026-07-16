import { lazy, Suspense, useMemo, useState } from 'react'
import { addMonths, format, subDays } from 'date-fns'
import { motion } from 'framer-motion'
import { useNavigate } from 'react-router-dom'
import type { Accent } from '../lib/theme'
import { ACCENTS } from '../lib/theme'
import type { EventType, ProgramSlug } from '../lib/types'
import { useStore } from '../store/AppStore'
import { planForDate, todayIso } from '../lib/plan'
import { currentStreak } from '../lib/streak'
import { buildReport, copyReport, downloadReport } from '../lib/exportReport'
import {
  AccentChip,
  EASE,
  GhostButton,
  GlassCard,
  GradientButton,
  SectionHeader,
  Sheet,
} from '../components/ui'
import { Calendar } from '../components/Calendar'
import { DaySheet } from '../components/DaySheet'
import { ChevronLeftIcon, ChevronRightIcon } from '../components/Icons'
import { useOrbitStore } from '../orbit/store/OrbitStore'
import { missionLabel } from '../orbit/domain/analysis'
import { useOrbitText } from '../orbit/ui/i18n'
import { isTrainingInductionEligible } from '../lib/trainingInduction'
import { TrainingInductionPanel } from '../components/workout/TrainingInductionPanel'
import { useLanguage } from '../lib/i18n'
import { UI_TRANSLATIONS } from '../lib/translations'
import { ManualWorkoutLogger, TodayManualWorkoutCard } from '../components/workout/ManualWorkoutLogger'

const CustomWorkoutBuilder = lazy(() =>
  import('../components/CustomWorkoutBuilder').then((module) => ({ default: module.CustomWorkoutBuilder })),
)

const EVENT_TYPES: Array<{ value: EventType; label: string }> = [
  { value: 'filming_championship', label: 'Filming Championship' },
  { value: 'travel', label: 'Travel' },
  { value: 'other', label: 'Other' },
]

export function WorkoutSection({ slug, accent, title }: { slug: ProgramSlug; accent: Accent; title: string }) {
  const { data, upsert, remove, toast } = useStore()
  const orbit = useOrbitStore()
  const navigate = useNavigate()
  const t = useOrbitText()
  const { language } = useLanguage()
  const [month, setMonth] = useState(() => new Date())
  const [selectedDay, setSelectedDay] = useState<string | null>(null)
  const [showEventForm, setShowEventForm] = useState(false)
  const [showExport, setShowExport] = useState(false)
  const [showWorkoutBuilder, setShowWorkoutBuilder] = useState(false)
  const [showManualWorkout, setShowManualWorkout] = useState(false)
  const [editingManualSessionId, setEditingManualSessionId] = useState<string | null>(null)
  const [editingManualExerciseId, setEditingManualExerciseId] = useState<string | null>(null)

  const today = todayIso()
  const program = data.programs.find((candidate) => candidate.slug === slug)
  const streak = useMemo(() => currentStreak(data, today), [data, today])
  const todayPlan = useMemo(() => planForDate(data, slug, today, false), [data, slug, today])
  const visibleOrbitSessions = useMemo(() => orbit.state.sessions.filter((session) => session.date.startsWith(format(month, 'yyyy-MM'))), [month, orbit.state.sessions])
  const showTrainingInduction = Boolean(
    data.profile &&
    isTrainingInductionEligible(data.profile.persona) &&
    data.settings?.addons.newbie_mode &&
    (slug === 'transition' || slug === 'main'),
  )
  const planText = (value: string): string => {
    if (language === 'en') return value
    const exact = UI_TRANSLATIONS[value]?.[language]
    if (exact) return exact
    const foundation = value.match(/^Foundation week (\d+) of 12: (restore movement quality|build repeatable volume|progress controlled load)$/i)
    if (foundation) {
      const phase = foundation[2].toLocaleLowerCase('en')
      if (language === 'ro') {
        const detail = phase === 'restore movement quality'
          ? 'refacerea calității mișcării'
          : phase === 'build repeatable volume'
            ? 'construirea unui volum repetabil'
            : 'progresie controlată a greutății'
        return `Săptămâna ${foundation[1]} din 12: ${detail}`
      }
      const detail = phase === 'restore movement quality'
        ? 'ฟื้นคุณภาพการเคลื่อนไหว'
        : phase === 'build repeatable volume'
          ? 'สร้างปริมาณที่ทำซ้ำได้'
          : 'เพิ่มน้ำหนักอย่างควบคุม'
      return `สัปดาห์ ${foundation[1]} จาก 12: ${detail}`
    }
    return t(value)
  }

  /* Deload marking via long-press */
  const toggleDeload = (dateIso: string): void => {
    const mark = data.deload_marks.find((m) => m.date === dateIso)
    if (mark) remove('deload_marks', mark.id)
    else upsert('deload_marks', { id: crypto.randomUUID(), user_id: data.profile?.user_id ?? '', date: dateIso })
    toast(mark ? 'Deload removed' : 'Deload marked', 'ok')
  }

  /* Event form state */
  const [evName, setEvName] = useState('')
  const [evType, setEvType] = useState<EventType>('filming_championship')
  const [evStart, setEvStart] = useState(today)
  const [evEnd, setEvEnd] = useState(today)

  const saveEvent = (): void => {
    if (!evName.trim() || evEnd < evStart) {
      toast('Give the event a name and a valid range')
      return
    }
    upsert('events', {
      id: crypto.randomUUID(),
      user_id: data.profile?.user_id ?? '',
      name: evName.trim(),
      type: evType,
      start_date: evStart,
      end_date: evEnd,
      notes: '',
    })
    setShowEventForm(false)
    setEvName('')
    toast('Event added. Taper engages 5 days out', 'ok')
  }

  /* Export state */
  const [exFrom, setExFrom] = useState(format(subDays(new Date(), 30), 'yyyy-MM-dd'))
  const [exTo, setExTo] = useState(today)

  const input =
    'glass w-full rounded-xl px-3 py-2.5 text-sm font-semibold text-ink outline-none placeholder:text-ink-faint'

  return (
    <div className="mx-auto w-full max-w-3xl">
      <SectionHeader
        accent={accent}
        title={planText(program?.name ?? title)}
        subtitle={planText(program?.description ?? (slug === 'transition' ? 'Current program, home only' : 'Full training programme'))}
        right={
          <div className="flex items-center gap-2">
            <div className="relative overflow-hidden rounded-2xl border border-white/85 bg-white/72 px-3 py-2 text-right shadow-[0_12px_30px_-20px_rgba(109,40,217,.8)] backdrop-blur-xl">
              <div className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-violet-400/70 to-transparent" />
              <p className="font-mono text-[7px] font-black tracking-[0.18em] text-violet-700 uppercase">{t('Streak')}</p>
              <p className="mt-0.5 whitespace-nowrap font-mono text-[11px] font-black text-ink">🔥 {t(`${streak} ${streak === 1 ? 'day' : 'days'}`)}</p>
            </div>
          </div>
        }
      />

      <div className="space-y-5">
        {showTrainingInduction && <TrainingInductionPanel slug={slug} />}

        {/* Today hero */}
        <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.45, ease: EASE }}>
          <GlassCard accent={accent} breathe className="p-5">
            <div className="flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">Today</p>
                <h2 data-plan-day-id={todayPlan.programDay?.id ?? ''} className="truncate font-display text-xl font-bold text-ink">
                  {planText(todayPlan.isRecoveryMicro ? 'Recovery micro-session' : (todayPlan.programDay?.name ?? 'Rest day'))}
                </h2>
                {todayPlan.programDay && (
                  <p className="text-xs font-semibold text-ink-soft">
                    {t(`~${todayPlan.programDay.est_minutes} min · ${todayPlan.exercises.length} exercises`)}
                  </p>
                )}
              </div>
              {todayPlan.exercises.length > 0 && (
                <GradientButton accent={accent} onClick={() => setSelectedDay(today)} className="shrink-0">
                  Open
                </GradientButton>
              )}
            </div>
            {todayPlan.badges.length > 0 && (
              <div className="mt-2.5 flex flex-wrap gap-1.5">
                {todayPlan.badges.slice(0, 3).map((b) => (
                  <AccentChip key={b} accent={ACCENTS.amber}>
                    {planText(b).toUpperCase()}
                  </AccentChip>
                ))}
              </div>
            )}
          </GlassCard>
        </motion.div>

        <TodayManualWorkoutCard
          date={today}
          onAdd={() => {
            setEditingManualSessionId(null)
            setEditingManualExerciseId(null)
            setShowManualWorkout(true)
          }}
          onEdit={(sessionId, exerciseId) => {
            setEditingManualSessionId(sessionId)
            setEditingManualExerciseId(exerciseId)
            setShowManualWorkout(true)
          }}
          accent={accent}
        />

        {/* Calendar */}
        <GlassCard accent={accent} className="p-4 sm:p-5">
          <div className="mb-4 flex items-center justify-between">
            <button
              type="button"
              onClick={() => setMonth((m) => addMonths(m, -1))}
              className="glass flex h-9 w-9 items-center justify-center rounded-full text-ink-soft active:scale-95"
              aria-label="Previous month"
            >
              <ChevronLeftIcon className="h-4 w-4" />
            </button>
            <h2 className="font-display text-lg font-bold text-ink">{format(month, 'MMMM yyyy')}</h2>
            <button
              type="button"
              onClick={() => setMonth((m) => addMonths(m, 1))}
              className="glass flex h-9 w-9 items-center justify-center rounded-full text-ink-soft active:scale-95"
              aria-label="Next month"
            >
              <ChevronRightIcon className="h-4 w-4" />
            </button>
          </div>
          <Calendar
            month={month}
            data={data}
            slug={slug}
            accent={accent}
            orbitSessions={visibleOrbitSessions}
            onSelectDay={setSelectedDay}
            onLongPressDay={toggleDeload}
          />
          <p className="mt-3 text-center text-[11px] font-medium text-ink-faint">
            Tap a day to plan it. Hold to mark deload.
          </p>
          {visibleOrbitSessions.length > 0 && <div className="mt-4 space-y-2 border-t border-white/70 pt-4"><p className="font-mono text-[10px] font-bold tracking-widest text-sky-800">{t('APEX ORBIT · PRESCRIBED / COMPLETED')}</p>{visibleOrbitSessions.slice(0, 8).map((session) => <div key={session.id} className="flex items-center justify-between gap-3 rounded-2xl bg-sky-50/65 px-3 py-2.5"><div className="min-w-0"><p className="truncate text-xs font-bold text-ink">{session.date} · {t(session.adapted.title)}</p><p className="text-[10px] text-ink-soft">{t(missionLabel(session.adapted.mission))} · {session.adapted.duration_min} min · {t(session.status)}</p></div><button type="button" onClick={() => session.completion_run_id ? navigate(`/orbit/debrief/${session.completion_run_id}`) : navigate('/orbit/run', { state: { mission: session.adapted.mission, campaignSessionId: session.id } })} className="shrink-0 rounded-xl bg-sky-900 px-3 py-2 text-[10px] font-bold text-white">{t(session.completion_run_id ? 'Debrief' : 'Start run')}</button></div>)}</div>}
        </GlassCard>

        {/* Custom workout studio */}
        <div className="relative overflow-hidden rounded-[30px] border border-violet-200/35 bg-[#07111f] p-5 text-white shadow-[0_28px_70px_-38px_rgba(109,40,217,.95)] sm:p-6">
          <div className="orbit-stars pointer-events-none absolute inset-0 opacity-55" aria-hidden />
          <div className="pointer-events-none absolute -top-24 right-[-3rem] h-64 w-64 rounded-full bg-violet-500/25 blur-3xl" aria-hidden />
          <div className="pointer-events-none absolute -bottom-28 left-[-4rem] h-56 w-56 rounded-full bg-cyan-400/15 blur-3xl" aria-hidden />
          <div className="relative grid items-center gap-5 sm:grid-cols-[minmax(0,1fr)_auto]">
            <div>
              <p className="font-mono text-[9px] font-black tracking-[.2em] text-cyan-200 uppercase">{t('APEX WORKOUT STUDIO')}</p>
              <h2 className="mt-2 font-display text-2xl font-bold">{t('Create your own workout')}</h2>
              <p className="mt-2 max-w-lg text-sm leading-relaxed text-slate-300">{t('Search machines, free weights, calisthenics, street training, HIIT and mobility. Your muscle map updates as you build.')}</p>
            </div>
            <button type="button" onClick={() => setShowWorkoutBuilder(true)} className="min-h-14 rounded-2xl bg-gradient-to-r from-violet-600 via-fuchsia-500 to-cyan-400 px-6 text-sm font-black text-white shadow-[0_18px_42px_-18px_rgba(168,85,247,.9)] transition active:scale-[.98]">
              {t('Build a workout')} →
            </button>
          </div>
        </div>

        {/* Events */}
        <GlassCard accent={ACCENTS.amber} className="p-5">
          <div className="flex items-center justify-between">
            <h2 className="font-display text-lg font-bold text-ink">Events & travel</h2>
            <GhostButton onClick={() => setShowEventForm(true)}>+ Add</GhostButton>
          </div>
          {data.events.length === 0 ? (
            <p className="mt-2 text-sm font-medium text-ink-soft">
              Important events and travel go here. The five days before an event ramp amber to
              crimson so APEX can protect your taper and recovery.
            </p>
          ) : (
            <div className="mt-3 space-y-2">
              {[...data.events]
                .sort((a, b) => a.start_date.localeCompare(b.start_date))
                .map((ev) => (
                  <div key={ev.id} className="flex items-center justify-between gap-2 rounded-2xl px-3.5 py-2.5" style={{ background: 'rgba(255,255,255,0.55)' }}>
                    <div className="min-w-0">
                      <p className="truncate text-sm font-bold text-ink">{ev.name}</p>
                      <p className="font-mono text-[11px] font-semibold text-ink-soft">
                        {ev.start_date} → {ev.end_date} · {EVENT_TYPES.find((t) => t.value === ev.type)?.label}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => remove('events', ev.id)}
                      className="shrink-0 rounded-full px-2.5 py-1 text-xs font-bold text-crimson/80 hover:bg-crimson/10"
                    >
                      Remove
                    </button>
                  </div>
                ))}
            </div>
          )}
        </GlassCard>

        {/* Export */}
        <div className="flex justify-end">
          <GhostButton onClick={() => setShowExport(true)}>Export for AI assessment</GhostButton>
        </div>
      </div>

      {/* Day sheet */}
      {selectedDay && (
        <DaySheet
          open={!!selectedDay}
          onClose={() => setSelectedDay(null)}
          dateIso={selectedDay}
          slug={slug}
          accent={accent}
        />
      )}

      <Suspense fallback={null}>
        <CustomWorkoutBuilder
          open={showWorkoutBuilder}
          onClose={() => setShowWorkoutBuilder(false)}
          onSaved={() => {
            if (slug !== 'custom') navigate('/custom-workouts')
          }}
          accent={ACCENTS.violet}
        />
      </Suspense>

      <ManualWorkoutLogger
        open={showManualWorkout}
        onClose={() => {
          setShowManualWorkout(false)
          setEditingManualSessionId(null)
          setEditingManualExerciseId(null)
        }}
        date={today}
        editSessionId={editingManualSessionId}
        focusExerciseId={editingManualExerciseId}
        accent={accent}
      />

      {/* Event form */}
      <Sheet open={showEventForm} onClose={() => setShowEventForm(false)}>
        <h2 className="font-display text-xl font-bold text-ink">New event</h2>
        <div className="mt-4 space-y-3">
          <input className={input} placeholder="CISMM Monterrey" value={evName} onChange={(e) => setEvName(e.target.value)} />
          <div className="flex flex-wrap gap-2">
            {EVENT_TYPES.map((t) => (
              <button
                key={t.value}
                type="button"
                onClick={() => setEvType(t.value)}
                className="rounded-full px-3 py-1.5 text-xs font-bold transition-all"
                style={
                  evType === t.value
                    ? { background: ACCENTS.amber.gradient, color: '#fff' }
                    : { background: 'rgba(255,255,255,0.6)', color: '#55555f', border: '1px solid rgba(26,26,34,0.08)' }
                }
              >
                {t.label}
              </button>
            ))}
          </div>
          <div className="flex gap-3">
            <label className="flex-1 text-xs font-bold text-ink-soft">
              From
              <input type="date" className={`${input} mt-1`} value={evStart} onChange={(e) => setEvStart(e.target.value)} />
            </label>
            <label className="flex-1 text-xs font-bold text-ink-soft">
              To
              <input type="date" className={`${input} mt-1`} value={evEnd} onChange={(e) => setEvEnd(e.target.value)} />
            </label>
          </div>
          <GradientButton accent={ACCENTS.amber} className="w-full" onClick={saveEvent}>
            Save event
          </GradientButton>
        </div>
      </Sheet>

      {/* Export sheet */}
      <Sheet open={showExport} onClose={() => setShowExport(false)}>
        <h2 className="font-display text-xl font-bold text-ink">Export for AI assessment</h2>
        <p className="mt-1 text-sm font-medium text-ink-soft">
          Clean Markdown: calendar, sessions, daily logs and your current stats. Paste it straight
          into an AI.
        </p>
        <div className="mt-4 flex gap-3">
          <label className="flex-1 text-xs font-bold text-ink-soft">
            From
            <input type="date" className={`${input} mt-1`} value={exFrom} onChange={(e) => setExFrom(e.target.value)} />
          </label>
          <label className="flex-1 text-xs font-bold text-ink-soft">
            To
            <input type="date" className={`${input} mt-1`} value={exTo} onChange={(e) => setExTo(e.target.value)} />
          </label>
        </div>
        <div className="mt-4 flex gap-2">
          <GradientButton
            accent={accent}
            className="flex-1"
            onClick={() => {
              downloadReport(buildReport(data, slug, exFrom, exTo), `apex-${slug}-${exFrom}-${exTo}.md`)
              toast('Report downloaded', 'ok')
            }}
          >
            Download .md
          </GradientButton>
          <GhostButton
            className="flex-1"
            onClick={() => {
              void copyReport(buildReport(data, slug, exFrom, exTo)).then((ok) =>
                toast(ok ? 'Copied to clipboard' : 'Clipboard blocked', ok ? 'ok' : 'error'),
              )
            }}
          >
            Copy
          </GhostButton>
        </div>
      </Sheet>
    </div>
  )
}
