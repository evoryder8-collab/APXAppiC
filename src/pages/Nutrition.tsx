import { useEffect, useMemo, useRef, useState } from 'react'
import { motion } from 'framer-motion'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { addDays, differenceInCalendarDays, format, parseISO, startOfMonth, subDays } from 'date-fns'
import { useStore } from '../store/AppStore'
import { ACCENTS } from '../lib/theme'
import {
  AccentChip,
  GlassCard,
  SectionHeader,
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
  type LoggedMeal,
  type MealSlot,
} from '../lib/food'
import { normalizeDailyLogIntegers } from '../lib/sync'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { canPasteSimpleDay, dayMealCopyIdempotencyKey, simpleDaySwipeOffset } from '../lib/simpleMode'

const amber = ACCENTS.amber
const calendarLegacyMealSelectionId = (mealId: string): string => `planned:${mealId}`

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
  const { language } = useLanguage()
  const tx = (value: string): string => translateInterfaceText(value, language)
  const foodStore = useFoodStore()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const requestedSection = searchParams.get('section')
  const requestedDate = searchParams.get('date')
  const returnToSimple = searchParams.get('return') === 'simple'
  const handledRequestedSection = useRef(false)
  const today = todayIso()
  const [selectedLogDate, setSelectedLogDate] = useState(() => requestedDate && /^\d{4}-\d{2}-\d{2}$/.test(requestedDate) ? requestedDate : today)
  const [logMonth, setLogMonth] = useState(() => startOfMonth(new Date()))
  const nutritionSwipeStart = useRef<{ x: number; y: number; blockedByLocalGesture: boolean } | null>(null)
  const selectedDateObject = useMemo(() => parseISO(selectedLogDate), [selectedLogDate])
  const profile = data.profile
  const catalog = useMemo(() => activityCatalogMap(data.activity_types), [data.activity_types])
  const selectedActivityLogs = useMemo(
    () => data.activity_logs.filter((log) => log.date === selectedLogDate),
    [data.activity_logs, selectedLogDate],
  )
  const activityBlocks = useMemo(
    () => selectedActivityLogs.map((log) => blockFromActivityLog(log, catalog)),
    [catalog, selectedActivityLogs],
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
  const [waterDraft, setWaterDraft] = useState('0')
  const [plannedComposer, setPlannedComposer] = useState<{
    meal: TargetMeal
    slot: MealSlot
    items: ComposerFoodItem[]
    title: string
    replaceMealId: string | null
  } | null>(null)
  const [calendarContextDate, setCalendarContextDate] = useState<string | null>(null)
  const [copiedDay, setCopiedDay] = useState<string | null>(null)
  const [pasteTarget, setPasteTarget] = useState<string | null>(null)
  const [selectingCopyMeals, setSelectingCopyMeals] = useState(false)
  const [selectedCopyMealIds, setSelectedCopyMealIds] = useState<Set<string>>(new Set())
  const [calendarBusy, setCalendarBusy] = useState(false)
  const storedSelectedLog = data.daily_logs.find((d) => d.date === selectedLogDate)
  const selectedLog: DailyLog = {
    ...emptyDailyLog(selectedLogDate, profile?.user_id ?? 'local'),
    ...storedSelectedLog,
  }

  const patchLog = (patch: Partial<DailyLog>): void => {
    upsert('daily_logs', { ...selectedLog, ...patch })
  }

  useEffect(() => {
    setWaterDraft(String(selectedLog.water_l ?? 0))
  }, [selectedLog.water_l, selectedLogDate])

  useEffect(() => {
    if (handledRequestedSection.current || (requestedSection !== 'meals' && requestedSection !== 'supplements')) return
    handledRequestedSection.current = true
    window.requestAnimationFrame(() => {
      const target = document.getElementById(`nutrition-${requestedSection}`)
      if (target instanceof HTMLDetailsElement) target.open = true
      target?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    })
  }, [requestedSection])

  const setWater = (value: number): void => {
    const next = Math.min(6, Math.max(0, Math.round(value * 100) / 100))
    setWaterDraft(String(next))
    patchLog({ water_l: next })
  }

  const commitWaterDraft = (): void => {
    const parsed = Number(waterDraft.replace(',', '.'))
    if (!Number.isFinite(parsed)) {
      setWaterDraft(String(selectedLog.water_l ?? 0))
      return
    }
    setWater(parsed)
  }

  const activeDayLabel = preciseMode && activityEstimate
    ? PAL_LABELS[activityEstimate.level]
    : profile ? ACTIVITY_MULTIPLIERS[profile.activity_level].label : 'Adaptive'
  const mealPlan = useMemo(
    () => (targets ? buildTargetMealPlan(data.meals, targets, activeDayLabel) : []),
    [activeDayLabel, data.meals, targets],
  )
  const copiedMeals = useMemo(
    () => copiedDay ? foodStore.mealsForDate(copiedDay).slice().sort((left, right) => left.logged_at.localeCompare(right.logged_at)) : [],
    [copiedDay, foodStore],
  )
  const copiedLegacyChecks = useMemo(() => {
    if (!copiedDay) return []
    const structuredPlannedIds = new Set(copiedMeals.flatMap((meal) => meal.source_planned_meal_id ? [meal.source_planned_meal_id] : []))
    const unique = new Map<string, { selectionId: string; mealId: string; name: string; slot: MealSlot; kcal: number }>()
    for (const log of data.meal_logs.filter((candidate) => candidate.date === copiedDay)) {
      if (structuredPlannedIds.has(log.meal_id) || unique.has(log.meal_id)) continue
      const planned = mealPlan.find((meal) => meal.id === log.meal_id)
      unique.set(log.meal_id, {
        selectionId: calendarLegacyMealSelectionId(log.meal_id),
        mealId: log.meal_id,
        name: planned?.name ?? 'Planned meal',
        slot: planned ? mealSlotFor(planned) : 'snack',
        kcal: planned?.kcal ?? 0,
      })
    }
    return [...unique.values()]
  }, [copiedDay, copiedMeals, data.meal_logs, mealPlan])

  function mealSlotFor(meal: TargetMeal): MealSlot {
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
    const existing = foodStore.meals.find((value) => value.local_date === selectedLogDate && value.source_planned_meal_id === meal.id)
    if (existing) return
    const item = await plannedFoodItem(meal)
    await foodStore.logMeal({
      date: selectedLogDate, slot: mealSlotFor(meal), name: meal.name, items: [item], sourcePlannedMealId: meal.id,
      loggedAs: 'planned', idempotencyKey: `planned:${profile?.user_id}:${selectedLogDate}:${meal.id}`,
    })
  }

  const snapshotFood = async (entry: LoggedFoodEntry): Promise<FoodRecord> => {
    const existing = entry.food_id ? foodStore.foods.find((food) => food.id === entry.food_id) : null
    const frozenUnitSize = entry.quantity > 0 ? entry.equivalent_amount / entry.quantity : null
    if (existing) {
      return {
        ...existing,
        name: entry.snapshot_name,
        brand: entry.snapshot_brand,
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
        serving_grams_or_ml: entry.unit === 'serving' ? frozenUnitSize : existing.serving_grams_or_ml,
        piece_grams_or_ml: entry.unit === 'piece' ? frozenUnitSize : existing.piece_grams_or_ml,
      }
    }
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
      serving_amount: entry.unit === 'serving' ? 1 : null,
      serving_unit: entry.unit === 'serving' ? 'serving' : null,
      serving_grams_or_ml: entry.unit === 'serving' ? frozenUnitSize : null,
      piece_grams_or_ml: entry.unit === 'piece' ? frozenUnitSize : null,
      provider_updated_at: null,
      confidence: 'user_entered',
    })
  }

  const loggedMealItems = async (loggedMeal: LoggedMeal): Promise<ComposerFoodItem[]> => Promise.all(
    foodStore.entries
      .filter((entry) => entry.meal_id === loggedMeal.id)
      .sort((left, right) => left.sort_order - right.sort_order)
      .map(async (entry, index) => ({
        id: crypto.randomUUID(),
        food: await snapshotFood(entry),
        quantity: entry.quantity,
        unit: entry.unit,
        sort_order: index,
        optional: false,
        locked: true,
        adjustable: false,
        minimum_amount: null,
        maximum_amount: null,
        step_amount: entry.unit === 'piece' ? 1 : 5,
        adjustment_role: 'none' as const,
      })),
  )

  const editAndLog = async (row: PlannedMealTrackerRow): Promise<void> => {
    const meal = mealPlan.find((candidate) => candidate.id === row.id)
    if (!meal) return
    let items: ComposerFoodItem[] = []
    if (row.actual && row.entries.length > 0) {
      items = await loggedMealItems(row.actual)
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
    () => format(subDays(selectedDateObject, 1), 'yyyy-MM-dd'),
    [selectedDateObject],
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
      if (log.date >= selectedLogDate || log.source !== 'manual') continue
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
  }, [catalog, data.activity_logs, selectedLogDate])

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

  /* Index the selected day's check-offs once. A toggle updates the Set on the next data
     render without rescanning the full history for every visible pill. */
  const dayMealIds = useMemo(
    () => new Set(data.meal_logs.filter((log) => log.date === selectedLogDate).map((log) => log.meal_id)),
    [data.meal_logs, selectedLogDate],
  )
  const dayLoggedMeals = useMemo(
    () => foodStore.mealsForDate(selectedLogDate),
    [foodStore, selectedLogDate],
  )
  const consumedMeals = useMemo(
    () => reconcileConsumedMeals(dayLoggedMeals, mealPlan, dayMealIds),
    [dayLoggedMeals, dayMealIds, mealPlan],
  )
  const consumed = useMemo(() => aggregateConsumedMeals(consumedMeals), [consumedMeals])
  const actualByPlannedMeal = useMemo(() => {
    const result = new Map<string, (typeof dayLoggedMeals)[number]>()
    for (const actual of dayLoggedMeals) {
      if (!actual.source_planned_meal_id) continue
      const previous = result.get(actual.source_planned_meal_id)
      if (!previous || previous.updated_at.localeCompare(actual.updated_at) < 0) result.set(actual.source_planned_meal_id, actual)
    }
    return result
  }, [dayLoggedMeals])
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
        done: dayMealIds.has(meal.id) || actual != null,
        actual,
        entries: actual ? foodStore.entries.filter((entry) => entry.meal_id === actual.id).sort((a, b) => a.sort_order - b.sort_order) : [],
      }
    }), [actualByPlannedMeal, dayMealIds, foodStore.entries, mealPlan])
  const daySupplementIds = useMemo(
    () => new Set(data.supplement_logs.filter((log) => log.date === selectedLogDate).map((log) => log.supplement_id)),
    [data.supplement_logs, selectedLogDate],
  )

  /* Keep the daily record, the nutrition brain consumed by Avatar, reports and
     history, in lockstep with the reconciled ledger. This also repairs legacy
     days where checkmarks existed before structured meal snapshots did. */
  useEffect(() => {
    if (!profile) return
    const existing = data.daily_logs.find((log) => log.date === selectedLogDate)
    const structured = consumedMeals.length > 0
    const wasManual = existing?.nutrition_source !== 'structured'
    const next = normalizeDailyLogIntegers<DailyLog>({
      ...emptyDailyLog(selectedLogDate, profile.user_id),
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
    })
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
  }, [consumed.carbs_g, consumed.fat_g, consumed.kcal, consumed.protein_g, consumedMeals.length, data.daily_logs, profile, selectedLogDate, upsert])

  /* Meal check-offs for the selected day */
  const toggleMeal = async (row: PlannedMealTrackerRow): Promise<void> => {
    const meal = mealPlan.find((candidate) => candidate.id === row.id)
    if (!meal || !profile) return
    const existingCheck = data.meal_logs.find((log) => log.date === selectedLogDate && log.meal_id === meal.id)
    const actualMeals = foodStore.meals.filter((actual) => actual.local_date === selectedLogDate && actual.source_planned_meal_id === meal.id)
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
        date: selectedLogDate,
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

  const supDone = (id: string): boolean => daySupplementIds.has(id)
  const toggleSup = (id: string): void => {
    const existing = data.supplement_logs.find((l) => l.date === selectedLogDate && l.supplement_id === id)
    if (existing) remove('supplement_logs', existing.id)
    else
      upsert('supplement_logs', {
        id: crypto.randomUUID(),
        user_id: profile?.user_id ?? '',
        date: selectedLogDate,
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

  const beginCalendarCopy = (sourceDate: string): void => {
    setCopiedDay(sourceDate)
    setCalendarContextDate(null)
    setPasteTarget(null)
    setSelectingCopyMeals(false)
    setSelectedCopyMealIds(new Set())
  }

  const resetCalendarCopy = (): void => {
    setCalendarContextDate(null)
    setCopiedDay(null)
    setPasteTarget(null)
    setSelectingCopyMeals(false)
    setSelectedCopyMealIds(new Set())
  }

  const copyCalendarDayToTarget = async (targetDate: string, selectedMealIds: Set<string> | null): Promise<void> => {
    if (!copiedDay || !canPasteSimpleDay(copiedDay, targetDate) || calendarBusy) return
    setCalendarBusy(true)
    try {
      const sourceMeals = foodStore.mealsForDate(copiedDay)
        .filter((meal) => selectedMealIds == null || selectedMealIds.has(meal.id))
        .sort((left, right) => left.logged_at.localeCompare(right.logged_at))
      let targetMeals = foodStore.mealsForDate(targetDate)
      const targetPlannedChecks = new Set(data.meal_logs.filter((log) => log.date === targetDate).map((log) => log.meal_id))

      for (const sourceMeal of sourceMeals) {
        const replaceMeal = sourceMeal.source_planned_meal_id
          ? targetMeals.find((meal) => meal.source_planned_meal_id === sourceMeal.source_planned_meal_id)
          : undefined
        const copiedMeal = await foodStore.logMeal({
          date: targetDate,
          slot: sourceMeal.meal_slot,
          name: sourceMeal.display_name,
          items: await loggedMealItems(sourceMeal),
          sourcePresetId: sourceMeal.source_preset_id,
          sourcePlannedMealId: sourceMeal.source_planned_meal_id,
          replaceMealId: replaceMeal?.id,
          loggedAs: sourceMeal.logged_as,
          idempotencyKey: dayMealCopyIdempotencyKey(profile.user_id, copiedDay, targetDate, sourceMeal.id),
        })
        targetMeals = [copiedMeal, ...targetMeals.filter((meal) => meal.id !== replaceMeal?.id)]
        if (sourceMeal.source_planned_meal_id && !targetPlannedChecks.has(sourceMeal.source_planned_meal_id)) {
          upsert('meal_logs', {
            id: crypto.randomUUID(),
            user_id: profile.user_id,
            date: targetDate,
            meal_id: sourceMeal.source_planned_meal_id,
            checked_at: new Date().toISOString(),
          })
          targetPlannedChecks.add(sourceMeal.source_planned_meal_id)
        }
      }

      const structuredSourcePlannedIds = new Set(
        foodStore.mealsForDate(copiedDay).flatMap((meal) => meal.source_planned_meal_id ? [meal.source_planned_meal_id] : []),
      )
      for (const sourceCheck of data.meal_logs.filter((log) => log.date === copiedDay)) {
        const selectedLegacyCheck = !structuredSourcePlannedIds.has(sourceCheck.meal_id) && selectedMealIds?.has(calendarLegacyMealSelectionId(sourceCheck.meal_id))
        if (selectedMealIds != null && !selectedLegacyCheck) continue
        if (targetPlannedChecks.has(sourceCheck.meal_id)) continue
        upsert('meal_logs', {
          id: crypto.randomUUID(),
          user_id: profile.user_id,
          date: targetDate,
          meal_id: sourceCheck.meal_id,
          checked_at: new Date().toISOString(),
        })
        targetPlannedChecks.add(sourceCheck.meal_id)
      }

      toast(tx(selectedMealIds == null ? 'Day pasted' : 'Selected meals pasted'), 'ok')
      setSelectedLogDate(targetDate)
      setLogMonth(startOfMonth(parseISO(targetDate)))
      resetCalendarCopy()
    } catch (error) {
      toast(error instanceof Error ? error.message : tx('Could not paste this day.'), 'error')
    } finally {
      setCalendarBusy(false)
    }
  }

  const clearCalendarDay = async (date: string): Promise<void> => {
    if (calendarBusy) return
    setCalendarBusy(true)
    try {
      for (const meal of foodStore.mealsForDate(date)) await foodStore.deleteMeal(meal.id)
      for (const log of data.meal_logs.filter((value) => value.date === date)) remove('meal_logs', log.id)
      toast(tx('Meal and snack selections cleared'), 'ok')
      setCalendarContextDate(null)
      if (copiedDay === date) resetCalendarCopy()
    } catch (error) {
      toast(error instanceof Error ? error.message : tx('Could not clear this day.'), 'error')
    } finally {
      setCalendarBusy(false)
    }
  }

  const persistActivityBlocks = (nextBlocks: ActivityBlock[]): void => {
    const nextIds = new Set(nextBlocks.map((block) => block.id))
    for (const existing of selectedActivityLogs) {
      if (!nextIds.has(existing.id)) remove('activity_logs', existing.id)
    }
    for (const block of nextBlocks) {
      const existing = selectedActivityLogs.find((log) => log.id === block.id)
      upsert('activity_logs', activityLogFromBlock(block, profile, selectedLogDate, catalog, existing))
    }

    const nextEstimate = estimateActivityDay(profile, nextBlocks, catalog)
    const mode = nextBlocks.length > 0 ? 'precise' : 'quick'
    const estimatedTdee = mode === 'precise' ? nextEstimate.tdee : quickTargets.tdee
    const existingDay = data.daily_logs.find((log) => log.date === selectedLogDate)
    upsert('daily_logs', {
      ...emptyDailyLog(selectedLogDate, profile.user_id),
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
  const selectedIsFuture = selectedLogDate > today
  const dateLocale = language === 'ro' ? 'ro-RO' : language === 'th' ? 'th-TH' : 'en-GB'

  const moveNutritionDay = (offset: number): void => {
    const nextDate = addDays(selectedDateObject, offset)
    resetCalendarCopy()
    setSelectedLogDate(format(nextDate, 'yyyy-MM-dd'))
    setLogMonth(startOfMonth(nextDate))
  }

  const finishNutritionSwipe = (x: number, y: number): void => {
    const start = nutritionSwipeStart.current
    nutritionSwipeStart.current = null
    if (!start || plannedComposer) return
    const offset = simpleDaySwipeOffset(start, { x, y }, start.blockedByLocalGesture)
    if (offset !== 0) moveNutritionDay(offset)
  }

  return (
    <div
      className="mx-auto w-full max-w-3xl touch-pan-y"
      onTouchStart={(event) => {
        const touch = event.changedTouches[0]
        const target = event.target
        const blockedByLocalGesture = target instanceof Element && Boolean(target.closest('button, a, input, textarea, select, [role="button"], [data-nutrition-local-gesture]'))
        if (touch) nutritionSwipeStart.current = { x: touch.clientX, y: touch.clientY, blockedByLocalGesture }
      }}
      onTouchEnd={(event) => {
        const touch = event.changedTouches[0]
        if (touch) finishNutritionSwipe(touch.clientX, touch.clientY)
      }}
      onTouchCancel={() => {
        nutritionSwipeStart.current = null
      }}
    >
      <SectionHeader
        accent={amber}
        title="Nutrition"
        eyebrow={format(selectedDateObject, 'EEEE, d MMMM yyyy')}
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

      {returnToSimple && (
        <button type="button" onClick={() => navigate(-1)} className="glass mb-3 inline-flex items-center gap-2 rounded-full px-3 py-2 text-[11px] font-black text-amber-800" data-nutrition-local-gesture>
          <span aria-hidden>‹</span> {tx('Back to Simple Mode')}
        </button>
      )}

      <div className="mb-3 grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3" data-nutrition-local-gesture>
        <button type="button" onClick={() => moveNutritionDay(-1)} aria-label={tx('Previous day')} className="glass grid h-10 w-10 place-items-center rounded-full text-lg font-black text-ink-soft">‹</button>
        <button type="button" onClick={() => { resetCalendarCopy(); setSelectedLogDate(today); setLogMonth(startOfMonth(new Date())) }} className="glass min-w-0 rounded-2xl px-4 py-2.5 text-center">
          <span className="block truncate font-mono text-[10px] font-black tracking-[0.13em] text-ink uppercase">{format(selectedDateObject, 'EEEE, d MMMM')}</span>
          <span className="mt-0.5 block text-[9px] font-black tracking-wide text-amber-700 uppercase">{selectedLogDate === today ? tx('Today') : tx('Tap to return to today')}</span>
        </button>
        <button type="button" onClick={() => moveNutritionDay(1)} aria-label={tx('Next day')} className="glass grid h-10 w-10 place-items-center rounded-full text-lg font-black text-ink-soft">›</button>
      </div>
      <p className="mb-4 text-center text-[10px] font-semibold text-ink-faint">{tx('Swipe between days. Plan ahead or review what happened.')}</p>

      <div className="mb-4 flex justify-end">
        <Link to="/progress" state={{ from: '/nutrition' }} className="glass rounded-full px-3 py-2 text-[11px] font-bold text-violet-700">◫ Private visual progress</Link>
      </div>

      <div className="space-y-5">
        <div id="nutrition-meals" className="scroll-mt-28">
        <ActualFoodTracker
          key={selectedLogDate}
          date={selectedLogDate}
          planning={selectedIsFuture}
          dateLabel={selectedLogDate === today ? 'Today' : null}
          target={{ kcal: targets.kcal, protein_g: targets.protein_g, carbs_g: targets.carbs_g, fat_g: targets.fat_g }}
          consumed={consumed}
          consumedMeals={consumedMeals}
          plannedRows={plannedRows}
          activityLabel={activeDayLabel}
          onTogglePlanned={toggleMeal}
          onEditPlanned={editAndLog}
        />
        </div>

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
            {targets.bmrSource === 'custom' && (
              <span className="rounded-full bg-violet-500/10 px-2.5 py-1 text-[10px] font-bold text-violet-800">{tx(`Measured BMR active · ${targets.activeBmr} kcal`)}</span>
            )}
          </div>
          {showBmrInfo && (
            <motion.p
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              className="mt-2 rounded-xl px-3 py-2 text-[13px] leading-relaxed font-medium text-ink-soft"
              style={{ background: amber.wash }}
            >
              {targets.bmrSource === 'custom'
                ? tx('The measured BMR overrides the formula for live TDEE and targets. Katch-McArdle remains visible only as a reference.')
                : language === 'ro'
                  ? `Katch-McArdle calculează din masa corporală slabă, nu din greutatea totală, astfel încât masa grasă măsurată să nu umfle estimarea. Valoarea actuală de ${profile.body_fat_pct}% grăsime corporală produce TDEE-ul de referință de mai sus. APEX îl combină cu activitatea și obiectivul selectate pentru ținta live.`
                  : language === 'th'
                    ? `Katch-McArdle คำนวณจากมวลไร้ไขมันแทนน้ำหนักรวม จึงไม่ทำให้ค่าประมาณสูงเกินจากไขมันที่วัดได้ ค่าไขมันร่างกายปัจจุบัน ${profile.body_fat_pct}% สร้าง TDEE อ้างอิงด้านบน และ APEX จะรวมค่านี้กับกิจกรรมและเป้าหมายที่เลือกเพื่อสร้างเป้าปัจจุบัน`
                    : `Katch-McArdle computes from lean body mass instead of total weight, so measured fat mass does not inflate the estimate. Your current ${profile.body_fat_pct}% body-fat entry produces the reference TDEE above. APEX uses that estimate with your selected activity and goal to build the live target.`}
            </motion.p>
          )}

          <div className="mt-5 rounded-2xl border border-white/80 bg-white/38 p-3.5">
            <p className="mb-2 font-mono text-[9px] font-bold tracking-[0.16em] text-ink-faint uppercase">Activity level</p>
            <div className="flex flex-wrap gap-2">
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
                      : { background: 'rgba(255,255,255,0.72)', color: '#55555f', border: '1px solid rgba(26,26,34,0.08)' }
                  }
                >
                  {v.label}
                </button>
              ))}
            </div>
          </div>
          {preciseMode && (
            <p className="mt-2 text-[11px] font-semibold text-ink-faint">
              Computed from your day. Clear every activity block to return to Quick Mode.
            </p>
          )}
          <div className="mt-3 rounded-2xl border border-amber-300/15 bg-amber-50/48 p-3.5">
            <p className="mb-2 font-mono text-[10px] font-black tracking-[0.18em] text-amber-800 uppercase">Goal</p>
            <div className="grid gap-2 sm:grid-cols-3">
              {Object.entries(GOALS).map(([key, v]) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => setProfile({ goal: key as Goal })}
                  className="min-h-12 rounded-2xl px-4 py-2.5 text-sm font-bold transition-all"
                  style={
                    profile.goal === key
                      ? { background: amber.gradient, color: '#fff', boxShadow: `0 12px 26px -14px ${amber.glowStrong}` }
                      : { background: 'rgba(255,255,255,0.82)', color: '#3f3f48', border: '1px solid rgba(245,158,11,0.15)' }
                  }
                >
                  {v.label}
                </button>
              ))}
            </div>
          </div>
        </GlassCard>
        {preciseMode && selectedLogDate === today && (
          <div className="rounded-2xl border border-amber-500/15 p-4" style={{ background: amber.wash }}>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p className="font-display text-sm font-bold text-ink">{tx('Did the day go as planned?')}</p>
                <p className="mt-0.5 text-[10px] font-medium text-ink-soft">
                  {activityEstimate.tdee.toLocaleString()} kcal TDEE · PAL {activityEstimate.pal.toFixed(2)} · {PAL_LABELS[activityEstimate.level]}
                </p>
              </div>
              {allActivityFinal ? (
                <span className="rounded-full bg-emerald/10 px-3 py-1.5 text-[10px] font-bold text-emerald">{tx('Reconciled ✓')}</span>
              ) : (
                <div className="flex gap-2">
                  <button type="button" onClick={adjustActivities} className="rounded-xl bg-white/65 px-3 py-2 text-[10px] font-bold text-ink-soft shadow-sm">
                    {tx('Adjust blocks')}
                  </button>
                  <button type="button" onClick={reconcileActivities} className="rounded-xl px-3 py-2 text-[10px] font-bold text-white shadow-sm" style={{ background: amber.gradient }}>
                    {tx('Yes, finalize')}
                  </button>
                </div>
              )}
            </div>
          </div>
        )}
          </div>
        </details>

        {/* -------- Supplement timeline -------- */}
        <details id="nutrition-supplements" className="glass group scroll-mt-28 rounded-3xl p-4">
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3">
            <div><p className="font-display text-sm font-bold text-ink">Supplement stack</p><p className="mt-0.5 text-[10px] font-medium text-ink-soft">{daySupplementIds.size}/{data.supplements.length} · {format(selectedDateObject, 'd MMM')}</p></div>
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
              const active = selectedLogDate === today && nowMin >= group.time - 10 && nowMin <= group.time + 50
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

        {/* -------- Focused daily log -------- */}
        {!selectedIsFuture && (
          <div data-nutrition-local-gesture>
          <GlassCard accent={amber} className="defer-paint-tall p-5 sm:p-6">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <h2 className="font-display text-lg font-bold text-ink">{tx('Daily log')}</h2>
                <span className="font-mono text-xs font-bold text-ink-faint">
                  {format(selectedDateObject, 'EEEE, d MMMM yyyy')}
                </span>
              </div>
              {selectedLogDate !== today && (
                <button
                  type="button"
                  onClick={() => {
                    resetCalendarCopy()
                    setSelectedLogDate(today)
                    setLogMonth(startOfMonth(new Date()))
                  }}
                  className="rounded-full px-3 py-1.5 text-xs font-bold text-white"
                  style={{ background: amber.gradient }}
                >
                  {tx('Back to today')}
                </button>
              )}
            </div>
            <p className="mt-1 text-[13px] font-medium text-ink-soft">
              {tx('Nutrition is calculated from logged meals. Enter only water and morning weight here.')}
            </p>

            <div className="mt-5 space-y-4 border-t border-ink/8 pt-4">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div><p className="text-sm font-bold text-ink">{tx('Water')}</p><p className="text-[10px] font-medium text-ink-faint">{tx('Editable here or from the workout calendar.')}</p></div>
                <div className="flex items-center gap-2" aria-label={tx('Water in litres')}>
                  <button type="button" onClick={() => setWater(selectedLog.water_l - 0.25)} className="grid h-10 w-10 place-items-center rounded-xl bg-gradient-to-br from-sky-500 to-cyan-400 font-mono text-lg font-bold text-white shadow-[0_10px_24px_-12px_rgba(14,165,233,.8)]" aria-label={tx('Decrease water')}>−</button>
                  <label className="glass flex min-w-[7.25rem] items-center justify-center rounded-xl px-2 py-2"><input type="text" inputMode="decimal" value={waterDraft} onChange={(event) => { if (/^\d*(?:[.,]\d{0,2})?$/.test(event.target.value)) setWaterDraft(event.target.value) }} onBlur={commitWaterDraft} onKeyDown={(event) => event.key === 'Enter' && event.currentTarget.blur()} className="w-[4.4rem] bg-transparent text-right font-mono text-xl font-bold text-sky-900 outline-none" aria-label={tx('Exact water in litres')} /><span className="ml-1 text-xs font-bold text-sky-700">L</span></label>
                  <button type="button" onClick={() => setWater(selectedLog.water_l + 0.25)} className="grid h-10 w-10 place-items-center rounded-xl bg-gradient-to-br from-sky-500 to-cyan-400 font-mono text-lg font-bold text-white shadow-[0_10px_24px_-12px_rgba(14,165,233,.8)]" aria-label={tx('Increase water')}>+</button>
                </div>
              </div>
              <label className="flex flex-wrap items-center justify-between gap-3"><span><span className="block text-sm font-bold text-ink">{tx('Morning weight')}</span><span className="block text-[10px] font-medium text-ink-faint">{tx('Optional · feeds the 7-day calibration EMA')}</span></span><span className="glass flex items-center rounded-xl px-3 py-2"><input type="number" inputMode="decimal" min="25" max="300" step="0.1" value={selectedLog.weight_kg ?? ''} placeholder={String(profile.weight_kg)} onChange={(event) => patchLog({ weight_kg: event.target.value === '' ? null : Number(event.target.value) })} className="w-16 bg-transparent text-right font-mono text-base font-bold text-ink outline-none" aria-label={tx('Morning weight in kilograms')} /><span className="ml-1 text-xs font-semibold text-ink-soft">kg</span></span></label>
            </div>
          </GlassCard>
          </div>
        )}

        <details className="glass group rounded-3xl p-4" data-nutrition-local-gesture>
          <summary className="flex cursor-pointer list-none items-center justify-between gap-3">
            <div><p className="font-display text-sm font-bold text-ink">{tx('Calendar')}</p><p className="mt-0.5 text-[10px] font-medium text-ink-soft">{tx('Open any past or future date.')}</p></div>
            <span className="grid h-8 w-8 place-items-center rounded-full bg-white/65 text-lg text-ink-soft transition group-open:rotate-45">+</span>
          </summary>
          <div className="mt-4 border-t border-ink/7 pt-4">
            <NutritionLogCalendar
              month={logMonth}
              selectedDate={selectedLogDate}
              today={today}
              data={data}
              foodMeals={foodStore.meals}
              accent={amber}
              onMonthChange={setLogMonth}
              onSelectDate={(date) => {
                resetCalendarCopy()
                setSelectedLogDate(date)
              }}
              copySourceDate={copiedDay}
              onLongPressDate={(date) => {
                setCalendarContextDate(date)
                setPasteTarget(null)
                setSelectingCopyMeals(false)
              }}
              onCopyTarget={(date) => {
                if (!canPasteSimpleDay(copiedDay, date)) return
                setPasteTarget(date)
                setSelectingCopyMeals(false)
              }}
            />
          </div>
        </details>

        {calendarContextDate && (
          <div className="fixed inset-0 z-[90] flex items-center justify-center bg-slate-950/25 p-5 backdrop-blur-sm" onClick={() => setCalendarContextDate(null)} data-nutrition-local-gesture>
            <div role="dialog" aria-modal="true" aria-label={tx('Calendar day actions')} onClick={(event) => event.stopPropagation()} className="w-full max-w-xs rounded-[26px] border border-white/85 bg-white/96 p-4 shadow-2xl">
              <div className="mb-3 flex items-start justify-between gap-3"><div><p className="font-display text-base font-black text-ink">{new Intl.DateTimeFormat(dateLocale, { weekday: 'long', day: 'numeric', month: 'long' }).format(parseISO(calendarContextDate))}</p><p className="mt-1 text-[10px] font-semibold text-ink-faint">{tx('Copy or clear this day’s meals and snacks.')}</p></div><button type="button" onClick={() => setCalendarContextDate(null)} aria-label={tx('Close')} className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-ink/5 font-black text-ink-soft">×</button></div>
              <div className="grid gap-2">
                <button type="button" onClick={() => beginCalendarCopy(calendarContextDate)} className="rounded-2xl bg-cyan-600 px-4 py-3 text-left text-xs font-black text-white active:scale-[.98]">{tx('Copy')}</button>
                <button type="button" disabled={calendarBusy} onClick={() => void clearCalendarDay(calendarContextDate)} className="rounded-2xl bg-rose-50 px-4 py-3 text-left text-xs font-black text-rose-700 active:scale-[.98] disabled:opacity-50">{calendarBusy ? tx('Clearing…') : tx('Clear')}</button>
              </div>
            </div>
          </div>
        )}

        {copiedDay && pasteTarget && (
          <div className="fixed inset-0 z-[90] flex items-center justify-center bg-slate-950/25 p-5 backdrop-blur-sm" onClick={() => { setPasteTarget(null); setSelectingCopyMeals(false) }} data-nutrition-local-gesture>
            <div role="dialog" aria-modal="true" aria-label={tx('Paste copied day')} onClick={(event) => event.stopPropagation()} className="w-full max-w-sm rounded-[28px] border border-white/85 bg-white/96 p-4 shadow-2xl">
              <div className="flex items-start justify-between gap-3"><div><p className="font-display text-base font-black text-ink">{tx(selectingCopyMeals ? 'Select meals or snacks' : 'Paste copied day')}</p><p className="mt-0.5 text-[10px] font-semibold text-ink-faint">{new Intl.DateTimeFormat(dateLocale, { day: 'numeric', month: 'short' }).format(parseISO(copiedDay))} → {new Intl.DateTimeFormat(dateLocale, { day: 'numeric', month: 'short' }).format(parseISO(pasteTarget))}</p></div><button type="button" onClick={() => { setPasteTarget(null); setSelectingCopyMeals(false) }} aria-label={tx('Close')} className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-ink/5 font-black text-ink-soft">×</button></div>
              {!selectingCopyMeals ? (
                <div className="mt-4 grid gap-2">
                  <button type="button" disabled={calendarBusy} onClick={() => void copyCalendarDayToTarget(pasteTarget, null)} className="w-full rounded-2xl bg-cyan-600 px-4 py-3 text-left text-xs font-black text-white shadow-sm active:scale-[.98] disabled:opacity-50"><span className="block">{calendarBusy ? tx('Pasting…') : tx('Paste')}</span><span className="mt-0.5 block text-[9px] font-semibold text-white/75">{tx('All selected meals and snacks')}</span></button>
                  <button type="button" disabled={copiedMeals.length + copiedLegacyChecks.length === 0} onClick={() => { setSelectedCopyMealIds(new Set([...copiedMeals.map((meal) => meal.id), ...copiedLegacyChecks.map((check) => check.selectionId)])); setSelectingCopyMeals(true) }} className="w-full rounded-2xl border border-violet-100 bg-violet-50/70 px-4 py-3 text-left text-xs font-black text-violet-900 active:scale-[.98] disabled:opacity-40"><span className="block">{tx('Select')}</span><span className="mt-0.5 block text-[9px] font-semibold text-violet-700/70">{tx('Choose individual meals or snacks')}</span></button>
                </div>
              ) : (
                <div className="mt-4">
                  <div className="max-h-[42dvh] space-y-1.5 overflow-y-auto pr-0.5">
                    {copiedMeals.map((meal) => {
                      const checked = selectedCopyMealIds.has(meal.id)
                      const slotLabel = `${meal.meal_slot[0].toUpperCase()}${meal.meal_slot.slice(1)}`
                      return <button key={meal.id} type="button" aria-pressed={checked} onClick={() => setSelectedCopyMealIds((current) => { const next = new Set(current); if (checked) next.delete(meal.id); else next.add(meal.id); return next })} className="flex w-full items-center gap-2 rounded-2xl bg-slate-50/90 px-3 py-2.5 text-left"><span className={`grid h-6 w-6 shrink-0 place-items-center rounded-full text-[10px] font-black ${checked ? 'bg-violet-600 text-white' : 'border border-violet-200 text-transparent'}`}>✓</span><span className="min-w-0 flex-1"><span className="block truncate text-xs font-black text-ink">{tx(meal.display_name)}</span><span className="block font-mono text-[8px] font-semibold text-ink-faint">{tx(slotLabel)} · {Math.round(meal.total_kcal)} kcal</span></span></button>
                    })}
                    {copiedLegacyChecks.map((check) => {
                      const checked = selectedCopyMealIds.has(check.selectionId)
                      const slotLabel = `${check.slot[0].toUpperCase()}${check.slot.slice(1)}`
                      return <button key={check.selectionId} type="button" aria-pressed={checked} onClick={() => setSelectedCopyMealIds((current) => { const next = new Set(current); if (checked) next.delete(check.selectionId); else next.add(check.selectionId); return next })} className="flex w-full items-center gap-2 rounded-2xl bg-slate-50/90 px-3 py-2.5 text-left"><span className={`grid h-6 w-6 shrink-0 place-items-center rounded-full text-[10px] font-black ${checked ? 'bg-violet-600 text-white' : 'border border-violet-200 text-transparent'}`}>✓</span><span className="min-w-0 flex-1"><span className="block truncate text-xs font-black text-ink">{tx(check.name)}</span><span className="block font-mono text-[8px] font-semibold text-ink-faint">{tx(slotLabel)}{check.kcal > 0 ? ` · ${Math.round(check.kcal)} kcal` : ''}</span></span></button>
                    })}
                  </div>
                  <button type="button" disabled={calendarBusy || selectedCopyMealIds.size === 0} onClick={() => void copyCalendarDayToTarget(pasteTarget, selectedCopyMealIds)} className="mt-3 w-full rounded-2xl bg-violet-600 px-4 py-3 text-xs font-black text-white active:scale-[.98] disabled:opacity-40">{calendarBusy ? tx('Pasting…') : `${tx('Paste selected')} · ${selectedCopyMealIds.size}`}</button>
                </div>
              )}
            </div>
          </div>
        )}

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
          date={selectedLogDate}
          planning={selectedIsFuture}
          slot={plannedComposer.slot}
          title={plannedComposer.title}
          initialItems={plannedComposer.items}
          plannedMealId={plannedComposer.meal.id}
          replaceMealId={plannedComposer.replaceMealId}
          onLogged={() => {
            const existing = data.meal_logs.find((log) => log.date === selectedLogDate && log.meal_id === plannedComposer.meal.id)
            if (!existing) upsert('meal_logs', {
              id: crypto.randomUUID(),
              user_id: profile.user_id,
              date: selectedLogDate,
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
