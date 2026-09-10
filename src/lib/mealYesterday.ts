import { composerItemFromSelection, foodFromLoggedEntry, type LoggedMeal, type LoggedFoodEntry, type MealSlot } from './food.ts'

export function yesterdayMealItems(date: string, slot: MealSlot, owner: string | null, meals: LoggedMeal[], entries: LoggedFoodEntry[]) {
  if (!owner || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return []
  const previous = new Date(`${date}T12:00:00Z`)
  if (!Number.isFinite(previous.getTime())) return []
  previous.setUTCDate(previous.getUTCDate() - 1)
  const key = previous.toISOString().slice(0, 10)
  const candidates = meals.filter(m => m.user_id === owner && m.local_date === key && m.meal_slot === slot)
    .sort((a, b) => b.logged_at.localeCompare(a.logged_at) || b.id.localeCompare(a.id))
  for (const meal of candidates) {
    const rows = entries.filter(e => e.user_id === owner && e.meal_id === meal.id).sort((a, b) => a.sort_order - b.sort_order)
    if (!rows.length) continue
    return rows.map((entry, index) => {
      const food = foodFromLoggedEntry(entry)
      // Preserve fractional servings and the recorded evidence, not today's provider data.
      const mass = entry.quantity > 0 ? entry.equivalent_amount / entry.quantity : null
      food.serving_grams_or_ml = entry.unit === 'serving' ? mass : food.serving_grams_or_ml
      food.piece_grams_or_ml = entry.unit === 'piece' ? mass : food.piece_grams_or_ml
      food.nutrient_evidence = entry.snapshot_nutrient_evidence ?? []
      return composerItemFromSelection({ food, quantity: entry.quantity, unit: entry.unit }, index)
    })
  }
  return []
}
