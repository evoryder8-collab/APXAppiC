import { useMemo, useState } from 'react'
import { ACCENTS } from '../../lib/theme'
import type { LoggedFoodEntry, LoggedMeal, MealSlot, MealTotals } from '../../lib/food'
import { useFoodStore } from '../../store/FoodStore'
import { GlassCard } from '../ui'
import { MealComposer } from './MealComposer'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import type { ActivityLevel } from '../../lib/types'
import { NutritionGlance } from './NutritionGlance'
import {
  mealBlockLabel,
  mealSlotForClock,
  mealMomentIdFromIdempotencyKey,
  mealSlotForBlock,
  normalizeMealBlockSettings,
  rescheduleMealBlock,
  resolveMealBlockStatuses,
  type MealBlockKind,
  type MealBlockIdentity,
} from '../../lib/mealBlocks'
import { useStore } from '../../store/AppStore'
import { normalizeMealDaylineDensity, normalizeMealTimelineSnap, timeZoneFromSettings } from '../../lib/mealTiming'
import { MealDayline, type MealDaylineSlot } from './MealDayline'

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

export function ActualFoodTracker({
  date,
  planning,
  dateLabel,
  target,
  consumed,
  burnedKcal,
  activityLevel,
  plannedRows,
  onEditPlanned,
  onEditLogged,
  onDeleteLogged,
}: {
  date: string
  planning: boolean
  dateLabel: string | null
  target: MealTotals
  consumed: MealTotals
  burnedKcal: number
  activityLevel: ActivityLevel
  plannedRows: PlannedMealTrackerRow[]
  onEditPlanned: (row: PlannedMealTrackerRow) => Promise<void>
  onEditLogged: (meal: LoggedMeal, blockId: MealBlockKind | null, targetTime: string | null) => Promise<void>
  onDeleteLogged: (meal: LoggedMeal) => Promise<void>
}) {
  const store = useFoodStore()
  const { data, upsert, setSettings } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [composer, setComposer] = useState<ComposerTarget | null>(null)
  const [busyMeal, setBusyMeal] = useState<string | null>(null)
  const mealBlockSettings = normalizeMealBlockSettings(data.settings?.addons.meal_blocks)
  const mealBlockStatuses = resolveMealBlockStatuses({
    settings: mealBlockSettings,
    loggedMeals: store.mealsForDate(date),
    plannedMeals: plannedRows,
    checkedPlannedMealIds: new Set(plannedRows.filter((row) => row.done).map((row) => row.id)),
  })
  const enabledCustomBlocks = mealBlockSettings.custom_blocks.filter((block) => block.enabled)
  const customLoggedById = new Map(enabledCustomBlocks.flatMap((block) => {
    const meal = store.mealsForDate(date).find((candidate) => mealMomentIdFromIdempotencyKey(candidate.client_idempotency_key) === block.id)
    return meal ? [[block.id, meal] as const] : []
  }))
  const timelineFallbackTimes = useMemo(() => {
    const pairs: Array<[string, string]> = []
    for (const status of mealBlockStatuses) {
      if (status.loggedMeal) pairs.push([status.loggedMeal.id, status.block.time])
    }
    for (const block of enabledCustomBlocks) {
      const meal = customLoggedById.get(block.id)
      if (meal) pairs.push([meal.id, block.time])
    }
    return Object.fromEntries(pairs)
  }, [customLoggedById, enabledCustomBlocks, mealBlockStatuses])
  const timelineSlots = useMemo<MealDaylineSlot[]>(() => [
    ...mealBlockStatuses.map((status) => ({
      id: status.block.id,
      label: t(mealBlockLabel(status.block.kind)),
      time: status.block.time,
      slot: mealSlotForBlock(status.block.kind),
      mealId: status.loggedMeal?.id ?? null,
    })),
    ...enabledCustomBlocks.map((block) => ({
      id: block.id,
      label: block.label,
      time: block.time,
      slot: block.slot,
      mealId: customLoggedById.get(block.id)?.id ?? null,
    })),
  ], [customLoggedById, enabledCustomBlocks, language, mealBlockStatuses])

  const runBusy = async (id: string, action: () => Promise<void>) => {
    if (busyMeal) return
    setBusyMeal(id)
    try { await action() } finally { setBusyMeal(null) }
  }

  const openConfiguredBlock = (block: { kind: MealBlockKind; time: string }) => {
    const status = mealBlockStatuses.find((candidate) => candidate.block.kind === block.kind)
    if (status?.loggedMeal) {
      void runBusy(status.loggedMeal.id, () => onEditLogged(status.loggedMeal!, block.kind, block.time))
      return
    }
    const plannedRow = status?.plannedMeal
      ? plannedRows.find((row) => row.id === status.plannedMeal?.id) ?? null
      : null
    if (plannedRow) {
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
  }

  const openTimelineSlot = (slot: MealDaylineSlot) => {
    const configured = mealBlockStatuses.find((status) => status.block.id === slot.id)
    if (configured) {
      openConfiguredBlock(configured.block)
      return
    }
    const custom = enabledCustomBlocks.find((block) => block.id === slot.id)
    if (!custom) return
    const existing = customLoggedById.get(custom.id)
    if (existing) {
      void runBusy(existing.id, () => onEditLogged(existing, null, custom.time))
      return
    }
    setComposer({
      slot: custom.slot,
      blockId: null,
      mealIdentity: custom.id,
      title: custom.label,
      time: custom.time,
    })
  }

  const openTimelineMeal = (meal: LoggedMeal) => {
    const configured = mealBlockStatuses.find((status) => status.loggedMeal?.id === meal.id)
    const custom = enabledCustomBlocks.find((block) => customLoggedById.get(block.id)?.id === meal.id)
    void runBusy(meal.id, () => onEditLogged(
      meal,
      configured?.block.kind ?? null,
      configured?.block.time ?? custom?.time ?? null,
    ))
  }

  const openMealAtTime = (time: string) => {
    setComposer({
      slot: mealSlotForClock(time),
      blockId: null,
      mealIdentity: null,
      title: t('Meal'),
      time,
    })
  }

  const openRecoveryMeal = () => {
    const recovery = mealBlockStatuses.find((status) => status.block.kind === 'post_workout')
    if (recovery) {
      openConfiguredBlock(recovery.block)
      return
    }
    openMealAtTime(new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: timeZoneFromSettings(data.settings) }))
  }

  const rescheduleTimelineSlot = (slotId: string, time: string): void => {
    if (!data.settings) return
    setSettings({
      addons: {
        ...data.settings.addons,
        meal_blocks: rescheduleMealBlock(data.settings.addons.meal_blocks, slotId, time),
      },
    })
  }

  return (
    <>
      <GlassCard accent={amber} className="overflow-hidden p-0">
        <NutritionGlance key={date} eyebrow={dateLabel} target={target} consumed={consumed} burnedKcal={burnedKcal} activityLevel={activityLevel} status={store.syncing ? 'SYNCING' : store.queued ? 'QUEUED OFFLINE' : store.ready ? 'PRIVATE' : 'LOADING'} />

        <div className="border-t border-ink/6 bg-white/24 p-2.5 sm:p-4">
          <MealDayline
            detailed={(data.settings?.addons.interface_mode ?? 'clean') === 'detailed'}
            date={date}
            meals={store.mealsForDate(date)}
            entries={store.entries}
            timeZone={timeZoneFromSettings(data.settings)}
            density={normalizeMealDaylineDensity(data.settings?.addons.meal_dayline_density)}
            fallbackTimes={timelineFallbackTimes}
            slots={timelineSlots}
            sessions={data.workout_sessions}
            snapMinutes={normalizeMealTimelineSnap(data.settings?.addons.meal_timeline_snap_minutes)}
            onMealFinishedAt={store.setMealFinishedAt}
            onSlotTimeChanged={rescheduleTimelineSlot}
            onOpenMeal={openTimelineMeal}
            onOpenSlot={openTimelineSlot}
            onAddAtTime={openMealAtTime}
            onDeleteMeal={onDeleteLogged}
            onOpenRecoveryMeal={openRecoveryMeal}
            onWorkoutCompletedAt={(sessionId, completedAt) => {
              const session = data.workout_sessions.find((candidate) => candidate.id === sessionId)
              if (!session) throw new Error('This workout is no longer available.')
              upsert('workout_sessions', { ...session, completed_at: completedAt })
            }}
          />
        </div>

      </GlassCard>

      {composer && <MealComposer date={date} planning={planning} slot={composer.slot} mealBlockId={composer.blockId} mealIdentity={composer.mealIdentity} targetTime={composer.time} title={composer.title} onClose={() => setComposer(null)} />}
    </>
  )
}
