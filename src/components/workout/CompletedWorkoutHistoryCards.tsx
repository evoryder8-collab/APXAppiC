import { useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import { loadedStrengthVolume, workoutLogFactSummary } from '../../lib/exerciseLogging'
import {
  collapsedWorkoutDeleteTrayVisible,
  completedWorkoutDeletionPlan,
  externalWorkoutReceiptPresentation,
  externalWorkoutHidePlan,
  finishedWorkoutHistoryForDate,
} from '../../lib/completedWorkoutHistory'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { timeZoneFromSettings } from '../../lib/mealTiming'
import type { Accent } from '../../lib/theme'
import { ACCENTS } from '../../lib/theme'
import { workoutLogsInPerformedOrder } from '../../lib/workoutLogOrder'
import { isAPEXWorkoutSourceBundle } from '../../lib/wearableWorkoutLinking'
import { useStore } from '../../store/AppStore'
import { WorkoutStatsSheet } from './WorkoutStatsSheet'

export function CompletedWorkoutHistoryCards({
  date,
  limit,
  accent = ACCENTS.teal,
  includeQuickLogs = true,
}: {
  date?: string
  limit?: number
  accent?: Accent
  includeQuickLogs?: boolean
}) {
  const { data, remove, toast, upsert } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const timeZone = timeZoneFromSettings(data.settings)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [receiptSessionId, setReceiptSessionId] = useState<string | null>(null)
  const [pendingDelete, setPendingDelete] = useState<{ id: string; title: string } | null>(null)
  const [pendingHide, setPendingHide] = useState<{ id: string; title: string } | null>(null)
  const [revealedSessionId, setRevealedSessionId] = useState<string | null>(null)
  const [liveSwipe, setLiveSwipe] = useState<{ id: string; offset: number } | null>(null)
  const pointerStart = useRef<{ id: string; x: number; y: number; base: number; offset: number } | null>(null)
  const swipeConsumedClick = useRef(false)
  const history = useMemo(
    () => finishedWorkoutHistoryForDate(data, date, limit).filter((item) => (
      item.kind === 'external' || includeQuickLogs || !item.isQuickLog
    )),
    [data, date, includeQuickLogs, limit],
  )

  if (history.length === 0) return null

  const toggle = (sessionId: string): void => {
    if (swipeConsumedClick.current) {
      swipeConsumedClick.current = false
      return
    }
    setRevealedSessionId(null)
    setExpanded((current) => {
      const next = new Set(current)
      if (next.has(sessionId)) next.delete(sessionId)
      else next.add(sessionId)
      return next
    })
  }

  const beginSwipe = (sessionId: string, open: boolean, event: ReactPointerEvent<HTMLDivElement>): void => {
    if (open || (event.pointerType === 'mouse' && event.button !== 0)) return
    const base = revealedSessionId === sessionId ? -88 : 0
    pointerStart.current = { id: sessionId, x: event.clientX, y: event.clientY, base, offset: base }
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  const moveSwipe = (event: ReactPointerEvent<HTMLDivElement>): void => {
    const start = pointerStart.current
    if (!start) return
    const dx = event.clientX - start.x
    const dy = event.clientY - start.y
    if (Math.abs(dy) > Math.abs(dx) && Math.abs(dy) > 8) return
    const offset = Math.max(-88, Math.min(0, start.base + dx))
    start.offset = offset
    if (Math.abs(offset - start.base) > 8) swipeConsumedClick.current = true
    setLiveSwipe({ id: start.id, offset })
  }

  const endSwipe = (): void => {
    const start = pointerStart.current
    if (!start) return
    setRevealedSessionId(start.offset < -30 ? start.id : null)
    pointerStart.current = null
    setLiveSwipe(null)
    window.setTimeout(() => { swipeConsumedClick.current = false }, 0)
  }

  const confirmDeletion = (): void => {
    if (!pendingDelete) return
    const plan = completedWorkoutDeletionPlan(data, pendingDelete.id)
    if (!plan) {
      toast(t('This workout could not be deleted.'), 'error')
      setPendingDelete(null)
      return
    }
    for (const activity of data.imported_activities) {
      if (
        activity.user_id === (data.profile?.user_id ?? data.settings?.user_id)
        && activity.apex_workout_session_id === plan.sessionId
        && !isAPEXWorkoutSourceBundle(activity.source_bundle_id)
      ) {
        upsert('imported_activities', { ...activity, apex_workout_session_id: null })
      }
    }
    for (const logId of plan.logIds) remove('workout_logs', logId)
    remove('workout_sessions', plan.sessionId)
    setExpanded((current) => {
      const next = new Set(current)
      next.delete(plan.sessionId)
      return next
    })
    setRevealedSessionId(null)
    setPendingDelete(null)
    toast(t('Workout deleted.'), 'ok')
  }

  const confirmHide = (): void => {
    if (!pendingHide) return
    const hidden = externalWorkoutHidePlan(data, pendingHide.id)
    if (!hidden) {
      toast(t('This workout could not be hidden.'), 'error')
      setPendingHide(null)
      return
    }
    upsert('imported_activities', hidden)
    setExpanded((current) => {
      const next = new Set(current)
      next.delete(hidden.id)
      return next
    })
    setRevealedSessionId(null)
    setPendingHide(null)
    toast(t('Workout hidden from APEX.'), 'ok')
  }

  return (
    <section className="space-y-2" data-completed-workout-history>
      <div className="flex items-center justify-between px-1">
        <p className="font-mono text-[9px] font-black tracking-[.16em] text-emerald-800 uppercase">{t('Finished workouts')}</p>
        <p className="font-mono text-[8px] font-bold text-ink-faint">{history.length} {t(history.length === 1 ? 'session' : 'sessions')}</p>
      </div>
      {history.map((entry) => {
        if (entry.kind === 'external') {
          const { activity } = entry
          const open = expanded.has(activity.id)
          const receipt = externalWorkoutReceiptPresentation(activity, language, timeZone, t)
          const swipeOffset = liveSwipe?.id === activity.id
            ? liveSwipe.offset
            : revealedSessionId === activity.id ? -88 : 0
          return (
            <article key={activity.id} className="relative overflow-hidden rounded-[26px] border border-sky-100/90 bg-gradient-to-br from-sky-50/95 via-white/92 to-cyan-50/85 shadow-[0_20px_52px_-38px_rgba(2,132,199,.75)]" data-external-healthkit-workout>
              {collapsedWorkoutDeleteTrayVisible(open, swipeOffset) && (
                <button
                  type="button"
                  onClick={() => setPendingHide({ id: activity.id, title: receipt.title })}
                  className="absolute inset-y-0 right-0 grid w-[88px] place-items-center bg-sky-700 font-mono text-[8px] font-black tracking-wide text-white uppercase"
                  aria-label={`${t('Hide from APEX')}: ${receipt.title}`}
                >
                  <span className="grid gap-1 px-1 text-center"><span className="text-xl">⊘</span>{t('Hide from APEX')}</span>
                </button>
              )}
              <div
                className="relative bg-gradient-to-br from-sky-50/95 via-white/92 to-cyan-50/85 transition-transform duration-200 ease-out"
                style={{ transform: `translateX(${open ? 0 : swipeOffset}px)` }}
                onPointerDown={(event) => beginSwipe(activity.id, open, event)}
                onPointerMove={moveSwipe}
                onPointerUp={endSwipe}
                onPointerCancel={endSwipe}
              >
              <button
                type="button"
                onClick={() => toggle(activity.id)}
                aria-expanded={open}
                className="flex w-full items-start gap-3 px-4 pt-4 pb-3 text-left"
              >
                <span className="grid h-10 w-10 shrink-0 place-items-center rounded-2xl bg-sky-600 text-lg text-white shadow-sm" aria-hidden>♥</span>
                <span className="min-w-0 flex-1">
                  <span className="block font-mono text-[8px] font-black tracking-[.14em] text-sky-800 uppercase">{t('APPLE HEALTH')}</span>
                  <span className="mt-1 block break-words font-display text-base font-black leading-tight text-ink">{receipt.title}</span>
                  <span className="mt-1 block break-words font-mono text-[9px] font-bold leading-relaxed text-ink-faint">{[receipt.moment, receipt.duration, activity.source].filter(Boolean).join(' · ')}</span>
                </span>
                <span aria-hidden className={`mt-1 text-lg font-black text-sky-800 transition ${open ? 'rotate-180' : ''}`}>⌄</span>
              </button>

              {open && (
                <div className="border-t border-white/85 px-4 pt-3 pb-4" data-external-workout-receipt>
                  {(receipt.energy || receipt.distance) && (
                    <div className="grid grid-cols-2 gap-2">
                      {receipt.energy && <HistoryMetric label={t('Active energy')} value={receipt.energy} />}
                      {receipt.distance && <HistoryMetric label={t('Distance')} value={receipt.distance} />}
                    </div>
                  )}
                  <div className="mt-3 rounded-2xl border border-white/90 bg-white/72 p-3">
                    <p className="font-mono text-[8px] font-black tracking-[.14em] text-sky-800 uppercase">{t('READ-ONLY RECEIPT')}</p>
                    <p className="mt-2 text-xs leading-relaxed text-ink-soft">{t('Imported from Apple Health. This receipt is read-only in APEX.')}</p>
                    <p className="mt-2 break-words font-mono text-[9px] font-bold leading-relaxed text-ink-faint">{t('Source')}: {activity.source}</p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setPendingHide({ id: activity.id, title: receipt.title })}
                    className="mt-3 w-full rounded-2xl border border-sky-200 bg-white px-4 py-3 text-xs font-black text-sky-800"
                  >{t('Hide from APEX')}</button>
                </div>
              )}
              </div>
            </article>
          )
        }

        const { session, title, isQuickLog, linkedWearable } = entry
        const open = expanded.has(session.id)
        const logs = workoutLogsInPerformedOrder(data, session.id)
        const working = logs.filter((log) => !log.skipped)
        const movements = new Set(logs.map((log) => log.exercise_name)).size
        const volume = loadedStrengthVolume(working)
        const time = session.completed_at?.slice(11, 16) ?? null
        const groups = groupReceiptLogs(logs)
        const linkedReceipt = linkedWearable
          ? externalWorkoutReceiptPresentation(linkedWearable, language, timeZone, t)
          : null
        const swipeOffset = liveSwipe?.id === session.id
          ? liveSwipe.offset
          : revealedSessionId === session.id ? -88 : 0
        return (
          <article key={session.id} className="relative overflow-hidden rounded-[26px] border border-emerald-100/90 bg-gradient-to-br from-emerald-50/95 via-white/92 to-cyan-50/85 shadow-[0_20px_52px_-38px_rgba(5,150,105,.8)]">
            {collapsedWorkoutDeleteTrayVisible(open, swipeOffset) && (
              <button
                type="button"
                onClick={() => setPendingDelete({ id: session.id, title })}
                className="absolute inset-y-0 right-0 grid w-[88px] place-items-center bg-rose-600 font-mono text-[9px] font-black tracking-wide text-white uppercase"
                aria-label={`${t('Delete workout')}: ${t(title)}`}
              >
                <span className="grid gap-1 text-center"><span className="text-xl">×</span>{t('Delete')}</span>
              </button>
            )}

            <div
              className="relative bg-gradient-to-br from-emerald-50/95 via-white/92 to-cyan-50/85 transition-transform duration-200 ease-out"
              style={{ transform: `translateX(${open ? 0 : swipeOffset}px)` }}
              onPointerDown={(event) => beginSwipe(session.id, open, event)}
              onPointerMove={moveSwipe}
              onPointerUp={endSwipe}
              onPointerCancel={endSwipe}
            >
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
                  <span className="mt-1 block font-mono text-[9px] font-bold text-ink-faint">{[session.date, time, `${working.length} ${t('working sets')}`, `${movements} ${t(movements === 1 ? 'movement' : 'movements')}`, linkedWearable ? t('Wearable linked') : null].filter(Boolean).join(' · ')}</span>
                </span>
                <span aria-hidden className={`mt-1 text-lg font-black text-emerald-800 transition ${open ? 'rotate-180' : ''}`}>⌄</span>
              </button>

              {open ? (
                <div className="border-t border-white/85 px-4 pt-3 pb-4">
                  <div className="flex justify-end">
                    <button
                      type="button"
                      onClick={() => setPendingDelete({ id: session.id, title })}
                      className="grid h-9 w-9 place-items-center rounded-xl border border-rose-200 bg-rose-50 text-xl font-black text-rose-600"
                      aria-label={`${t('Delete workout')}: ${t(title)}`}
                    >×</button>
                  </div>
                  <div className="mt-[-2.25rem] grid grid-cols-3 gap-2 pr-11">
                    <HistoryMetric label={t('Loaded volume')} value={`${Math.round(volume).toLocaleString()} kg`} />
                    <HistoryMetric label={t('Working sets')} value={String(working.length)} />
                    <HistoryMetric label={t('Movements')} value={String(movements)} />
                  </div>
                  {linkedWearable && linkedReceipt && (
                    <div className="mt-3 rounded-2xl border border-sky-200/80 bg-gradient-to-br from-sky-50 to-cyan-50 p-3" data-linked-wearable-evidence>
                      <p className="font-mono text-[8px] font-black tracking-[.14em] text-sky-800 uppercase">{t('Linked wearable effort')}</p>
                      <p className="mt-1 break-words font-display text-sm font-black text-ink">{linkedReceipt.title}</p>
                      <p className="mt-1 break-words font-mono text-[9px] font-bold leading-relaxed text-ink-faint">{[linkedReceipt.moment, linkedReceipt.duration, linkedWearable.source].filter(Boolean).join(' · ')}</p>
                      {(linkedReceipt.energy || linkedReceipt.distance) && (
                        <div className="mt-2 grid grid-cols-2 gap-2">
                          {linkedReceipt.energy && <HistoryMetric label={t('Active energy')} value={linkedReceipt.energy} />}
                          {linkedReceipt.distance && <HistoryMetric label={t('Distance')} value={linkedReceipt.distance} />}
                        </div>
                      )}
                      <p className="mt-2 text-[10px] leading-relaxed font-semibold text-sky-900/70">{t('Device metrics are read-only and are not added to HealthKit energy twice.')}</p>
                    </div>
                  )}
                  <div className="mt-3 space-y-2" data-completed-workout-receipt>
                    {groups.map((group) => (
                      <div key={group.name} className="rounded-2xl border border-white/90 bg-white/72 p-3">
                        <p className="font-display text-sm font-black text-ink">{t(group.name)}</p>
                        <div className="mt-2 divide-y divide-slate-100">
                          {group.logs.map((log) => (
                            <div key={log.id} className="flex items-start gap-3 py-2 first:pt-0 last:pb-0">
                              <span className="shrink-0 font-mono text-[9px] font-black text-ink-faint">S{log.set_no}</span>
                              <span className="font-mono text-[10px] font-bold leading-relaxed text-ink">{workoutLogFactSummary(log).join(' · ')}</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    ))}
                  </div>
                  <button type="button" onClick={() => setReceiptSessionId(session.id)} className="mt-3 w-full rounded-2xl bg-emerald-600 px-4 py-3 text-xs font-black text-white shadow-sm">{t('Edit receipt')}</button>
                </div>
              ) : (
                <div aria-hidden className="pointer-events-none absolute inset-x-0 bottom-0 h-5 bg-gradient-to-t from-cyan-100/70 to-transparent" />
              )}
            </div>
          </article>
        )
      })}

      <WorkoutStatsSheet open={Boolean(receiptSessionId)} onClose={() => setReceiptSessionId(null)} sessionId={receiptSessionId} accent={accent} />
      {pendingDelete && (
        <div className="fixed inset-0 z-[90] grid place-items-center bg-slate-950/38 px-5 backdrop-blur-sm" role="presentation" onPointerDown={(event) => { if (event.target === event.currentTarget) setPendingDelete(null) }}>
          <div role="alertdialog" aria-modal="true" aria-labelledby="delete-workout-title" className="w-full max-w-sm rounded-[28px] border border-white/90 bg-white p-5 shadow-2xl">
            <p className="font-mono text-[9px] font-black tracking-[.15em] text-rose-600 uppercase">{t('Delete finished workout')}</p>
            <h3 id="delete-workout-title" className="mt-2 font-display text-xl font-black text-ink">{t('Delete this finished workout?')}</h3>
            <p className="mt-2 text-sm leading-relaxed text-ink-soft">{t('Its receipt and recorded sets will be removed from your history and progression.')}</p>
            <p className="mt-3 rounded-2xl bg-slate-50 px-3 py-2 font-mono text-xs font-bold text-ink">{t(pendingDelete.title)}</p>
            <div className="mt-4 grid grid-cols-2 gap-2">
              <button type="button" onClick={() => setPendingDelete(null)} className="rounded-2xl border border-slate-200 bg-white px-4 py-3 text-xs font-black text-ink">{t('Cancel')}</button>
              <button type="button" onClick={confirmDeletion} className="rounded-2xl bg-rose-600 px-4 py-3 text-xs font-black text-white">{t('Delete workout')}</button>
            </div>
          </div>
        </div>
      )}
      {pendingHide && (
        <div className="fixed inset-0 z-[90] grid place-items-center bg-slate-950/38 px-5 backdrop-blur-sm" role="presentation" onPointerDown={(event) => { if (event.target === event.currentTarget) setPendingHide(null) }}>
          <div role="alertdialog" aria-modal="true" aria-labelledby="hide-external-workout-title" className="w-full max-w-sm rounded-[28px] border border-white/90 bg-white p-5 shadow-2xl">
            <p className="font-mono text-[9px] font-black tracking-[.15em] text-sky-700 uppercase">{t('APPLE HEALTH')}</p>
            <h3 id="hide-external-workout-title" className="mt-2 font-display text-xl font-black text-ink">{t('Hide this Apple Health workout from APEX?')}</h3>
            <p className="mt-2 text-sm leading-relaxed text-ink-soft">{t('The original workout stays in Apple Health.')}</p>
            <p className="mt-3 rounded-2xl bg-slate-50 px-3 py-2 font-mono text-xs font-bold text-ink">{t(pendingHide.title)}</p>
            <div className="mt-4 grid grid-cols-2 gap-2">
              <button type="button" onClick={() => setPendingHide(null)} className="rounded-2xl border border-slate-200 bg-white px-4 py-3 text-xs font-black text-ink">{t('Cancel')}</button>
              <button type="button" onClick={confirmHide} className="rounded-2xl bg-sky-700 px-4 py-3 text-xs font-black text-white">{t('Hide from APEX')}</button>
            </div>
          </div>
        </div>
      )}
    </section>
  )
}

function groupReceiptLogs<T extends { exercise_name: string }>(logs: T[]): Array<{ name: string; logs: T[] }> {
  const groups: Array<{ name: string; logs: T[] }> = []
  for (const log of logs) {
    const existing = groups.find((group) => group.name === log.exercise_name)
    if (existing) existing.logs.push(log)
    else groups.push({ name: log.exercise_name, logs: [log] })
  }
  return groups
}

function HistoryMetric({ label, value }: { label: string; value: string }) {
  return <div className="rounded-2xl border border-white/90 bg-white/72 px-2 py-3 text-center"><p className="text-[8px] font-bold leading-tight text-ink-faint">{label}</p><p className="mt-1 font-mono text-sm font-black text-ink">{value}</p></div>
}
