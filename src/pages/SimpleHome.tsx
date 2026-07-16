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
import { ACTIVITY_MULTIPLIERS, buildTargetMealPlan, computeTargets, type TargetMeal } from '../lib/nutrition'
import { planForDate, todayIso } from '../lib/plan'
import { dailyLogId } from '../lib/ids'
import type { DailyLog, Supplement } from '../lib/types'
import { aggregateConsumedMeals, reconcileConsumedMeals, type ComposerFoodItem, type FoodRecord, type LoggedMeal, type MealSlot } from '../lib/food'
import { GlassCard, GradientButton } from '../components/ui'
import { AvatarIcon, DropletIcon, LeafIcon, OrbitIcon, TransitionIcon } from '../components/Icons'
import { PortalLanguageMenu } from '../components/PortalLanguageMenu'
import { parseWaterAmountToLitres, selectNextSimpleAction, simpleCompletion, simpleDaySwipeOffset, simpleWaterTargetComplete, toggleSimpleWaterTarget, weightFromKg, weightToKg, weightUnitFromSettings } from '../lib/simpleMode'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { useOrbitStore } from '../orbit/store/OrbitStore'
import { missionLabel } from '../orbit/domain/analysis'
import { NutritionGlance } from '../components/food/NutritionGlance'
import { ManualWorkoutLogger, TodayManualWorkoutCard } from '../components/workout/ManualWorkoutLogger'

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

