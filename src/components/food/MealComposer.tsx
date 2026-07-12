import { lazy, Suspense, useMemo, useState } from 'react'
import { AnimatePresence, motion } from 'framer-motion'
import { ACCENTS } from '../../lib/theme'
import {
  calculatePortion,
  isFoodNutritionComplete,
  mealTotals,
  parseDecimalInput,
  rankFoods,
  suggestPresetAdaptation,
  type AdaptiveContext,
  type ComposerFoodItem,
  type FoodRecord,
  type FoodUnit,
  type MealSlot,
} from '../../lib/food'
import { useFoodStore } from '../../store/FoodStore'
import { AccentChip, GlassCard, GradientButton } from '../ui'

const BarcodeScanner = lazy(() => import('./BarcodeScanner').then((module) => ({ default: module.BarcodeScanner })))
const amber = ACCENTS.amber

interface MealComposerProps {
  slot: MealSlot
  title?: string
  initialItems?: ComposerFoodItem[]
  plannedMealId?: string | null
  replaceMealId?: string | null
  adaptiveContext?: AdaptiveContext
  onClose: () => void
  onLogged?: () => void
}

function defaultUnit(food: FoodRecord): FoodUnit {
  if (food.piece_grams_or_ml) return 'piece'
  if (food.serving_grams_or_ml) return 'serving'
  return food.nutrition_basis === 'per_100ml' ? 'ml' : 'g'
}

function composerItem(food: FoodRecord, index: number): ComposerFoodItem {
  const unit = defaultUnit(food)
  return {
    id: crypto.randomUUID(), food, quantity: unit === 'piece' ? 1 : unit === 'serving' ? 1 : 100,
    unit, sort_order: index, optional: false, locked: false, adjustable: true,
    minimum_amount: null, maximum_amount: null, step_amount: unit === 'piece' ? 1 : 5,
    adjustment_role: food.carbs_100 != null && food.protein_100 != null && food.carbs_100 > food.protein_100 ? 'carb' : 'protein',
  }
}

