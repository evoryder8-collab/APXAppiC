import { useMemo, useState } from 'react'
import { loadedStrengthVolume } from '../../lib/exerciseLogging'
import { completedWorkoutHistoryForDate } from '../../lib/completedWorkoutHistory'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { manualWorkoutTitle } from '../../lib/manualWorkout'
import type { Accent } from '../../lib/theme'
import { ACCENTS } from '../../lib/theme'
import { workoutLogsInPerformedOrder } from '../../lib/workoutLogOrder'
import { useStore } from '../../store/AppStore'
import { ManualWorkoutLogger } from './ManualWorkoutLogger'
import { WorkoutStatsSheet } from './WorkoutStatsSheet'

export function CompletedWorkoutHistoryCards({
  date,
  accent = ACCENTS.teal,
  includeQuickLogs = true,
}: {
  date: string
  accent?: Accent
  includeQuickLogs?: boolean
}) {
  const { data } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [receiptSessionId, setReceiptSessionId] = useState<string | null>(null)
  const [manualEditSessionId, setManualEditSessionId] = useState<string | null>(null)
  const history = useMemo(
    () => completedWorkoutHistoryForDate(data, date).filter((item) => includeQuickLogs || !item.isQuickLog),
    [data, date, includeQuickLogs],
  )

  if (history.length === 0) return null

  const toggle = (sessionId: string): void => {
    setExpanded((current) => {
      const next = new Set(current)
      if (next.has(sessionId)) next.delete(sessionId)
      else next.add(sessionId)
      return next
    })
  }

  return (
    <section className="space-y-2" data-completed-workout-history>
      <div className="flex items-center justify-between px-1">
        <p className="font-mono text-[9px] font-black tracking-[.16em] text-emerald-800 uppercase">{t('Finished workouts')}</p>
        <p className="font-mono text-[8px] font-bold text-ink-faint">{history.length} {t(history.length === 1 ? 'session' : 'sessions')}</p>
      </div>
      {history.map(({ session, title, isQuickLog }) => {
        const open = expanded.has(session.id)
        const logs = workoutLogsInPerformedOrder(data, session.id)
        const working = logs.filter((log) => !log.skipped)
        const movements = new Set(logs.map((log) => log.exercise_name)).size
        const volume = loadedStrengthVolume(working)
        const time = session.completed_at?.slice(11, 16) ?? null
        return (
          <article key={session.id} className="relative overflow-hidden rounded-[26px] border border-emerald-100/90 bg-gradient-to-br from-emerald-50/95 via-white/92 to-cyan-50/85 shadow-[0_20px_52px_-38px_rgba(5,150,105,.8)]">
            <button
              type="button"
              onClick={() => toggle(session.id)}
              aria-expanded={open}
              className="flex w-full items-start gap-3 px-4 pt-4 pb-3 text-left"
            >
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-2xl bg-emerald-600 text-white shadow-sm">✓</span>
              <span className="min-w-0 flex-1">
                <span className="block font-mono text-[8px] font-black tracking-[.14em] text-emerald-800 uppercase">{t(isQuickLog ? 'Quick Log complete' : 'Tracked workout complete')}</span>
                <span className="mt-1 block break-words font-display text-base font-black leading-tight text-ink">{t(title)}</span>
                <span className="mt-1 block font-mono text-[9px] font-bold text-ink-faint">{[time, `${working.length} ${t('working sets')}`, `${movements} ${t(movements === 1 ? 'movement' : 'movements')}`].filter(Boolean).join(' · ')}</span>
              </span>
              <span aria-hidden className={`mt-1 text-lg font-black text-emerald-800 transition ${open ? 'rotate-180' : ''}`}>⌄</span>
            </button>

            {open ? (
              <div className="border-t border-white/85 px-4 pt-3 pb-4">
                <div className="grid grid-cols-3 gap-2">
                  <HistoryMetric label={t('Loaded volume')} value={`${Math.round(volume).toLocaleString()} kg`} />
                  <HistoryMetric label={t('Working sets')} value={String(working.length)} />
                  <HistoryMetric label={t('Movements')} value={String(movements)} />
                </div>
                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  <button type="button" onClick={() => setReceiptSessionId(session.id)} className="rounded-2xl bg-emerald-600 px-4 py-3 text-xs font-black text-white shadow-sm">{t('View & edit receipt')}</button>
                  {manualWorkoutTitle(session.notes) != null && (
                    <button type="button" onClick={() => setManualEditSessionId(session.id)} className="rounded-2xl border border-cyan-100 bg-white/85 px-4 py-3 text-xs font-black text-cyan-800">{t('Edit workout structure')}</button>
                  )}
                </div>
              </div>
            ) : (
              <div aria-hidden className="pointer-events-none absolute inset-x-0 bottom-0 h-5 bg-gradient-to-t from-cyan-100/70 to-transparent" />
            )}
          </article>
        )
      })}

      <WorkoutStatsSheet open={Boolean(receiptSessionId)} onClose={() => setReceiptSessionId(null)} sessionId={receiptSessionId} accent={accent} />
      <ManualWorkoutLogger
        open={Boolean(manualEditSessionId)}
        onClose={() => setManualEditSessionId(null)}
        date={date}
        editSessionId={manualEditSessionId}
        accent={accent}
      />
    </section>
  )
}

function HistoryMetric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-2xl border border-white/90 bg-white/72 px-2 py-3 text-center"><p className="text-[8px] font-bold leading-tight text-ink-faint">{label}</p><p className="mt-1 font-mono text-sm font-black text-ink">{value}</p></div>
}
