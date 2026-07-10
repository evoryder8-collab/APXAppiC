import { differenceInYears } from 'date-fns'
import type { ActivityLevel, Goal, Meal, Profile } from './types'

export function ageFrom(birthdate: string, at: Date = new Date()): number {
  return differenceInYears(at, new Date(birthdate + 'T00:00:00'))
}

/* Mifflin-St Jeor: weight/height/age based */
export function bmrMifflin(p: Profile): number {
  const age = ageFrom(p.birthdate)
  const base = 10 * p.weight_kg + 6.25 * p.height_cm - 5 * age
  return Math.round(base + (p.sex === 'male' ? 5 : -161))
}

/* Katch-McArdle: lean-mass based, more accurate when body fat % is known */
export function bmrKatch(p: Profile): number {
  const lean = p.weight_kg * (1 - p.body_fat_pct / 100)
  return Math.round(370 + 21.6 * lean)
}

export const ACTIVITY_MULTIPLIERS: Record<ActivityLevel, { label: string; factor: number }> = {
  sedentary: { label: 'Sedentary', factor: 1.2 },
  light: { label: 'Lightly active', factor: 1.375 },
  moderate: { label: 'Moderately active', factor: 1.55 },
  very: { label: 'Very active', factor: 1.725 },
  extra: { label: 'Extra active', factor: 1.9 },
}

export const GOALS: Record<Goal, { label: string; kcalDelta: number }> = {
  recomp: { label: 'Lean recomp', kcalDelta: -300 },
  maintain: { label: 'Maintain', kcalDelta: 0 },
  bulk: { label: 'Lean bulk', kcalDelta: 200 },
}

export interface Targets {
  bmrMifflin: number
  bmrKatch: number
  tdee: number
  kcal: number
  protein_g: number
  fat_g: number
  carbs_g: number
  water_l: number
}

export interface TargetMeal extends Meal {
  /* True when the displayed foods were rebuilt from the active calorie target. */
  portioned: boolean
}

/* TDEE builds on Katch-McArdle since body fat is known. Protein 2.2 g/kg. */
export function computeTargets(p: Profile): Targets {
  const katch = bmrKatch(p)
  const tdee = Math.round(katch * ACTIVITY_MULTIPLIERS[p.activity_level].factor)
  const kcal = tdee + GOALS[p.goal].kcalDelta
  const protein = Math.round(2.2 * p.weight_kg)
  const fat = Math.round(0.9 * p.weight_kg)
  const carbs = Math.max(0, Math.round((kcal - protein * 4 - fat * 9) / 4))
  return {
    bmrMifflin: bmrMifflin(p),
    bmrKatch: katch,
    tdee,
    kcal,
    protein_g: protein,
    fat_g: fat,
    carbs_g: carbs,
    water_l: 2.75,
  }
}

/* The original food brief totals 2,670 kcal. It remains the recipe reference,
   while the rendered portions and meal-level macro budget follow the live
   target. Keeping this derived avoids rewriting the user's Supabase meal rows
   every time an activity button is pressed. */
const REFERENCE_MEAL_KCAL = 2670

function stepped(base: number, scale: number, step: number, minimum = step): number {
  return Math.max(minimum, Math.round((base * scale) / step) * step)
}

function allocate(total: number, weights: number[]): number[] {
  const weightTotal = weights.reduce((sum, value) => sum + Math.max(0, value), 0)
  if (weights.length === 0) return []
  if (weightTotal === 0) {
    const even = Math.floor(total / weights.length)
    return weights.map((_, index) => even + (index < total - even * weights.length ? 1 : 0))
  }

  const exact = weights.map((weight) => (total * Math.max(0, weight)) / weightTotal)
  const result = exact.map(Math.floor)
  let left = total - result.reduce((sum, value) => sum + value, 0)
  const byRemainder = exact
    .map((value, index) => ({ index, remainder: value - Math.floor(value) }))
    .sort((a, b) => b.remainder - a.remainder)
  for (let i = 0; i < left; i += 1) result[byRemainder[i % byRemainder.length].index] += 1
  return result
}

function scaleQuantities(text: string, scale: number): string {
  return text.replace(/(\d+(?:\.\d+)?)\s*(g|ml|eggs?)/gi, (_match, amount: string, unit: string) => {
    const value = Number(amount)
    if (/egg/i.test(unit)) return `${Math.max(1, Math.round(value * scale))} eggs`
    const scaled = stepped(value, scale, 5)
    return `${scaled} ${unit.toLowerCase()}`
  })
}

function portionedFoods(meal: Meal, scale: number): string {
  const key = meal.name.trim().toLowerCase()
  if (key === 'breakfast') {
    return `${Math.max(2, Math.round(4 * scale))} eggs + ${stepped(35, scale, 5, 15)} g nut mix. Zero-starch, protein-first morning.`
  }
  if (key === 'oat jar') {
    return [
      `${stepped(80, scale, 5, 35)} g oats`,
      `${stepped(200, scale, 25, 100)} ml milk`,
      `${stepped(100, scale, 10, 50)} g berries`,
      `${stepped(100, scale, 10, 50)} g banana`,
      `${stepped(75, scale, 10, 40)} g kiwi`,
      `${stepped(200, scale, 25, 100)} g magerquark or chicken hearts`,
      `${stepped(15, scale, 5, 5)} g seed mix`,
      `${stepped(5, scale, 5, 5)} g EVOO`,
    ].join(' + ')
  }
  if (key === 'bulgur snack') {
    return `${stepped(70, scale, 5, 35)} g dry bulgur + ${stepped(200, scale, 25, 100)} g cottage cheese + ${stepped(200, scale, 25, 100)} g vegetables. Full days only.`
  }
  if (key === 'dinner') {
    return `${stepped(300, scale, 25, 150)} g sweet potato + ${stepped(200, scale, 25, 100)} g pollock or chicken + ${stepped(100, scale, 10, 40)} g avocado + ${stepped(200, scale, 25, 100)} g vegetables.`
  }
  if (key === 'casein shake') {
    return `Casein isolate ${stepped(45, scale, 5, 25)} g in water.`
  }
  return scaleQuantities(meal.foods, scale)
}

/* Builds a complete target-aligned timeline. Integer allocation uses largest
   remainders, so every meal card adds back up to the exact targets shown at
   the top even after rounding. */
export function buildTargetMealPlan(meals: Meal[], targets: Targets): TargetMeal[] {
  if (meals.length === 0) return []
  const scale = Math.min(1.35, Math.max(0.5, targets.kcal / REFERENCE_MEAL_KCAL))
  const kcal = allocate(targets.kcal, meals.map((meal) => meal.kcal))
  const protein = allocate(targets.protein_g, meals.map((meal) => meal.protein_g))
  const fat = allocate(targets.fat_g, meals.map((meal) => meal.fat_g))
  const carbs = allocate(targets.carbs_g, meals.map((meal) => meal.carbs_g))

  return meals.map((meal, index) => ({
    ...meal,
    foods: portionedFoods(meal, scale),
    kcal: kcal[index],
    protein_g: protein[index],
    fat_g: fat[index],
    carbs_g: carbs[index],
    portioned: true,
  }))
}
