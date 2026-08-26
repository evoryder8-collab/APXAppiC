import { estimateWaterContent } from '../../lib/hydration.ts'
import { lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ACCENTS } from '../../lib/theme'
import {
  availableFoodUnits,
  beginFoodSelection,
  calculatePortion,
  commitFoodSelection,
  composerItemFromSelection,
  displayFoodName,
  expandFoodSearchQueries,
  foodFromLoggedEntry,
  foodNeedsPrivateMaterialization,
  isFoodNutritionComplete,
  isPlannedPrescriptionFood,
  mealTotals,
  mergeExtendedFoodResults,
  normalizeFoodSearch,
  parseDecimalInput,
  rankFoods,
  type ComposerFoodItem,
  type FoodRecord,
  type FoodSelectionDraft,
  type FoodUnit,
  type MealSlot,
} from '../../lib/food'
import { useFoodStore } from '../../store/FoodStore'
import { GlassCard } from '../ui'
import { BarcodeIcon } from '../Icons'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { mealBlockIdempotencyKey, normalizeMealBlockSettings, type MealBlockIdentity, type MealBlockKind } from '../../lib/mealBlocks'
import { useStore } from '../../store/AppStore'
import { rankMealHistoryRecommendations } from '../../lib/mealExperience'
import { timeZoneFromSettings, zonedClock, zonedDateTimeToIso } from '../../lib/mealTiming'
import { computeTargets, nutritionPlanContext } from '../../lib/nutrition'
import { ATHLETE_SUPPORT_PROTOCOLS } from '../../lib/personalProtocol'
import type { IntroLanguage } from '../../lib/introLanguage'
import { mealMacroStatus, type MealMacroKind } from '../../lib/mealMacroGuidance'
import { defaultMealGuideSections } from '../../lib/mealGuide'
import {
  mealUndoSecondsRemaining,
  removeMealItemWithUndo,
  restoreMealItemFromUndo,
  type MealUndoState,
} from '../../lib/mealUndo'

const BarcodeScanner = lazy(() => import('./BarcodeScanner').then((module) => ({ default: module.BarcodeScanner })))
const amber = ACCENTS.amber

interface MealComposerProps {
  slot: MealSlot
  date?: string
  planning?: boolean
  title?: string
  initialItems?: ComposerFoodItem[]
  plannedMealId?: string | null
  mealBlockId?: MealBlockKind | null
  mealIdentity?: MealBlockIdentity | null
  targetTime?: string | null
  replaceMealId?: string | null
  onClose: () => void
  onLogged?: () => void
}

function foodProvenanceLabel(food: FoodRecord): string {
  if (food.source === 'private') return 'Your private food'
  if (food.source === 'open_food_facts') return 'Check the package label.'
  if (food.confidence === 'provider_verified') return 'Verified label or nutrition-provider reference'
  return 'Curated reference profile. Product labels can vary.'
}

const MEAL_PROTOCOL_INDEX: Record<MealSlot, number> = {
  breakfast: 0,
  lunch: 1,
  snack: 2,
  dinner: 3,
}

function goalAdjustedProtocolLine(line: string, persona: string, goal: string): string {
  const scale = persona === 'june'
    ? goal === 'recomp' ? 0.85 : goal === 'maintain' ? 0.93 : 1
    : goal === 'bulk' ? 1.1 : goal === 'maintain' ? 1.04 : 1
  if (scale === 1 || !/(?:oats?|bulgur|sweet potato|rice|evoo|walnuts?|seeds?|protein|whey)/i.test(line)) return line
  return line.replace(/^(\d+)(?:-(\d+))?\s*(g|ml)\b/i, (_match, lowText: string, highText: string | undefined, unit: string) => {
    const low = Math.max(1, Math.round((Number(lowText) * scale) / 5) * 5)
    const high = highText ? Math.max(low, Math.round((Number(highText) * scale) / 5) * 5) : null
    return `${low}${high && high !== low ? `-${high}` : ''} ${unit}`
  })
}

function protocolFoodQuery(line: string): { query: string; quantity: number; unit: FoodUnit } {
  const ranged = line.match(/^(\d+)(?:-(\d+))?\s*(g|ml)\s+(.+)$/i)
  if (ranged) {
    const low = Number(ranged[1])
    const high = ranged[2] ? Number(ranged[2]) : low
    return { query: ranged[4].replace(/\s+(?:when|or|according|providing|with)\b.*$/i, '').trim(), quantity: Math.round((low + high) / 2), unit: ranged[3].toLowerCase() as FoodUnit }
  }
  const piece = line.match(/^1\s+(.+)$/i)
  if (piece) return { query: piece[1].replace(/\s+or\b.*$/i, '').trim(), quantity: 1, unit: 'piece' }
  return {
    query: line.replace(/^Optional\s+/i, '').replace(/\s+or\b.*$/i, '').trim(),
    quantity: 100,
    unit: 'g',
  }
}

function translateProtocolLine(line: string, language: IntroLanguage): string {
  const portion = line.match(/^(\d+(?:-\d+)?\s*(?:g|ml))\s+(.+)$/i)
  if (!portion) return translateInterfaceText(line, language)
  return `${portion[1]} ${translateInterfaceText(portion[2], language)}`
}

