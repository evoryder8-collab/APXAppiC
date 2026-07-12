import { useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import { ACCENTS } from '../../lib/theme'
import { aggregateLoggedMeals, type MealSlot, type MealTotals } from '../../lib/food'
import { todayIso } from '../../lib/plan'
import { useFoodStore } from '../../store/FoodStore'
import { AccentChip, GlassCard } from '../ui'
import { MealComposer } from './MealComposer'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'

const amber = ACCENTS.amber
const slots: MealSlot[] = ['breakfast', 'lunch', 'dinner', 'snack']

export function ActualFoodTracker({
  target,
  activityLabel,
  trainingToday,
}: {
  target: MealTotals
  activityLabel: string
  trainingToday: boolean
}) {
  const store = useFoodStore()
  const { language } = useLanguage()
  const today = todayIso()
  const [composer, setComposer] = useState<MealSlot | null>(null)
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null)
  const todayMeals = useMemo(() => store.mealsForDate(today).sort((a, b) => a.logged_at.localeCompare(b.logged_at)), [store, today])
  const consumed = useMemo(() => aggregateLoggedMeals(todayMeals), [todayMeals])
  const remaining = {
    kcal: Math.max(0, target.kcal - consumed.kcal),
    protein_g: Math.max(0, target.protein_g - consumed.protein_g),
    carbs_g: Math.max(0, target.carbs_g - consumed.carbs_g),
    fat_g: Math.max(0, target.fat_g - consumed.fat_g),
  }

  const metrics = [
    ['Calories', consumed.kcal, target.kcal, 'kcal'],
    ['Protein', consumed.protein_g, target.protein_g, 'g'],
    ['Carbs', consumed.carbs_g, target.carbs_g, 'g'],
    ['Fat', consumed.fat_g, target.fat_g, 'g'],
  ] as const

  return (
    <>
      <GlassCard accent={amber} className="p-5 sm:p-6">
        <div className="flex items-start justify-between gap-3">
          <div>
            <p className="font-mono text-[10px] font-bold tracking-[0.18em] text-amber-700 uppercase">Actual intake</p>
            <h2 className="mt-1 font-display text-lg font-bold text-ink">Food tracker</h2>
            <p className="mt-1 text-xs font-medium text-ink-soft">Your plan stays intact. Log what you actually ate here.</p>
          </div>
          <AccentChip accent={amber}>{store.syncing ? 'SYNCING' : store.queued ? 'QUEUED OFFLINE' : store.ready ? 'PRIVATE' : 'LOADING'}</AccentChip>
        </div>

        <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
          {metrics.map(([label, value, goal, unit]) => {
            const progress = goal > 0 ? Math.min(1, value / goal) : 0
            return (
              <div key={label}>
                <div className="flex items-baseline justify-between gap-1"><span className="text-[10px] font-bold text-ink-faint uppercase">{label}</span><span className="font-mono text-[10px] font-bold text-ink-soft">{Math.round(value)}/{Math.round(goal)}{unit}</span></div>
                <div className="mt-1 h-2 overflow-hidden rounded-full bg-ink/8"><motion.div initial={{ width: 0 }} animate={{ width: `${progress * 100}%` }} className="h-full rounded-full" style={{ background: amber.gradient }} /></div>
              </div>
            )
          })}
        </div>

        <div className="mt-4 flex gap-2 overflow-x-auto pb-1">
          {slots.map((slot) => (
            <button key={slot} type="button" onClick={() => setComposer(slot)} className="shrink-0 rounded-full bg-white/75 px-3 py-2 text-xs font-bold text-ink shadow-sm">
              + {translateInterfaceText(`${slot[0].toUpperCase()}${slot.slice(1)}`, language)}
            </button>
          ))}
        </div>

        {todayMeals.length === 0 ? (
          <div className="mt-4 rounded-2xl border border-dashed border-amber-500/25 px-4 py-5 text-center">
            <p className="text-sm font-bold text-ink">Nothing logged yet</p>
            <p className="mt-1 text-xs text-ink-soft">Use a meal above, scan a barcode, repeat a recent meal, or log one of your planned cards below.</p>
          </div>
        ) : (
          <div className="mt-4 space-y-2">
            {todayMeals.map((meal) => (
              <div key={meal.id} className="rounded-2xl bg-white/60 px-3 py-3">
                <div className="flex items-start justify-between gap-2">
                  <div>
                    <div className="flex flex-wrap items-center gap-2"><p className="text-sm font-bold text-ink">{meal.display_name}</p><span className="rounded-full bg-amber-500/10 px-2 py-0.5 text-[9px] font-bold text-amber-700 uppercase">{meal.logged_as}</span></div>
                    <p className="mt-1 font-mono text-[10px] font-semibold text-ink-soft">{meal.total_kcal} kcal · P {meal.total_protein_g} · C {meal.total_carbs_g} · F {meal.total_fat_g}</p>
                  </div>
                  {confirmDelete === meal.id ? (
                    <div className="flex gap-1"><button type="button" onClick={() => { void store.deleteMeal(meal.id); setConfirmDelete(null) }} className="rounded-lg bg-red-500 px-2 py-1 text-[10px] font-bold text-white">Delete</button><button type="button" onClick={() => setConfirmDelete(null)} className="rounded-lg bg-white px-2 py-1 text-[10px] font-bold">Cancel</button></div>
                  ) : <button type="button" onClick={() => setConfirmDelete(meal.id)} className="text-[10px] font-bold text-ink-faint">Undo</button>}
                </div>
              </div>
            ))}
          </div>
        )}

        <p className="mt-4 rounded-2xl bg-amber-500/8 px-3 py-2 text-xs font-semibold text-amber-800">
          {remaining.kcal > 0 ? `${Math.round(remaining.kcal)} kcal remain today. Protein remaining: ${Math.round(remaining.protein_g)} g.` : `You are ${Math.round(consumed.kcal - target.kcal)} kcal above today’s target. No judgement, just a clearer signal for the next choice.`}
        </p>
      </GlassCard>

      {composer && (
        <MealComposer
          slot={composer}
          adaptiveContext={{ target, consumed, activityLabel, trainingToday }}
          onClose={() => setComposer(null)}
        />
      )}
    </>
  )
}
