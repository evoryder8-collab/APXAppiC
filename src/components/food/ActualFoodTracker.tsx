import { useState } from 'react'
import { motion } from 'framer-motion'
import { ACCENTS } from '../../lib/theme'
import type { ConsumedMeal, LoggedFoodEntry, LoggedMeal, MealSlot, MealTotals } from '../../lib/food'
import { useFoodStore } from '../../store/FoodStore'
import { AccentChip, GlassCard } from '../ui'
import { MealComposer } from './MealComposer'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'

const amber = ACCENTS.amber
const slots: MealSlot[] = ['breakfast', 'lunch', 'dinner', 'snack']

export interface PlannedMealTrackerRow extends MealTotals {
  id: string
  time: string
  name: string
  foods: string
  done: boolean
  actual: LoggedMeal | null
  entries: LoggedFoodEntry[]
}

export function ActualFoodTracker({
  target,
  consumed,
  consumedMeals,
  plannedRows,
  activityLabel,
  trainingToday,
  onTogglePlanned,
  onEditPlanned,
}: {
  target: MealTotals
  consumed: MealTotals
  consumedMeals: ConsumedMeal[]
  plannedRows: PlannedMealTrackerRow[]
  activityLabel: string
  trainingToday: boolean
  onTogglePlanned: (row: PlannedMealTrackerRow) => Promise<void>
  onEditPlanned: (row: PlannedMealTrackerRow) => Promise<void>
}) {
  const store = useFoodStore()
  const { language } = useLanguage()
  const [composer, setComposer] = useState<MealSlot | null>(null)
  const [busyMeal, setBusyMeal] = useState<string | null>(null)
  const [expanded, setExpanded] = useState<string | null>(null)
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null)
  const remaining = target.kcal - consumed.kcal
  const calorieProgress = target.kcal > 0 ? Math.min(1, consumed.kcal / target.kcal) : 0
  const customMeals = consumedMeals
    .filter((meal) => meal.source === 'logged' && !meal.planned_meal_id && meal.logged_meal)
    .map((meal) => meal.logged_meal as LoggedMeal)
  const metrics = [
    ['Protein', consumed.protein_g, target.protein_g, '#ec4899'],
    ['Carbs', consumed.carbs_g, target.carbs_g, '#38bdf8'],
    ['Fat', consumed.fat_g, target.fat_g, '#a78bfa'],
  ] as const

  const toggle = async (row: PlannedMealTrackerRow) => {
    if (busyMeal) return
    setBusyMeal(row.id)
    try { await onTogglePlanned(row) } finally { setBusyMeal(null) }
  }

  const edit = async (row: PlannedMealTrackerRow) => {
    if (busyMeal) return
    setBusyMeal(row.id)
    try { await onEditPlanned(row) } finally { setBusyMeal(null) }
  }

  return (
    <>
      <GlassCard accent={amber} className="overflow-hidden p-0">
        <div className="relative overflow-hidden bg-gradient-to-br from-amber-50/95 via-white/80 to-cyan-50/80 p-5 sm:p-6">
          <div className="pointer-events-none absolute -top-20 -right-14 h-52 w-52 rounded-full bg-amber-300/20 blur-3xl" />
          <div className="relative flex items-start justify-between gap-3">
            <div><p className="font-mono text-[10px] font-bold tracking-[0.18em] text-amber-700 uppercase">Today</p><h2 className="mt-1 font-display text-xl font-bold text-ink">Nutrition at a glance</h2></div>
            <AccentChip accent={amber}>{store.syncing ? 'SYNCING' : store.queued ? 'QUEUED OFFLINE' : store.ready ? 'PRIVATE' : 'LOADING'}</AccentChip>
          </div>

          <div className="relative mt-5 grid grid-cols-[1fr_1.45fr_1fr] items-center gap-2 text-center">
            <div><p className="font-mono text-2xl font-bold text-ink">{Math.round(consumed.kcal)}</p><p className="mt-1 text-[10px] font-bold tracking-wide text-ink-faint uppercase">Eaten</p></div>
            <div className="relative mx-auto grid aspect-square w-full max-w-36 place-items-center rounded-full" style={{ background: `conic-gradient(${remaining < 0 ? '#f97316' : amber.bright} ${calorieProgress * 360}deg, rgba(26,26,34,.08) 0deg)` }}>
              <div className="absolute inset-[10px] rounded-full bg-white/95 shadow-inner" />
              <div className="relative"><p className="text-[10px] font-semibold text-ink-soft">{remaining >= 0 ? 'Remaining' : 'Over by'}</p><p className="font-mono text-3xl leading-tight font-bold text-ink">{Math.abs(Math.round(remaining))}</p><p className="font-mono text-[9px] font-semibold text-ink-faint">of {Math.round(target.kcal)} kcal</p></div>
            </div>
            <div><p className="font-mono text-lg font-bold text-ink">{plannedRows.filter((row) => row.done).length}/{plannedRows.length}</p><p className="mt-1 text-[10px] font-bold tracking-wide text-ink-faint uppercase">Meals</p></div>
          </div>

          <div className="relative mt-5 grid grid-cols-3 gap-2">
            {metrics.map(([label, value, goal, color]) => {
              const progress = goal > 0 ? Math.min(1, value / goal) : 0
              return (
                <div key={label} className="rounded-2xl border border-white/80 bg-white/70 p-3 shadow-sm">
                  <div className="flex items-baseline justify-between gap-1"><span className="text-[10px] font-bold text-ink">{label}</span><span className="font-mono text-[9px] font-bold text-ink-faint">{Math.round(value)}/{Math.round(goal)}g</span></div>
                  <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-ink/8"><motion.div initial={{ width: 0 }} animate={{ width: `${progress * 100}%` }} className="h-full rounded-full" style={{ background: color }} /></div>
                </div>
              )
            })}
          </div>
        </div>

        <div className="border-t border-ink/6 bg-white/35 p-4 sm:p-5">
          <div className="flex items-end justify-between gap-3"><div><h3 className="font-display text-lg font-bold text-ink">Meals</h3><p className="text-[11px] font-medium text-ink-soft">One tap logs the plan. Change anything you actually ate.</p></div><span className="font-mono text-[9px] font-bold text-ink-faint">{activityLabel.toUpperCase()}</span></div>
          <div className="mt-3 overflow-hidden rounded-3xl border border-white/80 bg-white/65 shadow-sm">
            {plannedRows.map((row, index) => {
              const actual = row.actual
              const changed = actual?.logged_as === 'changed'
              const title = changed && actual ? actual.display_name : row.name
              const kcal = actual?.total_kcal ?? row.kcal
              const protein = actual?.total_protein_g ?? row.protein_g
              const carbs = actual?.total_carbs_g ?? row.carbs_g
              const fat = actual?.total_fat_g ?? row.fat_g
              const isExpanded = expanded === row.id
              return (
                <div key={row.id} data-planned-meal={row.id} className={index ? 'border-t border-ink/7' : ''}>
                  <div className="flex items-center gap-3 px-3 py-3.5">
                    <button type="button" disabled={busyMeal === row.id} onClick={() => void toggle(row)} aria-label={`${row.done ? 'Remove' : 'Log'} ${row.name}`} className={`grid h-9 w-9 shrink-0 place-items-center rounded-full border-2 transition active:scale-90 disabled:opacity-40 ${row.done ? 'border-transparent text-white' : 'border-amber-300 text-transparent'}`} style={row.done ? { background: amber.gradient } : undefined}>
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" className="h-4 w-4"><path d="m5 13 4 4L19 7" strokeLinecap="round" strokeLinejoin="round" /></svg>
                    </button>
                    <button type="button" onClick={() => setExpanded(isExpanded ? null : row.id)} className="min-w-0 flex-1 text-left">
                      <div className="flex items-center gap-2"><span className="font-mono text-[10px] font-bold text-amber-700">{row.time}</span>{changed && <span className="rounded-full bg-violet-500/10 px-2 py-0.5 text-[8px] font-bold text-violet-700 uppercase">Replaced</span>}</div>
                      <p className="mt-0.5 truncate text-sm font-bold text-ink">{title}</p>
                      <p className="mt-0.5 truncate text-[10px] font-medium text-ink-soft">{changed ? `Instead of ${row.name}` : row.done ? actual ? 'Logged exactly as shown' : 'Counted from your plan' : row.foods}</p>
                    </button>
                    <div className="shrink-0 text-right"><p className="font-mono text-sm font-bold text-ink">{Math.round(kcal)}</p><p className="text-[8px] font-bold text-ink-faint uppercase">kcal</p></div>
                    <button type="button" disabled={busyMeal === row.id} onClick={() => void edit(row)} className="shrink-0 rounded-xl bg-ink/5 px-2.5 py-2 text-[9px] font-bold text-ink-soft disabled:opacity-40">{row.done ? 'Edit' : 'Change'}</button>
                  </div>
                  {isExpanded && (
                    <div className="border-t border-ink/6 bg-amber-50/55 px-4 py-3">
                      <div className="flex flex-wrap gap-x-4 gap-y-1 font-mono text-[10px] font-semibold text-ink-soft"><span>{Math.round(kcal)} kcal</span><span>P {protein}</span><span>C {carbs}</span><span>F {fat}</span></div>
                      {actual && row.entries.length > 0 ? (
                        <div className="mt-2 space-y-1">{row.entries.map((entry) => <div key={entry.id} className="flex items-center justify-between gap-3 text-[10px] font-medium text-ink-soft"><span className="min-w-0 truncate">{entry.snapshot_name} · {entry.quantity} {entry.unit}</span><span className="shrink-0 font-mono font-bold">{entry.kcal} kcal</span></div>)}</div>
                      ) : <p className="mt-2 text-[10px] leading-relaxed font-medium text-ink-soft">{row.foods}</p>}
                    </div>
                  )}
                </div>
              )
            })}
          </div>

          {customMeals.length > 0 && (
            <div className="mt-3 space-y-2">
              {customMeals.map((meal) => (
                <div key={meal.id} className="flex items-center justify-between gap-3 rounded-2xl bg-white/65 px-3 py-3 shadow-sm">
                  <div className="min-w-0"><div className="flex items-center gap-2"><span className="rounded-full bg-cyan-500/10 px-2 py-0.5 text-[8px] font-bold text-cyan-700 uppercase">Extra</span><p className="truncate text-sm font-bold text-ink">{meal.display_name}</p></div><p className="mt-1 font-mono text-[10px] font-semibold text-ink-soft">{meal.total_kcal} kcal · P {meal.total_protein_g} · C {meal.total_carbs_g} · F {meal.total_fat_g}</p></div>
                  {confirmDelete === meal.id ? <div className="flex gap-1"><button type="button" onClick={() => { void store.deleteMeal(meal.id); setConfirmDelete(null) }} className="rounded-lg bg-red-500 px-2 py-1 text-[9px] font-bold text-white">Remove</button><button type="button" onClick={() => setConfirmDelete(null)} className="rounded-lg bg-white px-2 py-1 text-[9px] font-bold">Keep</button></div> : <button type="button" onClick={() => setConfirmDelete(meal.id)} className="text-[9px] font-bold text-ink-faint">Undo</button>}
                </div>
              ))}
            </div>
          )}

          <div className="mt-4 grid grid-cols-4 gap-2">
            {slots.map((slot) => <button key={slot} type="button" onClick={() => setComposer(slot)} className="rounded-2xl bg-white/75 px-1 py-2.5 text-[9px] font-bold text-ink shadow-sm"><span className="block text-base leading-none text-amber-600">+</span><span className="mt-1 block truncate">{translateInterfaceText(`${slot[0].toUpperCase()}${slot.slice(1)}`, language)}</span></button>)}
          </div>
        </div>
      </GlassCard>

      {composer && <MealComposer slot={composer} adaptiveContext={{ target, consumed, activityLabel, trainingToday }} onClose={() => setComposer(null)} />}
    </>
  )
}
