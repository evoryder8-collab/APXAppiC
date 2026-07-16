import { motion, useReducedMotion } from 'framer-motion'
import type { ReactNode } from 'react'
import { ACCENTS } from '../../lib/theme'
import type { MealTotals } from '../../lib/food'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { AccentChip } from '../ui'

const amber = ACCENTS.amber

export function NutritionGlance({
  target,
  consumed,
  mealsDone,
  mealsTotal,
  status,
  eyebrow = 'Today',
  cornerControl,
  onOpen,
}: {
  target: MealTotals
  consumed: MealTotals
  mealsDone: number
  mealsTotal: number
  status: string
  eyebrow?: string | null
  cornerControl?: ReactNode
  onOpen?: () => void
}) {
  const { language } = useLanguage()
  const reduceMotion = useReducedMotion()
  const t = (value: string): string => translateInterfaceText(value, language)
  const remaining = target.kcal - consumed.kcal
  const calorieProgress = target.kcal > 0 ? Math.min(1, consumed.kcal / target.kcal) : 0
  const metrics = [
    ['Protein', consumed.protein_g, target.protein_g, '#ec4899'],
    ['Carbs', consumed.carbs_g, target.carbs_g, '#38bdf8'],
    ['Fat', consumed.fat_g, target.fat_g, '#a78bfa'],
  ] as const

  return (
    <div className="relative overflow-hidden bg-gradient-to-br from-amber-50/95 via-white/80 to-cyan-50/80 p-5 sm:p-6">
      <div className="pointer-events-none absolute -top-20 -right-14 h-52 w-52 rounded-full bg-amber-300/20 blur-3xl" />
      <div className="relative flex items-start justify-between gap-3">
        <div>{eyebrow && <p key={eyebrow} className="font-mono text-[10px] font-bold tracking-[0.18em] text-amber-700 uppercase">{t(eyebrow)}</p>}{onOpen ? <button type="button" onClick={onOpen} className={`${eyebrow ? 'mt-1 ' : ''}flex items-center gap-1.5 text-left font-display text-xl font-bold text-ink active:opacity-65`}>{t('Nutrition at a glance')}<span className="text-sm text-amber-700" aria-hidden>↗</span></button> : <h2 className={eyebrow ? 'mt-1 font-display text-xl font-bold text-ink' : 'font-display text-xl font-bold text-ink'}>{t('Nutrition at a glance')}</h2>}</div>
        <div className="flex shrink-0 flex-col items-end gap-2">
          <AccentChip accent={amber}>{t(status)}</AccentChip>
          {cornerControl}
        </div>
      </div>

      <div className="relative mt-5 grid grid-cols-[1fr_1.45fr_1fr] items-center gap-2 text-center">
        <div><p className="font-mono text-2xl font-bold text-ink">{Math.round(consumed.kcal)}</p><p className="mt-1 text-[10px] font-bold tracking-wide text-ink-faint uppercase">{t('Eaten')}</p></div>
        <div className="relative mx-auto aspect-square w-full max-w-40">
          <motion.div
            className="absolute -inset-3 rounded-full blur-xl"
            style={{ background: remaining < 0 ? 'rgba(249,115,22,.28)' : 'radial-gradient(circle, rgba(251,191,36,.35), rgba(56,189,248,.12) 58%, transparent 72%)' }}
            animate={reduceMotion ? undefined : { opacity: [0.42, 0.86, 0.48], scale: [0.94, 1.06, 0.97] }}
            transition={{ duration: 3.4, repeat: Infinity, ease: 'easeInOut' }}
            aria-hidden
          />
          <div
            className="absolute inset-0 rounded-full p-[9px] shadow-[0_18px_45px_-22px_rgba(245,158,11,.72)]"
            style={{ background: `conic-gradient(from -90deg, ${remaining < 0 ? '#f97316' : '#fb923c'} 0deg, ${remaining < 0 ? '#ef4444' : '#fbbf24'} ${calorieProgress * 270}deg, ${remaining < 0 ? '#fb7185' : '#22d3ee'} ${calorieProgress * 360}deg, rgba(26,26,34,.075) 0deg)` }}
          >
            <div className="relative grid h-full w-full place-items-center overflow-hidden rounded-full border border-white/85 bg-[radial-gradient(circle_at_35%_25%,rgba(255,255,255,.98),rgba(255,251,235,.93)_48%,rgba(236,254,255,.88))] shadow-[inset_0_2px_10px_rgba(255,255,255,.95),inset_0_-10px_24px_rgba(245,158,11,.08)]">
              <motion.div
                className="absolute -inset-1 rounded-full opacity-65"
                style={{ background: 'conic-gradient(from 10deg, transparent 0 68%, rgba(255,255,255,.85) 74%, rgba(251,191,36,.22) 79%, transparent 86%)' }}
                animate={reduceMotion ? undefined : { rotate: 360 }}
                transition={{ duration: 8, repeat: Infinity, ease: 'linear' }}
                aria-hidden
              />
              <motion.div className="relative" animate={reduceMotion ? undefined : { scale: [1, 1.025, 1] }} transition={{ duration: 2.8, repeat: Infinity, ease: 'easeInOut' }}>
                <p className="text-[10px] font-semibold text-ink-soft">{t(remaining >= 0 ? 'Remaining' : 'Over by')}</p>
                <p className="font-mono text-3xl leading-tight font-bold text-ink">{Math.abs(Math.round(remaining))}</p>
                <p className="font-mono text-[9px] font-semibold text-ink-faint">{t('of')} {Math.round(target.kcal)} kcal</p>
              </motion.div>
            </div>
          </div>
        </div>
        <div><p className="font-mono text-lg font-bold text-ink">{mealsDone}/{mealsTotal}</p><p className="mt-1 text-[10px] font-bold tracking-wide text-ink-faint uppercase">{t('Meals')}</p></div>
      </div>

      <div className="relative mt-5 grid grid-cols-3 gap-2">
        {metrics.map(([label, value, goal, color]) => {
          const progress = goal > 0 ? Math.min(1, value / goal) : 0
          return (
            <div key={label} className="min-w-0 rounded-2xl border border-white/80 bg-white/72 px-2.5 py-3 shadow-[0_8px_22px_-18px_rgba(15,23,42,.55)] sm:px-3">
              <div className="min-w-0">
                <span className="block min-h-5 break-words text-[9px] leading-[1.05rem] font-bold text-ink sm:text-[10px]">{t(label)}</span>
                <span className="mt-0.5 block whitespace-nowrap font-mono text-[clamp(8px,2.25vw,10px)] font-bold tracking-[-0.04em] text-ink-faint sm:tracking-normal">{Math.round(value)}/{Math.round(goal)}g</span>
              </div>
              <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-ink/8"><motion.div initial={{ width: 0 }} animate={{ width: `${progress * 100}%` }} className="h-full rounded-full" style={{ background: color }} /></div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
