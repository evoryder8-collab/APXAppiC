import { lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import {
  addDays,
  addMonths,
  eachDayOfInterval,
  endOfMonth,
  endOfWeek,
  format,
  isSameDay,
  isSameMonth,
  parseISO,
  startOfMonth,
  startOfWeek,
} from 'date-fns'
import { Link, useNavigate } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { useStore } from '../store/AppStore'
import { useFoodStore } from '../store/FoodStore'
import { ACCENTS } from '../lib/theme'
import { ACTIVITY_MULTIPLIERS, GOALS, buildTargetMealPlan, computeTargets, type TargetMeal } from '../lib/nutrition'
import { planForDate, todayIso } from '../lib/plan'
import { dailyLogId } from '../lib/ids'
import type { ActivityLevel, DailyLog, Goal, Supplement } from '../lib/types'
import { aggregateConsumedMeals, displayFoodName, reconcileConsumedMeals, type ComposerFoodItem, type FoodRecord, type LoggedMeal, type MealSlot } from '../lib/food'
import { GlassCard, GradientButton } from '../components/ui'
import { AvatarIcon, DropletIcon, LeafIcon, OrbitIcon, TransitionIcon } from '../components/Icons'
import { PortalLanguageMenu } from '../components/PortalLanguageMenu'
import { canFinishDaySwipe, canPasteSimpleDay, canStartDaySwipe, dayMealCopyIdempotencyKey, daySwipeHasSingleTrackedTouch, isDaySwipeInteractiveTarget, parseWaterAmountToLitres, rankSimpleMacroContributors, selectNextSimpleAction, simpleCompletion, simpleDaySwipeOffset, simpleWaterTargetComplete, weightFromKg, weightToKg, weightUnitFromSettings, type SimpleMacroKey } from '../lib/simpleMode'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { useOrbitStore } from '../orbit/store/OrbitStore'
import { missionLabel } from '../orbit/domain/analysis'
import { NutritionGlance } from '../components/food/NutritionGlance'
import { ManualWorkoutLogger, TodayManualWorkoutCard } from '../components/workout/ManualWorkoutLogger'
import { WeightTrend } from '../components/WeightTrend'
import { FloatingActiveDate } from '../components/FloatingActiveDate'
import { mealBlockIdempotencyKey, mealBlockIdFromIdempotencyKey, mealBlockLabel, mealSlotForBlock, normalizeMealBlockSettings, resolveMealBlockStatuses, type MealBlockKind } from '../lib/mealBlocks'

const emerald = ACCENTS.emerald
const QuickMealComposer = lazy(() => import('../components/food/MealComposer').then((module) => ({ default: module.MealComposer })))

function minuteOf(value: string): number {
  const [hours, minutes] = value.split(':').map(Number)
  return hours * 60 + minutes
}

function supplementTime(supplement: Supplement, trainingTime: string): number {
  if (supplement.timing === 'clock' && supplement.clock_time) return minuteOf(supplement.clock_time)
  return minuteOf(trainingTime) + (supplement.offset_min ?? 0)
}

function clockOf(minutes: number): string {
  const safe = ((minutes % 1440) + 1440) % 1440
  return `${String(Math.floor(safe / 60)).padStart(2, '0')}:${String(safe % 60).padStart(2, '0')}`
}

function mealSlotFor(meal: TargetMeal): MealSlot {
  const hour = Number(meal.time.slice(0, 2))
  if (meal.name.toLowerCase().includes('snack') || meal.name.toLowerCase().includes('shake')) return 'snack'
  if (hour < 11) return 'breakfast'
  if (hour < 16) return 'lunch'
  return 'dinner'
}

const legacyMealSelectionId = (mealId: string): string => `planned:${mealId}`

export function SimpleHome() {
  const { data, snapshots, upsert, remove, setProfile, setSettings, toast } = useStore()
  const foodStore = useFoodStore()
  const orbit = useOrbitStore()
  const navigate = useNavigate()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [showManualWorkout, setShowManualWorkout] = useState(false)
  const [editingManualSessionId, setEditingManualSessionId] = useState<string | null>(null)
  const [editingManualExerciseName, setEditingManualExerciseName] = useState<string | null>(null)
  const [busyMeal, setBusyMeal] = useState<string | null>(null)
  const [weightDraft, setWeightDraft] = useState('')
  const [quickPanel, setQuickPanel] = useState<'meals' | 'supplements' | 'water' | 'targets' | 'macro' | 'weight' | null>(null)
  const [selectedMacro, setSelectedMacro] = useState<SimpleMacroKey>('protein_g')
  const [quickMealBlockId, setQuickMealBlockId] = useState<MealBlockKind | null>(null)
  const [quickMealEditor, setQuickMealEditor] = useState<{ slot: MealSlot; blockId: MealBlockKind; title: string; items: ComposerFoodItem[]; plannedMealId: string | null; replaceMealId: string | null } | null>(null)
  const [customWaterOpen, setCustomWaterOpen] = useState(false)
  const [customWaterDraft, setCustomWaterDraft] = useState('')
  const today = todayIso()
  const [selectedDate, setSelectedDate] = useState(today)
  const [showCalendar, setShowCalendar] = useState(false)
  const [calendarMonth, setCalendarMonth] = useState(() => startOfMonth(parseISO(today)))
  const [calendarContextDate, setCalendarContextDate] = useState<string | null>(null)
  const [copiedDay, setCopiedDay] = useState<string | null>(null)
  const [pasteTarget, setPasteTarget] = useState<string | null>(null)
  const [selectingCopyMeals, setSelectingCopyMeals] = useState(false)
  const [selectedCopyMealIds, setSelectedCopyMealIds] = useState<Set<string>>(new Set())
  const [calendarBusy, setCalendarBusy] = useState(false)
  const calendarPressTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const calendarLongPressFired = useRef(false)
  const swipeStart = useRef<{ x: number; y: number; touchId: number; blockedByLocalGesture: boolean } | null>(null)
  const summaryActionsRef = useRef<HTMLDivElement>(null)
  const selectedDateObject = useMemo(() => parseISO(selectedDate), [selectedDate])
  const profile = data.profile
  const settings = data.settings
  const weightUnit = weightUnitFromSettings(settings)
  const adhdMode = settings?.addons.adhd_mode ?? false
  const showOrbitShortcut = settings?.addons.simple_show_orbit ?? true
  const showBodyIndexShortcut = settings?.addons.simple_show_body_index ?? true
  const showGuidedPlan = settings?.addons.simple_show_guided_plan ?? true
  const showHydrationReminder = settings?.addons.simple_show_hydration_reminder ?? false
  const showManualWorkoutCard = settings?.addons.simple_show_manual_workout ?? false
  const mealBlockSettings = useMemo(() => normalizeMealBlockSettings(settings?.addons.meal_blocks), [settings?.addons.meal_blocks])
  const targets = useMemo(() => profile ? computeTargets(profile) : null, [profile])
  const mealPlan = useMemo(
    () => profile && targets
      ? buildTargetMealPlan(data.meals, targets, ACTIVITY_MULTIPLIERS[profile.activity_level].label)
      : [],
    [data.meals, profile, targets],
  )
  const dateFoodMeals = useMemo(() => foodStore.mealsForDate(selectedDate), [foodStore, selectedDate])
  const dateMealIds = useMemo(
    () => new Set(data.meal_logs.filter((log) => log.date === selectedDate).map((log) => log.meal_id)),
    [data.meal_logs, selectedDate],
  )
  const consumedMeals = useMemo(
    () => reconcileConsumedMeals(dateFoodMeals, mealPlan, dateMealIds),
    [dateFoodMeals, dateMealIds, mealPlan],
  )
  const consumed = useMemo(() => aggregateConsumedMeals(consumedMeals), [consumedMeals])
  const mealBlockStatuses = useMemo(() => resolveMealBlockStatuses({
    settings: mealBlockSettings,
    loggedMeals: dateFoodMeals,
    plannedMeals: mealPlan,
    checkedPlannedMealIds: dateMealIds,
  }), [dateFoodMeals, dateMealIds, mealBlockSettings, mealPlan])
  const macroContributors = useMemo(() => {
    const mealIds = new Set(dateFoodMeals.map((meal) => meal.id))
    const localizedEntries = foodStore.entries
      .filter((entry) => mealIds.has(entry.meal_id))
      .map((entry) => {
        const food = entry.food_id ? foodStore.foods.find((candidate) => candidate.id === entry.food_id) : null
        return food ? { ...entry, snapshot_name: displayFoodName(food, language) } : entry
      })
    return rankSimpleMacroContributors(localizedEntries, selectedMacro)
  }, [dateFoodMeals, foodStore.entries, foodStore.foods, language, selectedMacro])
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
        selectionId: legacyMealSelectionId(log.meal_id),
        mealId: log.meal_id,
        name: planned?.name ?? 'Planned meal',
        slot: planned ? mealSlotFor(planned) : 'snack',
        kcal: planned?.kcal ?? 0,
      })
    }
    return [...unique.values()]
  }, [copiedDay, copiedMeals, data.meal_logs, mealPlan])
  const trainingTime = profile?.training_time ?? '19:00'
  const supplementGroups = useMemo(() => {
    const grouped = new Map<string, { label: string; time: number; items: Supplement[] }>()
    for (const supplement of [...data.supplements].sort((a, b) => a.sort_order - b.sort_order)) {
      const time = supplementTime(supplement, trainingTime)
      const key = supplement.group_label || 'Supplements'
      const current = grouped.get(key) ?? { label: key, time, items: [] }
      current.time = Math.min(current.time, time)
      current.items.push(supplement)
      grouped.set(key, current)
    }
    return [...grouped.values()].sort((a, b) => a.time - b.time)
  }, [data.supplements, trainingTime])
  const dateSupplementLogs = useMemo(
    () => data.supplement_logs.filter((log) => log.date === selectedDate),
    [data.supplement_logs, selectedDate],
  )
  const supplementDoneIds = useMemo(() => new Set(dateSupplementLogs.map((log) => log.supplement_id)), [dateSupplementLogs])
  const plan = useMemo(() => planForDate(data, 'transition', selectedDate, false), [data, selectedDate])
  const workoutDone = data.workout_sessions.some((session) => session.date === selectedDate && session.completed)
  const dailyLog = data.daily_logs.find((log) => log.date === selectedDate)
  const water = dailyLog?.water_l ?? 0
  const waterDone = targets ? simpleWaterTargetComplete(water, targets.water_l) : false

  useEffect(() => {
    const kg = dailyLog?.weight_kg
    setWeightDraft(kg == null ? '' : String(Number(weightFromKg(kg, weightUnit).toFixed(1))))
  }, [dailyLog?.weight_kg, selectedDate, weightUnit])

  useEffect(() => {
    if (sessionStorage.getItem('apex-simple-return-anchor') !== 'summary-actions') return
    sessionStorage.removeItem('apex-simple-return-anchor')
    window.requestAnimationFrame(() => summaryActionsRef.current?.scrollIntoView({ block: 'center' }))
  }, [])

  useEffect(() => () => {
    if (calendarPressTimer.current) clearTimeout(calendarPressTimer.current)
  }, [])

  if (!profile || !targets || !settings) return null

  const groupIsDone = (group: { items: Supplement[] }): boolean =>
    group.items.length > 0 && group.items.every((item) => supplementDoneIds.has(item.id))

  const toggleSupplement = (item: Supplement): void => {
    const existing = dateSupplementLogs.find((log) => log.supplement_id === item.id)
    if (existing) {
      remove('supplement_logs', existing.id)
      return
    }
    upsert('supplement_logs', {
      id: crypto.randomUUID(), user_id: profile.user_id, date: selectedDate, supplement_id: item.id,
      checked_at: new Date().toISOString(),
    })
  }

  const completedMeals = mealBlockStatuses.filter((status) => status.completed).length
  const totalMealBlocks = mealBlockStatuses.length
  const completedGroups = supplementGroups.filter(groupIsDone).length
  const hasWorkout = plan.exercises.length > 0
  const totalTasks = totalMealBlocks + supplementGroups.length + 1 + Number(hasWorkout)
  const completedTasks = completedMeals + completedGroups + Number(waterDone) + Number(hasWorkout && workoutDone)
  const completion = simpleCompletion(completedTasks, totalTasks)

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

  const snapshotFood = async (entry: (typeof foodStore.entries)[number]): Promise<FoodRecord> => {
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
      name: entry.snapshot_name, names_i18n: { en: entry.snapshot_name }, brand: entry.snapshot_brand,
      barcode: null, provider_product_id: null, external_image_url: null, package_quantity: null,
      nutrition_basis: entry.snapshot_nutrition_basis, preparation_state: entry.snapshot_preparation_state,
      kcal_100: entry.snapshot_kcal_100, protein_100: entry.snapshot_protein_100,
      carbs_100: entry.snapshot_carbs_100, fat_100: entry.snapshot_fat_100,
      fibre_100: entry.snapshot_fibre_100, sugar_100: entry.snapshot_sugar_100,
      saturated_fat_100: entry.snapshot_saturated_fat_100, salt_100: entry.snapshot_salt_100,
      serving_amount: entry.unit === 'serving' ? 1 : null,
      serving_unit: entry.unit === 'serving' ? 'serving' : null,
      serving_grams_or_ml: entry.unit === 'serving' ? frozenUnitSize : null,
      piece_grams_or_ml: entry.unit === 'piece' ? frozenUnitSize : null,
      provider_updated_at: null, confidence: 'user_entered',
    })
  }

  const loggedMealItems = async (loggedMeal: LoggedMeal): Promise<ComposerFoodItem[]> => Promise.all(
    foodStore.entries
      .filter((entry) => entry.meal_id === loggedMeal.id)
      .sort((left, right) => left.sort_order - right.sort_order)
      .map(async (entry, index) => ({
        id: crypto.randomUUID(), food: await snapshotFood(entry), quantity: entry.quantity, unit: entry.unit,
        sort_order: index, optional: false, locked: true, adjustable: false,
        minimum_amount: null, maximum_amount: null, step_amount: entry.unit === 'piece' ? 1 : 5,
        adjustment_role: 'none' as const,
      })),
  )

  const editQuickPlannedMeal = async (meal: TargetMeal, blockId: MealBlockKind): Promise<void> => {
    const actual = dateFoodMeals.find((logged) => logged.source_planned_meal_id === meal.id)
    const items = actual ? await loggedMealItems(actual) : [await plannedFoodItem(meal)]
    setQuickPanel(null)
    setQuickMealEditor({
      slot: mealSlotForBlock(blockId), blockId, title: actual?.display_name ?? meal.name, items,
      plannedMealId: meal.id, replaceMealId: actual?.id ?? null,
    })
  }

  const editQuickCustomMeal = async (meal: LoggedMeal, blockId?: MealBlockKind): Promise<void> => {
    const assignedBlock = blockId
      ?? mealBlockIdFromIdempotencyKey(meal.client_idempotency_key)
      ?? (meal.source_preset_id ? mealBlockSettings.preset_assignments[meal.source_preset_id] : undefined)
      ?? mealBlockStatuses.find((status) => status.loggedMeal?.id === meal.id)?.block.id
      ?? (meal.meal_slot as MealBlockKind)
    setQuickPanel(null)
    setQuickMealEditor({
      slot: meal.meal_slot, blockId: assignedBlock, title: meal.display_name, items: await loggedMealItems(meal),
      plannedMealId: meal.source_planned_meal_id, replaceMealId: meal.id,
    })
  }

  const toggleMeal = async (meal: TargetMeal): Promise<void> => {
    if (!profile || busyMeal) return
    setBusyMeal(meal.id)
    try {
      const existingFoodMeal = dateFoodMeals.find((logged) => logged.source_planned_meal_id === meal.id)
      const existingCheck = data.meal_logs.find((logged) => logged.date === selectedDate && logged.meal_id === meal.id)
      if (existingFoodMeal || existingCheck) {
        if (existingFoodMeal) await foodStore.deleteMeal(existingFoodMeal.id)
        if (existingCheck) remove('meal_logs', existingCheck.id)
        toast(`${meal.name} reopened`, 'ok')
      } else {
        const item = await plannedFoodItem(meal)
        const blockId = mealBlockStatuses.find((status) => status.plannedMeal?.id === meal.id)?.block.id
        await foodStore.logMeal({
          date: selectedDate, slot: mealSlotFor(meal), name: meal.name, items: [item], sourcePlannedMealId: meal.id,
          loggedAs: 'planned', idempotencyKey: mealBlockIdempotencyKey(`simple-planned:${profile.user_id}:${selectedDate}:${meal.id}`, blockId),
        })
        upsert('meal_logs', {
          id: crypto.randomUUID(), user_id: profile.user_id, date: selectedDate, meal_id: meal.id,
          checked_at: new Date().toISOString(),
        })
        toast(`${meal.name} logged as planned`, 'ok')
      }
    } finally {
      setBusyMeal(null)
    }
  }

  const openMealBlock = async (status: (typeof mealBlockStatuses)[number]): Promise<void> => {
    if (status.loggedMeal) {
      await editQuickCustomMeal(status.loggedMeal, status.block.id)
      return
    }
    if (status.plannedMeal) {
      if (status.completed) await toggleMeal(status.plannedMeal)
      else await editQuickPlannedMeal(status.plannedMeal, status.block.id)
      return
    }
    setQuickPanel(null)
    setQuickMealBlockId(status.block.id)
  }

  const removeMealBlockEntry = async (status: (typeof mealBlockStatuses)[number]): Promise<void> => {
    if (status.loggedMeal) await foodStore.deleteMeal(status.loggedMeal.id)
    if (status.plannedMeal) {
      const check = data.meal_logs.find((log) => log.date === selectedDate && log.meal_id === status.plannedMeal?.id)
      if (check) remove('meal_logs', check.id)
    }
  }

  const toggleSupplementGroup = (group: { items: Supplement[] }): void => {
    if (!profile) return
    if (groupIsDone(group)) {
      for (const item of group.items) {
        const existing = dateSupplementLogs.find((log) => log.supplement_id === item.id)
        if (existing) remove('supplement_logs', existing.id)
      }
      toast(`${group.items.length} supplements reopened`, 'ok')
      return
    }
    for (const item of group.items) {
      if (supplementDoneIds.has(item.id)) continue
      upsert('supplement_logs', {
        id: crypto.randomUUID(), user_id: profile.user_id, date: selectedDate, supplement_id: item.id,
        checked_at: new Date().toISOString(),
      })
    }
    toast(`${group.items.length} supplements checked`, 'ok')
  }

  const patchDailyLogForDate = (date: string, patch: Partial<DailyLog>): void => {
    if (!profile) return
    const existing = data.daily_logs.find((log) => log.date === date)
    const base: DailyLog = existing ?? {
      id: dailyLogId(date, profile.user_id), user_id: profile.user_id, date,
      kcal: null, protein_g: null, fat_g: null, carbs_g: null, water_l: 0,
      estimated_tdee: null, computed_pal: null, activity_mode: 'quick', weight_kg: null,
    }
    upsert('daily_logs', { ...base, ...patch })
  }

  const patchDailyLog = (patch: Partial<DailyLog>): void => patchDailyLogForDate(selectedDate, patch)

  const setWaterAmount = (value: number): void => {
    patchDailyLog({ water_l: Math.min(6, Math.max(0, Number(value.toFixed(2)))) })
  }

  const commitMorningWeight = (): void => {
    const normalized = weightDraft.trim().replace(',', '.')
    if (!normalized) {
      patchDailyLog({ weight_kg: null })
      return
    }
    const displayValue = Number(normalized)
    const valueKg = weightToKg(displayValue, weightUnit)
    if (!Number.isFinite(displayValue) || !Number.isFinite(valueKg) || valueKg < 25 || valueKg > 300) {
      setWeightDraft(dailyLog?.weight_kg == null ? '' : String(Number(weightFromKg(dailyLog.weight_kg, weightUnit).toFixed(1))))
      toast(t('Enter a valid weight.'), 'error')
      return
    }
    const roundedKg = Number(valueKg.toFixed(1))
    setWeightDraft(String(Number(weightFromKg(roundedKg, weightUnit).toFixed(1))))
    patchDailyLog({ weight_kg: roundedKg })
    toast(t('Morning weight saved'), 'ok')
  }

  const addWater = (): void => setWaterAmount(water + 0.25)
  const openNewManualWorkout = (): void => {
    setEditingManualSessionId(null)
    setEditingManualExerciseName(null)
    setShowManualWorkout(true)
  }
  const openManualWorkout = (sessionId: string, canonicalName: string): void => {
    setEditingManualSessionId(sessionId)
    setEditingManualExerciseName(canonicalName)
    setShowManualWorkout(true)
  }
  const closeManualWorkout = (): void => {
    setShowManualWorkout(false)
    setEditingManualSessionId(null)
    setEditingManualExerciseName(null)
  }
  const openTraining = (): void => {
    navigate(hasWorkout && !workoutDone ? `/player/transition/${selectedDate}` : '/transition')
  }

  const openNutritionSection = (section: 'meals' | 'supplements'): void => {
    sessionStorage.setItem('apex-simple-return-anchor', 'summary-actions')
    navigate(`/nutrition?section=${section}&date=${selectedDate}&return=simple`)
  }

  const addQuickWater = (litres: number): void => {
    setWaterAmount(water + litres)
    setQuickPanel(null)
    setCustomWaterOpen(false)
    setCustomWaterDraft('')
    toast(t('Water added'), 'ok')
  }

  const submitCustomWater = (): void => {
    const litres = parseWaterAmountToLitres(customWaterDraft)
    if (litres == null) {
      toast(t('Enter ml or litres.'), 'error')
      return
    }
    addQuickWater(litres)
  }

  const beginCopyDay = (sourceDate: string): void => {
    setCopiedDay(sourceDate)
    setCalendarContextDate(null)
    setPasteTarget(null)
    setSelectingCopyMeals(false)
    setSelectedCopyMealIds(new Set())
  }

  const copyDayToTarget = async (targetDate: string, selectedMealIds: Set<string> | null): Promise<void> => {
    if (!profile || !copiedDay || !canPasteSimpleDay(copiedDay, targetDate) || calendarBusy) return
    setCalendarBusy(true)
    try {
      const sourceMeals = foodStore.mealsForDate(copiedDay)
        .filter((meal) => selectedMealIds == null || selectedMealIds.has(meal.id))
        .sort((left, right) => left.logged_at.localeCompare(right.logged_at))
      const sourceBlockStatuses = resolveMealBlockStatuses({
        settings: mealBlockSettings,
        loggedMeals: foodStore.mealsForDate(copiedDay),
        plannedMeals: mealPlan,
        checkedPlannedMealIds: new Set(data.meal_logs.filter((log) => log.date === copiedDay).map((log) => log.meal_id)),
      })
      let targetMeals = foodStore.mealsForDate(targetDate)
      const targetPlannedChecks = new Set(data.meal_logs.filter((log) => log.date === targetDate).map((log) => log.meal_id))

      for (const sourceMeal of sourceMeals) {
        const sourceBlockId = sourceBlockStatuses.find((status) => status.loggedMeal?.id === sourceMeal.id)?.block.id
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
          idempotencyKey: mealBlockIdempotencyKey(dayMealCopyIdempotencyKey(profile.user_id, copiedDay, targetDate, sourceMeal.id), sourceBlockId),
        })
        targetMeals = [copiedMeal, ...targetMeals.filter((meal) => meal.id !== replaceMeal?.id)]
        if (sourceMeal.source_planned_meal_id && !targetPlannedChecks.has(sourceMeal.source_planned_meal_id)) {
          upsert('meal_logs', {
            id: crypto.randomUUID(), user_id: profile.user_id, date: targetDate,
            meal_id: sourceMeal.source_planned_meal_id, checked_at: new Date().toISOString(),
          })
          targetPlannedChecks.add(sourceMeal.source_planned_meal_id)
        }
      }

      const structuredSourcePlannedIds = new Set(
        foodStore.mealsForDate(copiedDay).flatMap((meal) => meal.source_planned_meal_id ? [meal.source_planned_meal_id] : []),
      )
      for (const sourceCheck of data.meal_logs.filter((log) => log.date === copiedDay)) {
        const selectedLegacyCheck = !structuredSourcePlannedIds.has(sourceCheck.meal_id) && selectedMealIds?.has(legacyMealSelectionId(sourceCheck.meal_id))
        if (selectedMealIds != null && !selectedLegacyCheck) continue
        if (targetPlannedChecks.has(sourceCheck.meal_id)) continue
        upsert('meal_logs', {
          id: crypto.randomUUID(), user_id: profile.user_id, date: targetDate,
          meal_id: sourceCheck.meal_id, checked_at: new Date().toISOString(),
        })
        targetPlannedChecks.add(sourceCheck.meal_id)
      }

      toast(t(selectedMealIds == null ? 'Day pasted' : 'Selected meals pasted'), 'ok')
      setSelectedDate(targetDate)
      setCalendarMonth(startOfMonth(parseISO(targetDate)))
      setShowCalendar(false)
      setCopiedDay(null)
      setPasteTarget(null)
      setSelectingCopyMeals(false)
      setSelectedCopyMealIds(new Set())
    } catch (error) {
      toast(error instanceof Error ? error.message : t('Could not paste this day.'), 'error')
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
      toast(t('Meal and snack selections cleared'), 'ok')
      setCalendarContextDate(null)
      if (copiedDay === date) setCopiedDay(null)
    } catch (error) {
      toast(error instanceof Error ? error.message : t('Could not clear this day.'), 'error')
    } finally {
      setCalendarBusy(false)
    }
  }

  const resetCalendarCopy = (): void => {
    setCalendarContextDate(null)
    setCopiedDay(null)
    setPasteTarget(null)
    setSelectingCopyMeals(false)
    setSelectedCopyMealIds(new Set())
  }

  const closeCalendar = (): void => {
    setShowCalendar(false)
    resetCalendarCopy()
  }

  const moveDay = (offset: number): void => {
    setSelectedDate(format(addDays(selectedDateObject, offset), 'yyyy-MM-dd'))
    setQuickPanel(null)
    setShowCalendar(false)
    resetCalendarCopy()
  }

  const chooseDate = (date: Date): void => {
    setSelectedDate(format(date, 'yyyy-MM-dd'))
    setCalendarMonth(startOfMonth(date))
    setQuickPanel(null)
    setShowCalendar(false)
    resetCalendarCopy()
  }

  const finishSwipe = (x: number, y: number): void => {
    const start = swipeStart.current
    swipeStart.current = null
    if (!start || showManualWorkout) return
    const offset = simpleDaySwipeOffset(start, { x, y }, start.blockedByLocalGesture)
    if (offset !== 0) moveDay(offset)
  }

  const nowMinutes = selectedDate === today ? new Date().getHours() * 60 + new Date().getMinutes() : 0
  const actionCandidates = [
    ...mealBlockStatuses.filter((status) => !status.completed).map((status) => ({
      time: minuteOf(status.block.time), eyebrow: 'Next meal', title: status.plannedMeal?.name ?? mealBlockLabel(status.block.kind),
      meta: status.plannedMeal ? `${status.block.time} · ${status.plannedMeal.kcal} kcal` : status.block.time,
      action: status.plannedMeal ? 'Log as planned' : 'Add food',
      run: () => void openMealBlock(status), accent: ACCENTS.amber,
    })),
    ...supplementGroups.filter((group) => !groupIsDone(group)).map((group) => ({
      time: group.time, eyebrow: 'Next supplements', title: group.label,
      meta: `${clockOf(group.time)} · ${t(`${group.items.length} items`)}`, action: 'Mark group done',
      run: () => toggleSupplementGroup(group), accent: ACCENTS.ice,
    })),
    ...(showGuidedPlan && hasWorkout && !workoutDone ? [{
      time: minuteOf(trainingTime), eyebrow: 'Today’s movement', title: plan.programDay?.name ?? 'Training',
      meta: t(`~${plan.programDay?.est_minutes ?? 15} min · ${plan.exercises.length} exercises`), action: 'Start session',
      run: () => navigate(`/player/transition/${selectedDate}`), accent: ACCENTS.teal,
    }] : []),
    ...(showHydrationReminder && !waterDone ? [{
      time: 21 * 60, eyebrow: 'Hydration', title: t(`${water.toFixed(2)} of ${targets.water_l.toFixed(2)} L`),
      meta: 'One glass takes one tap', action: '+ 250 ml', run: addWater, accent: ACCENTS.ice,
    }] : []),
  ]
  const nextAction = selectNextSimpleAction(actionCandidates, nowMinutes) ?? {
    time: nowMinutes, eyebrow: 'Routine complete', title: 'You kept the promise today',
    meta: 'Everything essential is logged', action: 'View progress',
    run: () => navigate('/avatar'), accent: ACCENTS.emerald,
  }

  const current = snapshots.at(-1)
  const previous = snapshots[Math.max(0, snapshots.length - 15)] ?? current
  const momentum = current && previous ? current.overall - previous.overall : 0
  const firstName = profile?.display_name.split(' ')[0] ?? 'You'
  const orbitSession = orbit.state.sessions.find((session) => session.date === selectedDate && session.status === 'planned')
  const dateLocale = language === 'ro' ? 'ro-RO' : language === 'th' ? 'th-TH' : 'en-GB'
  const selectedDateLabel = new Intl.DateTimeFormat(dateLocale, { weekday: 'long', day: 'numeric', month: 'long' }).format(selectedDateObject)
  const calendarMonthLabel = new Intl.DateTimeFormat(dateLocale, { month: 'long', year: 'numeric' }).format(calendarMonth)
  const calendarDays = eachDayOfInterval({
    start: startOfWeek(startOfMonth(calendarMonth), { weekStartsOn: 1 }),
    end: endOfWeek(endOfMonth(calendarMonth), { weekStartsOn: 1 }),
  })
  const weekdayLabels = Array.from({ length: 7 }, (_, index) => new Intl.DateTimeFormat(dateLocale, { weekday: 'narrow' }).format(addDays(new Date(2026, 0, 5), index)))
  const hasDayData = (date: Date): boolean => {
    const iso = format(date, 'yyyy-MM-dd')
    return data.daily_logs.some((log) => log.date === iso)
      || data.meal_logs.some((log) => log.date === iso)
      || data.supplement_logs.some((log) => log.date === iso)
      || data.workout_sessions.some((session) => session.date === iso)
      || foodStore.mealsForDate(iso).length > 0
  }

  const beginCalendarPress = (date: Date): void => {
    if (calendarPressTimer.current) clearTimeout(calendarPressTimer.current)
    calendarLongPressFired.current = false
    calendarPressTimer.current = setTimeout(() => {
      calendarLongPressFired.current = true
      setCalendarContextDate(format(date, 'yyyy-MM-dd'))
      if (typeof navigator !== 'undefined' && 'vibrate' in navigator) navigator.vibrate?.(12)
    }, 520)
  }

  const endCalendarPress = (): void => {
    if (calendarPressTimer.current) clearTimeout(calendarPressTimer.current)
    calendarPressTimer.current = null
  }

  const activateCalendarDate = (date: Date): void => {
    const iso = format(date, 'yyyy-MM-dd')
    if (calendarLongPressFired.current) {
      calendarLongPressFired.current = false
      return
    }
    if (copiedDay === iso) return
    if (canPasteSimpleDay(copiedDay, iso)) {
      setPasteTarget(iso)
      setSelectingCopyMeals(false)
      return
    }
    chooseDate(date)
  }

  return (
    <div
      className="ios-focus-safe mx-auto w-full max-w-3xl touch-pan-y touch-pinch-zoom"
      onTouchStart={(event) => {
        const blockedByLocalGesture = isDaySwipeInteractiveTarget(event.target)
        if (!canStartDaySwipe(event.touches.length, blockedByLocalGesture)) {
          swipeStart.current = null
          return
        }
        const touch = event.touches[0]
        if (touch) swipeStart.current = { x: touch.clientX, y: touch.clientY, touchId: touch.identifier, blockedByLocalGesture }
      }}
      onTouchMove={(event) => {
        const start = swipeStart.current
        if (start && !daySwipeHasSingleTrackedTouch(Array.from(event.touches, (touch) => touch.identifier), start.touchId)) {
          swipeStart.current = null
        }
      }}
      onTouchEnd={(event) => {
        const start = swipeStart.current
        const changedTouches = Array.from(event.changedTouches)
        if (!start || !canFinishDaySwipe(event.touches.length, changedTouches.map((touch) => touch.identifier), start.touchId)) {
          swipeStart.current = null
          return
        }
        const touch = changedTouches[0]
        finishSwipe(touch.clientX, touch.clientY)
      }}
      onTouchCancel={() => {
        swipeStart.current = null
      }}
    >
      <FloatingActiveDate label={selectedDateLabel} />
      <motion.header initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} className="mb-5">
        <div className="flex items-center justify-between gap-3">
          <button type="button" onClick={() => moveDay(-1)} aria-label={t('Previous day')} className="grid h-9 w-9 place-items-center rounded-full bg-white/65 text-lg font-black text-ink-soft shadow-sm">‹</button>
          <button
            type="button"
            onClick={() => { setCalendarMonth(startOfMonth(selectedDateObject)); setShowCalendar(true) }}
            aria-haspopup="dialog"
            aria-expanded={showCalendar}
            className="min-w-0 rounded-full bg-white/55 px-4 py-2 text-center shadow-sm transition active:scale-[.98]"
          >
            <span className="block truncate font-mono text-[10px] font-bold tracking-[0.14em] text-ink-faint uppercase">{selectedDateLabel}</span>
            <span className="mt-0.5 block text-[9px] font-black tracking-wide text-violet-700 uppercase">{selectedDate === today ? t('Today') : t('Open calendar')}</span>
          </button>
          <button type="button" onClick={() => moveDay(1)} aria-label={t('Next day')} className="grid h-9 w-9 place-items-center rounded-full bg-white/65 text-lg font-black text-ink-soft shadow-sm">›</button>
        </div>
        <div className="mt-1 flex items-end justify-between gap-3">
          <div><h1 className="font-display text-[30px] leading-tight font-bold tracking-tight text-ink">{selectedDate === today ? t(`Today, ${firstName}.`) : `${firstName}.`}</h1><p className="mt-1 text-sm font-medium text-ink-soft">{t(selectedDate === today ? 'Only what matters. One tap at a time.' : 'Swipe between days. Plan ahead or review what happened.')}</p></div>
          <div className="relative grid h-16 w-16 shrink-0 place-items-center rounded-full" style={{ background: `conic-gradient(#10b981 ${completion}%, rgba(26,26,34,0.08) 0)` }}>
            <div className="grid h-[52px] w-[52px] place-items-center rounded-full bg-white/90 font-mono text-sm font-bold text-ink">{completion}%</div>
          </div>
        </div>
      </motion.header>

      <div className="space-y-4">
        <GlassCard accent={ACCENTS.amber} className="overflow-hidden p-0">
          <NutritionGlance
            target={targets}
            consumed={consumed}
            mealsDone={completedMeals}
            mealsTotal={totalMealBlocks}
            status={foodStore.syncing ? 'SYNCING' : foodStore.queued ? 'QUEUED OFFLINE' : foodStore.ready ? 'PRIVATE' : 'LOADING'}
            onOpen={() => openNutritionSection('meals')}
            onRingClick={() => setQuickPanel('targets')}
            onMacroClick={(macro) => { setSelectedMacro(macro); setQuickPanel('macro') }}
            cornerControl={selectedDate <= today ? (
              <div data-simple-local-gesture className="flex items-center gap-1">
                <label className="flex items-center rounded-lg border border-amber-200/65 bg-white/82 px-2 py-1 shadow-sm" title={t('Morning weight')}>
                  <input
                    type="text"
                    inputMode="decimal"
                    value={weightDraft}
                    placeholder={String(Number(weightFromKg(profile.weight_kg, weightUnit).toFixed(1)))}
                    onChange={(event) => {
                      if (/^\d*(?:[.,]\d{0,1})?$/.test(event.target.value)) setWeightDraft(event.target.value)
                    }}
                    onClick={(event) => event.stopPropagation()}
                    onBlur={commitMorningWeight}
                    onKeyDown={(event) => event.key === 'Enter' && event.currentTarget.blur()}
                    className="w-11 bg-transparent text-right font-mono text-base font-black text-ink outline-none"
                    aria-label={t(weightUnit === 'lb' ? 'Morning weight in pounds' : 'Morning weight in kilograms')}
                  />
                  <span className="ml-1 font-mono text-[8px] font-black text-ink-faint uppercase">{weightUnit}</span>
                </label>
                <button type="button" onClick={(event) => { event.stopPropagation(); setQuickPanel('weight') }} aria-label={t('Open weight trend')} className="grid h-7 w-7 place-items-center rounded-lg border border-violet-100 bg-white/82 text-[12px] font-black text-violet-700 shadow-sm transition active:scale-90">⌁</button>
              </div>
            ) : undefined}
          />
        </GlassCard>

        <div ref={summaryActionsRef} id="simple-summary-actions" className="grid scroll-mt-28 grid-cols-4 gap-2" data-simple-local-gesture>
          <SimpleMetric icon={<LeafIcon className="h-4 w-4" />} value={`${completedMeals}/${totalMealBlocks}`} label={t('Meals')} done={totalMealBlocks > 0 && completedMeals === totalMealBlocks} onClick={() => setQuickPanel('meals')} ariaLabel={t('Edit meals')} />
          <SimpleMetric icon="✦" value={`${supplementDoneIds.size}/${data.supplements.length}`} label={t('Supps')} done={data.supplements.length > 0 && supplementDoneIds.size === data.supplements.length} onClick={() => setQuickPanel('supplements')} ariaLabel={t('Open supplements')} />
          <SimpleMetric icon={<DropletIcon className="h-4 w-4" />} value={`${water.toFixed(1)}L`} label={t('Water')} done={waterDone} onClick={() => { setCustomWaterOpen(false); setQuickPanel('water') }} ariaLabel={t('Add water')} />
          <SimpleMetric icon={<TransitionIcon className="h-4 w-4" />} value={workoutDone ? t('Done') : hasWorkout ? `${plan.programDay?.est_minutes ?? 15}m` : t('Rest')} label={t('Training')} done={workoutDone || !hasWorkout} onClick={openTraining} ariaLabel={t('Open training')} />
        </div>

        {showManualWorkoutCard && <TodayManualWorkoutCard compact date={selectedDate} onAdd={openNewManualWorkout} onEdit={openManualWorkout} />}

        {!adhdMode && <GlassCard accent={nextAction.accent} breathe className="p-5 sm:p-6">
          <p className="font-mono text-[10px] font-bold tracking-[0.18em] uppercase" style={{ color: nextAction.accent.deep }}>{nextAction.eyebrow}</p>
          <div className="mt-2 grid items-end gap-4 sm:grid-cols-[minmax(0,1fr)_auto]">
            <div className="min-w-0"><h2 className="break-words font-display text-[clamp(1.35rem,6vw,1.75rem)] leading-tight font-bold text-ink">{nextAction.title}</h2><p className="mt-1 text-xs font-semibold text-ink-soft">{nextAction.meta}</p></div>
            <GradientButton accent={nextAction.accent} onClick={nextAction.run} className="w-full sm:w-auto sm:shrink-0">{nextAction.action}</GradientButton>
          </div>
        </GlassCard>}

        {!adhdMode && showGuidedPlan && hasWorkout && !workoutDone && (
          <GlassCard accent={ACCENTS.teal} className="p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0"><p className="truncate font-display text-base font-bold text-ink">{t(plan.programDay?.name ?? 'Guided workout')}</p><p className="text-[11px] font-medium text-ink-soft">{t('Start directly. Skip calendar and setup.')}</p></div>
              <button type="button" onClick={() => setSettings({ addons: { ...settings.addons, simple_show_guided_plan: false } })} aria-label={t('Hide guided plan')} className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-white/75 font-black text-ink-faint">×</button>
            </div>
            <div className="mt-3 flex justify-end gap-2"><button type="button" onClick={() => navigate(`/player/transition/${selectedDate}?lite=1`)} className="rounded-xl bg-white/70 px-3 py-2 text-[10px] font-bold text-ink-soft">{t('Quick')}</button><GradientButton accent={ACCENTS.teal} onClick={() => navigate(`/player/transition/${selectedDate}`)}>{t('Start')}</GradientButton></div>
          </GlassCard>
        )}

        {!adhdMode && showOrbitShortcut && <Link to={orbit.state.active_run ? '/orbit/run' : orbitSession ? '/orbit/campaign' : '/orbit'} className="block">
          <GlassCard accent={ACCENTS.ice} className="p-4">
            <div className="flex items-center gap-3"><div className="grid h-11 w-11 place-items-center rounded-2xl text-white" style={{ background: ACCENTS.ice.gradient }}><OrbitIcon className="h-5 w-5" /></div><div className="min-w-0 flex-1"><p className="font-display text-base font-bold text-ink">APEX Orbit</p><p className="truncate text-[11px] font-medium text-ink-soft">{orbit.state.active_run ? t('Continue interrupted run') : orbitSession ? `${orbitSession.adapted.duration_min} min · ${t(missionLabel(orbitSession.adapted.mission))}` : t('Your next run, already reasoned through')}</p></div><span className="font-mono text-[10px] font-bold text-sky-700">{t('RUN')}</span></div>
          </GlassCard>
        </Link>}

        {!adhdMode && showBodyIndexShortcut && <Link to="/avatar" className="block">
          <GlassCard accent={emerald} className="p-4">
            <div className="flex items-center gap-3"><div className="grid h-11 w-11 place-items-center rounded-2xl text-white" style={{ background: emerald.gradient }}><AvatarIcon className="h-5 w-5" /></div><div className="min-w-0 flex-1"><p className="font-display text-base font-bold text-ink">Your body index</p><p className="text-[11px] font-medium text-ink-soft">{t(`${momentum >= 0 ? '+' : ''}${momentum.toFixed(1)} over 14 days · tap for the full story`)}</p></div><span className="font-mono text-2xl font-bold text-emerald">{current?.overall.toFixed(0) ?? 'N/A'}</span></div>
          </GlassCard>
        </Link>}

        {!adhdMode && <div className="grid grid-cols-2 gap-2 text-center text-[11px] font-bold text-ink-soft"><Link to="/nutrition" className="glass rounded-2xl px-3 py-3">Food or activity changed?</Link><Link to="/transition" className="glass rounded-2xl px-3 py-3">Open full schedule</Link></div>}
      </div>
      <AnimatePresence>
        {showCalendar && (
          <motion.div
            className="fixed inset-0 z-[79] flex items-center justify-center p-4"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            data-simple-local-gesture
          >
            <button type="button" onClick={closeCalendar} aria-label={t('Close calendar')} className="absolute inset-0 bg-ink/20 backdrop-blur-md" />
            <motion.div
              initial={{ opacity: 0, scale: 0.93, y: 10 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.96, y: 8 }}
              className="relative flex h-[min(35dvh,330px)] min-h-[286px] w-[min(88vw,344px)] flex-col overflow-hidden rounded-[26px] border border-white/95 bg-white/96 p-4 shadow-[0_28px_80px_-30px_rgba(15,23,42,.72)]"
              role="dialog"
              aria-modal="true"
              aria-label={t('Choose a day')}
            >
              <div className="flex items-center justify-between gap-2">
                <button type="button" onClick={() => setCalendarMonth((value) => addMonths(value, -1))} aria-label={t('Previous month')} className="grid h-8 w-8 place-items-center rounded-full bg-ink/5 font-black text-ink-soft">‹</button>
                <div className="text-center"><p className="font-display text-sm font-black text-ink capitalize">{calendarMonthLabel}</p>{copiedDay ? <p className="mt-0.5 font-mono text-[8px] font-black tracking-wide text-cyan-700 uppercase">{t('Choose where to paste')}</p> : <button type="button" onClick={() => chooseDate(parseISO(today))} className="mt-0.5 font-mono text-[8px] font-black tracking-wide text-violet-700 uppercase">{t('Jump to today')}</button>}</div>
                <button type="button" onClick={() => setCalendarMonth((value) => addMonths(value, 1))} aria-label={t('Next month')} className="grid h-8 w-8 place-items-center rounded-full bg-ink/5 font-black text-ink-soft">›</button>
              </div>
              <div className="mt-2 grid grid-cols-7 text-center font-mono text-[8px] font-black text-ink-faint uppercase">
                {weekdayLabels.map((label, index) => <span key={`${label}-${index}`}>{label}</span>)}
              </div>
              <div className="mt-1 grid min-h-0 flex-1 grid-cols-7 gap-0.5" style={{ gridTemplateRows: `repeat(${Math.ceil(calendarDays.length / 7)}, minmax(0, 1fr))` }}>
                {calendarDays.map((date) => {
                  const active = isSameDay(date, selectedDateObject)
                  const todayDate = isSameDay(date, parseISO(today))
                  const inMonth = isSameMonth(date, calendarMonth)
                  const populated = hasDayData(date)
                  const iso = format(date, 'yyyy-MM-dd')
                  const copiedSource = copiedDay === iso
                  const pasteable = canPasteSimpleDay(copiedDay, iso)
                  return (
                    <button
                      key={iso}
                      type="button"
                      onPointerDown={() => beginCalendarPress(date)}
                      onPointerUp={endCalendarPress}
                      onPointerCancel={endCalendarPress}
                      onPointerLeave={endCalendarPress}
                      onContextMenu={(event) => {
                        event.preventDefault()
                        endCalendarPress()
                        calendarLongPressFired.current = true
                        setCalendarContextDate(iso)
                      }}
                      onClick={() => activateCalendarDate(date)}
                      aria-pressed={active}
                      aria-label={new Intl.DateTimeFormat(dateLocale, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(date)}
                      className={`relative grid min-h-0 touch-manipulation place-items-center rounded-xl font-mono text-[10px] font-black transition active:scale-90 ${copiedSource ? 'bg-cyan-700 text-white ring-2 ring-cyan-200' : pasteable ? 'border border-dashed border-cyan-400 bg-cyan-50 text-cyan-900' : active ? 'bg-violet-500 text-white shadow-sm' : todayDate ? 'bg-violet-100 text-violet-800' : inMonth ? 'text-ink' : 'text-ink-faint/45'}`}
                    >
                      {format(date, 'd')}
                      {copiedSource && <span className="absolute top-0.5 right-1 text-[7px]" aria-hidden>⧉</span>}
                      {populated && !active && <span className="absolute bottom-1 h-1 w-1 rounded-full bg-emerald" />}
                    </button>
                  )
                })}
              </div>
            </motion.div>
          </motion.div>
        )}
        {showCalendar && calendarContextDate && (
          <motion.div className="fixed inset-0 z-[82] flex items-center justify-center p-5" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} data-simple-local-gesture>
            <button type="button" onClick={() => setCalendarContextDate(null)} aria-label={t('Close')} className="absolute inset-0 bg-ink/28 backdrop-blur-md" />
            <motion.div initial={{ scale: 0.92, y: 10 }} animate={{ scale: 1, y: 0 }} exit={{ scale: 0.95, y: 8 }} className="relative w-full max-w-[310px] rounded-[24px] border border-white bg-white/96 p-4 shadow-2xl" role="dialog" aria-modal="true">
              <p className="font-display text-base font-black text-ink">{new Intl.DateTimeFormat(dateLocale, { weekday: 'long', day: 'numeric', month: 'long' }).format(parseISO(calendarContextDate))}</p>
              <p className="mt-1 text-[10px] font-semibold text-ink-faint">{t('Copy or clear this day’s meals and snacks.')}</p>
              <div className="mt-4 space-y-2">
                <button type="button" disabled={calendarBusy || foodStore.mealsForDate(calendarContextDate).length === 0 && !data.meal_logs.some((log) => log.date === calendarContextDate)} onClick={() => beginCopyDay(calendarContextDate)} className="w-full rounded-2xl bg-cyan-50 px-3 py-3 text-left text-xs font-black text-cyan-900 active:scale-[.98] disabled:opacity-40">⧉ {t('Copy')}</button>
                <button type="button" disabled={calendarBusy || foodStore.mealsForDate(calendarContextDate).length === 0 && !data.meal_logs.some((log) => log.date === calendarContextDate)} onClick={() => void clearCalendarDay(calendarContextDate)} className="w-full rounded-2xl bg-rose-50 px-3 py-3 text-left text-xs font-black text-rose-700 active:scale-[.98] disabled:opacity-40">{calendarBusy ? '…' : `× ${t('Clear')}`}</button>
              </div>
            </motion.div>
          </motion.div>
        )}
        {showCalendar && copiedDay && pasteTarget && (
          <motion.div className="fixed inset-0 z-[82] flex items-center justify-center p-5" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} data-simple-local-gesture>
            <button type="button" onClick={() => { setPasteTarget(null); setSelectingCopyMeals(false) }} aria-label={t('Close')} className="absolute inset-0 bg-ink/28 backdrop-blur-md" />
            <motion.div initial={{ scale: 0.92, y: 10 }} animate={{ scale: 1, y: 0 }} exit={{ scale: 0.95, y: 8 }} className="relative w-full max-w-[330px] overflow-hidden rounded-[24px] border border-white bg-white/96 p-4 shadow-2xl" role="dialog" aria-modal="true">
              <div className="flex items-start justify-between gap-3">
                <div><p className="font-display text-base font-black text-ink">{t(selectingCopyMeals ? 'Select meals or snacks' : 'Paste copied day')}</p><p className="mt-0.5 text-[10px] font-semibold text-ink-faint">{new Intl.DateTimeFormat(dateLocale, { day: 'numeric', month: 'short' }).format(parseISO(copiedDay))} → {new Intl.DateTimeFormat(dateLocale, { day: 'numeric', month: 'short' }).format(parseISO(pasteTarget))}</p></div>
                <button type="button" onClick={() => { setPasteTarget(null); setSelectingCopyMeals(false) }} aria-label={t('Close')} className="grid h-8 w-8 place-items-center rounded-full bg-ink/5 font-black text-ink-soft">×</button>
              </div>
              {!selectingCopyMeals ? (
                <div className="mt-4 space-y-2">
                  <button type="button" disabled={calendarBusy} onClick={() => void copyDayToTarget(pasteTarget, null)} className="w-full rounded-2xl bg-cyan-600 px-4 py-3 text-left text-xs font-black text-white shadow-sm active:scale-[.98] disabled:opacity-50"><span className="block">{calendarBusy ? t('Pasting…') : t('Paste')}</span><span className="mt-0.5 block text-[9px] font-semibold text-white/75">{t('All selected meals and snacks')}</span></button>
                  <button type="button" disabled={copiedMeals.length + copiedLegacyChecks.length === 0} onClick={() => { setSelectedCopyMealIds(new Set([...copiedMeals.map((meal) => meal.id), ...copiedLegacyChecks.map((check) => check.selectionId)])); setSelectingCopyMeals(true) }} className="w-full rounded-2xl border border-violet-100 bg-violet-50/70 px-4 py-3 text-left text-xs font-black text-violet-900 active:scale-[.98] disabled:opacity-40"><span className="block">{t('Select')}</span><span className="mt-0.5 block text-[9px] font-semibold text-violet-700/70">{t('Choose individual meals or snacks')}</span></button>
                </div>
              ) : (
                <div className="mt-3">
                  <div className="max-h-[36dvh] space-y-1.5 overflow-y-auto pr-0.5">
                    {copiedMeals.map((meal) => {
                      const checked = selectedCopyMealIds.has(meal.id)
                      const slotLabel = `${meal.meal_slot[0].toUpperCase()}${meal.meal_slot.slice(1)}`
                      return <button key={meal.id} type="button" aria-pressed={checked} onClick={() => setSelectedCopyMealIds((current) => { const next = new Set(current); if (checked) next.delete(meal.id); else next.add(meal.id); return next })} className="flex w-full items-center gap-2 rounded-2xl bg-slate-50/90 px-3 py-2.5 text-left"><span className={`grid h-6 w-6 shrink-0 place-items-center rounded-full text-[10px] font-black ${checked ? 'bg-violet-600 text-white' : 'border border-violet-200 text-transparent'}`}>✓</span><span className="min-w-0 flex-1"><span className="block truncate text-xs font-black text-ink">{t(meal.display_name)}</span><span className="block font-mono text-[8px] font-semibold text-ink-faint">{t(slotLabel)} · {Math.round(meal.total_kcal)} kcal</span></span></button>
                    })}
                    {copiedLegacyChecks.map((check) => {
                      const checked = selectedCopyMealIds.has(check.selectionId)
                      const slotLabel = `${check.slot[0].toUpperCase()}${check.slot.slice(1)}`
                      return <button key={check.selectionId} type="button" aria-pressed={checked} onClick={() => setSelectedCopyMealIds((current) => { const next = new Set(current); if (checked) next.delete(check.selectionId); else next.add(check.selectionId); return next })} className="flex w-full items-center gap-2 rounded-2xl bg-slate-50/90 px-3 py-2.5 text-left"><span className={`grid h-6 w-6 shrink-0 place-items-center rounded-full text-[10px] font-black ${checked ? 'bg-violet-600 text-white' : 'border border-violet-200 text-transparent'}`}>✓</span><span className="min-w-0 flex-1"><span className="block truncate text-xs font-black text-ink">{t(check.name)}</span><span className="block font-mono text-[8px] font-semibold text-ink-faint">{t(slotLabel)}{check.kcal > 0 ? ` · ${Math.round(check.kcal)} kcal` : ''}</span></span></button>
                    })}
                  </div>
                  <button type="button" disabled={calendarBusy || selectedCopyMealIds.size === 0} onClick={() => void copyDayToTarget(pasteTarget, selectedCopyMealIds)} className="mt-3 w-full rounded-2xl bg-violet-600 px-4 py-3 text-xs font-black text-white active:scale-[.98] disabled:opacity-40">{calendarBusy ? t('Pasting…') : `${t('Paste selected')} · ${selectedCopyMealIds.size}`}</button>
                </div>
              )}
            </motion.div>
          </motion.div>
        )}
        {quickPanel && (
          <motion.div
            className="fixed inset-0 z-[78] flex items-center justify-center p-5"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            data-simple-local-gesture
          >
            <button type="button" onClick={() => setQuickPanel(null)} aria-label={t('Close')} className="absolute inset-0 bg-ink/20 backdrop-blur-md" />
            <motion.div
              initial={{ opacity: 0, scale: 0.93, y: 12 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.96, y: 8 }}
              className={`relative w-full overflow-hidden rounded-[24px] border border-white/95 bg-white/95 p-4 shadow-[0_28px_80px_-30px_rgba(15,23,42,.7)] ${quickPanel === 'water' ? 'max-w-[310px]' : quickPanel === 'supplements' ? 'flex h-[min(32dvh,300px)] max-w-[330px] flex-col' : quickPanel === 'weight' ? 'max-w-[390px]' : 'max-w-[330px]'}`}
              role="dialog"
              aria-modal="true"
              aria-label={t(quickPanel === 'water' ? 'Water quick add' : quickPanel === 'supplements' ? 'Quick supplements' : quickPanel === 'targets' ? 'Daily calorie target' : quickPanel === 'macro' ? 'Daily food contributors' : quickPanel === 'weight' ? 'Weight trend' : 'Quick meals')}
            >
              <div className="flex items-start justify-between gap-3">
                <div><p className="font-display text-base font-black text-ink">{t(quickPanel === 'water' ? 'Water quick add' : quickPanel === 'supplements' ? 'Quick supplements' : quickPanel === 'targets' ? 'Daily calorie target' : quickPanel === 'macro' ? 'Daily food contributors' : quickPanel === 'weight' ? 'Weight trend' : 'Quick meals')}</p><p className="mt-0.5 text-[10px] font-semibold text-ink-faint">{quickPanel === 'water' ? `${water.toFixed(2)} / ${targets.water_l.toFixed(2)} L` : quickPanel === 'supplements' ? t('Tap any supplement to check or reopen it.') : quickPanel === 'targets' ? `${targets.kcal} kcal · ${t(GOALS[profile.goal].label)} · ${t(ACTIVITY_MULTIPLIERS[profile.activity_level].label)}` : quickPanel === 'macro' ? t('Ranked by contribution from today’s logged foods.') : quickPanel === 'weight' ? t('Your saved morning weigh-ins across weeks and months.') : t('Tap a meal to add, edit or remove it.')}</p></div>
                <button type="button" onClick={() => setQuickPanel(null)} aria-label={t('Close')} className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-ink/5 text-lg font-black text-ink-soft">×</button>
              </div>

              {quickPanel === 'meals' ? (
                <div className="mt-3">
                  <div className="max-h-[16dvh] space-y-1.5 overflow-y-auto pr-0.5">
                    {mealBlockStatuses.map((status) => {
                      const title = mealBlockLabel(status.block.kind)
                      const detail = status.loggedMeal?.display_name ?? status.plannedMeal?.name
                      return (
                        <div key={status.block.id} className="flex items-center gap-1 rounded-2xl bg-slate-50/90 pr-1.5">
                          <button type="button" disabled={busyMeal === status.plannedMeal?.id} onClick={() => void openMealBlock(status)} className="flex min-w-0 flex-1 items-center gap-2 px-3 py-2.5 text-left disabled:opacity-50">
                            <span className={`grid h-7 w-7 shrink-0 place-items-center rounded-full text-xs font-black ${status.completed ? 'bg-emerald text-white' : 'border border-amber-300 bg-white text-amber-700'}`}>{status.completed ? '✓' : '+'}</span>
                            <span className="min-w-0 flex-1"><span className="block truncate text-xs font-black text-ink">{t(title)}</span><span className="block truncate font-mono text-[9px] font-semibold text-ink-faint">{status.block.time}{detail ? ` · ${t(detail)}` : ''}</span></span>
                          </button>
                          {status.completed && <button type="button" onClick={() => void removeMealBlockEntry(status)} aria-label={`${t('Remove')} ${t(title)}`} className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-rose-50 text-[11px] font-black text-rose-600 shadow-sm">×</button>}
                        </div>
                      )
                    })}
                    {dateFoodMeals.filter((meal) => !mealBlockStatuses.some((status) => status.loggedMeal?.id === meal.id)).map((meal) => (
                      <div key={meal.id} className="flex items-center gap-2 rounded-2xl border border-violet-100 bg-violet-50/55 px-2 py-1.5">
                        <button type="button" onClick={() => void editQuickCustomMeal(meal)} className="min-w-0 flex-1 rounded-xl px-1 py-1 text-left"><span className="block truncate text-xs font-black text-ink">{meal.display_name}</span><span className="block font-mono text-[9px] font-semibold text-ink-faint">{Math.round(meal.total_kcal)} kcal · {t('Custom')} · {t('Tap to edit')}</span></button>
                        <button type="button" onClick={() => void foodStore.deleteMeal(meal.id)} aria-label={`${t('Remove')} ${meal.display_name}`} className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-rose-50 font-black text-rose-600">×</button>
                      </div>
                    ))}
                  </div>
                  <button type="button" onClick={() => openNutritionSection('meals')} className="mt-3 w-full rounded-2xl bg-amber-100/75 px-3 py-2.5 text-xs font-black text-amber-900">+ {t('Open full meal editor')}</button>
                </div>
              ) : quickPanel === 'supplements' ? (
                <div className="mt-3 flex min-h-0 flex-1 flex-col">
                  <div className="min-h-0 flex-1 space-y-2 overflow-y-auto pr-0.5">
                    {supplementGroups.map((group) => (
                      <section key={group.label}>
                        <div className="mb-1 flex items-center justify-between gap-2 px-1"><p className="truncate text-[9px] font-black tracking-wide text-ink-faint uppercase">{t(group.label)}</p><span className="font-mono text-[8px] font-bold text-ink-faint">{clockOf(group.time)}</span></div>
                        <div className="space-y-1">
                          {group.items.map((item) => {
                            const done = supplementDoneIds.has(item.id)
                            return (
                              <button key={item.id} type="button" onClick={() => toggleSupplement(item)} aria-pressed={done} className="flex w-full items-center gap-2 rounded-2xl bg-slate-50/90 px-3 py-2 text-left transition active:scale-[.985]">
                                <span className={`grid h-6 w-6 shrink-0 place-items-center rounded-full text-[10px] font-black ${done ? 'bg-emerald text-white' : 'border border-violet-200 bg-white text-transparent'}`}>✓</span>
                                <span className="min-w-0 flex-1"><span className={`block truncate text-[11px] font-black ${done ? 'text-ink-soft' : 'text-ink'}`}>{t(item.name)}</span><span className="block truncate font-mono text-[8px] font-semibold text-ink-faint">{item.dose}</span></span>
                              </button>
                            )
                          })}
                        </div>
                      </section>
                    ))}
                  </div>
                  <button type="button" onClick={() => openNutritionSection('supplements')} className="mt-3 w-full rounded-2xl bg-violet-100/80 px-3 py-2.5 text-xs font-black text-violet-900">{t('Open full supplement stack')}</button>
                </div>
              ) : quickPanel === 'targets' ? (
                <div className="mt-4">
                  <p className="font-mono text-[9px] font-black tracking-wide text-ink-faint uppercase">{t('Goal')}</p>
                  <div className="mt-2 grid grid-cols-3 gap-1.5">
                    {(Object.keys(GOALS) as Goal[]).map((goal) => {
                      const active = profile.goal === goal
                      return <button key={goal} type="button" aria-pressed={active} onClick={() => setProfile({ goal })} className={`rounded-xl px-2 py-2.5 text-[9px] font-black transition active:scale-95 ${active ? 'bg-amber-500 text-white shadow-sm' : 'bg-amber-50 text-amber-900'}`}>{t(GOALS[goal].label)}</button>
                    })}
                  </div>
                  <p className="mt-4 border-t border-ink/8 pt-3 font-mono text-[9px] font-black tracking-wide text-ink-faint uppercase">{t('Activity level')}</p>
                  <div className="mt-2 grid grid-cols-2 gap-1.5">
                    {(Object.keys(ACTIVITY_MULTIPLIERS) as ActivityLevel[]).map((activity) => {
                      const active = profile.activity_level === activity
                      return <button key={activity} type="button" aria-pressed={active} onClick={() => setProfile({ activity_level: activity })} className={`rounded-xl px-2.5 py-2 text-[9px] font-black transition active:scale-95 ${active ? 'bg-cyan-600 text-white shadow-sm' : 'bg-cyan-50 text-cyan-900'}`}>{t(ACTIVITY_MULTIPLIERS[activity].label)}</button>
                    })}
                  </div>
                  <p className="mt-3 text-center font-mono text-[9px] font-black text-ink-soft">{t('Updated target')}: {targets.kcal} kcal</p>
                </div>
              ) : quickPanel === 'weight' ? (
                <div className="mt-4">
                  <WeightTrend logs={data.daily_logs} anchorDate={selectedDate <= today ? selectedDate : today} unit={weightUnit} />
                </div>
              ) : quickPanel === 'macro' ? (
                <div className="mt-4">
                  <div className="flex gap-1 rounded-xl bg-ink/5 p-1">
                    {(['protein_g', 'carbs_g', 'fat_g'] as SimpleMacroKey[]).map((macro) => {
                      const label = macro === 'protein_g' ? 'Protein' : macro === 'carbs_g' ? 'Carbs' : 'Fat'
                      return <button key={macro} type="button" onClick={() => setSelectedMacro(macro)} aria-pressed={selectedMacro === macro} className={`flex-1 rounded-lg px-2 py-2 text-[9px] font-black ${selectedMacro === macro ? 'bg-white text-violet-800 shadow-sm' : 'text-ink-soft'}`}>{t(label)}</button>
                    })}
                  </div>
                  <div className="mt-3 max-h-[34dvh] space-y-1.5 overflow-y-auto">
                    {macroContributors.length > 0 ? macroContributors.map((contributor, index) => (
                      <div key={contributor.name} className="flex items-center gap-2 rounded-2xl bg-slate-50/90 px-3 py-2.5"><span className="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-violet-100 font-mono text-[9px] font-black text-violet-800">{index + 1}</span><span className="min-w-0 flex-1 truncate text-[11px] font-black text-ink">{contributor.name}</span><span className="shrink-0 font-mono text-[10px] font-black text-ink-soft">{contributor.amount.toFixed(contributor.amount % 1 ? 1 : 0)} g</span></div>
                    )) : <div className="rounded-2xl bg-slate-50 px-3 py-5 text-center text-[11px] font-semibold text-ink-faint">{t('No logged foods contribute to this macro yet.')}</div>}
                  </div>
                </div>
              ) : (
                <div className="mt-4">
                  {!customWaterOpen ? (
                    <div className="grid grid-cols-2 gap-2">
                      {[250, 300, 500].map((ml) => <button key={ml} type="button" onClick={() => addQuickWater(ml / 1000)} className="rounded-2xl bg-cyan-50 px-3 py-3 font-mono text-xs font-black text-cyan-800 active:scale-95">{ml} ml</button>)}
                      <button type="button" onClick={() => setCustomWaterOpen(true)} className="rounded-2xl bg-cyan-600 px-3 py-3 text-xs font-black text-white active:scale-95">{t('Custom')}</button>
                    </div>
                  ) : (
                    <div>
                      <label className="block text-[10px] font-black tracking-wide text-ink-faint uppercase">{t('Enter ml or litres')}</label>
                      <div className="mt-2 flex gap-2">
                        <input autoFocus type="text" inputMode="decimal" value={customWaterDraft} onChange={(event) => setCustomWaterDraft(event.target.value)} onKeyDown={(event) => event.key === 'Enter' && submitCustomWater()} placeholder={t('e.g. 750 ml or 0.75 L')} className="min-w-0 flex-1 rounded-xl border border-cyan-100 bg-cyan-50/50 px-3 py-2 font-mono text-base font-bold text-ink outline-none focus:border-cyan-400" />
                        <button type="button" onClick={submitCustomWater} className="rounded-xl bg-cyan-600 px-3 py-2 text-xs font-black text-white">{t('Add')}</button>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
      {quickMealBlockId && (
        <Suspense fallback={null}>
          <QuickMealComposer
            slot={mealSlotForBlock(quickMealBlockId)}
            mealBlockId={quickMealBlockId}
            date={selectedDate}
            title={t(mealBlockLabel(quickMealBlockId))}
            onClose={() => setQuickMealBlockId(null)}
            onLogged={() => setQuickMealBlockId(null)}
          />
        </Suspense>
      )}
      {quickMealEditor && (
        <Suspense fallback={null}>
          <QuickMealComposer
            slot={quickMealEditor.slot}
            mealBlockId={quickMealEditor.blockId}
            date={selectedDate}
            title={quickMealEditor.title}
            initialItems={quickMealEditor.items}
            plannedMealId={quickMealEditor.plannedMealId}
            replaceMealId={quickMealEditor.replaceMealId}
            onClose={() => setQuickMealEditor(null)}
            onLogged={() => setQuickMealEditor(null)}
          />
        </Suspense>
      )}
      <ManualWorkoutLogger open={showManualWorkout} onClose={closeManualWorkout} date={selectedDate} editSessionId={editingManualSessionId} focusExerciseName={editingManualExerciseName} />
      <PortalLanguageMenu />
    </div>
  )
}

function SimpleMetric({ icon, value, label, done, onClick, ariaLabel }: { icon: ReactNode; value: string; label: string; done: boolean; onClick?: () => void; ariaLabel?: string }) {
  const className = `glass relative rounded-2xl px-1.5 py-2.5 text-center ${done ? 'ring-1 ring-emerald/25' : ''} ${onClick ? 'cursor-pointer transition active:scale-[.96]' : ''}`
  const content = <><div className={`mx-auto grid h-6 w-6 place-items-center rounded-full ${done ? 'bg-emerald/12 text-emerald' : 'bg-ink/5 text-ink-soft'}`}>{done ? '✓' : icon}</div><p className="mt-1 font-mono text-[10px] font-bold text-ink">{value}</p><p className="truncate text-[8px] font-bold tracking-wide text-ink-faint uppercase">{label}</p>{onClick && <span className="absolute top-1.5 right-2 text-[8px] font-black text-ink-faint">↗</span>}</>
  return onClick ? <button type="button" onClick={onClick} aria-label={ariaLabel ?? label} className={className}>{content}</button> : <div className={className}>{content}</div>
}
