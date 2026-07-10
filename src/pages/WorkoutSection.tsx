import { useMemo, useState } from 'react'
import { addMonths, format, subDays } from 'date-fns'
import { motion } from 'framer-motion'
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

const EVENT_TYPES: Array<{ value: EventType; label: string }> = [
  { value: 'filming_championship', label: 'Filming Championship' },
  { value: 'travel', label: 'Travel' },
  { value: 'other', label: 'Other' },
]

export function WorkoutSection({ slug, accent, title }: { slug: ProgramSlug; accent: Accent; title: string }) {
  const { data, upsert, remove, toast } = useStore()
  const [month, setMonth] = useState(() => new Date())
  const [selectedDay, setSelectedDay] = useState<string | null>(null)
  const [showEventForm, setShowEventForm] = useState(false)
  const [showExport, setShowExport] = useState(false)

  const today = todayIso()
  const streak = useMemo(() => currentStreak(data, today), [data, today])
  const todayPlan = useMemo(() => planForDate(data, slug, today, false), [data, slug, today])

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
        title={title}
        subtitle={slug === 'transition' ? 'Current program, home only' : 'Elite V6, full version'}
        right={
          <div className="flex items-center gap-2">
            <AccentChip accent={accent} solid className="!text-[12px]">
              🔥 {streak} DAY{streak === 1 ? '' : 'S'}
            </AccentChip>
          </div>
        }
      />

      <div className="space-y-5">
        {/* Today hero */}
        <motion.div initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.45, ease: EASE }}>
          <GlassCard accent={accent} breathe className="p-5">
            <div className="flex items-center justify-between gap-3">
              <div className="min-w-0">
                <p className="font-mono text-[11px] font-bold tracking-widest text-ink-faint uppercase">Today</p>
                <h2 className="truncate font-display text-xl font-bold text-ink">
                  {todayPlan.isRecoveryMicro ? 'Recovery micro-session' : (todayPlan.programDay?.name ?? 'Rest day')}
                </h2>
                {todayPlan.programDay && (
                  <p className="text-xs font-semibold text-ink-soft">
                    ~{todayPlan.programDay.est_minutes} min · {todayPlan.exercises.length} exercises
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
                    {b.toUpperCase()}
                  </AccentChip>
                ))}
              </div>
            )}
          </GlassCard>
        </motion.div>

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
            onSelectDay={setSelectedDay}
            onLongPressDay={toggleDeload}
          />
          <p className="mt-3 text-center text-[11px] font-medium text-ink-faint">
            Tap a day to plan it. Hold to mark deload.
          </p>
        </GlassCard>

        {/* Events */}
        <GlassCard accent={ACCENTS.amber} className="p-5">
          <div className="flex items-center justify-between">
            <h2 className="font-display text-lg font-bold text-ink">Events & travel</h2>
            <GhostButton onClick={() => setShowEventForm(true)}>+ Add</GhostButton>
          </div>
          {data.events.length === 0 ? (
            <p className="mt-2 text-sm font-medium text-ink-soft">
              Championships and travel go here. The 5 days before ramp amber to crimson and the
              taper engine handles your back.
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
