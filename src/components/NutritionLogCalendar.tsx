import { useMemo } from 'react'
import { addDays, addMonths, format, getISODay, isSameMonth, startOfMonth } from 'date-fns'
import type { Accent } from '../lib/theme'
import type { AppData } from '../lib/types'
import { ChevronLeftIcon, ChevronRightIcon } from './Icons'

interface NutritionLogCalendarProps {
  month: Date
  selectedDate: string
  today: string
  data: AppData
  accent: Accent
  onMonthChange: (month: Date) => void
  onSelectDate: (dateIso: string) => void
}

const WEEKDAYS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']

export function NutritionLogCalendar({
  month,
  selectedDate,
  today,
  data,
  accent,
  onMonthChange,
  onSelectDate,
}: NutritionLogCalendarProps) {
  const cells = useMemo(() => {
    const first = startOfMonth(month)
    const start = addDays(first, -(getISODay(first) - 1))
    return [...Array(42)].map((_, index) => addDays(start, index))
  }, [month])

  const dailyByDate = useMemo(() => new Map(data.daily_logs.map((log) => [log.date, log])), [data.daily_logs])
  const mealCountByDate = useMemo(() => {
    const counts = new Map<string, number>()
    for (const log of data.meal_logs) counts.set(log.date, (counts.get(log.date) ?? 0) + 1)
    return counts
  }, [data.meal_logs])
  const supplementCountByDate = useMemo(() => {
    const counts = new Map<string, number>()
    for (const log of data.supplement_logs) counts.set(log.date, (counts.get(log.date) ?? 0) + 1)
    return counts
  }, [data.supplement_logs])

  const expectedMeals = Math.max(1, data.meals.length)
  const expectedSupplements = Math.max(1, data.supplements.length)

  return (
    <div className="mt-5 border-t border-ink/8 pt-5">
      <div className="mb-4 flex items-center justify-between">
        <button
          type="button"
          onClick={() => onMonthChange(addMonths(month, -1))}
          className="glass flex h-9 w-9 items-center justify-center rounded-full text-ink-soft active:scale-95"
          aria-label="Previous month"
        >
          <ChevronLeftIcon className="h-4 w-4" />
        </button>
        <div className="text-center">
          <p className="font-display text-base font-bold text-ink">Log history</p>
          <p className="font-mono text-[11px] font-semibold text-ink-faint">{format(month, 'MMMM yyyy')}</p>
        </div>
        <button
          type="button"
          onClick={() => onMonthChange(addMonths(month, 1))}
          className="glass flex h-9 w-9 items-center justify-center rounded-full text-ink-soft active:scale-95"
          aria-label="Next month"
        >
          <ChevronRightIcon className="h-4 w-4" />
        </button>
      </div>

      <div className="mb-2 grid grid-cols-7 gap-1.5 px-1">
        {WEEKDAYS.map((weekday) => (
          <div key={weekday} className="text-center font-mono text-[10px] font-bold tracking-wider text-ink-faint">
            {weekday}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-1.5">
        {cells.map((date) => {
          const dateIso = format(date, 'yyyy-MM-dd')
          const inMonth = isSameMonth(date, month)
          const future = dateIso > today
          const daily = dailyByDate.get(dateIso)
          const mealCount = mealCountByDate.get(dateIso) ?? 0
          const supplementCount = supplementCountByDate.get(dateIso) ?? 0
          const waterHit = (daily?.water_l ?? 0) >= 2.5
          const mealHit = mealCount >= expectedMeals
          const supplementHit = supplementCount >= expectedSupplements
          const hasNutrition = !!daily && (
            daily.kcal != null || daily.protein_g != null || daily.fat_g != null ||
            daily.carbs_g != null || daily.water_l > 0
          )
          const hasAny = hasNutrition || mealCount > 0 || supplementCount > 0
          const complete = waterHit && mealHit && supplementHit
          const selected = dateIso === selectedDate

          return (
            <button
              key={dateIso}
              type="button"
              disabled={!inMonth || future}
              onClick={() => onSelectDate(dateIso)}
              aria-label={`${format(date, 'd MMMM yyyy')}: ${mealCount} meals, ${supplementCount} supplements, ${daily?.water_l ?? 0} litres water`}
              className="relative aspect-square overflow-hidden rounded-xl transition-transform active:scale-95 disabled:cursor-default"
              style={{
                background: !inMonth
                  ? 'transparent'
                  : complete
                    ? 'linear-gradient(145deg, rgba(16,185,129,0.22), rgba(52,211,153,0.08))'
                    : hasAny
                      ? 'linear-gradient(145deg, rgba(245,158,11,0.18), rgba(251,191,36,0.06))'
                      : 'rgba(255,255,255,0.45)',
                border: selected
                  ? `2px solid ${accent.bright}`
                  : inMonth
                    ? '1px solid rgba(26,26,34,0.07)'
                    : '1px solid transparent',
                color: !inMonth || future ? 'rgba(26,26,34,0.22)' : '#1a1a22',
                boxShadow: selected ? `0 0 16px -5px ${accent.glowStrong}` : undefined,
              }}
            >
              {inMonth && <span className="absolute top-1 left-1.5 font-mono text-[11px] font-bold">{format(date, 'd')}</span>}
              {inMonth && !future && (
                <span className="absolute inset-x-0 bottom-1.5 flex justify-center gap-1" aria-hidden>
                  <span className="h-1.5 w-1.5 rounded-full" style={{ background: mealCount > 0 ? (mealHit ? '#10b981' : '#f59e0b') : 'rgba(26,26,34,0.12)' }} />
                  <span className="h-1.5 w-1.5 rounded-full" style={{ background: supplementCount > 0 ? (supplementHit ? '#10b981' : '#f59e0b') : 'rgba(26,26,34,0.12)' }} />
                  <span className="h-1.5 w-1.5 rounded-full" style={{ background: waterHit ? '#38bdf8' : 'rgba(26,26,34,0.12)' }} />
                </span>
              )}
            </button>
          )
        })}
      </div>

      <div className="mt-3 flex flex-wrap justify-center gap-x-3 gap-y-1 font-mono text-[10px] font-semibold text-ink-faint">
        <span><i className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-emerald" />complete</span>
        <span><i className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-amber-bright" />partial</span>
        <span><i className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-sky-400" />water target</span>
      </div>
    </div>
  )
}
