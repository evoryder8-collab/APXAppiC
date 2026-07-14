import { useEffect, useMemo, useState } from 'react'
import { motion } from 'framer-motion'
import { Link } from 'react-router-dom'
import { differenceInCalendarDays, format, getISODay, startOfMonth, subDays } from 'date-fns'
import { useStore } from '../store/AppStore'
import { ACCENTS } from '../lib/theme'
import {
  AccentChip,
  GlassCard,
  SectionHeader,
  Sparkline,
  Stepper,
  Toggle,
} from '../components/ui'
import { computeTargets, buildTargetMealPlan, ACTIVITY_MULTIPLIERS, GOALS, type TargetMeal } from '../lib/nutrition'
import { todayIso } from '../lib/plan'
import { dailyLogId } from '../lib/ids'
import type { ActivityLevel, DailyLog, Goal, Supplement } from '../lib/types'
import { ensurePermission } from '../lib/notify'
import { NutritionLogCalendar } from '../components/NutritionLogCalendar'
import { TodaysActivities } from '../components/TodaysActivities'
import {
  activityCatalogMap,
  activityLogFromBlock,
  blockFromActivityLog,
  blockSummary,
  calibrateActivityK,
  estimateActivityDay,
  netKcalForBlock,
  PAL_LABELS,
  type ActivityBlock,
  type ActivityPreset,
} from '../lib/activity'
import { ActualFoodTracker } from '../components/food/ActualFoodTracker'
import type { PlannedMealTrackerRow } from '../components/food/ActualFoodTracker'
import { MealComposer } from '../components/food/MealComposer'
import { useFoodStore } from '../store/FoodStore'
import {
  aggregateConsumedMeals,
  reconcileConsumedMeals,
  type ComposerFoodItem,
  type FoodRecord,
  type LoggedFoodEntry,
  type MealSlot,
} from '../lib/food'

const amber = ACCENTS.amber

function minutesOf(hm: string): number {
  const [h, m] = hm.split(':').map(Number)
  return h * 60 + m
}

