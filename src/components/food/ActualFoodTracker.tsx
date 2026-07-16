import { useRef, useState, type ReactNode, type TouchEvent as ReactTouchEvent } from 'react'
import { ACCENTS } from '../../lib/theme'
import type { ConsumedMeal, LoggedFoodEntry, LoggedMeal, MealSlot, MealTotals } from '../../lib/food'
import { useFoodStore } from '../../store/FoodStore'
import { GlassCard } from '../ui'
import { MealComposer } from './MealComposer'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { NutritionGlance } from './NutritionGlance'
import {
  createCustomMealBlock,
  mealBlockLabel,
  mealMomentIdFromIdempotencyKey,
  mealSlotForBlock,
  normalizeMealBlockSettings,
  resolveMealBlockStatuses,
  type MealBlockKind,
  type MealBlockIdentity,
} from '../../lib/mealBlocks'
import { useStore } from '../../store/AppStore'
import { MEAL_ROW_REVEAL_PX, mealRowSwipeOffset } from '../../lib/mealExperience'

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

interface ComposerTarget {
  slot: MealSlot
  blockId: MealBlockKind | null
  mealIdentity: MealBlockIdentity | null
  title: string
  time: string
}

function SwipeMealRow({
  id,
  open,
  deletable,
  disabled = false,
  className = '',
  openLabel,
  deleteLabel,
  deleteActionLabel,
  onOpenChange,
  onActivate,
  onDelete,
  children,
}: {
  id: string
  open: boolean
  deletable: boolean
  disabled?: boolean
  className?: string
  openLabel: string
  deleteLabel: string
  deleteActionLabel: string
  onOpenChange: (id: string | null) => void
  onActivate: () => void
  onDelete: () => Promise<void>
  children: ReactNode
}) {
  const start = useRef<{ x: number; y: number; touchId: number } | null>(null)
  const suppressClick = useRef(false)
  const [drag, setDrag] = useState<number | null>(null)
  const settled = open ? -MEAL_ROW_REVEAL_PX : 0

  const trackedTouch = (event: ReactTouchEvent<HTMLElement>) => {
    const tracked = start.current
    return tracked ? Array.from(event.changedTouches).find((touch) => touch.identifier === tracked.touchId) ?? null : null
  }

  return (
    <div
      className={`relative overflow-hidden ${className}`}
      data-nutrition-local-gesture
      data-meal-row-gesture={id}
      style={{ touchAction: 'pan-y pinch-zoom' }}
      onTouchStart={(event) => {
        event.stopPropagation()
        if (!deletable || disabled || event.touches.length !== 1) return
        const touch = event.touches[0]
        start.current = { x: touch.clientX, y: touch.clientY, touchId: touch.identifier }
        setDrag(settled)
      }}
      onTouchMove={(event) => {
        const tracked = start.current
        if (!tracked || event.touches.length !== 1 || event.touches[0]?.identifier !== tracked.touchId) return
        const touch = event.touches[0]
        const dx = touch.clientX - tracked.x
        const dy = touch.clientY - tracked.y
        if (Math.abs(dy) > Math.abs(dx) * 1.2) {
          start.current = null
          setDrag(null)
          return
        }
        event.stopPropagation()
        suppressClick.current = Math.abs(dx) > 8
        setDrag(Math.max(-MEAL_ROW_REVEAL_PX, Math.min(0, settled + dx)))
      }}
      onTouchEnd={(event) => {
        event.stopPropagation()
        const tracked = start.current
        const touch = trackedTouch(event)
        start.current = null
        setDrag(null)
        if (!tracked || !touch) return
        const next = mealRowSwipeOffset(tracked, { x: touch.clientX, y: touch.clientY }, open)
        onOpenChange(next < 0 ? id : null)
      }}
      onTouchCancel={(event) => {
        event.stopPropagation()
        start.current = null
        setDrag(null)
      }}
    >
      {deletable && (
        <button
          type="button"
          disabled={disabled}
          tabIndex={open ? 0 : -1}
          aria-hidden={!open}
          onClick={(event) => {
            event.stopPropagation()
            void onDelete().finally(() => onOpenChange(null))
          }}
          aria-label={deleteLabel}
          className="absolute inset-y-0 right-0 flex w-[104px] flex-col items-center justify-center bg-rose-600 text-white disabled:opacity-50"
        >
          <span className="grid h-9 w-9 place-items-center rounded-full bg-white/15 text-lg font-black">×</span>
          <span className="mt-1 text-[9px] font-black tracking-wide uppercase">{deleteActionLabel}</span>
        </button>
      )}
      <div
        role="button"
        tabIndex={0}
        aria-label={openLabel}
        className="relative bg-white outline-none transition-transform duration-200 ease-out focus-visible:ring-2 focus-visible:ring-amber-400/60"
        style={{ transform: `translate3d(${drag ?? settled}px,0,0)` }}
        onClick={() => {
          if (suppressClick.current) {
            suppressClick.current = false
            return
          }
          if (open) {
            onOpenChange(null)
            return
          }
          onActivate()
        }}
        onKeyDown={(event) => {
          if (event.target !== event.currentTarget) return
          if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault()
            onActivate()
          }
        }}
      >
        {children}
      </div>
    </div>
  )
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
  onEditLogged,
  onDeleteLogged,
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
  onEditLogged: (meal: LoggedMeal, blockId: MealBlockKind | null, targetTime: string | null) => Promise<void>
  onDeleteLogged: (meal: LoggedMeal) => Promise<void>
}) {
  const store = useFoodStore()
  const { data, setSettings } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [composer, setComposer] = useState<ComposerTarget | null>(null)
  const [busyMeal, setBusyMeal] = useState<string | null>(null)
  const [revealedMeal, setRevealedMeal] = useState<string | null>(null)
  const [addMealOpen, setAddMealOpen] = useState(false)
  const [customOpen, setCustomOpen] = useState(false)
  const [customDraft, setCustomDraft] = useState<{ name: string; time: string; slot: MealSlot }>({ name: '', time: '16:00', slot: 'snack' })
  const mealBlockSettings = normalizeMealBlockSettings(data.settings?.addons.meal_blocks)
  const mealBlockStatuses = resolveMealBlockStatuses({
    settings: mealBlockSettings,
    loggedMeals: store.mealsForDate(date),
    plannedMeals: plannedRows,
    checkedPlannedMealIds: new Set(plannedRows.filter((row) => row.done).map((row) => row.id)),
  })
  /* Empty canonical moments belong only in the single Add meal sheet. The
     main list contains real plan rows and durable logged rows, never a second
     grid of competing plus buttons. */
  const standaloneLoggedBlockStatuses = mealBlockStatuses.filter((status) => !status.plannedMeal && status.loggedMeal)
  const assignedBlockMealIds = new Set(mealBlockStatuses.flatMap((status) => status.loggedMeal ? [status.loggedMeal.id] : []))
  const enabledCustomBlocks = mealBlockSettings.custom_blocks.filter((block) => block.enabled)
  const customLoggedById = new Map(enabledCustomBlocks.flatMap((block) => {
    const meal = store.mealsForDate(date).find((candidate) => mealMomentIdFromIdempotencyKey(candidate.client_idempotency_key) === block.id)
    return meal ? [[block.id, meal] as const] : []
  }))
  const customMeals = consumedMeals
    .filter((meal) => meal.source === 'logged' && !meal.planned_meal_id && meal.logged_meal && !assignedBlockMealIds.has(meal.logged_meal.id))
    .map((meal) => meal.logged_meal as LoggedMeal)

  const runBusy = async (id: string, action: () => Promise<void>) => {
    if (busyMeal) return
    setBusyMeal(id)
    try { await action() } finally { setBusyMeal(null) }
  }

  const openConfiguredBlock = (block: { kind: MealBlockKind; time: string }) => {
    const status = mealBlockStatuses.find((candidate) => candidate.block.kind === block.kind)
    if (status?.loggedMeal) {
      setAddMealOpen(false)
      void runBusy(status.loggedMeal.id, () => onEditLogged(status.loggedMeal!, block.kind, block.time))
      return
    }
    const plannedRow = status?.plannedMeal
      ? plannedRows.find((row) => row.id === status.plannedMeal?.id) ?? null
      : null
    if (plannedRow) {
      setAddMealOpen(false)
      void runBusy(plannedRow.id, () => onEditPlanned(plannedRow))
      return
    }
    setComposer({
      slot: mealSlotForBlock(block.kind),
      blockId: block.kind,
      mealIdentity: block.kind,
      title: t(mealBlockLabel(block.kind)),
      time: block.time,
    })
    setAddMealOpen(false)
  }

  const saveCustomBlock = () => {
    if (!data.settings || !customDraft.name.trim()) return
    const block = createCustomMealBlock({ label: customDraft.name, time: customDraft.time, slot: customDraft.slot })
    setSettings({
      addons: {
        ...data.settings.addons,
        meal_blocks: {
          ...mealBlockSettings,
          custom_blocks: [...mealBlockSettings.custom_blocks, block],
        },
      },
    })
    setComposer({ slot: block.slot, blockId: null, mealIdentity: block.id, title: block.label, time: block.time })
    setCustomDraft({ name: '', time: '16:00', slot: 'snack' })
    setCustomOpen(false)
    setAddMealOpen(false)
  }

  return (
    <>
      <GlassCard accent={amber} className="overflow-hidden p-0">
        <NutritionGlance key={date} eyebrow={dateLabel} target={target} consumed={consumed} mealsDone={mealBlockStatuses.filter((status) => status.completed).length + customLoggedById.size} mealsTotal={mealBlockStatuses.length + enabledCustomBlocks.length} status={store.syncing ? 'SYNCING' : store.queued ? 'QUEUED OFFLINE' : store.ready ? 'PRIVATE' : 'LOADING'} />

        <div className="border-t border-ink/6 bg-white/35 p-4 sm:p-5">
          <div className="flex items-end justify-between gap-3"><div><h3 className="font-display text-lg font-bold text-ink">{t('Meals')}</h3><p className="text-[11px] font-medium text-ink-soft">{t('Tap a logged meal to see or change what you ate.')}</p></div><span className="font-mono text-[9px] font-bold text-ink-faint">{activityLabel.toUpperCase()}</span></div>
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
              const deleteId = actual?.id ?? `planned:${row.id}`
              return (
                <SwipeMealRow
                  key={row.id}
                  id={deleteId}
                  open={revealedMeal === deleteId}
                  deletable={done}
                  disabled={busyMeal === row.id || busyMeal === actual?.id}
                  className={index ? 'border-t border-ink/7' : ''}
                  openLabel={`${t('Open')} ${title}`}
                  deleteLabel={`${t('Delete')} ${title}`}
                  deleteActionLabel={t('Delete')}
                  onOpenChange={setRevealedMeal}
                  onActivate={() => {
                    if (actual) void runBusy(actual.id, () => onEditLogged(actual, blockStatus?.block.kind ?? null, row.time))
                    else void runBusy(row.id, () => onEditPlanned(resolvedRow))
                  }}
                  onDelete={() => runBusy(actual?.id ?? row.id, () => actual ? onDeleteLogged(actual) : onTogglePlanned(resolvedRow))}
                >
                  <div className="flex items-center gap-3 px-3 py-3.5">
                    {done ? (
                      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full text-white" style={{ background: amber.gradient }} aria-hidden>✓</span>
                    ) : (
                      <button type="button" disabled={busyMeal === row.id} onClick={(event) => { event.stopPropagation(); void runBusy(row.id, () => onTogglePlanned(resolvedRow)) }} aria-label={`${t('Log')} ${row.name}`} className="grid h-9 w-9 shrink-0 place-items-center rounded-full border-2 border-amber-300 text-transparent transition active:scale-90 disabled:opacity-40">✓</button>
                    )}
                    <div className="min-w-0 flex-1 text-left">
                      <div className="flex items-center gap-2"><span className="font-mono text-[10px] font-bold text-amber-700">{row.time}</span>{changed && <span className="rounded-full bg-violet-500/10 px-2 py-0.5 text-[8px] font-bold text-violet-700 uppercase">{t('Replaced')}</span>}</div>
                      <p className="mt-0.5 truncate text-sm font-bold text-ink">{title}</p>
                      <p className="mt-0.5 truncate text-[10px] font-medium text-ink-soft">{linkedOnlyByBlock ? `${t('Counts as')} ${t(mealBlockLabel(blockStatus!.block.kind))}` : changed ? `${t('Instead of')} ${row.name}` : done ? actual ? t('Tap to review or edit') : t('Counted from your plan') : row.foods}</p>
                    </div>
                    <div className="shrink-0 text-right"><p className="font-mono text-sm font-bold text-ink">{Math.round(kcal)}</p><p className="text-[8px] font-bold text-ink-faint uppercase">kcal</p></div>
                  </div>
                </SwipeMealRow>
              )
            })}

            {standaloneLoggedBlockStatuses.map((status, index) => {
              const meal = status.loggedMeal!
              const label = meal.display_name
              return (
                <SwipeMealRow
                  key={status.block.id}
                  id={meal.id}
                  open={revealedMeal === meal.id}
                  deletable
                  disabled={busyMeal === meal.id}
                  className={plannedRows.length > 0 || index > 0 ? 'border-t border-ink/7' : ''}
                  openLabel={`${t('Open')} ${label}`}
                  deleteLabel={`${t('Delete')} ${label}`}
                  deleteActionLabel={t('Delete')}
                  onOpenChange={setRevealedMeal}
                  onActivate={() => void runBusy(meal.id, () => onEditLogged(meal, status.block.kind, status.block.time))}
                  onDelete={() => runBusy(meal.id, () => onDeleteLogged(meal))}
                >
                  <div className="flex items-center gap-3 px-3 py-3.5">
                    <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full border-2 border-transparent text-white" style={{ background: amber.gradient }}>✓</span>
                    <div className="min-w-0 flex-1 text-left"><span className="font-mono text-[10px] font-bold text-amber-700">{status.block.time}</span><p className="mt-0.5 truncate text-sm font-bold text-ink">{label}</p><p className="mt-0.5 truncate text-[10px] font-medium text-ink-soft">{t('Tap to review or edit')}</p></div>
                    <div className="shrink-0 text-right"><p className="font-mono text-sm font-bold text-ink">{Math.round(meal.total_kcal)}</p><p className="text-[8px] font-bold text-ink-faint uppercase">kcal</p></div>
                  </div>
                </SwipeMealRow>
              )
            })}
          </div>

          {customMeals.length > 0 && (
            <div className="mt-3 overflow-hidden rounded-3xl border border-white/80 shadow-sm">
              {customMeals.map((meal, index) => (
                <SwipeMealRow
                  key={meal.id}
                  id={meal.id}
                  open={revealedMeal === meal.id}
                  deletable
                  disabled={busyMeal === meal.id}
                  className={index ? 'border-t border-ink/7' : ''}
                  openLabel={`${t('Open')} ${meal.display_name}`}
                  deleteLabel={`${t('Delete')} ${meal.display_name}`}
                  deleteActionLabel={t('Delete')}
                  onOpenChange={setRevealedMeal}
                  onActivate={() => void runBusy(meal.id, () => onEditLogged(meal, null, null))}
                  onDelete={() => runBusy(meal.id, () => onDeleteLogged(meal))}
                >
                  <div className="flex items-center gap-3 px-3 py-3.5">
                    <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-cyan-500/10 text-[9px] font-black text-cyan-700 uppercase">{t('Extra')}</span>
                    <div className="min-w-0 flex-1"><p className="truncate text-sm font-bold text-ink">{meal.display_name}</p><p className="mt-1 font-mono text-[10px] font-semibold text-ink-soft">{meal.total_kcal} kcal · P {meal.total_protein_g} · C {meal.total_carbs_g} · F {meal.total_fat_g}</p></div>
                  </div>
                </SwipeMealRow>
              ))}
            </div>
          )}

          <button type="button" onClick={() => setAddMealOpen(true)} className="mt-4 flex w-full items-center justify-center gap-2 rounded-2xl border border-amber-300/45 bg-white/75 px-4 py-3 text-sm font-black text-amber-800 shadow-sm transition active:scale-[.985]" data-nutrition-local-gesture><span className="text-lg leading-none">+</span>{t('Add meal')}</button>
        </div>
      </GlassCard>

      {addMealOpen && (
        <div className="fixed inset-0 z-[75] flex items-end justify-center bg-slate-950/25 p-3 backdrop-blur-sm sm:items-center" onClick={() => { setAddMealOpen(false); setCustomOpen(false) }} data-nutrition-local-gesture>
          <div role="dialog" aria-modal="true" aria-label={t('Add meal')} onClick={(event) => event.stopPropagation()} className="max-h-[76dvh] w-full max-w-md overflow-y-auto rounded-[28px] border border-white/90 bg-white/96 p-4 shadow-2xl">
            <div className="flex items-start justify-between gap-3"><div><p className="font-display text-lg font-black text-ink">{t('Add meal')}</p><p className="mt-0.5 text-[10px] font-semibold text-ink-soft">{t('Choose a meal moment or create your own.')}</p></div><button type="button" onClick={() => setAddMealOpen(false)} className="grid h-8 w-8 place-items-center rounded-full bg-ink/5 font-black text-ink-soft">×</button></div>
            <div className="mt-4 space-y-2">
              {mealBlockSettings.blocks.filter((block) => block.enabled).map((block) => (
                <button key={block.id} type="button" onClick={() => openConfiguredBlock(block)} className="flex w-full items-center justify-between rounded-2xl bg-slate-50 px-3 py-3 text-left"><span className="text-sm font-black text-ink">{t(mealBlockLabel(block.kind))}</span><span className="font-mono text-[10px] font-bold text-ink-faint">{block.time}</span></button>
              ))}
              {mealBlockSettings.custom_blocks.filter((block) => block.enabled).map((block) => (
                <button key={block.id} type="button" onClick={() => {
                  const existing = customLoggedById.get(block.id)
                  if (existing) void runBusy(existing.id, () => onEditLogged(existing, null, block.time))
                  else setComposer({ slot: block.slot, blockId: null, mealIdentity: block.id, title: block.label, time: block.time })
                  setAddMealOpen(false)
                }} className="flex w-full items-center justify-between rounded-2xl bg-cyan-50/65 px-3 py-3 text-left"><span><span className="block text-sm font-black text-ink">{block.label}</span><span className="block text-[9px] font-bold text-cyan-700 uppercase">{t(customLoggedById.has(block.id) ? 'Logged · tap to edit' : 'Custom')}</span></span><span className="font-mono text-[10px] font-bold text-ink-faint">{block.time}</span></button>
              ))}
            </div>
            {!customOpen ? (
              <button type="button" onClick={() => setCustomOpen(true)} className="mt-3 w-full rounded-2xl border border-dashed border-violet-300 px-4 py-3 text-xs font-black text-violet-800">+ {t('Create a custom meal')}</button>
            ) : (
              <div className="mt-3 rounded-2xl bg-violet-50/65 p-3">
                <input value={customDraft.name} onChange={(event) => setCustomDraft((current) => ({ ...current, name: event.target.value }))} placeholder={t('Meal name')} className="w-full rounded-xl bg-white px-3 py-2.5 text-sm font-bold text-ink outline-none" />
                <div className="mt-2 grid grid-cols-2 gap-2"><input type="time" value={customDraft.time} onChange={(event) => setCustomDraft((current) => ({ ...current, time: event.target.value }))} className="rounded-xl bg-white px-3 py-2.5 font-mono text-sm font-bold" /><select value={customDraft.slot} onChange={(event) => setCustomDraft((current) => ({ ...current, slot: event.target.value as MealSlot }))} className="rounded-xl bg-white px-3 py-2.5 text-sm font-bold">{(['breakfast', 'lunch', 'dinner', 'snack'] as MealSlot[]).map((slot) => <option key={slot} value={slot}>{t(`${slot[0].toUpperCase()}${slot.slice(1)}`)}</option>)}</select></div>
                <button type="button" disabled={!customDraft.name.trim()} onClick={saveCustomBlock} className="mt-2 w-full rounded-xl bg-violet-600 px-3 py-2.5 text-xs font-black text-white disabled:opacity-40">{t('Create and add foods')}</button>
              </div>
            )}
          </div>
        </div>
      )}

      {composer && <MealComposer date={date} planning={planning} slot={composer.slot} mealBlockId={composer.blockId} mealIdentity={composer.mealIdentity} targetTime={composer.time} title={composer.title} onClose={() => setComposer(null)} />}
    </>
  )
}