export function SimpleHome() {
  const { data, snapshots, upsert, remove, toast } = useStore()
  const foodStore = useFoodStore()
  const orbit = useOrbitStore()
  const navigate = useNavigate()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [showChecklist, setShowChecklist] = useState(false)
  const [showManualWorkout, setShowManualWorkout] = useState(false)
  const [editingManualSessionId, setEditingManualSessionId] = useState<string | null>(null)
  const [editingManualExerciseName, setEditingManualExerciseName] = useState<string | null>(null)
  const [busyMeal, setBusyMeal] = useState<string | null>(null)
  const [weightDraft, setWeightDraft] = useState('')
  const [quickPanel, setQuickPanel] = useState<'meals' | 'supplements' | 'water' | null>(null)
  const [quickMealSlot, setQuickMealSlot] = useState<MealSlot | null>(null)
  const [quickMealEditor, setQuickMealEditor] = useState<{ slot: MealSlot; title: string; items: ComposerFoodItem[]; plannedMealId: string | null; replaceMealId: string | null } | null>(null)
  const [customWaterOpen, setCustomWaterOpen] = useState(false)
  const [customWaterDraft, setCustomWaterDraft] = useState('')
  const today = todayIso()
  const [selectedDate, setSelectedDate] = useState(today)
  const [showCalendar, setShowCalendar] = useState(false)
  const [calendarMonth, setCalendarMonth] = useState(() => startOfMonth(parseISO(today)))
  const swipeStart = useRef<{ x: number; y: number; blockedByLocalGesture: boolean } | null>(null)
  const summaryActionsRef = useRef<HTMLDivElement>(null)
  const selectedDateObject = useMemo(() => parseISO(selectedDate), [selectedDate])
  const profile = data.profile
  const settings = data.settings
  const weightUnit = weightUnitFromSettings(settings)
  const adhdMode = settings?.addons.adhd_mode ?? false
  const showOrbitShortcut = settings?.addons.simple_show_orbit ?? true
  const showBodyIndexShortcut = settings?.addons.simple_show_body_index ?? true
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

  if (!profile || !targets) return null

  const mealIsDone = (meal: TargetMeal): boolean =>
    dateFoodMeals.some((logged) => logged.source_planned_meal_id === meal.id) ||
    data.meal_logs.some((logged) => logged.date === selectedDate && logged.meal_id === meal.id)
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

  const completedMeals = mealPlan.filter(mealIsDone).length
  const completedGroups = supplementGroups.filter(groupIsDone).length
  const hasWorkout = plan.exercises.length > 0
  const totalTasks = mealPlan.length + supplementGroups.length + 1 + Number(hasWorkout)
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
    if (existing) return existing
    return foodStore.savePrivateFood({
      name: entry.snapshot_name, names_i18n: { en: entry.snapshot_name }, brand: entry.snapshot_brand,
      barcode: null, provider_product_id: null, external_image_url: null, package_quantity: null,
      nutrition_basis: entry.snapshot_nutrition_basis, preparation_state: entry.snapshot_preparation_state,
      kcal_100: entry.snapshot_kcal_100, protein_100: entry.snapshot_protein_100,
      carbs_100: entry.snapshot_carbs_100, fat_100: entry.snapshot_fat_100,
      fibre_100: entry.snapshot_fibre_100, sugar_100: entry.snapshot_sugar_100,
      saturated_fat_100: entry.snapshot_saturated_fat_100, salt_100: entry.snapshot_salt_100,
      serving_amount: null, serving_unit: null, serving_grams_or_ml: null, piece_grams_or_ml: null,
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

  const editQuickPlannedMeal = async (meal: TargetMeal): Promise<void> => {
    const actual = dateFoodMeals.find((logged) => logged.source_planned_meal_id === meal.id)
    const items = actual ? await loggedMealItems(actual) : [await plannedFoodItem(meal)]
    setQuickPanel(null)
    setQuickMealEditor({
      slot: mealSlotFor(meal), title: actual?.display_name ?? meal.name, items,
      plannedMealId: meal.id, replaceMealId: actual?.id ?? null,
    })
  }

  const editQuickCustomMeal = async (meal: LoggedMeal): Promise<void> => {
    setQuickPanel(null)
    setQuickMealEditor({
      slot: meal.meal_slot, title: meal.display_name, items: await loggedMealItems(meal),
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
        await foodStore.logMeal({
          date: selectedDate, slot: mealSlotFor(meal), name: meal.name, items: [item], sourcePlannedMealId: meal.id,
          loggedAs: 'planned', idempotencyKey: `simple-planned:${profile.user_id}:${selectedDate}:${meal.id}`,
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

  const patchDailyLog = (patch: Partial<DailyLog>): void => {
    if (!profile) return
    const base: DailyLog = dailyLog ?? {
      id: dailyLogId(selectedDate, profile.user_id), user_id: profile.user_id, date: selectedDate,
      kcal: null, protein_g: null, fat_g: null, carbs_g: null, water_l: 0,
      estimated_tdee: null, computed_pal: null, activity_mode: 'quick', weight_kg: null,
    }
    upsert('daily_logs', { ...base, ...patch })
  }

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
  const toggleWater = (): void => setWaterAmount(toggleSimpleWaterTarget(water, targets.water_l))
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

  const moveDay = (offset: number): void => {
    setSelectedDate(format(addDays(selectedDateObject, offset), 'yyyy-MM-dd'))
    setShowChecklist(false)
    setQuickPanel(null)
    setShowCalendar(false)
  }

  const chooseDate = (date: Date): void => {
    setSelectedDate(format(date, 'yyyy-MM-dd'))
    setCalendarMonth(startOfMonth(date))
    setShowChecklist(false)
    setQuickPanel(null)
    setShowCalendar(false)
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
    ...mealPlan.filter((meal) => !mealIsDone(meal)).map((meal) => ({
      time: minuteOf(meal.time), eyebrow: 'Next meal', title: meal.name,
      meta: `${meal.time} · ${meal.kcal} kcal`, action: 'Log as planned',
      run: () => void toggleMeal(meal), accent: ACCENTS.amber,
    })),
    ...supplementGroups.filter((group) => !groupIsDone(group)).map((group) => ({
      time: group.time, eyebrow: 'Next supplements', title: group.label,
      meta: `${clockOf(group.time)} · ${t(`${group.items.length} items`)}`, action: 'Mark group done',
      run: () => toggleSupplementGroup(group), accent: ACCENTS.ice,
    })),
    ...(hasWorkout && !workoutDone ? [{
      time: minuteOf(trainingTime), eyebrow: 'Today’s movement', title: plan.programDay?.name ?? 'Training',
      meta: t(`~${plan.programDay?.est_minutes ?? 15} min · ${plan.exercises.length} exercises`), action: 'Start session',
      run: () => navigate(`/player/transition/${selectedDate}`), accent: ACCENTS.teal,
    }] : []),
    ...(!waterDone ? [{
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

  return (
    <div
      className="mx-auto w-full max-w-3xl touch-pan-y"
      onTouchStart={(event) => {
        const touch = event.changedTouches[0]
        const target = event.target
        const blockedByLocalGesture = target instanceof Element && Boolean(target.closest('[data-simple-local-gesture]'))
        if (touch) swipeStart.current = { x: touch.clientX, y: touch.clientY, blockedByLocalGesture }
      }}
      onTouchEnd={(event) => {
        const touch = event.changedTouches[0]
        if (touch) finishSwipe(touch.clientX, touch.clientY)
      }}
      onTouchCancel={() => {
        swipeStart.current = null
      }}
    >
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
            mealsTotal={mealPlan.length}
            status={foodStore.syncing ? 'SYNCING' : foodStore.queued ? 'QUEUED OFFLINE' : foodStore.ready ? 'PRIVATE' : 'LOADING'}
            onOpen={() => openNutritionSection('meals')}
            cornerControl={selectedDate <= today ? (
              <label data-simple-local-gesture className="flex items-center rounded-lg border border-amber-200/65 bg-white/82 px-2 py-1 shadow-sm" title={t('Morning weight')}>
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
                  className="w-11 bg-transparent text-right font-mono text-[11px] font-black text-ink outline-none"
                  aria-label={t(weightUnit === 'lb' ? 'Morning weight in pounds' : 'Morning weight in kilograms')}
                />
                <span className="ml-1 font-mono text-[8px] font-black text-ink-faint uppercase">{weightUnit}</span>
              </label>
            ) : undefined}
          />
        </GlassCard>

        <div ref={summaryActionsRef} id="simple-summary-actions" className="grid scroll-mt-28 grid-cols-4 gap-2" data-simple-local-gesture>
          <SimpleMetric icon={<LeafIcon className="h-4 w-4" />} value={`${completedMeals}/${mealPlan.length}`} label={t('Meals')} done={mealPlan.length > 0 && completedMeals === mealPlan.length} onClick={() => setQuickPanel('meals')} ariaLabel={t('Edit meals')} />
          <SimpleMetric icon="✦" value={`${supplementDoneIds.size}/${data.supplements.length}`} label={t('Supps')} done={data.supplements.length > 0 && supplementDoneIds.size === data.supplements.length} onClick={() => setQuickPanel('supplements')} ariaLabel={t('Open supplements')} />
          <SimpleMetric icon={<DropletIcon className="h-4 w-4" />} value={`${water.toFixed(1)}L`} label={t('Water')} done={waterDone} onClick={() => { setCustomWaterOpen(false); setQuickPanel('water') }} ariaLabel={t('Add water')} />
          <SimpleMetric icon={<TransitionIcon className="h-4 w-4" />} value={workoutDone ? t('Done') : hasWorkout ? `${plan.programDay?.est_minutes ?? 15}m` : t('Rest')} label={t('Training')} done={workoutDone || !hasWorkout} onClick={openTraining} ariaLabel={t('Open training')} />
        </div>

        <TodayManualWorkoutCard compact date={selectedDate} onAdd={openNewManualWorkout} onEdit={openManualWorkout} />

        {!adhdMode && <GlassCard accent={nextAction.accent} breathe className="p-5 sm:p-6">
          <p className="font-mono text-[10px] font-bold tracking-[0.18em] uppercase" style={{ color: nextAction.accent.deep }}>{nextAction.eyebrow}</p>
          <div className="mt-2 grid items-end gap-4 sm:grid-cols-[minmax(0,1fr)_auto]">
            <div className="min-w-0"><h2 className="break-words font-display text-[clamp(1.35rem,6vw,1.75rem)] leading-tight font-bold text-ink">{nextAction.title}</h2><p className="mt-1 text-xs font-semibold text-ink-soft">{nextAction.meta}</p></div>
            <GradientButton accent={nextAction.accent} onClick={nextAction.run} className="w-full sm:w-auto sm:shrink-0">{nextAction.action}</GradientButton>
          </div>
        </GlassCard>}

        {!adhdMode && <GlassCard className="p-4">
          <button type="button" onClick={() => setShowChecklist((value) => !value)} className="flex w-full items-center justify-between text-left">
            <div><p className="font-display text-base font-bold text-ink">Today’s checklist</p><p className="mt-0.5 text-[11px] font-medium text-ink-soft">{t(`${completedTasks} of ${totalTasks} essentials complete`)}</p></div>
            <span className="text-xl text-ink-soft">{showChecklist ? '−' : '+'}</span>
          </button>
          {showChecklist && (
            <div className="mt-3 space-y-2 border-t border-ink/8 pt-3">
              {mealPlan.map((meal) => <ChecklistRow key={meal.id} time={meal.time} title={meal.name} detail={`${meal.kcal} kcal`} done={mealIsDone(meal)} busy={busyMeal === meal.id} onClick={() => void toggleMeal(meal)} />)}
              {supplementGroups.map((group) => <ChecklistRow key={group.label} time={clockOf(group.time)} title={group.label} detail={t(`${group.items.length} supplements`)} done={groupIsDone(group)} onClick={() => toggleSupplementGroup(group)} />)}
              <ChecklistRow time="NOW" title={t('Water')} detail={`${water.toFixed(2)} / ${targets.water_l.toFixed(2)} L`} done={waterDone} onClick={toggleWater} />
            </div>
          )}
        </GlassCard>}

        {!adhdMode && hasWorkout && !workoutDone && (
          <GlassCard accent={ACCENTS.teal} className="p-4">
            <div className="flex items-center justify-between gap-3"><div><p className="font-display text-base font-bold text-ink">{plan.programDay?.name}</p><p className="text-[11px] font-medium text-ink-soft">Start directly. Skip calendar and setup.</p></div><div className="flex gap-2"><button type="button" onClick={() => navigate(`/player/transition/${selectedDate}?lite=1`)} className="rounded-xl bg-white/70 px-3 py-2 text-[10px] font-bold text-ink-soft">Quick</button><GradientButton accent={ACCENTS.teal} onClick={() => navigate(`/player/transition/${selectedDate}`)}>Start</GradientButton></div></div>
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
            <button type="button" onClick={() => setShowCalendar(false)} aria-label={t('Close calendar')} className="absolute inset-0 bg-ink/20 backdrop-blur-md" />
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
                <div className="text-center"><p className="font-display text-sm font-black text-ink capitalize">{calendarMonthLabel}</p><button type="button" onClick={() => chooseDate(parseISO(today))} className="mt-0.5 font-mono text-[8px] font-black tracking-wide text-violet-700 uppercase">{t('Jump to today')}</button></div>
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
                  return (
                    <button
                      key={format(date, 'yyyy-MM-dd')}
                      type="button"
                      onClick={() => chooseDate(date)}
                      aria-pressed={active}
                      aria-label={new Intl.DateTimeFormat(dateLocale, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(date)}
                      className={`relative grid min-h-0 place-items-center rounded-xl font-mono text-[10px] font-black transition active:scale-90 ${active ? 'bg-violet-500 text-white shadow-sm' : todayDate ? 'bg-violet-100 text-violet-800' : inMonth ? 'text-ink' : 'text-ink-faint/45'}`}
                    >
                      {format(date, 'd')}
                      {populated && !active && <span className="absolute bottom-1 h-1 w-1 rounded-full bg-emerald" />}
                    </button>
                  )
                })}
              </div>
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
              className={`relative w-full overflow-hidden rounded-[24px] border border-white/95 bg-white/95 p-4 shadow-[0_28px_80px_-30px_rgba(15,23,42,.7)] ${quickPanel === 'water' ? 'max-w-[310px]' : quickPanel === 'supplements' ? 'flex h-[min(32dvh,300px)] max-w-[330px] flex-col' : 'max-w-[330px]'}`}
              role="dialog"
              aria-modal="true"
              aria-label={t(quickPanel === 'water' ? 'Water quick add' : quickPanel === 'supplements' ? 'Quick supplements' : 'Quick meals')}
            >
              <div className="flex items-start justify-between gap-3">
                <div><p className="font-display text-base font-black text-ink">{t(quickPanel === 'water' ? 'Water quick add' : quickPanel === 'supplements' ? 'Quick supplements' : 'Quick meals')}</p><p className="mt-0.5 text-[10px] font-semibold text-ink-faint">{quickPanel === 'water' ? `${water.toFixed(2)} / ${targets.water_l.toFixed(2)} L` : quickPanel === 'supplements' ? t('Tap any supplement to check or reopen it.') : t('Tap a meal to add, edit or remove it.')}</p></div>
                <button type="button" onClick={() => setQuickPanel(null)} aria-label={t('Close')} className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-ink/5 text-lg font-black text-ink-soft">×</button>
              </div>

              {quickPanel === 'meals' ? (
                <div className="mt-3">
                  <div className="max-h-[16dvh] space-y-1.5 overflow-y-auto pr-0.5">
                    {mealPlan.map((meal) => {
                      const done = mealIsDone(meal)
                      return (
                        <div key={meal.id} className="flex items-center gap-1 rounded-2xl bg-slate-50/90 pr-1.5">
                          <button type="button" disabled={busyMeal === meal.id} onClick={() => void toggleMeal(meal)} className="flex min-w-0 flex-1 items-center gap-2 px-3 py-2.5 text-left disabled:opacity-50">
                            <span className={`grid h-7 w-7 shrink-0 place-items-center rounded-full text-xs font-black ${done ? 'bg-emerald text-white' : 'border border-amber-300 bg-white text-amber-700'}`}>{done ? '✓' : '+'}</span>
                            <span className="min-w-0 flex-1"><span className="block truncate text-xs font-black text-ink">{t(meal.name)}</span><span className="block font-mono text-[9px] font-semibold text-ink-faint">{meal.time} · {meal.kcal} kcal</span></span>
                          </button>
                          <button type="button" onClick={() => void editQuickPlannedMeal(meal)} aria-label={`${t('Edit')} ${t(meal.name)}`} className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-white text-[11px] font-black text-violet-700 shadow-sm">✎</button>
                        </div>
                      )
                    })}
                    {dateFoodMeals.filter((meal) => !meal.source_planned_meal_id).map((meal) => (
                      <div key={meal.id} className="flex items-center gap-2 rounded-2xl border border-violet-100 bg-violet-50/55 px-2 py-1.5">
                        <button type="button" onClick={() => void editQuickCustomMeal(meal)} className="min-w-0 flex-1 rounded-xl px-1 py-1 text-left"><span className="block truncate text-xs font-black text-ink">{meal.display_name}</span><span className="block font-mono text-[9px] font-semibold text-ink-faint">{Math.round(meal.total_kcal)} kcal · {t('Custom')} · {t('Tap to edit')}</span></button>
                        <button type="button" onClick={() => void foodStore.deleteMeal(meal.id)} aria-label={`${t('Remove')} ${meal.display_name}`} className="grid h-7 w-7 shrink-0 place-items-center rounded-full bg-rose-50 font-black text-rose-600">×</button>
                      </div>
                    ))}
                  </div>
                  <div className="mt-3 grid grid-cols-2 gap-2" aria-label={t('Add food')}>
                    {(['breakfast', 'lunch', 'dinner', 'snack'] as MealSlot[]).map((slot) => (
                      <button key={slot} type="button" onClick={() => { setQuickPanel(null); setQuickMealSlot(slot) }} className="rounded-2xl border border-amber-100 bg-amber-50/70 px-3 py-2.5 text-left text-[11px] font-black text-amber-900 active:scale-[.98]">
                        <span className="mr-1 text-amber-600">+</span>{t(`${slot[0].toUpperCase()}${slot.slice(1)}`)}
                      </button>
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
                        <input autoFocus type="text" inputMode="decimal" value={customWaterDraft} onChange={(event) => setCustomWaterDraft(event.target.value)} onKeyDown={(event) => event.key === 'Enter' && submitCustomWater()} placeholder={t('e.g. 750 ml or 0.75 L')} className="min-w-0 flex-1 rounded-xl border border-cyan-100 bg-cyan-50/50 px-3 py-2 font-mono text-xs font-bold text-ink outline-none focus:border-cyan-400" />
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
      {quickMealSlot && (
        <Suspense fallback={null}>
          <QuickMealComposer
            slot={quickMealSlot}
            date={selectedDate}
            onClose={() => setQuickMealSlot(null)}
            onLogged={() => setQuickMealSlot(null)}
          />
        </Suspense>
      )}
      {quickMealEditor && (
        <Suspense fallback={null}>
          <QuickMealComposer
            slot={quickMealEditor.slot}
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

function ChecklistRow({ time, title, detail, done, busy = false, onClick }: { time: string; title: string; detail: string; done: boolean; busy?: boolean; onClick: () => void }) {
  return <button type="button" disabled={busy} onClick={onClick} className="flex w-full items-center gap-3 rounded-2xl bg-white/55 px-3 py-2.5 text-left disabled:opacity-60"><span className={`grid h-7 w-7 shrink-0 place-items-center rounded-full text-xs font-bold ${done ? 'bg-emerald text-white' : 'border border-ink/15 text-transparent'}`}>✓</span><span className="min-w-0 flex-1"><span className={`block truncate text-[13px] font-bold ${done ? 'text-ink-soft line-through' : 'text-ink'}`}>{title}</span><span className="block truncate text-[10px] font-medium text-ink-faint">{detail}</span></span><span className="font-mono text-[9px] font-bold text-ink-faint">{time}</span></button>
}
