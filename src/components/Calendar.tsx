/*
 * Monthly glass calendar. Every planned day carries its session type as a
 * color-coded tile (no clueless white squares): completed days fill with the
 * type gradient, deloads get the ice shimmer, event approaches ramp amber to
 * crimson, event days burn solid.
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
import type { AppData, DayType, ProgramSlug } from '../lib/types'
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

/* Session-type visual identity: code + hue, shared with the legend */
export const DAY_TYPE_META: Record<DayType, { code: string; label: string; bright: string; deep: string; gradient: string }> = {
  legs_a: { code: 'LA', label: 'Legs A', bright: '#10b981', deep: '#047857', gradient: 'linear-gradient(135deg, #059669, #34d399)' },
  legs_b: { code: 'LB', label: 'Legs B', bright: '#10b981', deep: '#047857', gradient: 'linear-gradient(135deg, #059669, #34d399)' },
  push: { code: 'PU', label: 'Push', bright: '#f59e0b', deep: '#b45309', gradient: 'linear-gradient(135deg, #f59e0b, #fbbf24)' },
  pull: { code: 'PL', label: 'Pull', bright: '#8b5cf6', deep: '#6d28d9', gradient: 'linear-gradient(135deg, #7c3aed, #a78bfa)' },
  upper: { code: 'UP', label: 'Upper', bright: '#14b8a6', deep: '#0f766e', gradient: 'linear-gradient(135deg, #0d9488, #2dd4bf)' },
  mobility: { code: 'MO', label: 'Mobility', bright: '#38bdf8', deep: '#0369a1', gradient: 'linear-gradient(135deg, #0ea5e9, #7dd3fc)' },
  fix: { code: 'FX', label: 'Fix', bright: '#38bdf8', deep: '#0369a1', gradient: 'linear-gradient(135deg, #0ea5e9, #7dd3fc)' },
  t25: { code: 'T25', label: 'Cardio', bright: '#f43f5e', deep: '#be123c', gradient: 'linear-gradient(135deg, #e11d48, #fb7185)' },
}