export function MealComposer({
  slot,
  title,
  initialItems = [],
  plannedMealId = null,
  replaceMealId = null,
  adaptiveContext,
  onClose,
  onLogged,
}: MealComposerProps) {
  const store = useFoodStore()
  const [items, setItems] = useState<ComposerFoodItem[]>(initialItems)
  const [name, setName] = useState(title ?? `${slot[0].toUpperCase()}${slot.slice(1)}`)
  const [query, setQuery] = useState('')
  const [remoteResults, setRemoteResults] = useState<FoodRecord[]>([])
  const [searching, setSearching] = useState(false)
  const [scanner, setScanner] = useState(false)
  const [message, setMessage] = useState<string | null>(null)
  const [manualOpen, setManualOpen] = useState(false)
  const [presetName, setPresetName] = useState('')
  const [loadedPresetId, setLoadedPresetId] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [manual, setManual] = useState({ name: '', kcal: '', protein: '', carbs: '', fat: '', preparation: 'as_sold' as FoodRecord['preparation_state'] })

  const ranked = useMemo(() => rankFoods(query, store.foods, store.preferences, slot).slice(0, 12), [query, slot, store.foods, store.preferences])
  const totals = useMemo(() => mealTotals(items), [items])
  const suggestions = useMemo(() => adaptiveContext ? suggestPresetAdaptation(items, adaptiveContext) : [], [adaptiveContext, items])
  const slotPresets = useMemo(() => store.presets.filter((preset) => !preset.archived && preset.meal_slot === slot), [slot, store.presets])
  const recentMeals = useMemo(() => store.meals.filter((meal) => meal.meal_slot === slot).slice(0, 4), [slot, store.meals])

  const addFood = (food: FoodRecord) => {
    const preference = store.preferences.find((value) => value.food_id === food.id)
    const next = composerItem(food, items.length)
    if (preference?.usual_amount && preference.usual_unit) {
      next.quantity = preference.usual_amount
      next.unit = preference.usual_unit
    }
    setItems((current) => [...current, next])
    setQuery('')
    setRemoteResults([])
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
    const result = await store.widerSearch(query.trim())
    setRemoteResults(result.results)
    if (!result.results.length) setMessage(result.message ?? 'No wider-search matches. Create a private food instead.')
    setSearching(false)
  }

  const lookupCode = async (barcode: string) => {
    setScanner(false)
    setSearching(true)
    const result = await store.lookupBarcode(barcode)
    setSearching(false)
    if (result.food && isFoodNutritionComplete(result.food)) addFood(result.food)
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
  }

  const selectRemote = async (food: FoodRecord) => {
    if (!food.barcode) return
    await lookupCode(food.barcode)
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
    addFood(food)
    setManualOpen(false)
  }

  const applySuggestion = () => {
    const suggestion = suggestions[0]
    if (suggestion) patchItem(suggestion.item_id, { quantity: suggestion.proposed_quantity })
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
      return { ...composerItem(food, index), quantity: entry.quantity, unit: entry.unit }
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
      await store.logMeal({
        slot, name: name.trim() || 'Meal', items, sourcePlannedMealId: plannedMealId,
        replaceMealId, loggedAs: plannedMealId ? (initialItems.length ? 'changed' : 'planned') : 'custom',
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
            <p className="font-mono text-[10px] tracking-[0.18em] text-ink-faint uppercase">Actual intake · {slot}</p>
            <h2 className="font-display text-xl font-bold text-ink">Build this meal</h2>
          </div>
          <button type="button" onClick={onClose} className="glass rounded-full px-4 py-2 text-sm font-bold text-ink">Close</button>
        </div>

        <div className="mt-4 space-y-4">
          <GlassCard accent={amber} className="p-4">
            <label className="text-xs font-bold text-ink-soft">Meal name</label>
            <input value={name} onChange={(event) => setName(event.target.value)} className="mt-1 w-full bg-transparent font-display text-lg font-bold text-ink outline-none" />
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
              <button type="button" onClick={() => setScanner(true)} className="rounded-2xl px-4 text-xl" style={{ background: amber.gradient }} aria-label="Scan barcode">▣</button>
            </div>
            <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
              {store.preferences.filter((value) => value.favourite).slice(0, 6).map((preference) => {
                const food = store.foods.find((value) => value.id === preference.food_id)
                return food ? <button key={food.id} type="button" onClick={() => addFood(food)} className="shrink-0 rounded-full bg-amber-500/10 px-3 py-1.5 text-xs font-bold text-amber-700">★ {preference.personal_name || food.name}</button> : null
              })}
              <button type="button" onClick={() => setManualOpen((value) => !value)} className="shrink-0 rounded-full bg-white/70 px-3 py-1.5 text-xs font-bold text-ink-soft">+ Private food</button>
            </div>
            {(query || remoteResults.length > 0) && (
              <div className="mt-3 max-h-72 space-y-1 overflow-y-auto">
                {(remoteResults.length ? remoteResults : ranked).map((food) => (
                  <button key={food.id} type="button" onClick={() => remoteResults.length ? void selectRemote(food) : addFood(food)} className="flex w-full items-center justify-between rounded-xl px-3 py-2 text-left hover:bg-white/75">
                    <span><span className="block text-sm font-bold text-ink">{food.name}</span><span className="text-[10px] font-medium text-ink-faint">{food.brand || food.preparation_state.replace('_', ' ')} · {food.kcal_100 ?? '?'} kcal / 100</span></span>
                    <span className="text-lg text-amber-600">+</span>
                  </button>
                ))}
                {!remoteResults.length && query.length >= 2 && (
                  <button type="button" disabled={searching} onClick={() => void searchWider()} className="w-full rounded-xl border border-amber-500/20 px-3 py-2 text-xs font-bold text-amber-700">
                    {searching ? 'Searching Open Food Facts…' : 'Search wider on Open Food Facts'}
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
              const units: FoodUnit[] = ['g', 'ml', ...(item.food.serving_grams_or_ml ? ['serving' as const] : []), ...(item.food.piece_grams_or_ml ? ['piece' as const] : [])]
              return (
                <GlassCard key={item.id} accent={amber} className="p-4">
                  <div className="flex items-start justify-between gap-2">
                    <div><h3 className="text-sm font-bold text-ink">{item.food.name}</h3><p className="text-[10px] text-ink-faint">{item.food.brand || item.food.preparation_state.replace('_', ' ')}</p></div>
                    <div className="flex gap-1">
                      <button type="button" onClick={() => moveItem(index, -1)} disabled={index === 0} className="rounded-lg bg-white/65 px-2 py-1 text-xs disabled:opacity-25">↑</button>
                      <button type="button" onClick={() => moveItem(index, 1)} disabled={index === items.length - 1} className="rounded-lg bg-white/65 px-2 py-1 text-xs disabled:opacity-25">↓</button>
                      <button type="button" onClick={() => setItems((current) => current.filter((value) => value.id !== item.id))} className="rounded-lg bg-red-500/8 px-2 py-1 text-xs font-bold text-red-600">×</button>
                    </div>
                  </div>
                  <div className="mt-3 flex items-center gap-2">
                    <input inputMode="decimal" value={item.quantity} onChange={(event) => patchItem(item.id, { quantity: Math.max(0, parseDecimalInput(event.target.value) ?? 0) })} className="w-28 rounded-xl bg-white/75 px-3 py-2 font-mono text-sm font-bold outline-none" />
                    <select value={item.unit} onChange={(event) => patchItem(item.id, { unit: event.target.value as FoodUnit })} className="rounded-xl bg-white/75 px-3 py-2 text-sm font-bold">
                      {units.map((unit) => <option key={unit} value={unit}>{unit}</option>)}
                    </select>
                    <button type="button" onClick={() => void store.setPreference(item.food.id, { favourite: !store.preferences.find((value) => value.food_id === item.food.id)?.favourite })} className="ml-auto text-xl" aria-label="Toggle favourite">{store.preferences.find((value) => value.food_id === item.food.id)?.favourite ? '★' : '☆'}</button>
                  </div>
                  <div className="mt-2 flex gap-3 font-mono text-[10px] font-semibold text-ink-soft">
                    <span>{portion?.kcal ?? '?'} kcal</span><span>P {portion?.protein_g ?? '?'}</span><span>C {portion?.carbs_g ?? '?'}</span><span>F {portion?.fat_g ?? '?'}</span>
                  </div>
                  <div className="mt-2 flex flex-wrap gap-2 text-[10px] font-semibold text-ink-soft">
                    <label><input type="checkbox" checked={item.adjustable} onChange={(event) => patchItem(item.id, { adjustable: event.target.checked })} /> adaptive</label>
                    <label><input type="checkbox" checked={item.locked} onChange={(event) => patchItem(item.id, { locked: event.target.checked })} /> lock</label>
                    <select value={item.adjustment_role} onChange={(event) => patchItem(item.id, { adjustment_role: event.target.value as ComposerFoodItem['adjustment_role'] })} className="rounded-lg bg-white/65 px-2">
                      <option value="carb">carb flex</option><option value="protein">protein flex</option><option value="energy">energy flex</option><option value="none">fixed</option>
                    </select>
                  </div>
                  <div className="mt-2 grid grid-cols-2 gap-2">
                    <input
                      defaultValue={store.preferences.find((value) => value.food_id === item.food.id)?.personal_name ?? ''}
                      onBlur={(event) => void store.setPreference(item.food.id, { personal_name: event.target.value.trim() || null })}
                      placeholder="Personal label"
                      className="rounded-lg bg-white/65 px-2 py-1.5 text-[10px] outline-none"
                    />
                    <input
                      defaultValue={(store.preferences.find((value) => value.food_id === item.food.id)?.aliases ?? []).join(', ')}
                      onBlur={(event) => void store.setPreference(item.food.id, { aliases: event.target.value.split(',').map((value) => value.trim()).filter(Boolean) })}
                      placeholder="Aliases, comma separated"
                      className="rounded-lg bg-white/65 px-2 py-1.5 text-[10px] outline-none"
                    />
                  </div>
                </GlassCard>
              )
            })}
          </div>

          {suggestions[0] && (
            <GlassCard accent={amber} className="p-4">
              <div className="flex items-start justify-between gap-3">
                <div><AccentChip accent={amber}>APEX SUGGESTION</AccentChip><p className="mt-2 text-xs font-semibold text-ink-soft">{suggestions[0].explanation}</p><p className="mt-1 font-mono text-xs font-bold text-ink">{suggestions[0].original_quantity} → {suggestions[0].proposed_quantity} {suggestions[0].unit} · {suggestions[0].delta.kcal > 0 ? '+' : ''}{suggestions[0].delta.kcal} kcal</p></div>
                <button type="button" onClick={applySuggestion} className="rounded-xl bg-amber-500 px-3 py-2 text-xs font-bold text-white">Apply</button>
              </div>
            </GlassCard>
          )}

          {message && <p className="rounded-2xl bg-amber-500/10 px-4 py-3 text-xs font-semibold text-amber-800">{message}</p>}

          {items.length > 0 && (
            <GlassCard className="p-4">
              <p className="text-xs font-bold text-ink">Keep this combination</p>
              <div className="mt-2 flex flex-wrap gap-2">
                <input value={presetName} onChange={(event) => setPresetName(event.target.value)} placeholder={name} className="min-w-44 flex-1 rounded-xl bg-white/75 px-3 py-2 text-sm outline-none" />
                <button type="button" onClick={() => void savePreset(false)} className="rounded-xl bg-white/80 px-3 py-2 text-xs font-bold text-ink">{loadedPresetId ? 'Update preset' : 'Save preset'}</button>
                {loadedPresetId && <button type="button" onClick={() => void savePreset(true)} className="rounded-xl bg-white/65 px-3 py-2 text-xs font-bold text-ink-soft">Save as new</button>}
              </div>
              <p className="mt-2 text-[10px] font-medium text-ink-faint">Logging below changes today only. A saved preset changes only when you use the buttons above.</p>
            </GlassCard>
          )}

          <GradientButton accent={amber} disabled={saving || !items.length} onClick={() => void log()} className="w-full">
            {saving ? 'Saving privately…' : replaceMealId ? `Replace meal · ${totals.kcal} kcal` : `Log meal · ${totals.kcal} kcal`}
          </GradientButton>
          <p className="text-center text-[10px] font-medium text-ink-faint">Logged entries are immutable snapshots. Editing a food later will never rewrite your history.</p>
        </div>
      </div>
      {scanner && <Suspense fallback={null}><BarcodeScanner onDetected={(code) => void lookupCode(code)} onClose={() => setScanner(false)} /></Suspense>}
    </div>
  )
}
