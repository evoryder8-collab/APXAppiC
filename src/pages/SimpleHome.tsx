import { useMemo, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { addDays, format, parseISO } from 'date-fns'
import { Link, useNavigate } from 'react-router-dom'
import { motion } from 'framer-motion'
import { useStore } from '../store/AppStore'
import { useFoodStore } from '../store/FoodStore'
import { ACCENTS } from '../lib/theme'
import { ACTIVITY_MULTIPLIERS, buildTargetMealPlan, computeTargets, type TargetMeal } from '../lib/nutrition'
import { planForDate, todayIso } from '../lib/plan'
import { dailyLogId } from '../lib/ids'
import type { DailyLog, Supplement } from '../lib/types'
import { aggregateConsumedMeals, reconcileConsumedMeals, type ComposerFoodItem, type MealSlot } from '../lib/food'
import { GlassCard, GradientButton } from '../components/ui'
import { AvatarIcon, DropletIcon, LeafIcon, OrbitIcon, TransitionIcon } from '../components/Icons'
import { PortalLanguageMenu } from '../components/PortalLanguageMenu'
import { selectNextSimpleAction, simpleCompletion, simpleDaySwipeOffset, simpleWaterTargetComplete, toggleSimpleWaterTarget } from '../lib/simpleMode'
import { translateInterfaceText, useLanguage } from '../lib/i18n'
import { useOrbitStore } from '../orbit/store/OrbitStore'
import { missionLabel } from '../orbit/domain/analysis'
import { NutritionGlance } from '../components/food/NutritionGlance'
import { ManualWorkoutLogger, TodayManualWorkoutCard } from '../components/workout/ManualWorkoutLogger'

const emerald = ACCENTS.emerald

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
  const today = todayIso()
  const [selectedDate, setSelectedDate] = useState(today)
  const swipeStart = useRef<{ x: number; y: number; blockedByLocalGesture: boolean } | null>(null)
  const selectedDateObject = useMemo(() => parseISO(selectedDate), [selectedDate])
  const profile = data.profile
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

  if (!profile || !targets) return null

  const mealIsDone = (meal: TargetMeal): boolean =>
    dateFoodMeals.some((logged) => logged.source_planned_meal_id === meal.id) ||
    data.meal_logs.some((logged) => logged.date === selectedDate && logged.meal_id === meal.id)
  const groupIsDone = (group: { items: Supplement[] }): boolean =>
    group.items.length > 0 && group.items.every((item) => supplementDoneIds.has(item.id))

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

  const setWaterAmount = (value: number): void => {
    if (!profile) return
    const base: DailyLog = dailyLog ?? {
      id: dailyLogId(selectedDate, profile.user_id), user_id: profile.user_id, date: selectedDate,
      kcal: null, protein_g: null, fat_g: null, carbs_g: null, water_l: 0,
      estimated_tdee: null, computed_pal: null, activity_mode: 'quick', weight_kg: null,
    }
    upsert('daily_logs', { ...base, water_l: Math.min(6, Math.max(0, Number(value.toFixed(2)))) })
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

  const moveDay = (offset: number): void => {
    setSelectedDate(format(addDays(selectedDateObject, offset), 'yyyy-MM-dd'))
    setShowChecklist(false)
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
          <button type="button" onClick={() => setSelectedDate(today)} className="min-w-0 rounded-full bg-white/55 px-4 py-2 text-center shadow-sm">
            <span className="block truncate font-mono text-[10px] font-bold tracking-[0.14em] text-ink-faint uppercase">{format(selectedDateObject, 'EEEE, d MMMM')}</span>
            <span className="mt-0.5 block text-[9px] font-black tracking-wide text-violet-700 uppercase">{selectedDate === today ? t('Today') : t('Tap to return to today')}</span>
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
        <Link to="/nutrition" className="block" aria-label={t('Open nutrition details')}>
          <GlassCard accent={ACCENTS.amber} className="overflow-hidden p-0">
            <NutritionGlance
              target={targets}
              consumed={consumed}
              mealsDone={completedMeals}
              mealsTotal={mealPlan.length}
              status={foodStore.syncing ? 'SYNCING' : foodStore.queued ? 'QUEUED OFFLINE' : foodStore.ready ? 'PRIVATE' : 'LOADING'}
            />
          </GlassCard>
        </Link>

        <TodayManualWorkoutCard date={selectedDate} onAdd={openNewManualWorkout} onEdit={openManualWorkout} />

        <GlassCard accent={nextAction.accent} breathe className="p-5 sm:p-6">
          <p className="font-mono text-[10px] font-bold tracking-[0.18em] uppercase" style={{ color: nextAction.accent.deep }}>{nextAction.eyebrow}</p>
          <div className="mt-2 grid items-end gap-4 sm:grid-cols-[minmax(0,1fr)_auto]">
            <div className="min-w-0"><h2 className="break-words font-display text-[clamp(1.35rem,6vw,1.75rem)] leading-tight font-bold text-ink">{nextAction.title}</h2><p className="mt-1 text-xs font-semibold text-ink-soft">{nextAction.meta}</p></div>
            <GradientButton accent={nextAction.accent} onClick={nextAction.run} className="w-full sm:w-auto sm:shrink-0">{nextAction.action}</GradientButton>
          </div>
        </GlassCard>

        <div className="grid grid-cols-4 gap-2">
          <SimpleMetric icon={<LeafIcon className="h-4 w-4" />} value={`${completedMeals}/${mealPlan.length}`} label={t('Meals')} done={completedMeals === mealPlan.length} />
          <SimpleMetric icon="✦" value={`${completedGroups}/${supplementGroups.length}`} label={t('Supps')} done={completedGroups === supplementGroups.length} />
          <SimpleMetric icon={<DropletIcon className="h-4 w-4" />} value={`${water.toFixed(1)}L`} label={t('Water')} done={waterDone} />
          <SimpleMetric icon={<TransitionIcon className="h-4 w-4" />} value={workoutDone ? t('Done') : hasWorkout ? `${plan.programDay?.est_minutes ?? 15}m` : t('Rest')} label={t('Training')} done={workoutDone || !hasWorkout} onClick={openTraining} ariaLabel={t('Open training')} />
        </div>

        <GlassCard className="p-4">
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
        </GlassCard>

        {hasWorkout && !workoutDone && (
          <GlassCard accent={ACCENTS.teal} className="p-4">
            <div className="flex items-center justify-between gap-3"><div><p className="font-display text-base font-bold text-ink">{plan.programDay?.name}</p><p className="text-[11px] font-medium text-ink-soft">Start directly. Skip calendar and setup.</p></div><div className="flex gap-2"><button type="button" onClick={() => navigate(`/player/transition/${selectedDate}?lite=1`)} className="rounded-xl bg-white/70 px-3 py-2 text-[10px] font-bold text-ink-soft">Quick</button><GradientButton accent={ACCENTS.teal} onClick={() => navigate(`/player/transition/${selectedDate}`)}>Start</GradientButton></div></div>
          </GlassCard>
        )}

        <Link to={orbit.state.active_run ? '/orbit/run' : orbitSession ? '/orbit/campaign' : '/orbit'} className="block">
          <GlassCard accent={ACCENTS.ice} className="p-4">
            <div className="flex items-center gap-3"><div className="grid h-11 w-11 place-items-center rounded-2xl text-white" style={{ background: ACCENTS.ice.gradient }}><OrbitIcon className="h-5 w-5" /></div><div className="min-w-0 flex-1"><p className="font-display text-base font-bold text-ink">APEX Orbit</p><p className="truncate text-[11px] font-medium text-ink-soft">{orbit.state.active_run ? t('Continue interrupted run') : orbitSession ? `${orbitSession.adapted.duration_min} min · ${t(missionLabel(orbitSession.adapted.mission))}` : t('Your next run, already reasoned through')}</p></div><span className="font-mono text-[10px] font-bold text-sky-700">{t('RUN')}</span></div>
          </GlassCard>
        </Link>

        <Link to="/avatar" className="block">
          <GlassCard accent={emerald} className="p-4">
            <div className="flex items-center gap-3"><div className="grid h-11 w-11 place-items-center rounded-2xl text-white" style={{ background: emerald.gradient }}><AvatarIcon className="h-5 w-5" /></div><div className="min-w-0 flex-1"><p className="font-display text-base font-bold text-ink">Your body index</p><p className="text-[11px] font-medium text-ink-soft">{t(`${momentum >= 0 ? '+' : ''}${momentum.toFixed(1)} over 14 days · tap for the full story`)}</p></div><span className="font-mono text-2xl font-bold text-emerald">{current?.overall.toFixed(0) ?? 'N/A'}</span></div>
          </GlassCard>
        </Link>

        <div className="grid grid-cols-2 gap-2 text-center text-[11px] font-bold text-ink-soft"><Link to="/nutrition" className="glass rounded-2xl px-3 py-3">Food or activity changed?</Link><Link to="/transition" className="glass rounded-2xl px-3 py-3">Open full schedule</Link></div>
      </div>
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