function hexToRgba(hex: string, alpha: number): string {
  const n = parseInt(hex.slice(1), 16)
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`
}

export function Calendar({ month, data, slug, accent, onSelectDay, onLongPressDay }: CalendarProps) {
  const program = data.programs.find((p) => p.slug === slug)

  const cells = useMemo(() => {
    const first = startOfMonth(month)
    const lead = getISODay(first) - 1
    const start = addDays(first, -lead)
    return [...Array(42)].map((_, i) => addDays(start, i))
  }, [month])

  /* weekday (1-7) -> session type for this program */
  const typeByWeekday = useMemo(() => {
    const map = new Map<number, DayType>()
    for (const d of data.program_days) {
      if (d.program_id === program?.id) map.set(d.weekday, d.day_type)
    }
    return map
  }, [data.program_days, program])

  const completedByDate = useMemo(() => {
    const dayById = new Map(
      data.program_days.filter((d) => d.program_id === program?.id).map((d) => [d.id, d.day_type]),
    )
    const map = new Map<string, { recovery: boolean; type: DayType | null }>()
    for (const s of data.workout_sessions) {
      if (!s.completed) continue
      const type = dayById.get(s.program_day_id) ?? null
      if (type == null && !s.is_event_recovery) continue
      map.set(s.date, { recovery: s.is_event_recovery, type })
    }
    return map
  }, [data.workout_sessions, data.program_days, program])

  const deloadDates = useMemo(() => new Set(data.deload_marks.map((m) => m.date)), [data.deload_marks])
  const waterDates = useMemo(
    () => new Set(data.daily_logs.filter((d) => d.water_l >= 2.5).map((d) => d.date)),
    [data.daily_logs],
  )
  /* imported Apple Health activity, shown as a small pulse ring */
  const importedDates = useMemo(
    () => new Set(data.imported_activities.map((a) => a.date)),
    [data.imported_activities],
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

  const legendTypes = useMemo(() => {
    const seen = new Map<string, { code: string; label: string; gradient: string }>()
    for (const t of typeByWeekday.values()) {
      const meta = DAY_TYPE_META[t]
      if (!seen.has(meta.code)) seen.set(meta.code, meta)
    }
    return [...seen.values()]
  }, [typeByWeekday])

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
          const planType = typeByWeekday.get(getISODay(d)) ?? null
          const meta = planType ? DAY_TYPE_META[planType] : null

          /* precedence: completed > event day > deload > approach ramp > planned wash */
          let style: React.CSSProperties = {
            background: 'rgba(255,255,255,0.5)',
            border: '1px solid rgba(26,26,34,0.06)',
            color: inMonth ? '#1a1a22' : 'rgba(26,26,34,0.25)',
          }
          let codeColor = meta ? meta.deep : '#9a9aa4'
          let cls = ''

          if (meta && inMonth) {
            style = {
              background: `linear-gradient(150deg, ${hexToRgba(meta.bright, 0.13)}, ${hexToRgba(meta.bright, 0.05)})`,
              border: `1px solid ${hexToRgba(meta.bright, 0.22)}`,
              color: '#1a1a22',
            }
          }
          if (deload && inMonth) {
            style = {
              background: 'linear-gradient(135deg, #7dd3fc 0%, #e0f2fe 100%)',
              border: '1px solid rgba(56,189,248,0.4)',
              color: '#075985',
            }
            codeColor = '#075985'
            cls = 'ice-shimmer'
          }
          if (ramp != null && !during && inMonth) {
            style = {
              background: `linear-gradient(135deg, rgba(245,158,11,${0.2 + ramp * 0.55}) 0%, rgba(220,38,38,${0.12 + ramp * 0.5}) 100%)`,
              border: '1px solid rgba(220,38,38,0.25)',
              color: ramp > 0.6 ? '#7f1d1d' : '#92400e',
            }
            codeColor = ramp > 0.6 ? '#7f1d1d' : '#92400e'
          }
          if (during && inMonth) {
            style = {
              background: 'linear-gradient(135deg, #f59e0b 0%, #dc2626 100%)',
              border: '1px solid transparent',
              color: '#fff',
            }
            codeColor = 'rgba(255,255,255,0.9)'
          }
          if (completed && inMonth && !completed.recovery) {
            const g = completed.type ? DAY_TYPE_META[completed.type] : null
            style = {
              background: g?.gradient ?? accent.gradient,
              border: '1px solid transparent',
              color: '#fff',
              boxShadow: `0 6px 16px -6px ${hexToRgba(g?.bright ?? accent.bright, 0.55)}`,
            }
            codeColor = 'rgba(255,255,255,0.95)'
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
              <span className="absolute top-1 left-1.5 font-mono text-[11px] leading-none font-bold">
                {format(d, 'd')}
              </span>
              <span className="absolute top-1 right-1.5 flex gap-0.5">
                {completed && (
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.5" className="h-2.5 w-2.5" style={{ color: codeColor }}>
                    <path d="m5 13 4 4L19 7" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                )}
                {waterDates.has(dateIso) && (
                  <span
                    className="h-1.5 w-1.5 rounded-full"
                    style={{ background: completed ? 'rgba(255,255,255,0.8)' : '#38bdf8' }}
                  />
                )}
              </span>
              {inMonth && meta && (
                <span
                  className="absolute inset-x-0 bottom-1 text-center font-mono text-[8.5px] leading-none font-bold tracking-widest"
                  style={{ color: codeColor }}
                >
                  {meta.code}
                </span>
              )}
              {inMonth && importedDates.has(dateIso) && !completed && (
                <span
                  className="absolute bottom-1 left-1.5 h-1.5 w-1.5 rounded-full"
                  style={{ background: 'conic-gradient(from 0deg, #f59e0b, #8b5cf6, #10b981, #f59e0b)' }}
                  title="Apple Health activity"
                />
              )}
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
      {/* legend */}
      <div className="mt-3 flex flex-wrap items-center justify-center gap-x-3 gap-y-1.5">
        {legendTypes.map((t) => (
          <span key={t.code} className="flex items-center gap-1 font-mono text-[10px] font-bold text-ink-soft">
            <span className="h-2.5 w-2.5 rounded-[4px]" style={{ background: t.gradient }} />
            {t.code} {t.label}
          </span>
        ))}
        <span className="flex items-center gap-1 font-mono text-[10px] font-bold text-ink-soft">
          <span className="h-2.5 w-2.5 rounded-[4px]" style={{ background: 'linear-gradient(135deg, #7dd3fc, #e0f2fe)' }} />
          Deload
        </span>
        <span className="flex items-center gap-1 font-mono text-[10px] font-bold text-ink-soft">
          <span className="h-2.5 w-2.5 rounded-full bg-sky-400" />
          Water 2.5L+
        </span>
      </div>
    </div>
  )
}
