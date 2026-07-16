import { lazy, Suspense, useMemo, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ACCENTS } from '../../lib/theme'
import {
  availableFoodUnits,
  beginFoodSelection,
  calculatePortion,
  commitFoodSelection,
  composerItemFromSelection,
  displayFoodName,
  isFoodNutritionComplete,
  mealTotals,
  mergeExtendedFoodResults,
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
import { mealBlockIdempotencyKey, normalizeMealBlockSettings, type MealBlockKind } from '../../lib/mealBlocks'
import { useStore } from '../../store/AppStore'

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
  replaceMealId?: string | null
  onClose: () => void
  onLogged?: () => void
}

function foodProvenanceLabel(food: FoodRecord): string {
  if (food.source === 'private') return 'Your private food'
  if (food.source === 'open_food_facts') return 'Open Food Facts community record. Check the package label.'
  if (food.confidence === 'provider_verified') return 'Verified label or nutrition-provider reference'
  return 'Curated reference profile. Product labels can vary.'
}

export function MealComposer({
  slot,
  date,
  planning = false,
  title,
  initialItems = [],
  plannedMealId = null,
  mealBlockId = null,
  replaceMealId = null,
  onClose,
  onLogged,
}: MealComposerProps) {
  const store = useFoodStore()
  const { data, setSettings } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const slotLabel = translateInterfaceText(`${slot[0].toUpperCase()}${slot.slice(1)}`, language)
  const [items, setItems] = useState<ComposerFoodItem[]>(initialItems)
  const [name, setName] = useState(title ?? slotLabel)
  const [query, setQuery] = useState('')
  const [remoteResults, setRemoteResults] = useState<FoodRecord[]>([])
  const [searching, setSearching] = useState(false)
  const [scanner, setScanner] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [manualOpen, setManualOpen] = useState(false)
  const [presetName, setPresetName] = useState('')
  const [loadedPresetId, setLoadedPresetId] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [selection, setSelection] = useState<FoodSelectionDraft | null>(null)
  const [addingSelection, setAddingSelection] = useState(false)
  const [controlHelp, setControlHelp] = useState<{ itemId: string; kind: 'adaptive' | 'lock' | 'role' } | null>(null)
  const [manual, setManual] = useState({ name: '', kcal: '', protein: '', carbs: '', fat: '', preparation: 'as_sold' as FoodRecord['preparation_state'] })

  const ranked = useMemo(() => rankFoods(query, store.foods, store.preferences, slot).slice(0, 12), [query, slot, store.foods, store.preferences])
  const displayedFoods = useMemo(() => mergeExtendedFoodResults(query, ranked, remoteResults).slice(0, 30), [query, ranked, remoteResults])
  const totals = useMemo(() => mealTotals(items), [items])
  const selectionPortion = useMemo(
    () => selection ? calculatePortion(selection.food, selection.quantity, selection.unit) : null,
    [selection],
  )
  const selectionReady = Boolean(selection && selection.quantity > 0 && selectionPortion)
  const mealBlockSettings = useMemo(() => normalizeMealBlockSettings(data.settings?.addons.meal_blocks), [data.settings?.addons.meal_blocks])
  const slotPresets = useMemo(() => store.presets.filter((preset) => {
    if (preset.archived || preset.meal_slot !== slot) return false
    if (!mealBlockId) return true
    const assigned = mealBlockSettings.preset_assignments[preset.id]
    return assigned == null || assigned === mealBlockId
  }), [mealBlockId, mealBlockSettings.preset_assignments, slot, store.presets])
  const recentMeals = useMemo(() => store.meals.filter((meal) => meal.meal_slot === slot).slice(0, 4), [slot, store.meals])

  const materializeFood = async (food: FoodRecord): Promise<FoodRecord> => {
    const needsPrivateCopy = food.id.startsWith('off:') || food.provider_product_id?.startsWith('apex-curated:')
    if (!needsPrivateCopy || food.owner_user_id) return food
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

  const openFoodSelection = (food: FoodRecord) => {
    const preference = store.preferences.find((value) => value.food_id === food.id)
    setSelection(beginFoodSelection(food, preference))
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

  const moveItem = (index: number, direction: -1 | 1) => {
    const target = index + direction
    if (target < 0 || target >= items.length) return
    setItems((current) => {
      const next = [...current]
      ;[next[index], next[target]] = [next[target], next[index]]
      return next.map((item, sort_order) => ({ ...item, sort_order }))
    })
  }

  const searchWider = async () => {
    if (query.trim().length < 2) return
    setSearching(true)
    setMessage(null)
    try {
      const result = await store.widerSearch(query.trim(), language)
      setRemoteResults(result.results)
      if (!result.results.length) setMessage(result.message ?? 'No additional matches. Your essential foods are still available above.')
    } catch {
      setMessage('Extended search is temporarily unavailable. Your essential foods are still available above.')
    } finally {
      setSearching(false)
    }
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
      serving_amount: null, serving_unit: null, serving_grams_or_ml: null, piece_grams_or_ml: null,
      provider_updated_at: null, confidence: 'user_entered',
    })
    openFoodSelection(food)
    setManualOpen(false)
  }

  const loadPreset = (id: string) => {
    const preset = store.presets.find((value) => value.id === id)
    setItems(store.itemsForPreset(id).map((item) => ({ ...item, id: crypto.randomUUID() })))
    if (preset) setName(preset.name)
    setLoadedPresetId(id)
  }

  const loadRecent = (mealId: string) => {
    const meal = store.meals.find((value) => value.id === mealId)
    if (!meal) return
    const next = store.entries.filter((entry) => entry.meal_id === mealId).map((entry, index) => {
      const food = store.foods.find((value) => value.id === entry.food_id)
      if (!food) return null
      return composerItemFromSelection({ food, quantity: entry.quantity, unit: entry.unit }, index)
    }).filter((item): item is ComposerFoodItem => item != null)
    setItems(next)
    setName(meal.display_name)
    setLoadedPresetId(null)
  }

  const savePreset = async (asNew = false) => {
    if (!items.length) return
    const current = !asNew && loadedPresetId ? store.presets.find((preset) => preset.id === loadedPresetId) : undefined
    const saved = await store.savePreset({
      id: current?.id,
      expectedVersion: current?.version,
      name: presetName.trim() || name,
      slot,
      items,
      sourcePlannedMealId: plannedMealId,
    })
    if (mealBlockId && data.settings) {
      setSettings({
        addons: {
          ...data.settings.addons,
          meal_blocks: {
            ...mealBlockSettings,
            preset_assignments: { ...mealBlockSettings.preset_assignments, [saved.id]: mealBlockId },
          },
        },
      })
    }
    setLoadedPresetId(saved.id)
    setPresetName('')
    setMessage('Reusable preset saved. Adjustable amounts can adapt without rewriting your template.')
  }

  const log = async () => {
    if (!items.length || totals.kcal <= 0) {
      setMessage('Add at least one complete food before logging.')
      return
    }
    setSaving(true)
    try {
      const assignedBlock = mealBlockId ?? (loadedPresetId ? mealBlockSettings.preset_assignments[loadedPresetId] : null)
      await store.logMeal({
        date, slot, name: name.trim() || 'Meal', items, sourcePresetId: loadedPresetId,
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
          <button type="button" onClick={onClose} className="glass rounded-full px-4 py-2 text-sm font-bold text-ink">Close</button>
        </div>

        <div className="mt-4 space-y-4">
          <GlassCard accent={amber} className="p-4">
            <label className="text-xs font-bold text-ink-soft">Meal name</label>
            <input aria-label="Meal name" value={name} onChange={(event) => setName(event.target.value)} className="mt-1 w-full bg-transparent font-display text-lg font-bold text-ink outline-none" />
            <div className="mt-3 grid grid-cols-4 gap-2 border-t border-ink/8 pt-3 text-center">
              {([['kcal', totals.kcal], ['protein', totals.protein_g], ['carbs', totals.carbs_g], ['fat', totals.fat_g]] as const).map(([label, value]) => (
                <div key={label}><p className="font-mono text-lg font-bold text-ink">{value}</p><p className="text-[9px] font-bold text-ink-faint uppercase">{label}</p></div>
              ))}
            </div>
          </GlassCard>

          <GlassCard className="overflow-visible p-3">
            <div className="flex gap-2">
              <input
                autoFocus
                value={query}
                onChange={(event) => { setQuery(event.target.value); setRemoteResults([]) }}
                onKeyDown={(event) => event.key === 'Enter' && void searchWider()}
                placeholder="Search foods, aliases or brands"
                className="min-w-0 flex-1 rounded-2xl bg-white/70 px-4 py-3 text-sm font-semibold text-ink outline-none"
              />
              <button
                type="button"
                onClick={() => setScanner(true)}
                className="flex h-[3.25rem] w-[4.25rem] shrink-0 flex-col items-center justify-center rounded-2xl text-white shadow-lg transition active:scale-95"
                style={{ background: amber.gradient, boxShadow: `0 10px 24px -10px ${amber.glowStrong}` }}
                aria-label="Scan a food barcode"
              >
                <BarcodeIcon className="h-[18px] w-8" />
                <span className="mt-1 font-mono text-[7px] font-bold tracking-[0.16em] uppercase">Scan</span>
              </button>
            </div>
            <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
              {store.preferences.filter((value) => value.favourite).slice(0, 6).map((preference) => {
                const food = store.foods.find((value) => value.id === preference.food_id)
                return food ? <button key={food.id} type="button" onClick={() => void selectFood(food)} className="shrink-0 rounded-full bg-amber-500/10 px-3 py-1.5 text-xs font-bold text-amber-700">★ {preference.personal_name || food.name}</button> : null
              })}
              <button type="button" onClick={() => setManualOpen((value) => !value)} className="shrink-0 rounded-full bg-white/70 px-3 py-1.5 text-xs font-bold text-ink-soft">+ Private food</button>
            </div>
            {(query || remoteResults.length > 0) && (
              <div className="mt-3 max-h-72 space-y-1 overflow-y-auto">
                {displayedFoods.map((food) => (
                  <button key={food.id} type="button" onClick={() => void selectFood(food)} className="flex w-full items-center justify-between rounded-xl px-3 py-2 text-left hover:bg-white/75">
                    <span><span className="block text-sm font-bold text-ink">{displayFoodName(food, language)}</span><span className="text-[10px] font-medium text-ink-faint">{food.brand || translateInterfaceText(food.preparation_state.replace('_', ' '), language)} · {food.kcal_100 ?? '?'} kcal / 100</span></span>
                    <span className="rounded-full bg-amber-500/10 px-2 py-1 text-[9px] font-black tracking-wide text-amber-700 uppercase">{t('Configure')}</span>
                  </button>
                ))}
                {query.length >= 2 && (
                  <button type="button" disabled={searching} onClick={() => void searchWider()} className="w-full rounded-xl border border-amber-500/20 px-3 py-2 text-xs font-bold text-amber-700">
                    {translateInterfaceText(searching ? 'Searching more foods…' : 'Extend search', language)}
                  </button>
                )}
              </div>
            )}
          </GlassCard>

          <AnimatePresence>
            {manualOpen && (
              <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }}>
                <GlassCard className="p-4">
                  <h3 className="font-display text-sm font-bold text-ink">Create a private food</h3>
                  <p className="mt-1 text-[11px] text-ink-soft">Values are per 100 g. Decimal commas are accepted. This record is visible only to you.</p>
                  <input value={manual.name} onChange={(event) => setManual((value) => ({ ...value, name: event.target.value }))} placeholder="Food name" className="mt-3 w-full rounded-xl bg-white/70 px-3 py-2 text-sm outline-none" />
                  <div className="mt-2 grid grid-cols-2 gap-2">
                    {(['kcal', 'protein', 'carbs', 'fat'] as const).map((field) => (
                      <input key={field} inputMode="decimal" value={manual[field]} onChange={(event) => setManual((value) => ({ ...value, [field]: event.target.value }))} placeholder={`${field} / 100 g`} className="rounded-xl bg-white/70 px-3 py-2 text-sm outline-none" />
                    ))}
                  </div>
                  <select value={manual.preparation} onChange={(event) => setManual((value) => ({ ...value, preparation: event.target.value as FoodRecord['preparation_state'] }))} className="mt-2 w-full rounded-xl bg-white/70 px-3 py-2 text-sm">
                    <option value="as_sold">As sold</option><option value="dry">Dry</option><option value="cooked">Cooked</option><option value="prepared">Prepared</option><option value="drained">Drained</option>
                  </select>
                  <button type="button" onClick={() => void createManual()} className="mt-3 rounded-xl bg-amber-500 px-4 py-2 text-xs font-bold text-white">Save privately and add</button>
                </GlassCard>
              </motion.div>
            )}
          </AnimatePresence>

          {(slotPresets.length > 0 || recentMeals.length > 0) && (
            <GlassCard className="p-4">
              <p className="text-[10px] font-bold tracking-wide text-ink-faint uppercase">Fast starts</p>
              <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
                {slotPresets.map((preset) => <button key={preset.id} type="button" onClick={() => loadPreset(preset.id)} className="shrink-0 rounded-full bg-white/75 px-3 py-2 text-xs font-bold text-ink">Preset · {preset.name}</button>)}
                {recentMeals.map((meal) => <button key={meal.id} type="button" onClick={() => loadRecent(meal.id)} className="shrink-0 rounded-full bg-white/75 px-3 py-2 text-xs font-bold text-ink">Repeat · {meal.display_name}</button>)}
              </div>
            </GlassCard>
          )}

          <div className="space-y-2">
            {items.map((item, index) => {
              const portion = calculatePortion(item.food, item.quantity, item.unit)
              const units = availableFoodUnits(item.food)
              return (
                <GlassCard key={item.id} accent={amber} className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div><h3 className="text-sm font-bold text-ink">{displayFoodName(item.food, language)}</h3><p className="text-[10px] text-ink-faint">{item.food.brand || translateInterfaceText(item.food.preparation_state.replace('_', ' '), language)}</p></div>
                    <div className="flex gap-1">
                      <button type="button" onClick={() => moveItem(index, -1)} disabled={index === 0} className="rounded-lg bg-white/65 px-2 py-1 text-xs disabled:opacity-25">↑</button>
                      <button type="button" onClick={() => moveItem(index, 1)} disabled={index === items.length - 1} className="rounded-lg bg-white/65 px-2 py-1 text-xs disabled:opacity-25">↓</button>
                      <button type="button" onClick={() => setItems((current) => current.filter((value) => value.id !== item.id))} className="rounded-lg bg-red-500/8 px-2 py-1 text-xs font-bold text-red-600">×</button>
                    </div>
                  </div>
                  <div className="mt-3 flex items-center gap-2">
                    <input aria-label={`Amount for ${item.food.name}`} inputMode="decimal" value={item.quantity} onChange={(event) => patchItem(item.id, { quantity: Math.max(0, parseDecimalInput(event.target.value) ?? 0) })} className="w-28 rounded-xl bg-white/75 px-3 py-2 font-mono text-sm font-bold outline-none" />
                    <select value={item.unit} onChange={(event) => patchItem(item.id, { unit: event.target.value as FoodUnit })} className="rounded-xl bg-white/75 px-3 py-2 text-sm font-bold">
                      {units.map((unit) => <option key={unit} value={unit}>{unit}</option>)}
                    </select>
                    <button type="button" onClick={() => void store.setPreference(item.food.id, { favourite: !store.preferences.find((value) => value.food_id === item.food.id)?.favourite })} className="ml-auto text-xl" aria-label="Toggle favourite">{store.preferences.find((value) => value.food_id === item.food.id)?.favourite ? '★' : '☆'}</button>
                  </div>
                  <div className="mt-2 flex gap-3 font-mono text-[10px] font-semibold text-ink-soft">
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
                  <div className="mt-2 grid grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] gap-2">
                    <input
                      defaultValue={store.preferences.find((value) => value.food_id === item.food.id)?.personal_name ?? ''}
                      onBlur={(event) => void store.setPreference(item.food.id, { personal_name: event.target.value.trim() || null })}
                      placeholder={t('Personal label')}
                      className="rounded-lg bg-white/65 px-2 py-1.5 text-[10px] outline-none"
                    />
                    {index === items.length - 1 ? (
                      <button
                        type="button"
                        disabled={saving || totals.kcal <= 0}
                        onClick={() => void log()}
                        className="rounded-xl px-3 py-2 text-[11px] font-black text-white shadow-[0_12px_24px_-14px_rgba(245,158,11,.9)] disabled:opacity-50"
                        style={{ background: amber.gradient }}
                      >
                        {saving ? t('Saving privately…') : t(replaceMealId ? 'Replace meal' : planning ? 'Add to day' : 'Add food')} · {totals.kcal} kcal
                      </button>
                    ) : <span />}
                  </div>
                </GlassCard>
              )
            })}
          </div>

          {message && <p className="rounded-2xl bg-amber-500/10 px-4 py-3 text-xs font-semibold text-amber-800">{translateInterfaceText(message, language)}</p>}

          {items.length > 0 && (
            <GlassCard className="p-4">
              <p className="text-xs font-bold text-ink">Keep this combination</p>
              <div className="mt-2 flex flex-wrap gap-2">
                <input value={presetName} onChange={(event) => setPresetName(event.target.value)} placeholder={name} className="min-w-44 flex-1 rounded-xl bg-white/75 px-3 py-2 text-sm outline-none" />
                <button type="button" onClick={() => void savePreset(false)} className="rounded-xl bg-white/80 px-3 py-2 text-xs font-bold text-ink">{loadedPresetId ? 'Update preset' : 'Save preset'}</button>
                {loadedPresetId && <button type="button" onClick={() => void savePreset(true)} className="rounded-xl bg-white/65 px-3 py-2 text-xs font-bold text-ink-soft">Save as new</button>}
              </div>
              <p className="mt-2 text-[10px] font-medium text-ink-faint">{t(planning ? 'Adding this meal changes only the selected date. Saved presets remain unchanged.' : 'Logging below changes today only. A saved preset changes only when you use the buttons above.')}</p>
            </GlassCard>
          )}
          <p className="text-center text-[10px] font-medium text-ink-faint">Logged entries are immutable snapshots. Editing a food later will never rewrite your history.</p>
        </div>
      </div>
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
              className="w-full max-w-md rounded-[1.75rem] border border-white/85 bg-canvas/96 p-4 shadow-[0_32px_90px_-32px_rgba(15,23,42,.65)] backdrop-blur-2xl"
              onPointerDown={(event) => event.stopPropagation()}
            >
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0">
                  <p className="font-mono text-[9px] font-bold tracking-[0.18em] text-amber-700 uppercase">{t('Configure amount')}</p>
                  <h3 className="mt-1 font-display text-lg leading-tight font-bold text-ink">{displayFoodName(selection.food, language)}</h3>
                  {selection.food.brand && <p className="mt-0.5 text-xs font-semibold text-ink-soft">{selection.food.brand}</p>}
                </div>
                <button type="button" disabled={addingSelection} onClick={() => setSelection(null)} className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/75 text-lg font-bold text-ink-soft disabled:opacity-40" aria-label={t('Close')}>×</button>
              </div>

              <div className="mt-4 rounded-2xl border border-white/80 bg-white/64 p-3">
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
                    <div key={label} className="min-w-0">
                      <p className="truncate font-mono text-sm font-black text-ink">{value}</p>
                      <p className="mt-0.5 truncate text-[8px] font-bold text-ink-faint uppercase">{label}</p>
                    </div>
                  ))}
                </div>
                {selection.food.salt_100 != null && <p className="mt-2 text-right text-[9px] font-semibold text-ink-faint">{t('Salt')} {selection.food.salt_100}g</p>}
              </div>

              <div className="mt-4 grid grid-cols-[minmax(0,1fr)_minmax(0,1.15fr)] gap-2">
                <label className="min-w-0">
                  <span className="mb-1 block text-[9px] font-bold tracking-wide text-ink-faint uppercase">{t('Quantity')}</span>
                  <input
                    autoFocus
                    inputMode="decimal"
                    value={selection.quantity}
                    onChange={(event) => setSelection((current) => current ? { ...current, quantity: Math.max(0, parseDecimalInput(event.target.value) ?? 0) } : current)}
                    className="w-full rounded-xl bg-white/80 px-3 py-2.5 font-mono text-base font-black text-ink outline-none ring-amber-400/40 focus:ring-2"
                    aria-label={t('Food quantity')}
                  />
                </label>
                <label className="min-w-0">
                  <span className="mb-1 block text-[9px] font-bold tracking-wide text-ink-faint uppercase">{t('Serving type')}</span>
                  <select
                    value={selection.unit}
                    onChange={(event) => {
                      const unit = event.target.value as FoodUnit
                      setSelection((current) => current ? { ...current, unit, quantity: unit === 'g' || unit === 'ml' ? 100 : 1 } : current)
                    }}
                    className="w-full rounded-xl bg-white/80 px-3 py-2.5 text-sm font-bold text-ink outline-none ring-amber-400/40 focus:ring-2"
                  >
                    {availableFoodUnits(selection.food).map((unit) => {
                      const equivalent = unit === 'serving' ? selection.food.serving_grams_or_ml : unit === 'piece' ? selection.food.piece_grams_or_ml : null
                      return <option key={unit} value={unit}>{t(unit)}{equivalent ? ` (${equivalent} ${selection.food.nutrition_basis === 'per_100ml' ? 'ml' : 'g'})` : ''}</option>
                    })}
                  </select>
                </label>
              </div>

              <div className="mt-3 rounded-xl bg-amber-500/8 px-3 py-2">
                <div className="flex flex-wrap items-center gap-x-3 gap-y-1 font-mono text-[10px] font-bold text-ink-soft">
                  <span>{selectionPortion?.kcal ?? t('N/A')} kcal</span>
                  <span>P {selectionPortion?.protein_g ?? t('N/A')}g</span>
                  <span>C {selectionPortion?.carbs_g ?? t('N/A')}g</span>
                  <span>F {selectionPortion?.fat_g ?? t('N/A')}g</span>
                </div>
                <p className="mt-1 text-[9px] leading-relaxed font-medium text-ink-faint">{t(foodProvenanceLabel(selection.food))}</p>
              </div>

              <div className="mt-4 grid grid-cols-[auto_minmax(0,1fr)] gap-2">
                <button type="button" disabled={addingSelection} onClick={() => setSelection(null)} className="rounded-xl bg-white/75 px-4 py-3 text-xs font-bold text-ink-soft disabled:opacity-40">{t('Cancel')}</button>
                <button
                  type="button"
                  disabled={addingSelection || !selectionReady}
                  onClick={() => void confirmFoodSelection()}
                  className="rounded-xl px-4 py-3 text-sm font-black text-white shadow-[0_12px_28px_-14px_rgba(245,158,11,.95)] disabled:opacity-45"
                  style={{ background: amber.gradient }}
                >
                  {t(addingSelection ? 'Adding…' : 'Add food')} · {selectionPortion?.kcal ?? 0} kcal
                </button>
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
      {scanner && <Suspense fallback={null}><BarcodeScanner onDetected={(code) => void lookupCode(code)} onClose={() => setScanner(false)} /></Suspense>}
    </div>
  )
}
