import { useEffect, useMemo, useRef } from 'react'
import { addDays, addMonths, format, getISODay, isSameMonth, startOfMonth } from 'date-fns'
import type { Accent } from '../lib/theme'
import type { AppData } from '../lib/types'
import type { LoggedMeal } from '../lib/food'
import { ChevronLeftIcon, ChevronRightIcon } from './Icons'
import { translateInterfaceText, useLanguage } from '../lib/i18n'

interface NutritionLogCalendarProps {
  month: Date
  selectedDate: string
  today: string
  data: AppData
  foodMeals: LoggedMeal[]
  accent: Accent
  onMonthChange: (month: Date) => void
  onSelectDate: (dateIso: string) => void
  copySourceDate?: string | null
  onLongPressDate?: (dateIso: string) => void
  onCopyTarget?: (dateIso: string) => void
}

export function NutritionLogCalendar({
  month,
  selectedDate,
  today,
  data,
  foodMeals,
  accent,
  onMonthChange,
  onSelectDate,
  copySourceDate = null,
  onLongPressDate,
  onCopyTarget,
}: NutritionLogCalendarProps) {
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const dateLocale = language === 'ro' ? 'ro-RO' : language === 'th' ? 'th-TH' : 'en-GB'
  const pressTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const pressStart = useRef<{ date: string; x: number; y: number } | null>(null)
  const suppressClickDate = useRef<string | null>(null)

  const cancelLongPress = (): void => {
    if (pressTimer.current) clearTimeout(pressTimer.current)
    pressTimer.current = null
    pressStart.current = null
  }

  useEffect(() => cancelLongPress, [])
  const cells = useMemo(() => {
    const first = startOfMonth(month)
    const start = addDays(first, -(getISODay(first) - 1))
    return [...Array(42)].map((_, index) => addDays(start, index))
  }, [month])
  const weekdayLabels = useMemo(
    () => cells.slice(0, 7).map((date) => new Intl.DateTimeFormat(dateLocale, { weekday: 'narrow' }).format(date)),
    [cells, dateLocale],
  )

  const dailyByDate = useMemo(() => new Map(data.daily_logs.map((log) => [log.date, log])), [data.daily_logs])
  const mealCountByDate = useMemo(() => {
    const counts = new Map<string, number>()
    for (const log of data.meal_logs) counts.set(log.date, (counts.get(log.date) ?? 0) + 1)
    const foodCounts = new Map<string, number>()
    for (const meal of foodMeals) foodCounts.set(meal.local_date, (foodCounts.get(meal.local_date) ?? 0) + 1)
    for (const [date, count] of foodCounts) counts.set(date, Math.max(counts.get(date) ?? 0, count))
    return counts
  }, [data.meal_logs, foodMeals])
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
          aria-label={t('Previous month')}
        >
          <ChevronLeftIcon className="h-4 w-4" />
        </button>
        <div className="text-center">
          <p className="font-display text-base font-bold text-ink">{t('Nutrition calendar')}</p>
          <p className="font-mono text-[11px] font-semibold text-ink-faint">{new Intl.DateTimeFormat(dateLocale, { month: 'long', year: 'numeric' }).format(month)}</p>
          {copySourceDate && <p className="mt-0.5 font-mono text-[8px] font-black tracking-wide text-cyan-700 uppercase">{t('Choose where to paste')}</p>}
        </div>
        <button
          type="button"
          onClick={() => onMonthChange(addMonths(month, 1))}
          className="glass flex h-9 w-9 items-center justify-center rounded-full text-ink-soft active:scale-95"
          aria-label={t('Next month')}
        >
          <ChevronRightIcon className="h-4 w-4" />
        </button>
      </div>

      <div className="mb-2 grid grid-cols-7 gap-1.5 px-1">
        {weekdayLabels.map((weekday, index) => (
          <div key={`${weekday}-${index}`} className="text-center font-mono text-[10px] font-bold tracking-wider text-ink-faint">
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
          const copiedSource = dateIso === copySourceDate
          const pasteTarget = Boolean(copySourceDate && dateIso !== copySourceDate)

          return (
            <button
              key={dateIso}
              type="button"
              disabled={!inMonth}
              onPointerDown={(event) => {
                if (!inMonth || !onLongPressDate) return
                cancelLongPress()
                pressStart.current = { date: dateIso, x: event.clientX, y: event.clientY }
                pressTimer.current = setTimeout(() => {
                  suppressClickDate.current = dateIso
                  pressTimer.current = null
                  pressStart.current = null
                  onLongPressDate(dateIso)
                }, 520)
              }}
              onPointerMove={(event) => {
                const start = pressStart.current
                if (!start || start.date !== dateIso) return
                if (Math.hypot(event.clientX - start.x, event.clientY - start.y) > 10) cancelLongPress()
              }}
              onPointerUp={cancelLongPress}
              onPointerCancel={cancelLongPress}
              onPointerLeave={cancelLongPress}
              onContextMenu={(event) => event.preventDefault()}
              onClick={() => {
                if (suppressClickDate.current === dateIso) {
                  suppressClickDate.current = null
                  return
                }
                if (pasteTarget && onCopyTarget) onCopyTarget(dateIso)
                else onSelectDate(dateIso)
              }}
              aria-label={`${format(date, 'd MMMM yyyy')}: ${mealCount} meals, ${supplementCount} supplements, ${daily?.water_l ?? 0} litres water`}
              className="relative aspect-square touch-manipulation overflow-hidden rounded-xl transition-transform active:scale-95 disabled:cursor-default"
              style={{
                background: !inMonth
                  ? 'transparent'
                  : copiedSource
                    ? 'linear-gradient(145deg, rgba(8,145,178,0.95), rgba(14,116,144,0.82))'
                    : pasteTarget
                      ? 'linear-gradient(145deg, rgba(207,250,254,0.94), rgba(236,254,255,0.72))'
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
                color: !inMonth ? 'rgba(26,26,34,0.22)' : copiedSource ? '#fff' : future ? 'rgba(26,26,34,0.58)' : '#1a1a22',
                boxShadow: copiedSource ? '0 10px 24px -14px rgba(8,145,178,.9)' : selected ? `0 0 16px -5px ${accent.glowStrong}` : undefined,
              }}
            >
              {inMonth && <span className="absolute top-1 left-1.5 font-mono text-[11px] font-bold">{format(date, 'd')}</span>}
              {copiedSource && <span className="absolute top-1 right-1.5 text-[8px] font-black" aria-hidden>⧉</span>}
              {pasteTarget && <span className="absolute top-1 right-1.5 h-1.5 w-1.5 rounded-full bg-cyan-500" aria-hidden />}
              {inMonth && future && !hasAny && <span className="absolute right-1.5 bottom-1 font-mono text-[11px] font-black text-amber-600">+</span>}
              {inMonth && (hasAny || !future) && (
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
        <span><i className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-emerald" />{t('complete')}</span>
        <span><i className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-amber-bright" />{t('partial')}</span>
        <span><i className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-sky-400" />{t('water target')}</span>
      </div>
    </div>
  )
}
