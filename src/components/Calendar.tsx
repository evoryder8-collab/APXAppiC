/*
 * Monthly glass calendar. Completed days fill with the section accent,
 * deload days get the ice gradient with an animated shimmer, event
 * approaches ramp amber-to-crimson, event days burn solid.
 */
import { useMemo, useRef } from 'react'
import {
  addDays,
  format,
  getISODay,
  isSameMonth,
  isToday,
  startOfMonth,
} from 'date-fns'
import type { Accent } from '../lib/theme'
import type { AppData, ProgramSlug } from '../lib/types'
import { approachRamp, eventContextFor } from '../lib/plan'

interface CalendarProps {
  month: Date
  data: AppData
  slug: ProgramSlug
  accent: Accent
  onSelectDay: (dateIso: string) => void
  onLongPressDay: (dateIso: string) => void
}

const WEEKDAYS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']

export function Calendar({ month, data, slug, accent, onSelectDay, onLongPressDay }: CalendarProps) {
  const program = data.programs.find((p) => p.slug === slug)

  const cells = useMemo(() => {
    const first = startOfMonth(month)
    const lead = getISODay(first) - 1
    const start = addDays(first, -lead)
    return [...Array(42)].map((_, i) => addDays(start, i))
  }, [month])

  const completedByDate = useMemo(() => {
    const dayIds = new Set(data.program_days.filter((d) => d.program_id === program?.id).map((d) => d.id))
    const map = new Map<string, { recovery: boolean }>()
    for (const s of data.workout_sessions) {
      if (!s.completed) continue
      if (!dayIds.has(s.program_day_id) && !s.is_event_recovery) continue
      map.set(s.date, { recovery: s.is_event_recovery })
    }
    return map
  }, [data.workout_sessions, data.program_days, program])

  const deloadDates = useMemo(() => new Set(data.deload_marks.map((m) => m.date)), [data.deload_marks])
  const waterDates = useMemo(
    () => new Set(data.daily_logs.filter((d) => d.water_l >= 2.5).map((d) => d.date)),
    [data.daily_logs],
  )

  const pressTimer = useRef<number | null>(null)
  const longFired = useRef(false)

  const startPress = (dateIso: string): void => {
    longFired.current = false
    pressTimer.current = window.setTimeout(() => {
      longFired.current = true
      onLongPressDay(dateIso)
    }, 550)
  }
  const cancelPress = (): void => {
    if (pressTimer.current) window.clearTimeout(pressTimer.current)
  }
  /* selection rides the click event so taps, mice and synthetic clicks all work;
     a completed long-press swallows the click that follows it */
  const clickDay = (dateIso: string, inMonth: boolean): void => {
    if (longFired.current) {
      longFired.current = false
      return
    }
    if (inMonth) onSelectDay(dateIso)
  }

  return (
    <div>
      <div className="mb-2 grid grid-cols-7 gap-1.5 px-1">
        {WEEKDAYS.map((w) => (
          <div key={w} className="text-center font-mono text-[10px] font-bold tracking-wider text-ink-faint">
            {w}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1.5">
        {cells.map((d) => {
          const dateIso = format(d, 'yyyy-MM-dd')
          const inMonth = isSameMonth(d, month)
          const completed = completedByDate.get(dateIso)
          const deload = deloadDates.has(dateIso)
          const ramp = approachRamp(dateIso, data.events)
          const during = eventContextFor(dateIso, data.events)?.isDuring ?? false
          const today = isToday(d)

          let style: React.CSSProperties = {
            background: 'rgba(255,255,255,0.55)',
            border: '1px solid rgba(26,26,34,0.07)',
            color: inMonth ? '#1a1a22' : 'rgba(26,26,34,0.28)',
          }
          let cls = ''
          if (deload && inMonth) {
            style = {
              background: 'linear-gradient(135deg, #7dd3fc 0%, #e0f2fe 100%)',
              border: '1px solid rgba(56,189,248,0.4)',
              color: '#075985',
            }
            cls = 'ice-shimmer'
          }
          if (ramp != null && !during && inMonth) {
            style = {
              background: `linear-gradient(135deg, rgba(245,158,11,${0.2 + ramp * 0.55}) 0%, rgba(220,38,38,${0.12 + ramp * 0.5}) 100%)`,
              border: '1px solid rgba(220,38,38,0.25)',
              color: ramp > 0.6 ? '#7f1d1d' : '#92400e',
            }
          }
          if (during && inMonth) {
            style = {
              background: 'linear-gradient(135deg, #f59e0b 0%, #dc2626 100%)',
              border: '1px solid transparent',
              color: '#fff',
            }
          }
          if (completed && inMonth && !completed.recovery) {
            style = {
              background: accent.gradient,
              border: '1px solid transparent',
              color: '#fff',
              boxShadow: `0 6px 16px -6px ${accent.glowStrong}`,
            }
          }
          if (completed?.recovery && inMonth) {
            style = { ...style, boxShadow: '0 0 0 2px rgba(255,255,255,0.9) inset' }
          }

          return (
            <button
              key={dateIso}
              type="button"
              aria-label={format(d, 'd MMMM yyyy')}
              onPointerDown={() => inMonth && startPress(dateIso)}
              onPointerUp={cancelPress}
              onPointerLeave={cancelPress}
              onClick={() => clickDay(dateIso, inMonth)}
              onContextMenu={(e) => {
                e.preventDefault()
                if (inMonth) onLongPressDay(dateIso)
              }}
              className={`relative aspect-square touch-manipulation overflow-hidden rounded-xl backdrop-blur-sm transition-transform select-none active:scale-95 ${cls} ${today ? 'breathe' : ''}`}
              style={{
                ...style,
                ...(today
                  ? ({ '--glow-soft': accent.glowSoft, '--glow-strong': accent.glowStrong } as React.CSSProperties)
                  : {}),
              }}
            >
              <span className="absolute top-1.5 left-2 font-mono text-[12px] font-bold">{format(d, 'd')}</span>
              <span className="absolute right-1.5 bottom-1.5 flex gap-0.5">
                {completed && <span className="h-1.5 w-1.5 rounded-full bg-white/90 shadow" />}
                {waterDates.has(dateIso) && (
                  <span className="h-1.5 w-1.5 rounded-full" style={{ background: completed && !deload ? 'rgba(255,255,255,0.7)' : '#38bdf8' }} />
                )}
              </span>
              {today && (
                <span
                  className="absolute inset-0 rounded-xl"
                  style={{ boxShadow: `inset 0 0 0 2px ${completed ? 'rgba(255,255,255,0.85)' : accent.bright}` }}
                  aria-hidden
                />
              )}
            </button>
          )
        })}
      </div>
    </div>
  )
}