export function MealComposer({
  slot,
  date,
  planning = false,
  title,
  initialItems = [],
  plannedMealId = null,
  mealBlockId = null,
  mealIdentity = null,
  targetTime = null,
  replaceMealId = null,
  onClose,
  onLogged,
}: MealComposerProps) {
  const store = useFoodStore()
  const { data, setSettings } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const slotLabel = translateInterfaceText(`${slot[0].toUpperCase()}${slot.slice(1)}`, language)
  const timeZone = timeZoneFromSettings(data.settings)
  const currentClock = zonedClock(new Date(), timeZone)
  const mealDate = date ?? currentClock.date
  const replacedMeal = replaceMealId ? store.meals.find((meal) => meal.id === replaceMealId) : null
  const defaultFinishedTime = replacedMeal
    ? zonedClock(replacedMeal.logged_at, timeZone).time
    : planning || mealDate !== currentClock.date
      ? targetTime ?? currentClock.time
      : currentClock.time
  const [items, setItems] = useState<ComposerFoodItem[]>(initialItems)
  const [name, setName] = useState(title ?? slotLabel)
  const [finishedTime, setFinishedTime] = useState(defaultFinishedTime)
  const [query, setQuery] = useState('')
  const [remoteResults, setRemoteResults] = useState<FoodRecord[]>([])
  const [searching, setSearching] = useState(false)
  const [scanner, setScanner] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [manualOpen, setManualOpen] = useState(false)
  const [presetName, setPresetName] = useState('')
  const [presetSubtitle, setPresetSubtitle] = useState('')
  const [appliedPresetIds, setAppliedPresetIds] = useState<string[]>([])
  const [presetReview, setPresetReview] = useState<{ id: string; name: string; subtitle: string; items: ComposerFoodItem[] } | null>(null)
  const [itemLayout, setItemLayout] = useState<'compact' | 'expanded'>('compact')
  const [foodFinderExpanded, setFoodFinderExpanded] = useState(false)
  const [itemSelectionMode, setItemSelectionMode] = useState(false)
  const [selectedItemIds, setSelectedItemIds] = useState<string[]>([])
  const [selectedPresetDraft, setSelectedPresetDraft] = useState<{ title: string; subtitle: string } | null>(null)
  const [savingPreset, setSavingPreset] = useState(false)
  const [saving, setSaving] = useState(false)
  const [selection, setSelection] = useState<FoodSelectionDraft | null>(null)
  const [addingSelection, setAddingSelection] = useState(false)
  const [quickAddingFoodId, setQuickAddingFoodId] = useState<string | null>(null)
  const [quickAddedFoodId, setQuickAddedFoodId] = useState<string | null>(null)
  const [quickAddedLabel, setQuickAddedLabel] = useState('')
  const [completedSearchKey, setCompletedSearchKey] = useState('')
  const remoteSearchCache = useRef(new Map<string, FoodRecord[]>())
  const quickAddedTimer = useRef<number | null>(null)
  const [controlHelp, setControlHelp] = useState<{ itemId: string; kind: 'adaptive' | 'lock' | 'role' } | null>(null)
  const [manual, setManual] = useState({ name: '', kcal: '', protein: '', carbs: '', fat: '', preparation: 'as_sold' as FoodRecord['preparation_state'] })
  const [protocolOpen, setProtocolOpen] = useState(false)
  const [protocolEditing, setProtocolEditing] = useState(false)
  const [undoRemoval, setUndoRemoval] = useState<MealUndoState<ComposerFoodItem> | null>(null)
  const [undoClock, setUndoClock] = useState(() => Date.now())

  const mealBlockSettings = useMemo(() => normalizeMealBlockSettings(data.settings?.addons.meal_blocks), [data.settings?.addons.meal_blocks])
  const effectiveTargetTime = targetTime
    ?? (mealBlockId ? mealBlockSettings.blocks.find((block) => block.id === mealBlockId)?.time ?? null : null)
  const sequenceIndex = mealBlockId
    ? mealBlockSettings.blocks.filter((block) => block.enabled).slice().sort((left, right) => left.time.localeCompare(right.time)).findIndex((block) => block.id === mealBlockId)
    : null
  const historyStarts = useMemo(() => rankMealHistoryRecommendations({
    context: {
      date: date ?? new Date().toISOString().slice(0, 10),
      slot,
      memoryMode: data.settings?.addons.meal_memory_mode ?? 'daily',
      blockId: mealIdentity ?? mealBlockId,
      targetTime: effectiveTargetTime,
      sequenceIndex: sequenceIndex != null && sequenceIndex >= 0 ? sequenceIndex : null,
      excludeMealId: replaceMealId,
    },
    meals: store.meals,
    entries: store.entries,
    foods: store.foods,
    presets: store.presets,
  }), [data.settings?.addons.meal_memory_mode, date, effectiveTargetTime, mealBlockId, mealIdentity, replaceMealId, sequenceIndex, slot, store.entries, store.foods, store.meals, store.presets])
  const rememberedSelectionByFoodId = useMemo(
    () => new Map(historyStarts.selections.map((selection) => [selection.foodId, selection])),
    [historyStarts.selections],
  )
  const ranked = useMemo(() => {
    if (query.trim()) return rankFoods(query, store.foods, store.preferences, slot).filter((food) => !isPlannedPrescriptionFood(food)).slice(0, 12)
    const usedFoodIds = new Set(store.preferences.filter((preference) => preference.favourite || preference.usage_count > 0).map((preference) => preference.food_id))
    const preferenceBackfill = (data.settings?.addons.meal_memory_mode ?? 'daily') === 'weekly' && historyStarts.foods.length > 0
      ? []
      : rankFoods('', store.foods, store.preferences, slot).filter((food) => usedFoodIds.has(food.id))
    const seen = new Set<string>()
    return [...historyStarts.foods, ...preferenceBackfill].filter((food) => {
      if (isPlannedPrescriptionFood(food)) return false
      if (seen.has(food.id)) return false
      seen.add(food.id)
      return true
    }).slice(0, 12)
  }, [data.settings?.addons.meal_memory_mode, historyStarts.foods, query, slot, store.foods, store.preferences])
  const alternateQueries = useMemo(() => expandFoodSearchQueries(query, language), [language, query])
  const displayedFoods = useMemo(
    () => mergeExtendedFoodResults(query, ranked, remoteResults, alternateQueries).slice(0, 30),
    [alternateQueries, query, ranked, remoteResults],
  )
  const visibleDisplayedFoods = useMemo(
    () => query.trim() || foodFinderExpanded ? displayedFoods : displayedFoods.slice(0, 2),
    [displayedFoods, foodFinderExpanded, query],
  )
  const totals = useMemo(() => mealTotals(items), [items])
  const undoSecondsRemaining = mealUndoSecondsRemaining(undoRemoval, undoClock)
  const selectedPresetItems = useMemo(
    () => items.filter((item) => selectedItemIds.includes(item.id)),
    [items, selectedItemIds],
  )
  const dailyTargets = useMemo(
    () => data.profile
      ? computeTargets(data.profile, nutritionPlanContext(data.settings?.addons.training_induction))
      : null,
    [data.profile, data.settings?.addons.training_induction],
  )
  const postWorkoutDinnerActive = mealBlockId === 'post_workout'
    && (data.settings?.addons.adaptive_post_workout_dinner ?? true)
    && finishedTime >= '19:00'
  const guideSlot: MealSlot = postWorkoutDinnerActive ? 'dinner' : slot
  const mealShare = guideSlot === 'breakfast' ? 0.25 : guideSlot === 'lunch' || guideSlot === 'dinner' ? 0.3 : 0.15
  const mealMacroTargets = dailyTargets
    ? {
        protein: Math.max(1, Math.round(dailyTargets.protein_g * mealShare)),
        carbs: Math.max(1, Math.round(dailyTargets.carbs_g * mealShare)),
        fat: Math.max(1, Math.round(dailyTargets.fat_g * mealShare)),
      }
    : null
  const protocolKey = data.profile
    ? `${data.profile.persona}:${guideSlot}:${data.profile.goal}:${language}${postWorkoutDinnerActive ? ':post-workout-dinner' : ''}`
    : ''
  const defaultProtocolLines = useMemo(() => {
    if (!data.profile) return []
    const protocol = ATHLETE_SUPPORT_PROTOCOLS[data.profile.persona]
    const meal = protocol?.meals[MEAL_PROTOCOL_INDEX[guideSlot]]
    if (meal) {
      return meal.foods.map((line) => goalAdjustedProtocolLine(line, data.profile!.persona, data.profile!.goal))
    }
    return defaultMealGuideSections(guideSlot).flatMap((section) => section.items)
  }, [data.profile, guideSlot])
  const genericGuideSections = data.profile
    && !ATHLETE_SUPPORT_PROTOCOLS[data.profile.persona]?.meals[MEAL_PROTOCOL_INDEX[guideSlot]]
    ? defaultMealGuideSections(guideSlot)
    : []
  const savedProtocolLines = protocolKey ? data.settings?.addons.meal_protocol_overrides?.[protocolKey] : undefined
  const protocolLines = savedProtocolLines ?? defaultProtocolLines.map((line) => translateProtocolLine(line, language))
  const [protocolDraft, setProtocolDraft] = useState<string[]>(protocolLines)
  useEffect(() => {
    if (!protocolEditing) setProtocolDraft(protocolLines)
  }, [protocolEditing, protocolKey, protocolLines.join('\u0000')])
  const selectionPortion = useMemo(
    () => selection ? calculatePortion(selection.food, selection.quantity, selection.unit) : null,
    [selection],
  )
  const selectionReady = Boolean(selection && selection.quantity > 0 && selectionPortion)
  const describeSelectionAmount = (draft: FoodSelectionDraft): string => {
    const number = new Intl.NumberFormat(language === 'ro' ? 'ro-RO' : language === 'th' ? 'th-TH' : 'en', {
      maximumFractionDigits: 2,
    }).format(draft.quantity)
    const translatedUnit = t(draft.unit)
    if (draft.unit === 'g' || draft.unit === 'ml') return `${number} ${translatedUnit}`
    const portion = calculatePortion(draft.food, draft.quantity, draft.unit)
    const basisUnit = draft.food.nutrition_basis === 'per_100ml' ? 'ml' : 'g'
    if (!portion) return `${number} ${translatedUnit}`
    const equivalent = new Intl.NumberFormat(language === 'ro' ? 'ro-RO' : language === 'th' ? 'th-TH' : 'en', {
      maximumFractionDigits: 1,
    }).format(portion.equivalent_amount)
    return `${number} ${translatedUnit} (${equivalent} ${t(basisUnit)})`
  }
  const slotPresets = useMemo(() => {
    const historicalOrder = new Map(historyStarts.presets.map((preset, index) => [preset.id, index]))
    return store.presets.filter((preset) => {
    if (preset.archived || preset.meal_slot !== slot) return false
    if (!mealBlockId) return true
    const assigned = mealBlockSettings.preset_assignments[preset.id]
    return assigned == null || assigned === mealBlockId
    }).sort((left, right) => (historicalOrder.get(left.id) ?? 999) - (historicalOrder.get(right.id) ?? 999) || right.updated_at.localeCompare(left.updated_at)).slice(0, 6)
  }, [historyStarts.presets, mealBlockId, mealBlockSettings.preset_assignments, slot, store.presets])
  const recentMeals = historyStarts.meals

  useEffect(() => () => {
    if (quickAddedTimer.current != null) window.clearTimeout(quickAddedTimer.current)
  }, [])

  useEffect(() => {
    if (!undoRemoval) return
    setUndoClock(Date.now())
    const interval = window.setInterval(() => setUndoClock(Date.now()), 250)
    const timeout = window.setTimeout(() => {
      setUndoRemoval((current) => current === undoRemoval ? null : current)
    }, Math.max(0, undoRemoval.expiresAt - Date.now()))
    return () => {
      window.clearInterval(interval)
      window.clearTimeout(timeout)
    }
  }, [undoRemoval])

  useEffect(() => {
    const trimmed = query.trim()
    if (trimmed.length < 2) {
      setRemoteResults([])
      setSearching(false)
      setCompletedSearchKey('')
      return
    }
    const key = `${language}:${normalizeFoodSearch(trimmed)}`
    const cached = remoteSearchCache.current.get(key)
    if (cached) {
      setRemoteResults(cached)
      setSearching(false)
      setCompletedSearchKey(key)
      return
    }

    let active = true
    setSearching(true)
    setCompletedSearchKey('')
    const timer = window.setTimeout(() => {
      void store.widerSearch(trimmed, language)
        .then((result) => {
          if (!active) return
          remoteSearchCache.current.set(key, result.results)
          setRemoteResults(result.results)
          setCompletedSearchKey(key)
        })
        .catch(() => {
          if (!active) return
          /* Provider failures never replace the useful offline catalog or
             surface infrastructure errors to the person logging a meal. */
          setRemoteResults([])
          setCompletedSearchKey(key)
        })
        .finally(() => {
          if (active) setSearching(false)
        })
    }, 420)
    return () => {
      active = false
      window.clearTimeout(timer)
    }
  }, [language, query, store.widerSearch])

  const materializeFood = async (food: FoodRecord): Promise<FoodRecord> => {
    /*
     * Offline protocol references are intentionally shipped in the client so
     * search works before the network does. Materialize both curated and
     * protocol records into the owner's food table before an entry references
     * them; otherwise Supabase's logged_food_entries.food_id FK can reject an
     * otherwise valid meal on first use.
     */
    if (!foodNeedsPrivateMaterialization(food)) return food
    const existing = store.foods.find((candidate) => candidate.owner_user_id && (
      candidate.provider_product_id === food.provider_product_id || Boolean(food.barcode && candidate.barcode === food.barcode)
    ))
    if (existing) return existing
    return store.savePrivateFood({
      name: food.name,
      names_i18n: food.names_i18n,
      brand: food.brand,
      barcode: food.barcode,
      provider_product_id: food.provider_product_id,
      water_ml_100: food.water_ml_100,
      water_basis: food.water_basis ?? 'unknown',
      water_source_id: food.water_source_id ?? null,
      external_image_url: food.external_image_url,
      package_quantity: food.package_quantity,
      nutrition_basis: food.nutrition_basis,
      preparation_state: food.preparation_state,
      kcal_100: food.kcal_100,
      protein_100: food.protein_100,
      carbs_100: food.carbs_100,
      fat_100: food.fat_100,
      fibre_100: food.fibre_100,
      sugar_100: food.sugar_100,
      saturated_fat_100: food.saturated_fat_100,
      salt_100: food.salt_100,
      serving_amount: food.serving_amount,
      serving_unit: food.serving_unit,
      serving_grams_or_ml: food.serving_grams_or_ml,
      piece_grams_or_ml: food.piece_grams_or_ml,
      provider_updated_at: food.provider_updated_at,
      confidence: food.confidence,
    })
  }

  const selectionDraftForFood = (food: FoodRecord): FoodSelectionDraft => {
    const preference = store.preferences.find((value) => value.food_id === food.id)
    return beginFoodSelection(food, preference, rememberedSelectionByFoodId.get(food.id))
  }

  const openFoodSelection = (food: FoodRecord) => {
    setSelection(selectionDraftForFood(food))
    setMessage(null)
  }

  const confirmFoodSelection = async () => {
    if (!selection || selection.quantity <= 0 || !calculatePortion(selection.food, selection.quantity, selection.unit)) return
    setAddingSelection(true)
    try {
      const trackableFood = await materializeFood(selection.food)
      setItems((current) => commitFoodSelection(current, { ...selection, food: trackableFood }))
      setQuery('')
      setRemoteResults([])
      setSelection(null)
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'This food could not be added. Please try again.')
    } finally {
      setAddingSelection(false)
    }
  }

  const patchItem = (id: string, patch: Partial<ComposerFoodItem>) => {
    setItems((current) => current.map((item) => item.id === id ? { ...item, ...patch } : item))
  }

  const removeItem = (id: string) => {
    const removed = removeMealItemWithUndo(items, id)
    if (!removed.undo) return
    setItems(removed.items.map((item, sort_order) => ({ ...item, sort_order })))
    setUndoClock(Date.now())
    setUndoRemoval(removed.undo)
    setSelectedItemIds((current) => current.filter((itemId) => itemId !== id))
  }

  const undoItemRemoval = () => {
    const restored = restoreMealItemFromUndo(items, undoRemoval)
    if (restored.restored) {
      setItems(restored.items.map((item, sort_order) => ({ ...item, sort_order })))
    }
    setUndoRemoval(null)
  }

  const toggleItemSelection = (id: string) => {
    setSelectedItemIds((current) => current.includes(id)
      ? current.filter((itemId) => itemId !== id)
      : [...current, id])
  }

  const cancelItemSelection = () => {
    setItemSelectionMode(false)
    setSelectedItemIds([])
    setSelectedPresetDraft(null)
  }

  const moveItem = (index: number, direction: -1 | 1) => {
    const target = index + direction
    if (target < 0 || target >= items.length) return
    setItems((current) => {
      const next = [...current]
      ;[next[index], next[target]] = [next[target], next[index]]
      return next.map((item, sort_order) => ({ ...item, sort_order }))
    })
  }

  const lookupCode = async (barcode: string) => {
    setScanner(false)
    setSearching(true)
    try {
      const result = await store.lookupBarcode(barcode)
      if (result.food && isFoodNutritionComplete(result.food)) openFoodSelection(result.food)
      else if (result.food) {
        setManual({
          name: result.food.name,
          kcal: result.food.kcal_100 == null ? '' : String(result.food.kcal_100),
          protein: result.food.protein_100 == null ? '' : String(result.food.protein_100),
          carbs: result.food.carbs_100 == null ? '' : String(result.food.carbs_100),
          fat: result.food.fat_100 == null ? '' : String(result.food.fat_100),
          preparation: result.food.preparation_state,
        })
        setManualOpen(true)
        setMessage('This provider record is incomplete. Review the missing values before saving your private corrected copy.')
      } else setMessage(result.message ?? (result.state === 'not_found' ? 'Product not found. Add it manually and keep it private.' : 'Nutrition is incomplete. Review it manually before logging.'))
    } catch {
      setMessage('Barcode lookup is temporarily unavailable. Search by name or create a private food instead.')
    } finally {
      setSearching(false)
    }
  }

  const selectFood = async (food: FoodRecord) => {
    if (isFoodNutritionComplete(food)) {
      openFoodSelection(food)
      return
    }
    if (food.barcode) {
      await lookupCode(food.barcode)
      return
    }
    setManual({
      name: food.name,
      kcal: food.kcal_100 == null ? '' : String(food.kcal_100),
      protein: food.protein_100 == null ? '' : String(food.protein_100),
      carbs: food.carbs_100 == null ? '' : String(food.carbs_100),
      fat: food.fat_100 == null ? '' : String(food.fat_100),
      preparation: food.preparation_state,
    })
    setManualOpen(true)
    setMessage('This result is incomplete. Review all per-100 g values before saving it privately.')
  }

  const quickAddFood = async (food: FoodRecord) => {
    if (!isFoodNutritionComplete(food)) {
      await selectFood(food)
      return
    }
    const draft = selectionDraftForFood(food)
    if (!calculatePortion(food, draft.quantity, draft.unit)) {
      openFoodSelection(food)
      return
    }
    setQuickAddingFoodId(food.id)
    setMessage(null)
    try {
      const trackableFood = await materializeFood(food)
      setItems((current) => commitFoodSelection(current, { ...draft, food: trackableFood }))
      if (quickAddedTimer.current != null) window.clearTimeout(quickAddedTimer.current)
      setQuickAddedFoodId(food.id)
      setQuickAddedLabel(`${t('Added')} · ${displayFoodName(food, language)} · ${describeSelectionAmount(draft)}`)
      quickAddedTimer.current = window.setTimeout(() => {
        setQuickAddedFoodId((current) => current === food.id ? null : current)
        setQuickAddedLabel('')
      }, 1_300)
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'This food could not be added. Please try again.')
    } finally {
      setQuickAddingFoodId((current) => current === food.id ? null : current)
    }
  }

  const addProtocolFood = async (line: string) => {
    const parsed = protocolFoodQuery(line)
    const match = rankFoods(parsed.query, store.foods, store.preferences, slot)[0]
    if (!match) {
      setQuery(parsed.query)
      setMessage(t('No exact saved food matched this guide item. Search results are ready for you to choose the correct label.'))
      return
    }
    if (!isFoodNutritionComplete(match)) {
      await selectFood(match)
      return
    }
    const supportedUnits = availableFoodUnits(match)
    const unit = supportedUnits.includes(parsed.unit) ? parsed.unit : match.nutrition_basis === 'per_100ml' ? 'ml' : 'g'
    const trackableFood = await materializeFood(match)
    setItems((current) => commitFoodSelection(current, {
      food: trackableFood,
      quantity: parsed.quantity,
      unit,
    }))
    setQuickAddedLabel(`${t('Added')} · ${displayFoodName(match, language)}`)
  }

  const saveProtocolGuide = () => {
    if (!data.settings || !protocolKey) return
    const cleaned = protocolDraft.map((line) => line.trim()).filter(Boolean)
    const nextOverrides = {
      ...(data.settings.addons.meal_protocol_overrides ?? {}),
    }
    if (cleaned.length > 0) nextOverrides[protocolKey] = cleaned
    else delete nextOverrides[protocolKey]
    setSettings({
      addons: {
        ...data.settings.addons,
        meal_protocol_overrides: nextOverrides,
      },
    })
    setProtocolEditing(false)
    setMessage(t('Predefined list saved for this goal.'))
  }

  const createManual = async () => {
    const values = [manual.kcal, manual.protein, manual.carbs, manual.fat].map(parseDecimalInput)
    if (!manual.name.trim() || values.some((value) => value == null || value < 0)) {
      setMessage('Name and all four per-100 g nutrition values are required.')
      return
    }
    const food = await store.savePrivateFood({
      name: manual.name.trim(), names_i18n: { en: manual.name.trim() }, brand: null, barcode: null,
      provider_product_id: null, external_image_url: null, package_quantity: null,
      nutrition_basis: 'per_100g', preparation_state: manual.preparation,
      kcal_100: values[0], protein_100: values[1], carbs_100: values[2], fat_100: values[3],
      fibre_100: null, sugar_100: null, saturated_fat_100: null, salt_100: null,
      water_ml_100: estimateWaterContent({
        name: manual.name.trim(), nutrition_basis: 'per_100g',
        kcal_100: values[0], protein_100: values[1],
        carbs_100: values[2], fat_100: values[3],
      })?.water_ml_100 ?? null,
      serving_amount: null, serving_unit: null, serving_grams_or_ml: null, piece_grams_or_ml: null,
      provider_updated_at: null, confidence: 'user_entered',
    })
    openFoodSelection(food)
    setManualOpen(false)
  }

  const loadPreset = (id: string) => {
    const preset = store.presets.find((value) => value.id === id)
    if (!preset) return
    setPresetReview({
      id,
      name: preset.name,
      subtitle: data.settings?.addons.meal_preset_subtitles?.[id] ?? '',
      items: store.itemsForPreset(id).map((item, index) => ({ ...item, id: crypto.randomUUID(), sort_order: index })),
    })
  }

  const confirmPresetReview = () => {
    if (!presetReview || presetReview.items.length === 0) return
    setItems((current) => [
      ...current,
      ...presetReview.items.map((item, index) => ({
        ...item,
        id: crypto.randomUUID(),
        sort_order: current.length + index,
      })),
    ])
    setAppliedPresetIds((current) => current.includes(presetReview.id) ? current : [...current, presetReview.id])
    setPresetReview(null)
    setMessage(t('Preset items added to this meal.'))
  }

  const loadRecent = (mealId: string) => {
    const meal = store.meals.find((value) => value.id === mealId)
    if (!meal) return
    const next = store.entries.filter((entry) => entry.meal_id === mealId).map((entry, index) => {
      const food = store.foods.find((value) => value.id === entry.food_id) ?? foodFromLoggedEntry(entry)
      return composerItemFromSelection({ food, quantity: entry.quantity, unit: entry.unit }, index)
    }).filter((item): item is ComposerFoodItem => item != null)
    setItems(next)
    setName(meal.display_name)
    setAppliedPresetIds([])
  }

  const persistPreset = async (
    presetItems: ComposerFoodItem[],
    title: string,
    subtitle: string,
    markApplied = true,
  ) => {
    if (!presetItems.length || savingPreset) return null
    setSavingPreset(true)
    try {
      const saved = await store.savePreset({
        name: title.trim() || name,
        slot,
        items: presetItems,
        sourcePlannedMealId: plannedMealId,
      })
      if (data.settings) {
        const nextSubtitles = { ...(data.settings.addons.meal_preset_subtitles ?? {}) }
        const cleanSubtitle = subtitle.trim()
        if (cleanSubtitle) nextSubtitles[saved.id] = cleanSubtitle
        else delete nextSubtitles[saved.id]
        setSettings({
          addons: {
            ...data.settings.addons,
            meal_preset_subtitles: nextSubtitles,
            ...(mealBlockId ? {
              meal_blocks: {
                ...mealBlockSettings,
                preset_assignments: { ...mealBlockSettings.preset_assignments, [saved.id]: mealBlockId },
              },
            } : {}),
          },
        })
      }
      if (markApplied) {
        setAppliedPresetIds((current) => current.includes(saved.id) ? current : [...current, saved.id])
      }
      return saved
    } catch (error) {
      setMessage(error instanceof Error ? error.message : t('Preset could not be saved.'))
      return null
    } finally {
      setSavingPreset(false)
    }
  }

  const savePreset = async () => {
    const saved = await persistPreset(items, presetName, presetSubtitle)
    if (!saved) return
    setPresetName('')
    setPresetSubtitle('')
    setMessage('Reusable preset saved. Adjustable amounts can adapt without rewriting your template.')
  }

  const saveSelectedPreset = async () => {
    if (!selectedPresetDraft || selectedPresetItems.length === 0) {
      setMessage(t('Choose at least one food'))
      return
    }
    const saved = await persistPreset(
      selectedPresetItems,
      selectedPresetDraft.title,
      selectedPresetDraft.subtitle,
      false,
    )
    if (!saved) return
    cancelItemSelection()
    setMessage(t('Selected-food preset saved.'))
  }

  const log = async () => {
    if (!items.length || totals.kcal <= 0) {
      setMessage('Add at least one complete food before logging.')
      return
    }
    setSaving(true)
    try {
      const sourcePresetId = appliedPresetIds.length === 1 ? appliedPresetIds[0] : null
      const assignedBlock = mealIdentity ?? mealBlockId ?? (sourcePresetId ? mealBlockSettings.preset_assignments[sourcePresetId] : null)
      await store.logMeal({
        date: mealDate,
        slot,
        name: name.trim() || 'Meal',
        items,
        finishedAt: zonedDateTimeToIso(mealDate, finishedTime, timeZone),
        sourcePresetId,
        sourcePlannedMealId: plannedMealId,
        replaceMealId, loggedAs: planning ? 'planned' : plannedMealId ? (initialItems.length ? 'changed' : 'planned') : 'custom',
        idempotencyKey: mealBlockIdempotencyKey(crypto.randomUUID(), assignedBlock),
      })
      onLogged?.()
      onClose()
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Meal could not be logged.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 z-[80] overflow-y-auto bg-canvas/92 backdrop-blur-xl" role="dialog" aria-modal="true" aria-label="Meal composer">
      <div className="mx-auto min-h-dvh w-full max-w-3xl px-4 pt-[calc(1rem+env(safe-area-inset-top))] pb-[calc(2rem+env(safe-area-inset-bottom))]">
        <div className="sticky top-0 z-20 -mx-2 flex items-center justify-between rounded-2xl bg-canvas/85 px-2 py-2 backdrop-blur-xl">
          <div>
            <p className="font-mono text-[10px] tracking-[0.18em] text-ink-faint uppercase">{t(planning ? 'Future meal plan' : 'Actual intake')} · {slotLabel}</p>
            <h2 className="font-display text-xl font-bold text-ink">{t(planning ? 'Plan this meal' : 'Build this meal')}</h2>
          </div>
          <button type="button" onClick={onClose} className="glass rounded-full px-4 py-2 text-sm font-bold text-ink">{t('Close')}</button>
        </div>

        <div className="mt-4 space-y-4">
          <GlassCard accent={amber} className="p-4">
            <div className="flex items-start gap-3">
              <label className="min-w-0 flex-1">
                <span className="text-xs font-bold text-ink-soft">{t('Meal name')}</span>
                <input aria-label={t('Meal name')} value={name} onChange={(event) => setName(event.target.value)} className="mt-1 w-full bg-transparent font-display text-lg font-bold text-ink outline-none" />
              </label>
              <label className="shrink-0 rounded-2xl border border-amber-100/90 bg-white/72 px-3 py-2 shadow-sm">
                <span className="block text-[8px] font-black tracking-wide text-amber-800 uppercase">{t('Meal finished at')}</span>
                <input
                  type="time"
                  value={finishedTime}
                  onChange={(event) => setFinishedTime(event.target.value)}
                  aria-label={t('Meal finished at')}
                  className="mt-0.5 block w-[5.6rem] bg-transparent font-mono text-sm font-black text-ink outline-none"
                />
              </label>
            </div>
            <p className="mt-2 text-[9px] font-semibold text-ink-faint">{t('This time places the meal on your Dayline and updates timing trends.')}</p>
            <div className="mt-3 flex items-center justify-between gap-3 border-t border-ink/8 pt-3">
              <div>
                <p className="font-mono text-xl font-black text-ink">{totals.kcal} <span className="text-[10px] text-ink-faint">kcal</span></p>
                <p className="text-[9px] font-bold text-ink-faint uppercase">{t('This meal')}</p>
              </div>
              {protocolLines.length > 0 && (
                <button
                  type="button"
                  onClick={() => setProtocolOpen((value) => !value)}
                  className="rounded-xl border border-amber-300/35 bg-amber-50/75 px-3 py-2 text-xs font-black text-amber-800 shadow-sm"
                >
                  {t('Predefined list')} {protocolOpen ? '−' : '+'}
                </button>
              )}
            </div>
            {postWorkoutDinnerActive && (
              <p className="mt-2 rounded-xl bg-emerald-50/80 px-3 py-2 text-[9px] font-black text-emerald-800">
                {t('Dinner guide active for this post-workout meal')}
              </p>
            )}
            {mealMacroTargets && (
              <div className="mt-3 grid grid-cols-3 gap-2" aria-label={t('Meal macro completion')}>
                {([
                  ['Protein', totals.protein_g, mealMacroTargets.protein, '#ec4899'],
                  ['Carbs', totals.carbs_g, mealMacroTargets.carbs, '#22b8e6'],
                  ['Fat', totals.fat_g, mealMacroTargets.fat, '#9b7be8'],
                ] as const).map(([label, value, target, color]) => {
                  const macro = label.toLowerCase() as MealMacroKind
                  const status = mealMacroStatus(
                    value,
                    target,
                    macro,
                    data.profile?.persona ?? 'matthew',
                    data.profile?.goal ?? 'maintain',
                  )
                  const warning = status.state === 'high'
                  const above = status.state === 'above'
                  return (
                    <div key={label} className={`min-w-0 rounded-2xl border px-2.5 py-2.5 ${warning ? 'border-rose-200 bg-rose-50/72' : above ? 'border-amber-200 bg-amber-50/55' : 'border-white/85 bg-white/62'}`}>
                      <div className="min-w-0">
                        <p className="truncate text-[10px] font-black text-ink">{t(label)}</p>
                        <span className={`mt-0.5 block truncate font-mono text-[9px] font-black ${warning ? 'text-rose-700' : above ? 'text-amber-700' : status.state === 'reached' ? 'text-emerald-700' : 'text-ink-faint'}`}>{value}/{target}g</span>
                      </div>
                      <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-ink/7">
                        <motion.div
                          className="h-full rounded-full"
                          animate={{ width: `${Math.min(100, status.completion * 100)}%` }}
                          style={{ background: warning ? '#e11d48' : color, boxShadow: `0 0 10px ${warning ? '#e11d4866' : `${color}66`}` }}
                        />
                      </div>
                      <p className={`mt-1 min-h-[1.25rem] text-[8px] leading-tight font-bold ${warning ? 'text-rose-700' : above ? 'text-amber-700' : 'text-ink-faint'}`}>
                        {warning
                          ? `+${status.overBy}g ${t('over meal range')}`
                          : above
                            ? `+${status.overBy}g ${t('above guide')}`
                            : status.state === 'reached'
                              ? t('minimum reached')
                              : t('toward meal guide')}
                      </p>
                    </div>
                  )
                })}
              </div>
            )}
          </GlassCard>

          <AnimatePresence initial={false}>
            {protocolOpen && protocolLines.length > 0 && (
              <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
                <GlassCard accent={amber} className="p-4">
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <p className="font-mono text-[9px] font-black tracking-[.15em] text-amber-700 uppercase">{t('Your meal guide')}</p>
                      <p className="mt-0.5 text-[11px] font-semibold text-ink-soft">{t('Adjusted for the current goal. Package labels remain the nutrition source.')}</p>
                    </div>
                    <button type="button" onClick={() => setProtocolEditing((value) => !value)} className="rounded-full bg-white/75 px-3 py-1.5 text-[10px] font-black text-ink">{t(protocolEditing ? 'Done editing' : 'Configure')}</button>
                  </div>
                  {!protocolEditing && !savedProtocolLines && genericGuideSections.length > 0 ? (
                    <div className="mt-3 space-y-4">
                      {genericGuideSections.map((section) => (
                        <section key={section.title} className="space-y-2">
                          <div className="flex items-center gap-2">
                            <p className="font-mono text-[9px] font-black tracking-[.14em] text-amber-800">{t(section.title)}</p>
                            <span className="h-px flex-1 bg-amber-500/15" />
                          </div>
                          {section.items.map((line, index) => {
                            const translated = translateProtocolLine(line, language)
                            return (
                              <div key={`${section.title}:${line}`} className="flex items-center gap-2 rounded-2xl border border-white/90 bg-white/66 px-3 py-2.5">
                                <span className="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-amber-500/10 font-mono text-[9px] font-black text-amber-800">{index + 1}</span>
                                <p className="min-w-0 flex-1 text-sm leading-snug font-bold text-ink">{translated}</p>
                                <button type="button" onClick={() => void addProtocolFood(line)} className="grid h-9 w-9 shrink-0 place-items-center rounded-full border border-amber-400/45 bg-white text-xl font-black text-amber-700 active:scale-90" aria-label={`${t('Add')} ${translated}`}>+</button>
                              </div>
                            )
                          })}
                        </section>
                      ))}
                    </div>
                  ) : (
                    <div className="mt-3 space-y-2">
                      {(protocolEditing ? protocolDraft : protocolLines).map((line, index) => (
                        <div key={`${index}:${line}`} className="flex items-center gap-2 rounded-2xl border border-white/90 bg-white/66 px-3 py-2.5">
                          <span className="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-amber-500/10 font-mono text-[9px] font-black text-amber-800">{index + 1}</span>
                          {protocolEditing ? (
                            <>
                              <input value={line} onChange={(event) => setProtocolDraft((current) => current.map((value, itemIndex) => itemIndex === index ? event.target.value : value))} className="min-w-0 flex-1 bg-transparent text-sm font-bold text-ink outline-none" />
                              <button type="button" onClick={() => setProtocolDraft((current) => current.filter((_, itemIndex) => itemIndex !== index))} className="grid h-7 w-7 place-items-center rounded-full bg-red-500/8 font-black text-red-600">×</button>
                            </>
                          ) : (
                            <>
                              <p className="min-w-0 flex-1 text-sm leading-snug font-bold text-ink">{line}</p>
                              <button type="button" onClick={() => void addProtocolFood(savedProtocolLines ? line : defaultProtocolLines[index] ?? line)} className="grid h-9 w-9 shrink-0 place-items-center rounded-full border border-amber-400/45 bg-white text-xl font-black text-amber-700 active:scale-90" aria-label={`${t('Add')} ${line}`}>+</button>
                            </>
                          )}
                        </div>
                      ))}
                    </div>
                  )}
                  {protocolEditing && (
                    <div className="mt-3 flex gap-2">
                      <button type="button" onClick={() => setProtocolDraft((current) => [...current, ''])} className="rounded-xl bg-white/75 px-3 py-2 text-xs font-black text-ink">+ {t('Item')}</button>
                      <button type="button" onClick={saveProtocolGuide} className="flex-1 rounded-xl px-3 py-2 text-xs font-black text-white" style={{ background: amber.gradient }}>{t('Save configuration')}</button>
                    </div>
                  )}
                </GlassCard>
              </motion.div>
            )}
          </AnimatePresence>

          <GlassCard className="overflow-visible p-3">
            <div className="flex gap-2">
              <input
                value={query}
                onFocus={() => setFoodFinderExpanded(true)}
                onChange={(event) => {
                  setQuery(event.target.value)
                  setRemoteResults([])
                  setCompletedSearchKey('')
                }}
                placeholder={t('Search foods, aliases or brands')}
                aria-label={t('Search foods, aliases or brands')}
                className="min-w-0 flex-1 rounded-2xl border border-white/90 bg-white/78 px-4 py-3 text-base font-semibold text-ink shadow-[0_10px_28px_-24px_rgba(15,23,42,.55)] outline-none ring-amber-400/35 placeholder:font-medium placeholder:text-ink-faint focus:ring-2"
              />
              <button
                type="button"
                onClick={() => setScanner(true)}
                className="flex h-[3.25rem] w-[4.25rem] shrink-0 flex-col items-center justify-center rounded-2xl text-white shadow-lg transition active:scale-95"
                style={{ background: amber.gradient, boxShadow: `0 10px 24px -10px ${amber.glowStrong}` }}
                aria-label={t('Scan a food barcode')}
              >
                <BarcodeIcon className="h-[18px] w-8" />
                <span className="mt-1 font-mono text-[7px] font-bold tracking-[0.16em] uppercase">{t('Scan')}</span>
              </button>
            </div>
            <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
              {store.preferences.filter((value) => value.favourite).slice(0, 6).map((preference) => {
                const food = store.foods.find((value) => value.id === preference.food_id)
                return food ? <button key={food.id} type="button" onClick={() => void selectFood(food)} className="shrink-0 rounded-full bg-amber-500/10 px-3 py-1.5 text-xs font-bold text-amber-700">★ {preference.personal_name || food.name}</button> : null
              })}
              <button type="button" onClick={() => setManualOpen((value) => !value)} className="shrink-0 rounded-full bg-white/70 px-3 py-1.5 text-xs font-bold text-ink-soft">{t('+ Private food')}</button>
            </div>
            <AnimatePresence initial={false}>
              {manualOpen && (
                <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
                  <div className="mt-3 rounded-2xl border border-amber-300/25 bg-amber-50/55 p-3">
                    <h3 className="font-display text-sm font-bold text-ink">{t('Create a private food')}</h3>
                    <p className="mt-1 text-[10px] text-ink-soft">{t('Values are per 100 g. Decimal commas are accepted. This record is visible only to you.')}</p>
                    <input value={manual.name} onChange={(event) => setManual((value) => ({ ...value, name: event.target.value }))} placeholder={t('Food name')} className="mt-3 w-full rounded-xl bg-white/80 px-3 py-2 text-sm outline-none" />
                    <div className="mt-2 grid grid-cols-2 gap-2">
                      {(['kcal', 'protein', 'carbs', 'fat'] as const).map((field) => (
                        <input key={field} inputMode="decimal" value={manual[field]} onChange={(event) => setManual((value) => ({ ...value, [field]: event.target.value }))} placeholder={`${t(field)} / 100 g`} className="rounded-xl bg-white/80 px-3 py-2 text-sm outline-none" />
                      ))}
                    </div>
                    <select value={manual.preparation} onChange={(event) => setManual((value) => ({ ...value, preparation: event.target.value as FoodRecord['preparation_state'] }))} className="mt-2 w-full rounded-xl bg-white/80 px-3 py-2 text-sm">
                      <option value="as_sold">{t('As sold')}</option><option value="dry">{t('Dry')}</option><option value="cooked">{t('Cooked')}</option><option value="prepared">{t('Prepared')}</option><option value="drained">{t('Drained')}</option>
                    </select>
                    <button type="button" onClick={() => void createManual()} className="mt-3 rounded-xl bg-amber-500 px-4 py-2 text-xs font-bold text-white">{t('Save privately and add')}</button>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
            <p className="sr-only" aria-live="polite">{quickAddedLabel}</p>
            {(displayedFoods.length > 0 || query.trim().length >= 2) && (
              <div className={`mt-4 space-y-2 pr-1 ${query.trim() || foodFinderExpanded ? 'max-h-[min(32rem,52dvh)] overflow-y-auto' : 'overflow-hidden'}`}>
                <div className="flex items-center justify-between gap-3 px-1 pb-1">
                  <div className="min-w-0">
                    <p className="text-[10px] font-black tracking-[0.14em] text-ink-faint uppercase">
                      {t(query.trim() ? 'Food results' : 'Recent & frequent')}
                    </p>
                    {!query.trim() && !foodFinderExpanded && displayedFoods.length > 2 && (
                      <p className="mt-0.5 text-[9px] font-semibold text-ink-faint">{t('Tap search to see all suggestions')}</p>
                    )}
                  </div>
                  <p className="text-right text-[10px] font-semibold text-ink-faint">
                    {searching ? t('Searching the full food catalog…') : t('Tap a food to change its amount')}
                  </p>
                </div>
                {visibleDisplayedFoods.map((food) => {
                  const preference = store.preferences.find((value) => value.food_id === food.id)
                  const rememberedSelection = rememberedSelectionByFoodId.get(food.id)
                  const quickSelection = beginFoodSelection(food, preference, rememberedSelection)
                  const quickPortion = calculatePortion(food, quickSelection.quantity, quickSelection.unit)
                  const hasSavedAmount = Boolean(
                    rememberedSelection
                    || (preference?.usage_count
                      && preference.usual_amount != null
                      && preference.usual_unit != null),
                  )
                  const quickAdding = quickAddingFoodId === food.id
                  const quickAdded = quickAddedFoodId === food.id
                  return (
                    <motion.div
                      key={food.id}
                      animate={quickAdded ? { scale: [1, 0.985, 1.01, 1] } : { scale: 1 }}
                      className={`group flex min-h-[5.5rem] items-stretch overflow-hidden rounded-2xl border bg-white/76 shadow-[0_12px_30px_-25px_rgba(15,23,42,.65)] transition hover:bg-white/90 ${quickAdded ? 'border-emerald-400/70 ring-2 ring-emerald-300/20' : 'border-white/90 hover:border-amber-300/45'}`}
                    >
                      <button
                        type="button"
                        onClick={() => void selectFood(food)}
                        className="min-w-0 flex-1 px-4 py-3 text-left outline-none ring-inset ring-amber-400/30 focus-visible:ring-2"
                        aria-label={`${t('Configure amount')} · ${displayFoodName(food, language)}`}
                      >
                        <span className="flex min-w-0 items-center gap-2">
                          <span className="block min-w-0 truncate font-display text-[1.05rem] leading-tight font-bold text-ink">
                            {displayFoodName(food, language)}
                          </span>
                          <AnimatePresence initial={false}>
                            {quickAdded && (
                              <motion.span
                                initial={{ opacity: 0, scale: 0.7, x: -5 }}
                                animate={{ opacity: 1, scale: 1, x: 0 }}
                                exit={{ opacity: 0, scale: 0.8 }}
                                className="shrink-0 rounded-full bg-emerald-500/12 px-2 py-0.5 text-[10px] font-black text-emerald-700"
                              >
                                ✓ {t('Added')}
                              </motion.span>
                            )}
                          </AnimatePresence>
                        </span>
                        <span className="mt-1 block text-[13px] leading-snug font-bold text-ink-soft">
                          {t(hasSavedAmount ? 'Last used' : 'Suggested portion')} · {describeSelectionAmount(quickSelection)}
                          {quickPortion ? ` · ${quickPortion.kcal} ${t('kcal')}` : ''}
                        </span>
                        <span className="mt-1 block truncate text-[11px] leading-snug font-medium text-ink-faint">
                          {food.brand || t(food.preparation_state.replace('_', ' '))}
                        </span>
                      </button>
                      <div className="grid w-[4.75rem] shrink-0 place-items-center border-l border-ink/6 bg-amber-500/[0.035] px-2">
                        <motion.button
                          type="button"
                          disabled={quickAdding || quickAdded}
                          onClick={() => void quickAddFood(food)}
                          animate={quickAdded ? { rotate: [0, -9, 8, 0], scale: [1, 1.14, 1] } : { rotate: 0, scale: 1 }}
                          className={`grid h-12 w-12 place-items-center rounded-full border-2 bg-white font-display text-2xl leading-none font-bold shadow-[0_8px_18px_-12px_rgba(217,119,6,.8)] transition active:scale-90 ${quickAdded ? 'border-emerald-500 bg-emerald-50 text-emerald-700' : 'border-amber-500/45 text-amber-700 hover:border-amber-500 hover:bg-amber-50'} disabled:opacity-70`}
                          aria-label={`${t('Quick add')} · ${displayFoodName(food, language)} · ${describeSelectionAmount(quickSelection)}`}
                        >
                          {quickAdding ? <span className="font-mono text-xs">•••</span> : quickAdded ? '✓' : '+'}
                        </motion.button>
                      </div>
                    </motion.div>
                  )
                })}
                {query.trim().length >= 2
                  && completedSearchKey === `${language}:${normalizeFoodSearch(query)}`
                  && !searching
                  && displayedFoods.length === 0 && (
                  <div className="rounded-2xl border border-amber-500/15 bg-amber-50/40 px-4 py-4 text-center">
                    <p className="text-sm font-bold text-ink">{t('No matching foods found')}</p>
                    <p className="mt-1 text-xs font-medium text-ink-soft">{t('Try a brand, another spelling, or create a private food from the package label.')}</p>
                  </div>
                )}
              </div>
            )}
          </GlassCard>

          {(slotPresets.length > 0 || recentMeals.length > 0) && (
            <GlassCard className="p-4">
              <p className="text-[10px] font-bold tracking-wide text-ink-faint uppercase">{t('Fast starts')}</p>
              <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
                {slotPresets.map((preset) => {
                  const subtitle = data.settings?.addons.meal_preset_subtitles?.[preset.id]
                  return (
                    <button key={preset.id} type="button" onClick={() => loadPreset(preset.id)} className="shrink-0 rounded-2xl bg-white/75 px-3 py-2 text-left text-xs font-bold text-ink">
                      <span className="block">{t('Preset')} · {preset.name}</span>
                      {subtitle && <span className="mt-0.5 block max-w-44 truncate text-[9px] font-semibold text-ink-faint">{subtitle}</span>}
                    </button>
                  )
                })}
                {recentMeals.map((meal) => <button key={meal.id} type="button" onClick={() => loadRecent(meal.id)} className="shrink-0 rounded-full bg-white/75 px-3 py-2 text-xs font-bold text-ink">{t('Repeat')} · {meal.display_name}</button>)}
              </div>
            </GlassCard>
          )}

          <div className={itemLayout === 'compact' ? 'space-y-1.5' : 'space-y-3'}>
            {items.length > 0 && (
              <div className="flex flex-wrap items-end justify-between gap-2 px-1">
                <div className="flex min-w-0 flex-wrap items-center gap-2">
                  <div>
                    <p className="font-mono text-[10px] font-black tracking-[0.14em] text-amber-700 uppercase">{t('In this meal')}</p>
                    <p className="mt-0.5 text-sm font-semibold text-ink-soft">{items.length} {t(items.length === 1 ? 'food' : 'foods')}</p>
                  </div>
                  {!itemSelectionMode ? (
                    <button
                      type="button"
                      onClick={() => {
                        setItemSelectionMode(true)
                        setSelectedItemIds([])
                      }}
                      className="rounded-full border border-amber-300/35 bg-white/82 px-3 py-1.5 text-[10px] font-black text-amber-800 shadow-sm"
                    >
                      {t('Select')}
                    </button>
                  ) : (
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="rounded-full bg-amber-500/10 px-2.5 py-1.5 text-[9px] font-black text-amber-800">
                        {selectedPresetItems.length} {t('selected')}
                      </span>
                      <button
                        type="button"
                        disabled={selectedPresetItems.length === 0}
                        onClick={() => setSelectedPresetDraft({ title: '', subtitle: '' })}
                        className="rounded-full bg-amber-500 px-3 py-1.5 text-[9px] font-black text-white shadow-sm disabled:opacity-35"
                      >
                        {t('Create preset')}
                      </button>
                      <button type="button" onClick={cancelItemSelection} className="rounded-full bg-white/75 px-2.5 py-1.5 text-[9px] font-black text-ink-soft">
                        {t('Cancel')}
                      </button>
                    </div>
                  )}
                </div>
                <div className="flex items-center gap-2">
                  <div className="flex rounded-xl bg-ink/5 p-0.5" role="group" aria-label={t('Food item layout')}>
                    {(['compact', 'expanded'] as const).map((layout) => (
                      <button
                        key={layout}
                        type="button"
                        aria-pressed={itemLayout === layout}
                        onClick={() => setItemLayout(layout)}
                        className={`rounded-[9px] px-2 py-1 text-[8px] font-black uppercase ${itemLayout === layout ? 'bg-white text-amber-800 shadow-sm' : 'text-ink-faint'}`}
                      >
                        {t(layout === 'compact' ? 'Compact' : 'Expanded')}
                      </button>
                    ))}
                  </div>
                  <p className="font-mono text-xs font-bold text-ink-faint">{totals.kcal} {t('kcal')}</p>
                </div>
              </div>
            )}
            {items.map((item, index) => {
              const portion = calculatePortion(item.food, item.quantity, item.unit)
              const units = availableFoodUnits(item.food)
              const itemSelected = selectedItemIds.includes(item.id)
              if (itemLayout === 'compact') {
                return (
                  <GlassCard key={item.id} accent={amber} className={`px-2.5 py-2 ${itemSelected ? 'ring-2 ring-amber-400/55' : ''}`}>
                    <div className="flex min-w-0 items-center gap-1.5">
                      {itemSelectionMode && (
                        <button
                          type="button"
                          aria-pressed={itemSelected}
                          aria-label={`${t(itemSelected ? 'Deselect' : 'Select')} · ${displayFoodName(item.food, language)}`}
                          onClick={() => toggleItemSelection(item.id)}
                          className={`grid h-7 w-7 shrink-0 place-items-center rounded-full border-2 text-[11px] font-black transition ${itemSelected ? 'border-amber-500 bg-amber-500 text-white' : 'border-ink/15 bg-white/78 text-transparent'}`}
                        >
                          ✓
                        </button>
                      )}
                      <div className="min-w-0 flex-1">
                        <h3 className="truncate font-display text-[13px] leading-tight font-black text-ink">{displayFoodName(item.food, language)}</h3>
                        <p className="mt-0.5 truncate font-mono text-[8px] font-bold text-ink-faint">
                          {portion?.kcal ?? '?'} kcal · P {portion?.protein_g ?? '?'} · C {portion?.carbs_g ?? '?'} · F {portion?.fat_g ?? '?'}
                        </p>
                      </div>
                      <input
                        aria-label={`Amount for ${item.food.name}`}
                        inputMode="decimal"
                        value={item.quantity}
                        onChange={(event) => patchItem(item.id, { quantity: Math.max(0, parseDecimalInput(event.target.value) ?? 0) })}
                        className="h-8 w-[3.65rem] rounded-lg border border-white/90 bg-white/82 px-1.5 text-right font-mono text-[12px] font-black text-ink outline-none"
                      />
                      <select
                        aria-label={`${t('Unit')} · ${displayFoodName(item.food, language)}`}
                        value={item.unit}
                        onChange={(event) => patchItem(item.id, { unit: event.target.value as FoodUnit })}
                        className="h-8 w-[3.45rem] rounded-lg border border-white/90 bg-white/82 px-1 text-[10px] font-black text-ink"
                      >
                        {units.map((unit) => <option key={unit} value={unit}>{t(unit)}</option>)}
                      </select>
                      <div className="grid grid-cols-2 gap-0.5">
                        <button type="button" onClick={() => moveItem(index, -1)} disabled={index === 0} className="grid h-4 w-4 place-items-center rounded bg-white/65 text-[8px] disabled:opacity-20">↑</button>
                        <button type="button" onClick={() => removeItem(item.id)} className="row-span-2 grid h-[2.05rem] w-5 place-items-center rounded-md bg-red-500/8 text-[10px] font-black text-red-600">×</button>
                        <button type="button" onClick={() => moveItem(index, 1)} disabled={index === items.length - 1} className="grid h-4 w-4 place-items-center rounded bg-white/65 text-[8px] disabled:opacity-20">↓</button>
                      </div>
                    </div>
                  </GlassCard>
                )
              }
              return (
                <GlassCard key={item.id} accent={amber} className={`p-4 ${itemSelected ? 'ring-2 ring-amber-400/55' : ''}`}>
                  <div className="flex items-start justify-between gap-2">
                    {itemSelectionMode && (
                      <button
                        type="button"
                        aria-pressed={itemSelected}
                        aria-label={`${t(itemSelected ? 'Deselect' : 'Select')} · ${displayFoodName(item.food, language)}`}
                        onClick={() => toggleItemSelection(item.id)}
                        className={`mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-full border-2 text-xs font-black transition ${itemSelected ? 'border-amber-500 bg-amber-500 text-white' : 'border-ink/15 bg-white/78 text-transparent'}`}
                      >
                        ✓
                      </button>
                    )}
                    <div className="min-w-0">
                      <h3 className="truncate font-display text-lg leading-tight font-bold text-ink">{displayFoodName(item.food, language)}</h3>
                      <p className="mt-1 truncate text-xs font-medium text-ink-faint">{item.food.brand || translateInterfaceText(item.food.preparation_state.replace('_', ' '), language)}</p>
                    </div>
                    <div className="flex gap-1">
                      <button type="button" onClick={() => moveItem(index, -1)} disabled={index === 0} className="rounded-lg bg-white/65 px-2 py-1 text-xs disabled:opacity-25">↑</button>
                      <button type="button" onClick={() => moveItem(index, 1)} disabled={index === items.length - 1} className="rounded-lg bg-white/65 px-2 py-1 text-xs disabled:opacity-25">↓</button>
                      <button type="button" onClick={() => removeItem(item.id)} className="rounded-lg bg-red-500/8 px-2 py-1 text-xs font-bold text-red-600">×</button>
                    </div>
                  </div>
                  <div className="mt-3 flex items-center gap-2">
                    <input aria-label={`Amount for ${item.food.name}`} inputMode="decimal" value={item.quantity} onChange={(event) => patchItem(item.id, { quantity: Math.max(0, parseDecimalInput(event.target.value) ?? 0) })} className="w-28 rounded-xl border border-white/90 bg-white/80 px-3 py-2.5 font-mono text-base font-bold outline-none" />
                    <select value={item.unit} onChange={(event) => patchItem(item.id, { unit: event.target.value as FoodUnit })} className="rounded-xl border border-white/90 bg-white/80 px-3 py-2.5 text-base font-bold">
                      {units.map((unit) => <option key={unit} value={unit}>{unit}</option>)}
                    </select>
                    <button type="button" onClick={() => void store.setPreference(item.food.id, { favourite: !store.preferences.find((value) => value.food_id === item.food.id)?.favourite })} className="ml-auto text-xl" aria-label="Toggle favourite">{store.preferences.find((value) => value.food_id === item.food.id)?.favourite ? '★' : '☆'}</button>
                  </div>
                  <div className="mt-3 flex flex-wrap gap-x-4 gap-y-1 rounded-xl bg-white/45 px-3 py-2 font-mono text-[11px] font-bold text-ink-soft">
                    <span>{portion?.kcal ?? '?'} kcal</span><span>P {portion?.protein_g ?? '?'}</span><span>C {portion?.carbs_g ?? '?'}</span><span>F {portion?.fat_g ?? '?'}</span>
                  </div>
                  <div className="mt-3 flex flex-wrap items-center gap-2 text-[10px] font-semibold text-ink-soft">
                    <span className="inline-flex items-center gap-1 rounded-full border border-white/90 bg-white/65 py-1 pr-1.5 pl-2.5">
                      <label className="inline-flex cursor-pointer items-center gap-1.5"><input type="checkbox" checked={item.adjustable} onChange={(event) => patchItem(item.id, { adjustable: event.target.checked, locked: !event.target.checked })} className="accent-amber-500" /> {t('adaptive')}</label>
                      <button type="button" onClick={() => setControlHelp((current) => current?.itemId === item.id && current.kind === 'adaptive' ? null : { itemId: item.id, kind: 'adaptive' })} className="grid h-4 w-4 place-items-center rounded-full bg-amber-500/15 font-mono text-[8px] font-black text-amber-800" aria-label="Adaptive amount information">i</button>
                    </span>
                    <span className="inline-flex items-center gap-1 rounded-full border border-white/90 bg-white/65 py-1 pr-1.5 pl-2.5">
                      <label className="inline-flex cursor-pointer items-center gap-1.5"><input type="checkbox" checked={item.locked} onChange={(event) => patchItem(item.id, { locked: event.target.checked, adjustable: !event.target.checked })} className="accent-amber-500" /> {t('lock')}</label>
                      <button type="button" onClick={() => setControlHelp((current) => current?.itemId === item.id && current.kind === 'lock' ? null : { itemId: item.id, kind: 'lock' })} className="grid h-4 w-4 place-items-center rounded-full bg-amber-500/15 font-mono text-[8px] font-black text-amber-800" aria-label="Locked amount information">i</button>
                    </span>
                    <span className="inline-flex items-center gap-1 rounded-full border border-white/90 bg-white/65 py-1 pr-1.5 pl-1">
                      <select value={item.adjustment_role} onChange={(event) => patchItem(item.id, { adjustment_role: event.target.value as ComposerFoodItem['adjustment_role'] })} className="rounded-full bg-transparent px-1.5 outline-none">
                        <option value="carb">carb flex</option><option value="protein">protein flex</option><option value="energy">energy flex</option><option value="none">fixed</option>
                      </select>
                      <button type="button" onClick={() => setControlHelp((current) => current?.itemId === item.id && current.kind === 'role' ? null : { itemId: item.id, kind: 'role' })} className="grid h-4 w-4 place-items-center rounded-full bg-amber-500/15 font-mono text-[8px] font-black text-amber-800" aria-label="Adjustment role information">i</button>
                    </span>
                  </div>
                  <AnimatePresence initial={false}>
                    {controlHelp?.itemId === item.id && (
                      <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
                        <div className="mt-2 rounded-xl border border-amber-400/15 bg-amber-50/70 px-3 py-2">
                          <p className="text-[10px] font-bold text-amber-900">
                            {controlHelp.kind === 'adaptive' ? 'Adaptive amount' : controlHelp.kind === 'lock' ? 'Locked amount' : 'Adjustment role'}
                          </p>
                          <p className="mt-0.5 text-[10px] leading-relaxed font-medium text-amber-950/70">
                            {controlHelp.kind === 'adaptive'
                              ? 'APEX may suggest a portion change when your activity or remaining macros change.'
                              : controlHelp.kind === 'lock'
                                ? 'Keep this exact amount today. Lock overrides adaptation, so Adaptive can stay on for later meals or future use.'
                                : 'Choose which macro this food is allowed to balance. Fixed means APEX never changes its amount.'}
                          </p>
                        </div>
                      </motion.div>
                    )}
                  </AnimatePresence>
                  <div className="mt-2">
                    <input
                      defaultValue={store.preferences.find((value) => value.food_id === item.food.id)?.personal_name ?? ''}
                      onBlur={(event) => void store.setPreference(item.food.id, { personal_name: event.target.value.trim() || null })}
                      placeholder={t('Personal label')}
                      className="w-full rounded-lg bg-white/65 px-2 py-1.5 text-[10px] outline-none"
                    />
                  </div>
                </GlassCard>
              )
            })}
          </div>

          <AnimatePresence initial={false}>
            {undoRemoval && undoSecondsRemaining > 0 && (
              <motion.div
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: 10 }}
                className="flex items-center gap-3 rounded-2xl border border-red-400/20 bg-white/82 px-4 py-2.5 shadow-[0_12px_30px_-24px_rgba(127,29,29,.65)]"
                role="status"
              >
                <span className="min-w-0 flex-1 truncate text-xs font-bold text-ink-soft">
                  {displayFoodName(undoRemoval.item.food, language)} {t('removed')}
                </span>
                <button
                  type="button"
                  onClick={undoItemRemoval}
                  aria-label="Undo removed meal item"
                  className="shrink-0 rounded-full bg-amber-500/15 px-4 py-2 text-xs font-black text-amber-800"
                >
                  {t('Undo')} · {undoSecondsRemaining}s
                </button>
              </motion.div>
            )}
          </AnimatePresence>

          {items.length > 0 && (
            <motion.button
              type="button"
              disabled={saving || totals.kcal <= 0}
              onClick={() => void log()}
              whileTap={{ scale: 0.985 }}
              className="sticky bottom-[calc(.75rem+env(safe-area-inset-bottom))] z-20 w-full rounded-[1.35rem] px-5 py-4 text-base font-black text-white shadow-[0_20px_42px_-18px_rgba(245,158,11,.95)] ring-1 ring-white/55 disabled:opacity-50"
              style={{ background: amber.gradient }}
            >
              {saving
                ? t('Saving meal…')
                : `${t(replaceMealId ? 'Save changes & close' : planning ? 'Save to day & close' : 'Save meal & close')} · ${totals.kcal} ${t('kcal')}`}
            </motion.button>
          )}

          {message && <p className="rounded-2xl bg-amber-500/10 px-4 py-3 text-xs font-semibold text-amber-800">{translateInterfaceText(message, language)}</p>}

          {items.length > 0 && (
            <GlassCard className="p-4">
              <p className="text-xs font-bold text-ink">{t('Keep this combination')}</p>
              <div className="mt-2 grid gap-2 sm:grid-cols-2">
                <input value={presetName} onChange={(event) => setPresetName(event.target.value)} placeholder={t('Preset title')} className="min-w-0 rounded-xl bg-white/75 px-3 py-2 text-sm font-bold outline-none" />
                <input value={presetSubtitle} onChange={(event) => setPresetSubtitle(event.target.value)} placeholder={t('Subtitle (optional)')} className="min-w-0 rounded-xl bg-white/75 px-3 py-2 text-sm outline-none" />
              </div>
              <button type="button" disabled={savingPreset} onClick={() => void savePreset()} className="mt-2 w-full rounded-xl bg-white/85 px-3 py-2.5 text-xs font-black text-ink shadow-sm disabled:opacity-45">{t(savingPreset ? 'Saving…' : 'Save preset')}</button>
              <p className="mt-2 text-[10px] font-medium text-ink-faint">{t('Presets are reusable food groups. Add several presets to one meal without renaming the meal itself.')}</p>
            </GlassCard>
          )}
          <p className="text-center text-[10px] font-medium text-ink-faint">Logged entries are immutable snapshots. Editing a food later will never rewrite your history.</p>
        </div>
      </div>
      <AnimatePresence>
        {presetReview && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[102] grid place-items-center bg-slate-950/42 px-4 py-[calc(1rem+env(safe-area-inset-top))] backdrop-blur-md"
            onPointerDown={(event) => { if (event.target === event.currentTarget) setPresetReview(null) }}
          >
            <motion.div
              initial={{ opacity: 0, y: 16, scale: 0.97 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 10, scale: 0.98 }}
              role="dialog"
              aria-modal="true"
              aria-label={t('Review preset items')}
              className="flex max-h-[78dvh] w-full max-w-md flex-col overflow-hidden rounded-[1.75rem] border border-white/90 bg-canvas/98 p-4 shadow-[0_32px_90px_-32px_rgba(15,23,42,.75)]"
              onPointerDown={(event) => event.stopPropagation()}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="font-mono text-[9px] font-black tracking-[.16em] text-amber-700 uppercase">{t('Preset preview')}</p>
                  <h3 className="mt-1 truncate font-display text-xl font-black text-ink">{presetReview.name}</h3>
                  {presetReview.subtitle && <p className="mt-0.5 truncate text-xs font-semibold text-ink-soft">{presetReview.subtitle}</p>}
                </div>
                <button type="button" onClick={() => setPresetReview(null)} aria-label={t('Close')} className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/75 text-lg font-black text-ink-soft">×</button>
              </div>
              <p className="mt-2 text-[10px] font-semibold leading-relaxed text-ink-faint">{t('Check the saved amounts, adjust anything for today, then add this group to the current meal.')}</p>
              <div className="mt-3 min-h-0 flex-1 space-y-1.5 overflow-y-auto pr-0.5">
                {presetReview.items.map((item) => {
                  const portion = calculatePortion(item.food, item.quantity, item.unit)
                  return (
                    <div key={item.id} className="rounded-2xl border border-white/90 bg-white/76 px-3 py-2">
                      <div className="flex min-w-0 items-center gap-2">
                        <div className="min-w-0 flex-1">
                          <p className="truncate text-[12px] font-black text-ink">{displayFoodName(item.food, language)}</p>
                          <p className="mt-0.5 truncate font-mono text-[8px] font-bold text-ink-faint">{portion?.kcal ?? 0} kcal · P {portion?.protein_g ?? 0} · C {portion?.carbs_g ?? 0} · F {portion?.fat_g ?? 0}</p>
                        </div>
                        <input
                          inputMode="decimal"
                          value={item.quantity}
                          aria-label={`${t('Quantity')} · ${displayFoodName(item.food, language)}`}
                          onChange={(event) => setPresetReview((current) => current ? {
                            ...current,
                            items: current.items.map((candidate) => candidate.id === item.id ? { ...candidate, quantity: Math.max(0, parseDecimalInput(event.target.value) ?? 0) } : candidate),
                          } : current)}
                          className="h-9 w-[4.25rem] rounded-xl bg-amber-50/75 px-2 text-right font-mono text-sm font-black text-ink outline-none"
                        />
                        <select
                          value={item.unit}
                          onChange={(event) => setPresetReview((current) => current ? {
                            ...current,
                            items: current.items.map((candidate) => candidate.id === item.id ? { ...candidate, unit: event.target.value as FoodUnit } : candidate),
                          } : current)}
                          className="h-9 w-[4rem] rounded-xl bg-amber-50/75 px-1 text-[10px] font-black text-ink"
                        >
                          {availableFoodUnits(item.food).map((unit) => <option key={unit} value={unit}>{t(unit)}</option>)}
                        </select>
                      </div>
                    </div>
                  )
                })}
              </div>
              <button
                type="button"
                disabled={presetReview.items.length === 0 || mealTotals(presetReview.items).kcal <= 0}
                onClick={confirmPresetReview}
                className="mt-3 w-full rounded-2xl px-4 py-3.5 text-sm font-black text-white shadow-lg disabled:opacity-40"
                style={{ background: amber.gradient }}
              >
                {t('Add preset items')} · {mealTotals(presetReview.items).kcal} {t('kcal')}
              </button>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
      <AnimatePresence>
        {selectedPresetDraft && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[103] grid place-items-center bg-slate-950/45 px-4 py-[calc(1rem+env(safe-area-inset-top))] backdrop-blur-md"
            onPointerDown={(event) => {
              if (event.target === event.currentTarget && !savingPreset) setSelectedPresetDraft(null)
            }}
          >
            <motion.div
              initial={{ opacity: 0, y: 14, scale: 0.98 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 8, scale: 0.98 }}
              role="dialog"
              aria-modal="true"
              aria-label={t('Create preset from selected foods')}
              className="w-full max-w-md rounded-[1.75rem] border border-white/90 bg-canvas/98 p-4 shadow-[0_32px_90px_-32px_rgba(15,23,42,.75)]"
              onPointerDown={(event) => event.stopPropagation()}
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-mono text-[9px] font-black tracking-[.16em] text-amber-700 uppercase">{t('Selected foods')}</p>
                  <h3 className="mt-1 font-display text-xl font-black text-ink">{t('Create preset')}</h3>
                </div>
                <button
                  type="button"
                  disabled={savingPreset}
                  onClick={() => setSelectedPresetDraft(null)}
                  aria-label={t('Close')}
                  className="grid h-9 w-9 place-items-center rounded-full bg-white/78 text-lg font-black text-ink-soft disabled:opacity-40"
                >
                  ×
                </button>
              </div>
              <div className="mt-3 flex max-h-32 flex-wrap gap-1.5 overflow-y-auto rounded-2xl border border-white/90 bg-white/62 p-2.5">
                {selectedPresetItems.map((item) => (
                  <span key={item.id} className="max-w-full truncate rounded-full bg-amber-500/10 px-2.5 py-1 text-[10px] font-black text-amber-900">
                    {displayFoodName(item.food, language)}
                  </span>
                ))}
              </div>
              <div className="mt-3 grid gap-2">
                <input
                  autoFocus
                  value={selectedPresetDraft.title}
                  onChange={(event) => setSelectedPresetDraft((current) => current ? { ...current, title: event.target.value } : current)}
                  placeholder={t('Preset title')}
                  aria-label={t('Preset title')}
                  className="rounded-xl border border-white/90 bg-white/82 px-3 py-3 text-sm font-black text-ink outline-none ring-amber-400/35 focus:ring-2"
                />
                <input
                  value={selectedPresetDraft.subtitle}
                  onChange={(event) => setSelectedPresetDraft((current) => current ? { ...current, subtitle: event.target.value } : current)}
                  placeholder={t('Subtitle (optional)')}
                  aria-label={t('Subtitle (optional)')}
                  className="rounded-xl border border-white/90 bg-white/82 px-3 py-3 text-sm text-ink outline-none ring-amber-400/35 focus:ring-2"
                />
              </div>
              <div className="mt-4 grid grid-cols-[auto_minmax(0,1fr)] gap-2">
                <button
                  type="button"
                  disabled={savingPreset}
                  onClick={() => setSelectedPresetDraft(null)}
                  className="rounded-xl bg-white/80 px-4 py-3 text-sm font-black text-ink-soft disabled:opacity-40"
                >
                  {t('Cancel')}
                </button>
                <button
                  type="button"
                  disabled={savingPreset || selectedPresetItems.length === 0 || !selectedPresetDraft.title.trim()}
                  onClick={() => void saveSelectedPreset()}
                  className="rounded-xl px-4 py-3 text-sm font-black text-white shadow-lg disabled:opacity-40"
                  style={{ background: amber.gradient }}
                >
                  {t(savingPreset ? 'Saving…' : 'Save selected preset')} · {selectedPresetItems.length}
                </button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
      <AnimatePresence>
        {selection && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[100] grid place-items-center overflow-y-auto bg-slate-950/48 px-4 py-[calc(1rem+env(safe-area-inset-top))] backdrop-blur-md"
            onPointerDown={(event) => { if (event.target === event.currentTarget && !addingSelection) setSelection(null) }}
          >
            <motion.div
              initial={{ opacity: 0, y: 18, scale: 0.98 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 12, scale: 0.98 }}
              role="dialog"
              aria-modal="true"
              aria-label={t('Configure food amount')}
              className="w-full max-w-lg rounded-[1.9rem] border border-white/90 bg-canvas/98 p-5 shadow-[0_32px_90px_-32px_rgba(15,23,42,.65)] backdrop-blur-2xl"
              onPointerDown={(event) => event.stopPropagation()}
            >
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <p className="font-mono text-[10px] font-bold tracking-[0.18em] text-amber-700 uppercase">{t('Configure amount')}</p>
                  <h3 className="mt-1 font-display text-2xl leading-tight font-bold text-ink">{displayFoodName(selection.food, language)}</h3>
                  {selection.food.brand && <p className="mt-1 text-sm font-semibold text-ink-soft">{selection.food.brand}</p>}
                </div>
                <button type="button" disabled={addingSelection} onClick={() => setSelection(null)} className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/75 text-lg font-bold text-ink-soft disabled:opacity-40" aria-label={t('Close')}>×</button>
              </div>

              <div className="mt-5 rounded-2xl border border-white/90 bg-white/72 p-3.5 shadow-[0_14px_36px_-30px_rgba(15,23,42,.7)]">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-[10px] font-black tracking-wide text-ink-faint uppercase">
                    {t('Nutrition per')} 100 {selection.food.nutrition_basis === 'per_100ml' ? 'ml' : 'g'}
                  </p>
                  <span className="rounded-full bg-amber-500/10 px-2 py-1 text-[8px] font-bold text-amber-800">{t(selection.food.preparation_state.replace('_', ' '))}</span>
                </div>
                <div className="mt-3 grid grid-cols-4 gap-2 text-center">
                  {([
                    [t('kcal'), selection.food.kcal_100 ?? t('N/A')],
                    [t('Protein'), selection.food.protein_100 == null ? t('N/A') : `${selection.food.protein_100}g`],
                    [t('Carbs'), selection.food.carbs_100 == null ? t('N/A') : `${selection.food.carbs_100}g`],
                    [t('Fat'), selection.food.fat_100 == null ? t('N/A') : `${selection.food.fat_100}g`],
                  ] as const).map(([label, value]) => (
                    <div key={label} className="min-w-0 rounded-xl bg-canvas/72 px-1.5 py-2">
                      <p className="truncate font-mono text-base font-black text-ink">{value}</p>
                      <p className="mt-0.5 truncate text-[9px] font-bold text-ink-faint uppercase">{label}</p>
                    </div>
                  ))}
                </div>
                {selection.food.salt_100 != null && <p className="mt-2 text-right text-[9px] font-semibold text-ink-faint">{t('Salt')} {selection.food.salt_100}g</p>}
              </div>

              <div className="mt-5 grid grid-cols-[minmax(0,1fr)_minmax(0,1.2fr)] gap-3">
                <label className="min-w-0">
                  <span className="mb-1.5 block text-[10px] font-bold tracking-wide text-ink-faint uppercase">{t('Quantity')}</span>
                  <input
                    autoFocus
                    inputMode="decimal"
                    value={selection.quantity}
                    onChange={(event) => setSelection((current) => current ? { ...current, quantity: Math.max(0, parseDecimalInput(event.target.value) ?? 0) } : current)}
                    className="w-full rounded-xl border border-white/90 bg-white/85 px-3 py-3 font-mono text-lg font-black text-ink outline-none ring-amber-400/40 focus:ring-2"
                    aria-label={t('Food quantity')}
                  />
                </label>
                <label className="min-w-0">
                  <span className="mb-1.5 block text-[10px] font-bold tracking-wide text-ink-faint uppercase">{t('Serving type')}</span>
                  <select
                    value={selection.unit}
                    onChange={(event) => {
                      const unit = event.target.value as FoodUnit
                      setSelection((current) => current ? { ...current, unit, quantity: unit === 'g' || unit === 'ml' ? 100 : 1 } : current)
                    }}
                    className="w-full rounded-xl border border-white/90 bg-white/85 px-3 py-3 text-base font-bold text-ink outline-none ring-amber-400/40 focus:ring-2"
                  >
                    {availableFoodUnits(selection.food).map((unit) => {
                      const equivalent = unit === 'serving' ? selection.food.serving_grams_or_ml : unit === 'piece' ? selection.food.piece_grams_or_ml : null
                      return <option key={unit} value={unit}>{t(unit)}{equivalent ? ` (${equivalent} ${selection.food.nutrition_basis === 'per_100ml' ? 'ml' : 'g'})` : ''}</option>
                    })}
                  </select>
                </label>
              </div>

              <div className="mt-4 rounded-2xl border border-amber-400/10 bg-amber-500/8 px-4 py-3">
                <div className="flex flex-wrap items-center gap-x-4 gap-y-1 font-mono text-xs font-bold text-ink-soft">
                  <span>{selectionPortion?.kcal ?? t('N/A')} kcal</span>
                  <span>P {selectionPortion?.protein_g ?? t('N/A')}g</span>
                  <span>C {selectionPortion?.carbs_g ?? t('N/A')}g</span>
                  <span>F {selectionPortion?.fat_g ?? t('N/A')}g</span>
                </div>
                <p className="mt-1.5 text-[10px] leading-relaxed font-medium text-ink-faint">{t(foodProvenanceLabel(selection.food))}</p>
              </div>

              <div className="mt-5 grid grid-cols-[auto_minmax(0,1fr)] gap-2">
                <button type="button" disabled={addingSelection} onClick={() => setSelection(null)} className="rounded-xl bg-white/80 px-4 py-3.5 text-sm font-bold text-ink-soft disabled:opacity-40">{t('Cancel')}</button>
                <button
                  type="button"
                  disabled={addingSelection || !selectionReady}
                  onClick={() => void confirmFoodSelection()}
                  className="rounded-xl px-4 py-3.5 text-base font-black text-white shadow-[0_12px_28px_-14px_rgba(245,158,11,.95)] disabled:opacity-45"
                  style={{ background: amber.gradient }}
                >
                  {t(addingSelection ? 'Adding…' : 'Add food')} · {selectionPortion?.kcal ?? 0} kcal
                </button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
      {scanner && <Suspense fallback={null}><BarcodeScanner allowFrontCamera={data.settings?.addons.food_scanner_front_camera ?? false} onDetected={(code) => void lookupCode(code)} onClose={() => setScanner(false)} /></Suspense>}
    </div>
  )
}