function hmOf(minutes: number): string {
  const m = ((minutes % 1440) + 1440) % 1440
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`
}

function emptyDailyLog(date: string, userId: string): DailyLog {
  return {
    id: dailyLogId(date, userId),
    user_id: userId,
    date,
    kcal: null,
    protein_g: null,
    fat_g: null,
    carbs_g: null,
    water_l: 0,
    estimated_tdee: null,
    computed_pal: null,
    activity_mode: 'quick',
    weight_kg: null,
  }
}

export function resolveSupplementTime(s: Supplement, trainingTime: string): number {
  if (s.timing === 'clock' && s.clock_time) return minutesOf(s.clock_time)
  return minutesOf(trainingTime) + (s.offset_min ?? 0)
}

export function Nutrition() {
  const { data, upsert, remove, setProfile, setSettings, toast } = useStore()
  const foodStore = useFoodStore()
  const today = todayIso()
  const profile = data.profile
  const catalog = useMemo(() => activityCatalogMap(data.activity_types), [data.activity_types])
  const todayActivityLogs = useMemo(
    () => data.activity_logs.filter((log) => log.date === today),
    [data.activity_logs, today],
  )
  const activityBlocks = useMemo(
    () => todayActivityLogs.map((log) => blockFromActivityLog(log, catalog)),
    [catalog, todayActivityLogs],
  )
  const quickTargets = useMemo(() => (profile ? computeTargets(profile) : null), [profile])
  const activityEstimate = useMemo(
    () => (profile ? estimateActivityDay(profile, activityBlocks, catalog) : null),
    [profile, activityBlocks, catalog],
  )
  const preciseMode = activityBlocks.length > 0
  const targets = useMemo(() => {
    if (!quickTargets || !activityEstimate || !preciseMode) return quickTargets
    return {
      ...quickTargets,
      tdee: activityEstimate.tdee,
      kcal: activityEstimate.targetKcal,
      protein_g: activityEstimate.proteinG,
      fat_g: activityEstimate.fatG,
      carbs_g: activityEstimate.carbsG,
    }
  }, [activityEstimate, preciseMode, quickTargets])
  const [showBmrInfo, setShowBmrInfo] = useState(false)
  const [selectedLogDate, setSelectedLogDate] = useState(today)
  const [logMonth, setLogMonth] = useState(() => startOfMonth(new Date()))
  const [plannedComposer, setPlannedComposer] = useState<{
    meal: TargetMeal
    slot: MealSlot
    items: ComposerFoodItem[]
    title: string
    replaceMealId: string | null
  } | null>(null)

  const selectedLog: DailyLog = {
    ...emptyDailyLog(selectedLogDate, profile?.user_id ?? 'local'),
    ...data.daily_logs.find((d) => d.date === selectedLogDate),
  }

  const patchLog = (patch: Partial<DailyLog>): void => {
    upsert('daily_logs', { ...selectedLog, ...patch })
  }

  /* Sparkline data: the 7-day window ending at the selected history date. */
  const week = useMemo(() => {
    const end = new Date(selectedLogDate + 'T12:00:00')
    const days = [...Array(7)].map((_, i) => format(subDays(end, 6 - i), 'yyyy-MM-dd'))
    const byDate = new Map(data.daily_logs.map((d) => [d.date, d]))
    return {
      kcal: days.map((d) => byDate.get(d)?.kcal ?? null),
      protein: days.map((d) => byDate.get(d)?.protein_g ?? null),
      fat: days.map((d) => byDate.get(d)?.fat_g ?? null),
      carbs: days.map((d) => byDate.get(d)?.carbs_g ?? null),
      water: days.map((d) => byDate.get(d)?.water_l ?? null),
    }
  }, [data.daily_logs, selectedLogDate])

  const activeDayLabel = preciseMode && activityEstimate
    ? PAL_LABELS[activityEstimate.level]
    : profile ? ACTIVITY_MULTIPLIERS[profile.activity_level].label : 'Adaptive'
  const mealPlan = useMemo(
    () => (targets ? buildTargetMealPlan(data.meals, targets, activeDayLabel) : []),
    [activeDayLabel, data.meals, targets],
  )

  const mealSlotFor = (meal: TargetMeal): MealSlot => {
    const hour = Number(meal.time.slice(0, 2))
    if (meal.name.toLowerCase().includes('snack') || meal.name.toLowerCase().includes('shake')) return 'snack'
    if (hour < 11) return 'breakfast'
    if (hour < 16) return 'lunch'
    return 'dinner'
  }

  const plannedFoodItem = async (meal: TargetMeal): Promise<ComposerFoodItem> => {
    const providerId = `apex-plan:${meal.id}:${meal.kcal}:${meal.protein_g}:${meal.carbs_g}:${meal.fat_g}`
    let food = foodStore.foods.find((value) => value.owner_user_id === profile?.user_id && value.provider_product_id === providerId)
    if (!food) {
      food = await foodStore.savePrivateFood({
        name: `${meal.name} · planned prescription`, names_i18n: { en: `${meal.name} · planned prescription` },
        brand: 'APEX plan', barcode: null, provider_product_id: providerId, external_image_url: null,
        package_quantity: '1 planned meal', nutrition_basis: 'per_100g', preparation_state: 'prepared',
        kcal_100: meal.kcal, protein_100: meal.protein_g, carbs_100: meal.carbs_g, fat_100: meal.fat_g,
        fibre_100: null, sugar_100: null, saturated_fat_100: null, salt_100: null,
        serving_amount: 1, serving_unit: 'serving', serving_grams_or_ml: 100, piece_grams_or_ml: null,
        provider_updated_at: null, confidence: 'user_entered',
      })
    }
    return {
      id: crypto.randomUUID(), food, quantity: 1, unit: 'serving', sort_order: 0,
      optional: false, locked: true, adjustable: false, minimum_amount: 1, maximum_amount: 1,
      step_amount: 1, adjustment_role: 'none',
    }
  }

  const logAsPlanned = async (meal: TargetMeal): Promise<void> => {
    const existing = foodStore.meals.find((value) => value.local_date === today && value.source_planned_meal_id === meal.id)
    if (existing) return
    const item = await plannedFoodItem(meal)
    await foodStore.logMeal({
      slot: mealSlotFor(meal), name: meal.name, items: [item], sourcePlannedMealId: meal.id,
      loggedAs: 'planned', idempotencyKey: `planned:${profile?.user_id}:${today}:${meal.id}`,
    })
  }

  const snapshotFood = async (entry: LoggedFoodEntry): Promise<FoodRecord> => {
    const existing = entry.food_id ? foodStore.foods.find((food) => food.id === entry.food_id) : null
    if (existing) return existing
    return foodStore.savePrivateFood({
      name: entry.snapshot_name,
      names_i18n: { en: entry.snapshot_name },
      brand: entry.snapshot_brand,
      barcode: null,
      provider_product_id: null,
      external_image_url: null,
      package_quantity: null,
      nutrition_basis: entry.snapshot_nutrition_basis,
      preparation_state: entry.snapshot_preparation_state,
      kcal_100: entry.snapshot_kcal_100,
      protein_100: entry.snapshot_protein_100,
      carbs_100: entry.snapshot_carbs_100,
      fat_100: entry.snapshot_fat_100,
      fibre_100: entry.snapshot_fibre_100,
      sugar_100: entry.snapshot_sugar_100,
      saturated_fat_100: entry.snapshot_saturated_fat_100,
      salt_100: entry.snapshot_salt_100,
      serving_amount: null,
      serving_unit: null,
      serving_grams_or_ml: null,
      piece_grams_or_ml: null,
      provider_updated_at: null,
      confidence: 'user_entered',
    })
  }

  const editAndLog = async (row: PlannedMealTrackerRow): Promise<void> => {
    const meal = mealPlan.find((candidate) => candidate.id === row.id)
    if (!meal) return
    let items: ComposerFoodItem[] = []
    if (row.actual && row.entries.length > 0) {
      items = await Promise.all(row.entries.map(async (entry, index) => ({
        id: crypto.randomUUID(),
        food: await snapshotFood(entry),
        quantity: entry.quantity,
        unit: entry.unit,
        sort_order: index,
        optional: false,
        locked: false,
        adjustable: true,
        minimum_amount: null,
        maximum_amount: null,
        step_amount: entry.unit === 'piece' ? 1 : 5,
        adjustment_role: 'none' as const,
      })))
    } else {
      items = [await plannedFoodItem(meal)]
    }
    setPlannedComposer({
      meal,
      slot: mealSlotFor(meal),
      items,
      title: row.actual?.display_name ?? meal.name,
      replaceMealId: row.actual?.id ?? null,
    })
  }

  const yesterday = useMemo(
    () => format(subDays(new Date(`${today}T12:00:00`), 1), 'yyyy-MM-dd'),
    [today],
  )
  const yesterdayBlocks = useMemo(
    () => data.activity_logs
      .filter((log) => log.date === yesterday)
      .map((log) => blockFromActivityLog(log, catalog)),
    [catalog, data.activity_logs, yesterday],
  )
  const frequentPresets = useMemo<ActivityPreset[]>(() => {
    const grouped = new Map<string, { block: ActivityBlock; count: number; latest: string }>()
    for (const log of data.activity_logs) {
      if (log.date >= today || log.source !== 'manual') continue
      const block = blockFromActivityLog(log, catalog)
      const signature = [
        block.typeId,
        block.quantity,
        block.durationMin ?? '',
        block.distanceKm ?? '',
        block.steps ?? '',
        block.watchKcal ?? '',
      ].join(':')
      const existing = grouped.get(signature)
      grouped.set(signature, {
        block,
        count: (existing?.count ?? 0) + 1,
        latest: existing?.latest && existing.latest > log.date ? existing.latest : log.date,
      })
    }
    return [...grouped.values()]
      .sort((a, b) => b.count - a.count || b.latest.localeCompare(a.latest))
      .slice(0, 4)
      .map(({ block }) => {
        const type = catalog.get(block.typeId)
        return {
          label: `${blockSummary(block, catalog)} ${type?.shortName ?? 'activity'}`,
          typeId: block.typeId,
          patch: {
            quantity: block.quantity,
            durationMin: block.durationMin,
            distanceKm: block.distanceKm,
            steps: block.steps,
            watchKcal: block.watchKcal,
          },
        }
      })
  }, [catalog, data.activity_logs, today])

  const calibration = useMemo(
    () => profile
      ? calibrateActivityK(
          data.daily_logs.map((log) => ({
            date: log.date,
            intakeKcal: log.kcal,
            morningWeightKg: log.weight_kg,
            predictedTdee: log.estimated_tdee,
          })),
          profile.calibration_k,
        )
      : null,
    [data.daily_logs, profile],
  )

  useEffect(() => {
    if (!profile || !calibration?.eligible || calibration.observedTdee == null || calibration.predictedTdee == null) return
    if (Math.abs(calibration.nextK - profile.calibration_k) < 0.0005) return
    const last = profile.calibration_history.at(-1)
    if (last) {
      const elapsed = differenceInCalendarDays(
        new Date(`${today}T12:00:00`),
        new Date(last.applied_at),
      )
      if (elapsed < 7) return
    }
    setProfile({
      calibration_k: calibration.nextK,
      calibration_history: [
        ...profile.calibration_history,
        {
          applied_at: new Date().toISOString(),
          previous_k: calibration.previousK,
          next_k: calibration.nextK,
          observed_tdee: calibration.observedTdee,
          predicted_tdee: calibration.predictedTdee,
          sample_days: 14,
        },
      ].slice(-52),
    })
    toast('Activity engine calibrated from your last two weeks', 'ok')
  }, [calibration, profile, setProfile, toast, today])

  /* Index today's check-offs once. A toggle updates the Set on the next data
     render without rescanning the full history for every visible pill. */
  const todayMealIds = useMemo(
    () => new Set(data.meal_logs.filter((log) => log.date === today).map((log) => log.meal_id)),
    [data.meal_logs, today],
  )
  const todayLoggedMeals = useMemo(
    () => foodStore.mealsForDate(today),
    [foodStore, today],
  )
  const consumedMeals = useMemo(
    () => reconcileConsumedMeals(todayLoggedMeals, mealPlan, todayMealIds),
    [mealPlan, todayLoggedMeals, todayMealIds],
  )
  const consumed = useMemo(() => aggregateConsumedMeals(consumedMeals), [consumedMeals])
  const actualByPlannedMeal = useMemo(() => {
    const result = new Map<string, (typeof todayLoggedMeals)[number]>()
    for (const actual of todayLoggedMeals) {
      if (!actual.source_planned_meal_id) continue
      const previous = result.get(actual.source_planned_meal_id)
      if (!previous || previous.updated_at.localeCompare(actual.updated_at) < 0) result.set(actual.source_planned_meal_id, actual)
    }
    return result
  }, [todayLoggedMeals])
  const plannedRows = useMemo<PlannedMealTrackerRow[]>(() => mealPlan
    .slice()
    .sort((a, b) => a.time.localeCompare(b.time))
    .map((meal) => {
      const actual = actualByPlannedMeal.get(meal.id) ?? null
      return {
        id: meal.id,
        time: meal.time,
        name: meal.name,
        foods: meal.foods,
        kcal: meal.kcal,
        protein_g: meal.protein_g,
        carbs_g: meal.carbs_g,
        fat_g: meal.fat_g,
        done: todayMealIds.has(meal.id) || actual != null,
        actual,
        entries: actual ? foodStore.entries.filter((entry) => entry.meal_id === actual.id).sort((a, b) => a.sort_order - b.sort_order) : [],
      }
    }), [actualByPlannedMeal, foodStore.entries, mealPlan, todayMealIds])
  const todaySupplementIds = useMemo(
    () => new Set(data.supplement_logs.filter((log) => log.date === today).map((log) => log.supplement_id)),
    [data.supplement_logs, today],
  )

  /* Keep the daily record—the nutrition brain consumed by Avatar, reports and
     history—in lockstep with the reconciled ledger. This also repairs legacy
     days where checkmarks existed before structured meal snapshots did. */
  useEffect(() => {
    if (!profile) return
    const existing = data.daily_logs.find((log) => log.date === today)
    const structured = consumedMeals.length > 0
    const wasManual = existing?.nutrition_source !== 'structured'
    const next: DailyLog = {
      ...emptyDailyLog(today, profile.user_id),
      ...existing,
      manual_kcal: wasManual ? existing?.kcal ?? existing?.manual_kcal ?? null : existing?.manual_kcal ?? null,
      manual_protein_g: wasManual ? existing?.protein_g ?? existing?.manual_protein_g ?? null : existing?.manual_protein_g ?? null,
      manual_carbs_g: wasManual ? existing?.carbs_g ?? existing?.manual_carbs_g ?? null : existing?.manual_carbs_g ?? null,
      manual_fat_g: wasManual ? existing?.fat_g ?? existing?.manual_fat_g ?? null : existing?.manual_fat_g ?? null,
      kcal: structured ? consumed.kcal : existing?.manual_kcal ?? null,
      protein_g: structured ? consumed.protein_g : existing?.manual_protein_g ?? null,
      carbs_g: structured ? consumed.carbs_g : existing?.manual_carbs_g ?? null,
      fat_g: structured ? consumed.fat_g : existing?.manual_fat_g ?? null,
      nutrition_source: structured ? 'structured' : 'manual',
    }
    const unchanged = existing
      && existing.kcal === next.kcal
      && existing.protein_g === next.protein_g
      && existing.carbs_g === next.carbs_g
      && existing.fat_g === next.fat_g
      && existing.nutrition_source === next.nutrition_source
      && existing.manual_kcal === next.manual_kcal
      && existing.manual_protein_g === next.manual_protein_g
      && existing.manual_carbs_g === next.manual_carbs_g
      && existing.manual_fat_g === next.manual_fat_g
    if (!unchanged) upsert('daily_logs', next)
  }, [consumed.carbs_g, consumed.fat_g, consumed.kcal, consumed.protein_g, consumedMeals.length, data.daily_logs, profile, today, upsert])

  /* Meal check-offs for today */
  const toggleMeal = async (row: PlannedMealTrackerRow): Promise<void> => {
    const meal = mealPlan.find((candidate) => candidate.id === row.id)
    if (!meal || !profile) return
    const existingCheck = data.meal_logs.find((log) => log.date === today && log.meal_id === meal.id)
    const actualMeals = foodStore.meals.filter((actual) => actual.local_date === today && actual.source_planned_meal_id === meal.id)
    if (row.done) {
      for (const actual of actualMeals) await foodStore.deleteMeal(actual.id)
      if (existingCheck) remove('meal_logs', existingCheck.id)
      toast(`${meal.name} reopened`, 'ok')
      return
    }
    await logAsPlanned(meal)
    if (!existingCheck) {
      upsert('meal_logs', {
        id: crypto.randomUUID(),
        user_id: profile.user_id,
        date: today,
        meal_id: meal.id,
        checked_at: new Date().toISOString(),
      })
    }
    toast(`${meal.name} logged as planned`, 'ok')
  }

  /* Supplements resolved to today's clock and grouped */
  const trainingTime = profile?.training_time ?? '19:00'
  const nowMin = new Date().getHours() * 60 + new Date().getMinutes()
  const isTrainingDay = true // every weekday has a session in these programs
  const groups = useMemo(() => {
    const map = new Map<string, { time: number; items: Supplement[] }>()
    for (const s of [...data.supplements].sort((a, b) => a.sort_order - b.sort_order)) {
      if (s.training_days_only && !isTrainingDay) continue
      const t = resolveSupplementTime(s, trainingTime)
      const g = map.get(s.group_label) ?? { time: t, items: [] }
      g.items.push(s)
      map.set(s.group_label, g)
    }
    return [...map.entries()]
      .map(([label, g]) => ({ label, ...g }))
      .sort((a, b) => a.time - b.time)
  }, [data.supplements, trainingTime, isTrainingDay])

  const supDone = (id: string): boolean => todaySupplementIds.has(id)
  const toggleSup = (id: string): void => {
    const existing = data.supplement_logs.find((l) => l.date === today && l.supplement_id === id)
    if (existing) remove('supplement_logs', existing.id)
    else
      upsert('supplement_logs', {
        id: crypto.randomUUID(),
        user_id: profile?.user_id ?? '',
        date: today,
        supplement_id: id,
        checked_at: new Date().toISOString(),
      })
  }

  const enableNotifications = async (): Promise<void> => {
    const ok = await ensurePermission()
    if (ok) {
      setSettings({ notifications_on: true })
      toast('Meal and supplement reminders on', 'ok')
    } else {
      toast('Notifications blocked by the browser')
    }
  }

  if (!profile || !targets || !quickTargets || !activityEstimate) return null

  const persistActivityBlocks = (nextBlocks: ActivityBlock[]): void => {
    const nextIds = new Set(nextBlocks.map((block) => block.id))
    for (const existing of todayActivityLogs) {
      if (!nextIds.has(existing.id)) remove('activity_logs', existing.id)
    }
    for (const block of nextBlocks) {
      const existing = todayActivityLogs.find((log) => log.id === block.id)
      upsert('activity_logs', activityLogFromBlock(block, profile, today, catalog, existing))
    }

    const nextEstimate = estimateActivityDay(profile, nextBlocks, catalog)
    const mode = nextBlocks.length > 0 ? 'precise' : 'quick'
    const estimatedTdee = mode === 'precise' ? nextEstimate.tdee : quickTargets.tdee
    const existingDay = data.daily_logs.find((log) => log.date === today)
    upsert('daily_logs', {
      ...emptyDailyLog(today, profile.user_id),
      ...existingDay,
      activity_mode: mode,
      estimated_tdee: estimatedTdee,
      computed_pal: Math.round((estimatedTdee / nextEstimate.bmr) * 100) / 100,
    })
  }

  const allActivityFinal = activityBlocks.length > 0 && activityBlocks.every((block) => block.reconciled)
  const reconcileActivities = (): void => {
    persistActivityBlocks(activityBlocks.map((block) => ({ ...block, reconciled: true })))
    toast('Today’s activity plan is reconciled', 'ok')
  }

  const adjustActivities = (): void => {
    const target = document.getElementById('today-activities')
    const disclosure = target?.closest('details')
    if (disclosure) disclosure.open = true
    window.requestAnimationFrame(() => target?.scrollIntoView({ behavior: 'smooth', block: 'start' }))
  }

  const num = 'font-mono font-bold text-ink'
  const selectedDateObject = new Date(selectedLogDate + 'T12:00:00')
  const selectedMealIds = new Set(
    data.meal_logs.filter((log) => log.date === selectedLogDate).map((log) => log.meal_id),
  )
  const selectedLoggedMeals = foodStore.mealsForDate(selectedLogDate)
  const selectedConsumedMeals = reconcileConsumedMeals(selectedLoggedMeals, mealPlan, selectedMealIds)
  const selectedConsumed = aggregateConsumedMeals(selectedConsumedMeals)
  const selectedHasConsumedNutrition = selectedConsumedMeals.length > 0
  const selectedEffectiveMealIds = new Set([
    ...selectedMealIds,
    ...selectedLoggedMeals.map((meal) => meal.source_planned_meal_id).filter((id): id is string => id != null),
  ])
  const selectedSupplementIds = new Set(
    data.supplement_logs
      .filter((log) => log.date === selectedLogDate)
      .map((log) => log.supplement_id),
  )
  const selectedActivityBlocks = data.activity_logs
    .filter((log) => log.date === selectedLogDate)
    .map((log) => blockFromActivityLog(log, catalog))
  const plannedTrainingOnSelectedDate = data.program_days.some(
    (day) => day.weekday === getISODay(selectedDateObject),
  )
  const expectedSupplements = [...data.supplements]
    .filter((supplement) => !supplement.training_days_only || plannedTrainingOnSelectedDate)
    .sort((a, b) => a.sort_order - b.sort_order)
  const missingSupplements = expectedSupplements.filter(
    (supplement) => !selectedSupplementIds.has(supplement.id),
  )
  const selectedIsPast = selectedLogDate < today

  return (
    <div className="mx-auto w-full max-w-3xl">
      <SectionHeader
        accent={amber}
        title="Nutrition"
        eyebrow={format(new Date(`${today}T12:00:00`), 'EEEE, d MMMM yyyy')}
        subtitle="What you ate, what remains, and one clear next action"
        right={
          !data.settings?.notifications_on ? (
            <button
              type="button"
              onClick={() => void enableNotifications()}
              className="glass rounded-full px-3 py-1.5 text-xs font-bold text-ink-soft"
            >
              Enable reminders
            </button>
          ) : undefined
        }
      />

      <div className="mb-4 flex justify-end">
        <Link to="/progress" state={{ from: '/nutrition' }} className="glass rounded-full px-3 py-2 text-[11px] font-bold text-violet-700">◫ Private visual progress</Link>
      </div>

      <div className="space-y-5">
        <ActualFoodTracker
          target={{ kcal: targets.kcal, protein_g: targets.protein_g, carbs_g: targets.carbs_g, fat_g: targets.fat_g }}
          consumed={consumed}
          consumedMeals={consumedMeals}
          plannedRows={plannedRows}
          activityLabel={activeDayLabel}
          trainingToday={isTrainingDay}
          onTogglePlanned={toggleMeal}
          onEditPlanned={editAndLog}
        />

        <details className="glass group rounded-3xl p-3 sm:p-4">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-1 text-left">
            <div><p className="font-display text-sm font-bold text-ink">Activity & nutrition targets</p><p className="mt-0.5 text-[10px] font-medium text-ink-soft">{targets.kcal} kcal · {activeDayLabel} · {GOALS[profile.goal].label}</p></div>
            <span className="grid h-8 w-8 place-items-center rounded-full bg-white/65 text-lg text-ink-soft transition group-open:rotate-45">+</span>
          </summary>
          <div className="mt-4 space-y-4 border-t border-ink/7 pt-4">
        <TodaysActivities
          profile={profile}
          activityTypes={data.activity_types}
          blocks={activityBlocks}
          estimate={activityEstimate}
          quickTdee={quickTargets.tdee}
          quickLevel={profile.activity_level}
          frequentPresets={frequentPresets}
          yesterdayBlocks={yesterdayBlocks}
          onChange={persistActivityBlocks}
        />

        {/* -------- Targets -------- */}
        <GlassCard accent={amber} className="p-5 sm:p-6">
          <div className="flex items-start justify-between">
            <h2 className="font-display text-lg font-bold text-ink">Daily targets</h2>
            <AccentChip accent={amber}>
              {preciseMode ? `PRECISE · ${GOALS[profile.goal].label.toUpperCase()}` : GOALS[profile.goal].label.toUpperCase()}
            </AccentChip>
          </div>

          <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div>
              <p className="text-[11px] font-semibold tracking-wide text-ink-soft uppercase">Calories</p>
              <p className={`${num} text-3xl`} style={{ color: amber.deep }}>
                {targets.kcal}
              </p>
            </div>
            <div>
              <p className="text-[11px] font-semibold tracking-wide text-ink-soft uppercase">Protein</p>
              <p className={`${num} text-3xl`}>{targets.protein_g}g</p>
            </div>
            <div>
              <p className="text-[11px] font-semibold tracking-wide text-ink-soft uppercase">Fat</p>
              <p className={`${num} text-3xl`}>{targets.fat_g}g</p>
            </div>
            <div>
              <p className="text-[11px] font-semibold tracking-wide text-ink-soft uppercase">Carbs</p>
              <p className={`${num} text-3xl`}>{targets.carbs_g}g</p>
            </div>
          </div>

          <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-2 border-t border-ink/8 pt-4 text-sm">
            <p className="font-medium text-ink-soft">
              BMR Mifflin-St Jeor: <span className={num}>{targets.bmrMifflin}</span>
            </p>
            <p className="font-medium text-ink-soft">
              Katch-McArdle: <span className={num}>{targets.bmrKatch}</span>
              <button
                type="button"
                onClick={() => setShowBmrInfo((v) => !v)}
                className="ml-1.5 inline-flex h-4.5 w-4.5 items-center justify-center rounded-full text-[10px] font-bold text-white align-middle"
                style={{ background: amber.gradient }}
                aria-label="Why Katch-McArdle"
              >
                i
              </button>
            </p>
            <p className="font-medium text-ink-soft">
              TDEE: <span className={num}>{targets.tdee}</span>
            </p>
          </div>
          {showBmrInfo && (
            <motion.p
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              className="mt-2 rounded-xl px-3 py-2 text-[13px] leading-relaxed font-medium text-ink-soft"
              style={{ background: amber.wash }}
            >
              Katch-McArdle computes from lean body mass instead of total weight, so measured fat
              mass does not inflate the estimate. Your current {profile.body_fat_pct}% body-fat
              entry produces the reference TDEE above. APEX uses that estimate with your selected activity and goal to build the live target.
            </motion.p>
          )}

          <div className="mt-4 flex flex-wrap gap-2">
            {Object.entries(ACTIVITY_MULTIPLIERS).map(([key, v]) => (
              <button
                key={key}
                type="button"
                disabled={preciseMode}
                onClick={() => setProfile({ activity_level: key as ActivityLevel })}
                className="rounded-full px-3 py-1.5 text-xs font-bold transition-all disabled:cursor-not-allowed disabled:grayscale disabled:opacity-35"
                style={
                  profile.activity_level === key
                    ? { background: amber.gradient, color: '#fff' }
                    : { background: 'rgba(255,255,255,0.6)', color: '#55555f', border: '1px solid rgba(26,26,34,0.08)' }
                }
              >
                {v.label}
              </button>
            ))}
          </div>
          {preciseMode && (
            <p className="mt-2 text-[11px] font-semibold text-ink-faint">
              Computed from your day. Clear every activity block to return to Quick Mode.
            </p>
          )}
          <div className="mt-2 flex flex-wrap gap-2">
            {Object.entries(GOALS).map(([key, v]) => (
              <button
                key={key}
                type="button"
                onClick={() => setProfile({ goal: key as Goal })}
                className="rounded-full px-3 py-1.5 text-xs font-bold transition-all"
                style={
                  profile.goal === key
                    ? { background: amber.gradient, color: '#fff' }
                    : { background: 'rgba(255,255,255,0.6)', color: '#55555f', border: '1px solid rgba(26,26,34,0.08)' }
                }
              >
                {v.label}
              </button>
            ))}
          </div>
        </GlassCard>
          </div>
        </details>

        {/* -------- Supplement timeline -------- */}
        <details className="glass group rounded-3xl p-4">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3">
            <div><p className="font-display text-sm font-bold text-ink">Supplement stack</p><p className="mt-0.5 text-[10px] font-medium text-ink-soft">{todaySupplementIds.size}/{data.supplements.length} checked today</p></div>
            <span className="grid h-8 w-8 place-items-center rounded-full bg-white/65 text-lg text-ink-soft transition group-open:rotate-45">+</span>
          </summary>
          <div className="mt-4 border-t border-ink/7 pt-4">
          <div className="mb-3 flex items-center justify-end">
            <div className="flex items-center gap-2 text-xs font-semibold text-ink-soft">
              Training at
              <input
                type="time"
                value={trainingTime}
                onChange={(e) => setProfile({ training_time: e.target.value })}
                className="glass rounded-lg px-2 py-1 font-mono text-xs font-bold text-ink"
              />
            </div>
          </div>
          <div className="relative space-y-3 pl-6">
            <div
              className="absolute top-2 bottom-2 left-[9px] w-0.5 rounded-full"
              style={{ background: `linear-gradient(180deg, ${amber.soft}, ${amber.bright})`, opacity: 0.4 }}
              aria-hidden
            />
            {groups.map((group) => {
              const active = nowMin >= group.time - 10 && nowMin <= group.time + 50
              const allDone = group.items.every((s) => supDone(s.id))
              return (
                <div key={group.label} className="relative">
                  <span
                    className="absolute top-4 -left-6 h-3 w-3 rounded-full border-2 border-white"
                    style={{ background: allDone ? amber.gradient : 'rgba(26,26,34,0.15)' }}
                    aria-hidden
                  />
                  <GlassCard accent={amber} breathe={active} className="defer-paint p-4">
                    <div className="flex items-center justify-between">
                      <p className="font-display text-sm font-bold text-ink">{group.label}</p>
                      <span className="font-mono text-xs font-bold" style={{ color: amber.deep }}>
                        {hmOf(group.time)}
                        {active && ' · now'}
                      </span>
                    </div>
                    <div className="mt-2.5 flex flex-wrap gap-2">
                      {group.items.map((s) => {
                        const done = supDone(s.id)
                        return (
                          <button
                            key={s.id}
                            type="button"
                            onClick={() => toggleSup(s.id)}
                            className="rounded-full px-3 py-1.5 text-xs font-bold transition-all active:scale-95"
                            style={
                              done
                                ? { background: amber.gradient, color: '#fff' }
                                : {
                                    background: 'rgba(255,255,255,0.65)',
                                    color: '#3f3f48',
                                    border: `1px solid ${amber.glowSoft}`,
                                  }
                            }
                          >
                            {s.name}
                            {s.dose ? ` ${s.dose}` : ''}
                            {s.training_days_only ? ' (training days)' : ''}
                          </button>
                        )
                      })}
                    </div>
                  </GlassCard>
                </div>
              )
            })}
          </div>
          </div>
        </details>

        {/* -------- Evening daily log -------- */}
        <GlassCard accent={amber} className="defer-paint-tall p-5 sm:p-6">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <h2 className="font-display text-lg font-bold text-ink">Daily log</h2>
              <span className="font-mono text-xs font-bold text-ink-faint">
                {format(selectedDateObject, 'EEEE, d MMMM yyyy')}
              </span>
            </div>
            {selectedLogDate !== today && (
              <button
                type="button"
                onClick={() => {
                  setSelectedLogDate(today)
                  setLogMonth(startOfMonth(new Date()))
                }}
                className="rounded-full px-3 py-1.5 text-xs font-bold text-white"
                style={{ background: amber.gradient }}
              >
                Back to today
              </button>
            )}
          </div>
          <p className="mt-1 text-[13px] font-medium text-ink-soft">
            {selectedLogDate === today
              ? 'Twenty seconds before bed. This feeds the Health stat.'
              : 'Review or correct this past day. Changes sync to the same daily record.'}
          </p>
          {selectedLogDate === today && preciseMode && (
            <div className="mt-4 rounded-2xl border border-amber-500/15 p-4" style={{ background: amber.wash }}>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <p className="font-display text-sm font-bold text-ink">Did the day go as planned?</p>
                  <p className="mt-0.5 text-[10px] font-medium text-ink-soft">
                    {activityEstimate.tdee.toLocaleString()} kcal TDEE · PAL {activityEstimate.pal.toFixed(2)} · {PAL_LABELS[activityEstimate.level]}
                  </p>
                </div>
                {allActivityFinal ? (
                  <span className="rounded-full bg-emerald/10 px-3 py-1.5 text-[10px] font-bold text-emerald">Reconciled ✓</span>
                ) : (
                  <div className="flex gap-2">
                    <button type="button" onClick={adjustActivities} className="rounded-xl bg-white/65 px-3 py-2 text-[10px] font-bold text-ink-soft shadow-sm">
                      Adjust blocks
                    </button>
                    <button type="button" onClick={reconcileActivities} className="rounded-xl px-3 py-2 text-[10px] font-bold text-white shadow-sm" style={{ background: amber.gradient }}>
                      Yes, finalize
                    </button>
                  </div>
                )}
              </div>
            </div>
          )}
          {selectedLog.nutrition_source === 'structured' && (
            <p className="mt-4 rounded-xl bg-amber-500/8 px-3 py-2 text-[11px] font-semibold text-amber-800">
              Calories and macros are calculated from your actual food entries. Delete or replace a logged meal above to change them. Water and weight stay editable here.
            </p>
          )}
          <div className="mt-4 space-y-4">
            {(
              [
                { label: 'Calories', key: 'kcal', step: 50, unit: 'kcal', values: week.kcal },
                { label: 'Protein', key: 'protein_g', step: 5, unit: 'g', values: week.protein },
                { label: 'Fat', key: 'fat_g', step: 5, unit: 'g', values: week.fat },
                { label: 'Carbs', key: 'carbs_g', step: 10, unit: 'g', values: week.carbs },
              ] as const
            ).map((row) => (
              <div key={row.key} className="flex items-center justify-between gap-3">
                <div className="w-20">
                  <p className="text-sm font-bold text-ink">{row.label}</p>
                  <Sparkline values={row.values} accent={amber} width={72} height={22} />
                </div>
                {selectedLog.nutrition_source === 'structured' ? (
                  <div className="min-w-[9.5rem] rounded-2xl bg-white/70 px-4 py-3 text-center font-mono text-xl font-bold text-ink">
                    {(selectedLog[row.key] as number | null) ?? 0}<span className="ml-1 text-xs text-ink-soft">{row.unit}</span>
                  </div>
                ) : (
                  <Stepper
                    accent={amber}
                    value={(selectedLog[row.key] as number | null) ?? 0}
                    step={row.step}
                    unit={row.unit}
                    onChange={(v) => patchLog({ [row.key]: v, [`manual_${row.key}`]: v, nutrition_source: 'manual' })}
                  />
                )}
              </div>
            ))}
            <div className="flex items-center justify-between gap-3">
              <div className="w-20">
                <p className="text-sm font-bold text-ink">Water</p>
                <Sparkline values={week.water} accent={amber} width={72} height={22} />
              </div>
              <Stepper
                accent={amber}
                value={selectedLog.water_l}
                step={0.25}
                unit="L"
                onChange={(v) => patchLog({ water_l: v })}
              />
            </div>
            <label className="flex items-center justify-between gap-3">
              <span>
                <span className="block text-sm font-bold text-ink">Morning weight</span>
                <span className="block text-[10px] font-medium text-ink-faint">Optional · feeds the 7-day calibration EMA</span>
              </span>
              <span className="glass flex items-center rounded-xl px-3 py-2">
                <input
                  type="number"
                  inputMode="decimal"
                  min="25"
                  max="300"
                  step="0.1"
                  value={selectedLog.weight_kg ?? ''}
                  placeholder={String(profile.weight_kg)}
                  onChange={(event) => patchLog({ weight_kg: event.target.value === '' ? null : Number(event.target.value) })}
                  className="w-16 bg-transparent text-right font-mono text-base font-bold text-ink outline-none"
                  aria-label="Morning weight in kilograms"
                />
                <span className="ml-1 text-xs font-semibold text-ink-soft">kg</span>
              </span>
            </label>
          </div>
          <div className="mt-4 border-t border-ink/8 pt-3 text-xs font-medium text-ink-soft">
            Water is shared with the workout calendars. Log it wherever you are.
          </div>

          <NutritionLogCalendar
            month={logMonth}
            selectedDate={selectedLogDate}
            today={today}
            data={data}
            accent={amber}
            onMonthChange={setLogMonth}
            onSelectDate={setSelectedLogDate}
          />

          <div className="mt-4 rounded-2xl p-4" style={{ background: 'rgba(255,255,255,0.48)' }}>
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h3 className="font-display text-sm font-bold text-ink">
                {selectedLogDate === today ? "Today's record" : format(selectedDateObject, 'd MMMM')} at a glance
              </h3>
              <span className="font-mono text-[11px] font-bold text-ink-faint">
                {selectedEffectiveMealIds.size}/{data.meals.length} meals · {selectedSupplementIds.size}/{expectedSupplements.length} supplements
              </span>
            </div>

            <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-5">
              {(
                [
                  ['Calories', selectedHasConsumedNutrition ? selectedConsumed.kcal : selectedLog.kcal, 'kcal'],
                  ['Protein', selectedHasConsumedNutrition ? selectedConsumed.protein_g : selectedLog.protein_g, 'g'],
                  ['Fat', selectedHasConsumedNutrition ? selectedConsumed.fat_g : selectedLog.fat_g, 'g'],
                  ['Carbs', selectedHasConsumedNutrition ? selectedConsumed.carbs_g : selectedLog.carbs_g, 'g'],
                  ['Water', selectedLog.water_l || null, 'L'],
                ] as const
              ).map(([label, value, unit]) => (
                <div key={label} className="rounded-xl px-2.5 py-2" style={{ background: 'rgba(255,255,255,0.62)' }}>
                  <p className="text-[10px] font-bold tracking-wide text-ink-faint uppercase">{label}</p>
                  <p className="font-mono text-sm font-bold text-ink">{value == null ? 'Not logged' : `${value}${unit}`}</p>
                </div>
              ))}
            </div>

            <div className="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4">
              {[
                ['Activity mode', selectedLog.activity_mode === 'precise' ? 'Precise' : 'Quick'],
                ['Estimated TDEE', selectedLog.estimated_tdee == null ? 'Not logged' : `${selectedLog.estimated_tdee} kcal`],
                ['PAL', selectedLog.computed_pal == null ? 'Not logged' : Number(selectedLog.computed_pal).toFixed(2)],
                ['Morning weight', selectedLog.weight_kg == null ? 'Not logged' : `${selectedLog.weight_kg} kg`],
              ].map(([label, value]) => (
                <div key={label} className="rounded-xl px-2.5 py-2" style={{ background: amber.wash }}>
                  <p className="text-[9px] font-bold tracking-wide text-ink-faint uppercase">{label}</p>
                  <p className="mt-0.5 font-mono text-xs font-bold text-ink">{value}</p>
                </div>
              ))}
            </div>

            {selectedActivityBlocks.length > 0 && (
              <div className="mt-4">
                <p className="text-xs font-bold tracking-wide text-ink-soft uppercase">Activities</p>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {selectedActivityBlocks.map((block) => {
                    const type = catalog.get(block.typeId)
                    return (
                      <span key={block.id} className="rounded-full px-2.5 py-1 text-[10px] font-semibold text-ink-soft" style={{ background: amber.wash }}>
                        {type?.shortName ?? 'Activity'} · {blockSummary(block, catalog)} · {Math.round(netKcalForBlock(block, profile.weight_kg, catalog))} kcal
                      </span>
                    )
                  })}
                </div>
              </div>
            )}

            <div className="mt-4">
              <p className="text-xs font-bold tracking-wide text-ink-soft uppercase">Meals</p>
              <div className="mt-2 space-y-1.5">
                {[...data.meals]
                  .sort((a, b) => a.time.localeCompare(b.time))
                  .map((meal) => {
                    const done = selectedEffectiveMealIds.has(meal.id)
                    const actual = selectedLoggedMeals
                      .filter((logged) => logged.source_planned_meal_id === meal.id)
                      .sort((a, b) => b.updated_at.localeCompare(a.updated_at))[0]
                    return (
                      <div key={meal.id} className="flex items-center justify-between gap-3 rounded-xl px-3 py-2" style={{ background: done ? 'rgba(16,185,129,0.09)' : selectedIsPast ? 'rgba(220,38,38,0.06)' : 'rgba(26,26,34,0.035)' }}>
                        <div className="min-w-0"><p className="truncate text-xs font-semibold text-ink"><span className="mr-2 font-mono text-ink-faint">{meal.time}</span>{actual?.logged_as === 'changed' ? actual.display_name : meal.name}</p>{actual?.logged_as === 'changed' && <p className="mt-0.5 truncate pl-12 text-[9px] font-medium text-ink-faint">Replaced {meal.name} · {actual.total_kcal} kcal</p>}</div>
                        <span className={`shrink-0 text-[11px] font-bold ${done ? 'text-emerald' : selectedIsPast ? 'text-crimson' : 'text-ink-faint'}`}>
                          {done ? 'Eaten ✓' : selectedIsPast ? 'Missed / not logged' : 'Not checked'}
                        </span>
                      </div>
                    )
                  })}
              </div>
            </div>

            <div className="mt-4">
              <div className="flex items-center justify-between gap-2">
                <p className="text-xs font-bold tracking-wide text-ink-soft uppercase">Supplements</p>
                {missingSupplements.length === 0 && (
                  <span className="text-[11px] font-bold text-emerald">All scheduled items logged ✓</span>
                )}
              </div>
              {missingSupplements.length > 0 && (
                <>
                  <p className={`mt-1 text-[11px] font-semibold ${selectedIsPast ? 'text-crimson' : 'text-ink-faint'}`}>
                    {selectedIsPast ? 'Missed or not logged:' : 'Still unchecked:'}
                  </p>
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {missingSupplements.map((supplement) => (
                      <span key={supplement.id} className="rounded-full px-2.5 py-1 text-[10px] font-semibold text-ink-soft" style={{ background: selectedIsPast ? 'rgba(220,38,38,0.07)' : amber.wash }}>
                        {supplement.name}{supplement.dose ? ` · ${supplement.dose}` : ''}
                      </span>
                    ))}
                  </div>
                </>
              )}
            </div>

            {selectedIsPast && (
              <p className="mt-4 text-[10.5px] leading-relaxed font-medium text-ink-faint">
                “Missed / not logged” means no completion was recorded for that item; the app does not assume whether it was intentionally skipped.
              </p>
            )}
          </div>
        </GlassCard>

        {/* Reminders toggle */}
        {data.settings && (
          <GlassCard accent={amber} className="flex items-center justify-between p-4">
            <div>
              <p className="text-sm font-bold text-ink">Meal + stack reminders</p>
              <p className="text-xs font-medium text-ink-soft">Fires while APEX is open in a tab</p>
            </div>
            <Toggle
              accent={amber}
              on={data.settings.notifications_on}
              onChange={(v) => {
                if (v) void enableNotifications()
                else setSettings({ notifications_on: false })
              }}
            />
          </GlassCard>
        )}
      </div>

      {plannedComposer && (
        <MealComposer
          slot={plannedComposer.slot}
          title={plannedComposer.title}
          initialItems={plannedComposer.items}
          plannedMealId={plannedComposer.meal.id}
          replaceMealId={plannedComposer.replaceMealId}
          adaptiveContext={{
            target: { kcal: targets.kcal, protein_g: targets.protein_g, carbs_g: targets.carbs_g, fat_g: targets.fat_g },
            consumed,
            activityLabel: activeDayLabel,
            trainingToday: isTrainingDay,
          }}
          onLogged={() => {
            const existing = data.meal_logs.find((log) => log.date === today && log.meal_id === plannedComposer.meal.id)
            if (!existing) upsert('meal_logs', {
              id: crypto.randomUUID(),
              user_id: profile.user_id,
              date: today,
              meal_id: plannedComposer.meal.id,
              checked_at: new Date().toISOString(),
            })
            toast(`${plannedComposer.title} logged`, 'ok')
          }}
          onClose={() => setPlannedComposer(null)}
        />
      )}
    </div>
  )
}
