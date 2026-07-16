import { useState } from 'react'
import { ACCENTS } from '../../lib/theme'
import type { ConsumedMeal, LoggedFoodEntry, LoggedMeal, MealTotals } from '../../lib/food'
import { useFoodStore } from '../../store/FoodStore'
import { GlassCard } from '../ui'
import { MealComposer } from './MealComposer'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { NutritionGlance } from './NutritionGlance'
import { mealBlockLabel, mealSlotForBlock, normalizeMealBlockSettings, resolveMealBlockStatuses, type MealBlockKind } from '../../lib/mealBlocks'
import { useStore } from '../../store/AppStore'

const amber = ACCENTS.amber
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
  date,
  planning,
  dateLabel,
  target,
  consumed,
  consumedMeals,
  plannedRows,
  activityLabel,
  onTogglePlanned,
  onEditPlanned,
}: {
  date: string
  planning: boolean
  dateLabel: string | null
  target: MealTotals
  consumed: MealTotals
  consumedMeals: ConsumedMeal[]
  plannedRows: PlannedMealTrackerRow[]
  activityLabel: string
  onTogglePlanned: (row: PlannedMealTrackerRow) => Promise<void>
  onEditPlanned: (row: PlannedMealTrackerRow) => Promise<void>
}) {
  const store = useFoodStore()
  const { data } = useStore()
  const { language } = useLanguage()
  const [composer, setComposer] = useState<MealBlockKind | null>(null)
  const [busyMeal, setBusyMeal] = useState<string | null>(null)
  const [expanded, setExpanded] = useState<string | null>(null)
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null)
  const mealBlockSettings = normalizeMealBlockSettings(data.settings?.addons.meal_blocks)
  const mealBlockStatuses = resolveMealBlockStatuses({
    settings: mealBlockSettings,
    loggedMeals: store.mealsForDate(date),
    plannedMeals: plannedRows,
    checkedPlannedMealIds: new Set(plannedRows.filter((row) => row.done).map((row) => row.id)),
  })
  const unplannedBlockStatuses = mealBlockStatuses.filter((status) => !status.plannedMeal)
  const assignedBlockMealIds = new Set(mealBlockStatuses.flatMap((status) => status.loggedMeal ? [status.loggedMeal.id] : []))
  const customMeals = consumedMeals
    .filter((meal) => meal.source === 'logged' && !meal.planned_meal_id && meal.logged_meal && !assignedBlockMealIds.has(meal.logged_meal.id))
    .map((meal) => meal.logged_meal as LoggedMeal)

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
        <NutritionGlance key={date} eyebrow={dateLabel} target={target} consumed={consumed} mealsDone={mealBlockStatuses.filter((status) => status.completed).length} mealsTotal={mealBlockStatuses.length} status={store.syncing ? 'SYNCING' : store.queued ? 'QUEUED OFFLINE' : store.ready ? 'PRIVATE' : 'LOADING'} />

        <div className="border-t border-ink/6 bg-white/35 p-4 sm:p-5">
          <div className="flex items-end justify-between gap-3"><div><h3 className="font-display text-lg font-bold text-ink">Meals</h3><p className="text-[11px] font-medium text-ink-soft">One tap logs the plan. Change anything you actually ate.</p></div><span className="font-mono text-[9px] font-bold text-ink-faint">{activityLabel.toUpperCase()}</span></div>
          <div className="mt-3 overflow-hidden rounded-3xl border border-white/80 bg-white/65 shadow-sm">
            {plannedRows.map((row, index) => {
              const blockStatus = mealBlockStatuses.find((status) => status.plannedMeal?.id === row.id)
              const actual = row.actual ?? blockStatus?.loggedMeal ?? null
              const linkedOnlyByBlock = Boolean(actual && !row.actual)
              const done = row.done || Boolean(blockStatus?.completed)
              const entries = row.entries.length > 0 ? row.entries : actual ? store.entries.filter((entry) => entry.meal_id === actual.id).sort((a, b) => a.sort_order - b.sort_order) : []
              const resolvedRow = { ...row, done, actual, entries }
              const changed = actual?.logged_as === 'changed'
              const title = (changed || linkedOnlyByBlock) && actual ? actual.display_name : row.name
              const kcal = actual?.total_kcal ?? row.kcal
              const protein = actual?.total_protein_g ?? row.protein_g
              const carbs = actual?.total_carbs_g ?? row.carbs_g
              const fat = actual?.total_fat_g ?? row.fat_g
              const isExpanded = expanded === row.id
              return (
                <div key={row.id} data-planned-meal={row.id} className={index ? 'border-t border-ink/7' : ''}>
                  <div className="flex items-center gap-3 px-3 py-3.5">
                    <button type="button" disabled={busyMeal === row.id} onClick={() => linkedOnlyByBlock && actual ? void store.deleteMeal(actual.id) : void toggle(resolvedRow)} aria-label={`${done ? 'Remove' : 'Log'} ${row.name}`} className={`grid h-9 w-9 shrink-0 place-items-center rounded-full border-2 transition active:scale-90 disabled:opacity-40 ${done ? 'border-transparent text-white' : 'border-amber-300 text-transparent'}`} style={done ? { background: amber.gradient } : undefined}>
                      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" className="h-4 w-4"><path d="m5 13 4 4L19 7" strokeLinecap="round" strokeLinejoin="round" /></svg>
                    </button>
                    <button type="button" onClick={() => setExpanded(isExpanded ? null : row.id)} className="min-w-0 flex-1 text-left">
                      <div className="flex items-center gap-2"><span className="font-mono text-[10px] font-bold text-amber-700">{row.time}</span>{changed && <span className="rounded-full bg-violet-500/10 px-2 py-0.5 text-[8px] font-bold text-violet-700 uppercase">Replaced</span>}</div>
                      <p className="mt-0.5 truncate text-sm font-bold text-ink">{title}</p>
                      <p className="mt-0.5 truncate text-[10px] font-medium text-ink-soft">{linkedOnlyByBlock ? `${translateInterfaceText('Counts as', language)} ${translateInterfaceText(mealBlockLabel(blockStatus!.block.kind), language)}` : changed ? `Instead of ${row.name}` : done ? actual ? 'Logged exactly as shown' : 'Counted from your plan' : row.foods}</p>
                    </button>
                    <div className="shrink-0 text-right"><p className="font-mono text-sm font-bold text-ink">{Math.round(kcal)}</p><p className="text-[8px] font-bold text-ink-faint uppercase">kcal</p></div>
                    <button type="button" disabled={busyMeal === row.id} onClick={() => void edit(resolvedRow)} className="shrink-0 rounded-xl bg-ink/5 px-2.5 py-2 text-[9px] font-bold text-ink-soft disabled:opacity-40">{done ? 'Edit' : 'Change'}</button>
                  </div>
                  {isExpanded && (
                    <div className="border-t border-ink/6 bg-amber-50/55 px-4 py-3">
                      <div className="flex flex-wrap gap-x-4 gap-y-1 font-mono text-[10px] font-semibold text-ink-soft"><span>{Math.round(kcal)} kcal</span><span>P {protein}</span><span>C {carbs}</span><span>F {fat}</span></div>
                      {actual && entries.length > 0 ? (
                        <div className="mt-2 space-y-1">{entries.map((entry) => <div key={entry.id} className="flex items-center justify-between gap-3 text-[10px] font-medium text-ink-soft"><span className="min-w-0 truncate">{entry.snapshot_name} · {entry.quantity} {entry.unit}</span><span className="shrink-0 font-mono font-bold">{entry.kcal} kcal</span></div>)}</div>
                      ) : <p className="mt-2 text-[10px] leading-relaxed font-medium text-ink-soft">{row.foods}</p>}
                    </div>
                  )}
                </div>
              )
            })}
            {unplannedBlockStatuses.map((status, index) => (
              <div key={status.block.id} className={plannedRows.length > 0 || index > 0 ? 'border-t border-ink/7' : ''}>
                <div className="flex items-center gap-3 px-3 py-3.5">
                  <button type="button" onClick={() => !status.loggedMeal && setComposer(status.block.id)} aria-label={`${status.completed ? 'Completed' : 'Add'} ${mealBlockLabel(status.block.kind)}`} className={`grid h-9 w-9 shrink-0 place-items-center rounded-full border-2 transition active:scale-90 ${status.completed ? 'border-transparent text-white' : 'border-amber-300 text-amber-700'}`} style={status.completed ? { background: amber.gradient } : undefined}>{status.completed ? '✓' : '+'}</button>
                  <button type="button" onClick={() => !status.loggedMeal && setComposer(status.block.id)} className="min-w-0 flex-1 text-left">
                    <span className="font-mono text-[10px] font-bold text-amber-700">{status.block.time}</span>
                    <p className="mt-0.5 truncate text-sm font-bold text-ink">{translateInterfaceText(mealBlockLabel(status.block.kind), language)}</p>
                    <p className="mt-0.5 truncate text-[10px] font-medium text-ink-soft">{status.loggedMeal ? status.loggedMeal.display_name : translateInterfaceText('Tap to add a saved preset or food', language)}</p>
                  </button>
                  {status.loggedMeal && <><div className="shrink-0 text-right"><p className="font-mono text-sm font-bold text-ink">{Math.round(status.loggedMeal.total_kcal)}</p><p className="text-[8px] font-bold text-ink-faint uppercase">kcal</p></div><button type="button" onClick={() => void store.deleteMeal(status.loggedMeal!.id)} className="grid h-8 w-8 place-items-center rounded-full bg-rose-50 text-xs font-black text-rose-600" aria-label={`Remove ${status.loggedMeal.display_name}`}>×</button></>}
                </div>
              </div>
            ))}
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
            {mealBlockStatuses.map(({ block }) => <button key={block.id} type="button" onClick={() => setComposer(block.id)} className="rounded-2xl bg-white/75 px-1 py-2.5 text-[9px] font-bold text-ink shadow-sm"><span className="block text-base leading-none text-amber-600">+</span><span className="mt-1 block truncate">{translateInterfaceText(mealBlockLabel(block.kind), language)}</span></button>)}
          </div>
        </div>
      </GlassCard>

      {composer && <MealComposer date={date} planning={planning} slot={mealSlotForBlock(composer)} mealBlockId={composer} title={translateInterfaceText(mealBlockLabel(composer), language)} onClose={() => setComposer(null)} />}
    </>
  )
}
