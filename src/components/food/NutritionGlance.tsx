import { motion, useReducedMotion } from 'framer-motion'
import type { ReactNode } from 'react'
import { ACCENTS } from '../../lib/theme'
import type { MealTotals } from '../../lib/food'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import type { ActivityLevel } from '../../lib/types'
import { resolveNutritionCalorieBalance } from '../../lib/nutritionBalance'
import { AccentChip } from '../ui'

const amber = ACCENTS.amber

export function NutritionGlance({
  target,
  consumed,
  burnedKcal,
  activityLevel,
  completion,
  status,
  eyebrow = 'Today',
  cornerControl,
  onOpen,
  onRingClick,
  onMacroClick,
}: {
  target: MealTotals | null
  consumed: MealTotals
  burnedKcal: number
  activityLevel: ActivityLevel
  completion?: number
  status: string
  eyebrow?: string | null
  cornerControl?: ReactNode
  onOpen?: () => void
  onRingClick?: () => void
  onMacroClick?: (macro: 'protein_g' | 'carbs_g' | 'fat_g') => void
}) {
  const { language } = useLanguage()
  const reduceMotion = useReducedMotion()
  const t = (value: string): string => translateInterfaceText(value, language)
  const shortActivityLevel: Record<typeof language, Record<ActivityLevel, string>> = {
    en: { sedentary: 'Sedentary', light: 'Light', moderate: 'Moderate', very: 'Very active', extra: 'Extra active' },
    ro: { sedentary: 'Sedentar', light: 'Ușor activ', moderate: 'Moderat', very: 'Foarte activ', extra: 'Extrem' },
    th: { sedentary: 'น้อย', light: 'เบา', moderate: 'ปานกลาง', very: 'มาก', extra: 'มากเป็นพิเศษ' },
  }
  const balance = target ? resolveNutritionCalorieBalance(target.kcal, consumed.kcal) : null
  const isOverTarget = balance?.isOverTarget === true
  const calorieProgress = target ? Math.min(1, consumed.kcal / target.kcal) : 0
  const metrics = [
    ['Protein', 'protein_g', consumed.protein_g, target?.protein_g ?? null, '#ec4899'],
    ['Carbs', 'carbs_g', consumed.carbs_g, target?.carbs_g ?? null, '#38bdf8'],
    ['Fat', 'fat_g', consumed.fat_g, target?.fat_g ?? null, '#a78bfa'],
  ] as const

  return (
    <div className="relative overflow-hidden bg-gradient-to-br from-amber-50/95 via-white/80 to-cyan-50/80 p-4 sm:p-6">
      <div className="pointer-events-none absolute -top-20 -right-14 h-52 w-52 rounded-full bg-amber-300/20 blur-3xl" />
      <div className="relative flex items-start justify-between gap-3">
        <div>{eyebrow && <p key={eyebrow} className="font-mono text-[10px] font-bold tracking-[0.18em] text-amber-700 uppercase">{t(eyebrow)}</p>}{onOpen ? <button type="button" onClick={onOpen} className={`${eyebrow ? 'mt-1 ' : ''}flex items-center gap-1.5 text-left font-display text-xl font-bold text-ink active:opacity-65`}>{t('Nutrition at a glance')}<span className="text-sm text-amber-700" aria-hidden>↗</span></button> : <h2 className={eyebrow ? 'mt-1 font-display text-xl font-bold text-ink' : 'font-display text-xl font-bold text-ink'}>{t('Nutrition at a glance')}</h2>}</div>
        <div className="flex shrink-0 items-start gap-2">
          <div className="flex flex-col items-end gap-2">
            <AccentChip accent={amber}>{t(status)}</AccentChip>
            {completion == null && cornerControl}
          </div>
          {completion != null && (
            <div
              role="progressbar"
              aria-label={t('Daily completion')}
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={completion}
              className="relative grid h-12 w-12 shrink-0 place-items-center rounded-full"
              style={{ background: `conic-gradient(#10b981 ${completion}%, rgba(26,26,34,0.08) 0)` }}
            >
              <div className="grid h-10 w-10 place-items-center rounded-full bg-white/92 font-mono text-[10px] font-bold text-ink">{completion}%</div>
            </div>
          )}
        </div>
      </div>
      {completion != null && cornerControl && <div className="relative mt-2 flex justify-end">{cornerControl}</div>}

      <div className="relative mt-5 grid grid-cols-[minmax(0,.9fr)_minmax(7rem,1.25fr)_minmax(0,.9fr)] items-center gap-1.5 text-center sm:gap-2">
        <div className="min-w-0">
          <p className="max-w-full whitespace-nowrap font-mono text-[clamp(1.15rem,5.8vw,1.5rem)] leading-none font-bold tracking-[-0.055em] text-ink tabular-nums">{Math.round(consumed.kcal)}</p>
          <p className="mt-1 truncate text-[9px] font-bold tracking-wide text-ink-faint uppercase sm:text-[10px]">{t('Eaten')}</p>
        </div>
        <motion.button
          type="button"
          onClick={onRingClick}
          disabled={!onRingClick}
          whileTap={onRingClick ? { scale: 0.96 } : undefined}
          aria-label={onRingClick ? t(target ? 'Change calorie goal and activity level' : 'Target unavailable') : undefined}
          className="relative mx-auto aspect-square w-full min-w-0 max-w-40 rounded-full text-center disabled:cursor-default"
        >
          <motion.div
            className="absolute -inset-3 rounded-full blur-xl"
            style={{ background: isOverTarget ? 'rgba(239,68,68,.30)' : 'radial-gradient(circle, rgba(251,191,36,.35), rgba(56,189,248,.12) 58%, transparent 72%)' }}
            animate={reduceMotion ? undefined : { opacity: [0.42, 0.86, 0.48], scale: [0.94, 1.06, 0.97] }}
            transition={{ duration: 3.4, repeat: Infinity, ease: 'easeInOut' }}
            aria-hidden
          />
          <div
            className="absolute inset-0 rounded-full p-[9px] shadow-[0_18px_45px_-22px_rgba(245,158,11,.72)]"
            style={{ background: `conic-gradient(from -90deg, ${isOverTarget ? '#f97316' : '#fb923c'} 0deg, ${isOverTarget ? '#ef4444' : '#fbbf24'} ${calorieProgress * 270}deg, ${isOverTarget ? '#fb7185' : '#22d3ee'} ${calorieProgress * 360}deg, rgba(26,26,34,.075) 0deg)` }}
          >
            <div className="relative grid h-full w-full place-items-center overflow-hidden rounded-full border border-white/85 bg-[radial-gradient(circle_at_35%_25%,rgba(255,255,255,.98),rgba(255,251,235,.93)_48%,rgba(236,254,255,.88))] shadow-[inset_0_2px_10px_rgba(255,255,255,.95),inset_0_-10px_24px_rgba(245,158,11,.08)]">
              <motion.div
                className="absolute -inset-1 rounded-full opacity-65"
                style={{ background: 'conic-gradient(from 10deg, transparent 0 68%, rgba(255,255,255,.85) 74%, rgba(251,191,36,.22) 79%, transparent 86%)' }}
                animate={reduceMotion ? undefined : { rotate: 360 }}
                transition={{ duration: 8, repeat: Infinity, ease: 'linear' }}
                aria-hidden
              />
              <motion.div className="relative min-w-0 max-w-full px-1" animate={reduceMotion ? undefined : { scale: [1, 1.025, 1] }} transition={{ duration: 2.8, repeat: Infinity, ease: 'easeInOut' }}>
                {target && balance ? (
                  <>
                    <p className={`text-[10px] font-semibold ${isOverTarget ? 'text-red-600' : 'text-ink-soft'}`}>{t(balance.label)}</p>
                    <p className={`whitespace-nowrap font-mono text-[clamp(1.35rem,7vw,1.875rem)] leading-tight font-bold tracking-[-0.06em] tabular-nums ${isOverTarget ? 'text-red-600' : 'text-ink'}`}>{balance.amount}</p>
                    <p className="whitespace-nowrap font-mono text-[clamp(7px,2vw,9px)] font-semibold tracking-[-0.035em] text-ink-faint">{t('of')} {Math.round(target.kcal)} kcal</p>
                  </>
                ) : (
                  <p className="px-2 text-[10px] leading-tight font-black text-rose-700">{t('Target unavailable')}</p>
                )}
              </motion.div>
            </div>
          </div>
          {onRingClick && <span className="pointer-events-none absolute right-0 bottom-0 grid h-6 w-6 place-items-center rounded-full border border-white bg-white/90 text-[10px] font-black text-amber-700 shadow-sm" aria-hidden>✦</span>}
        </motion.button>
        <div className="min-w-0"><p className="whitespace-nowrap font-mono text-[clamp(1rem,4.8vw,1.125rem)] leading-none font-bold text-ink tabular-nums">{Math.round(burnedKcal)}</p><p className="mt-1 text-[9px] font-bold tracking-wide text-ink-faint uppercase sm:text-[10px]">{t('Burned')}</p><p className="mt-1 truncate font-mono text-[8px] font-bold tracking-tight text-amber-700 uppercase">{shortActivityLevel[language][activityLevel]}</p></div>
      </div>

      <div className="relative mt-5 grid grid-cols-3 gap-2">
        {metrics.map(([label, macro, value, goal, color]) => {
          const progress = goal != null && goal > 0 ? Math.min(1, value / goal) : 0
          const className = "min-w-0 rounded-2xl border border-white/80 bg-white/72 px-2.5 py-3 text-left shadow-[0_8px_22px_-18px_rgba(15,23,42,.55)] sm:px-3"
          const content = <>
            <div className="min-w-0">
              <span className="block min-h-5 break-words text-[9px] leading-[1.05rem] font-bold text-ink sm:text-[10px]">{t(label)}</span>
              <span className="mt-0.5 block whitespace-nowrap font-mono text-[clamp(8px,2.25vw,10px)] font-bold tracking-[-0.04em] text-ink-faint sm:tracking-normal">{Math.round(value)}{goal == null ? 'g' : `/${Math.round(goal)}g`}</span>
            </div>
            {goal != null && <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-ink/8"><motion.div initial={{ width: 0 }} animate={{ width: `${progress * 100}%` }} className="h-full rounded-full" style={{ background: color }} /></div>}
          </>
          return (
            onMacroClick
              ? <motion.button key={label} type="button" whileTap={{ scale: 0.96 }} onClick={() => onMacroClick(macro)} aria-label={`${t(label)}: ${t('show daily food contributors')}`} className={className}>{content}</motion.button>
              : <div key={label} className={className}>{content}</div>
          )
        })}
      </div>
    </div>
  )
}
