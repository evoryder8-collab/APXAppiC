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

export const GOALS: Record<Goal, { label: string; factor: number }> = {
  recomp: { label: 'Lean recomp', factor: 0.89 },
  maintain: { label: 'Maintain', factor: 1 },
  bulk: { label: 'Lean bulk', factor: 1.07 },
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
  bmrSource: 'custom' | 'katch' | 'mifflin'
  activeBmr: number
}

export interface TargetMeal extends Meal {
  /* True when the displayed foods were rebuilt from the active calorie target. */
  portioned: boolean
  portionNote: string
}

const PROTEIN_G_PER_KG: Record<ActivityLevel, number> = {
  sedentary: 1.6,
  light: 1.75,
  moderate: 1.9,
  very: 2,
  extra: 2.1,
}

const GOAL_PROTEIN_ADJUSTMENT: Record<Goal, number> = {
  recomp: 0.2,
  maintain: 0,
  bulk: -0.1,
}

const FAT_ENERGY_SHARE: Record<Goal, number> = {
  recomp: 0.25,
  maintain: 0.275,
  bulk: 0.28,
}

const FAT_FLOOR_G_PER_KG: Record<Goal, number> = {
  recomp: 0.7,
  maintain: 0.8,
  bulk: 0.8,
}

export interface MacroTargets {
  protein_g: number
  fat_g: number
  carbs_g: number
  protein_g_per_kg: number
  fat_energy_share: number
}

/* APEX protects protein inside the athlete-supported range, keeps fat near the
   middle of the adult AMDR with a body-weight floor, then assigns the remaining
   energy to carbohydrate. Activity and goal therefore update all three targets
   instead of leaving protein and fat frozen while only carbohydrate moves. */
export function computeMacroTargets(
  weightKg: number,
  activityLevel: ActivityLevel,
  goal: Goal,
  targetKcal: number,
): MacroTargets {
  const proteinGPerKg = Math.min(2.4, Math.max(1.6, PROTEIN_G_PER_KG[activityLevel] + GOAL_PROTEIN_ADJUSTMENT[goal]))
  const proteinG = Math.round(weightKg * proteinGPerKg)
  const fatEnergyShare = FAT_ENERGY_SHARE[goal]
  const fatFromEnergy = targetKcal * fatEnergyShare / 9
  const fatFloor = weightKg * FAT_FLOOR_G_PER_KG[goal]
  const fatG = Math.round(Math.max(fatFloor, fatFromEnergy))
  const carbsG = Math.max(0, Math.round((targetKcal - proteinG * 4 - fatG * 9) / 4))
  return {
    protein_g: proteinG,
    fat_g: fatG,
    carbs_g: carbsG,
    protein_g_per_kg: Math.round(proteinGPerKg * 100) / 100,
    fat_energy_share: fatEnergyShare,
  }
}

/* TDEE builds on Katch-McArdle when a credible body-fat value is available. */
export function computeTargets(p: Profile): Targets {
  const katch = bmrKatch(p)
  const mifflin = bmrMifflin(p)
  const hasBodyFat = Number.isFinite(p.body_fat_pct) && p.body_fat_pct > 0 && p.body_fat_pct < 75
  const hasCustomBmr = p.custom_bmr != null && Number.isFinite(p.custom_bmr) && p.custom_bmr >= 800 && p.custom_bmr <= 4000
  const activeBmr = hasCustomBmr ? Math.round(p.custom_bmr!) : hasBodyFat ? katch : mifflin
  const tdee = Math.round(activeBmr * ACTIVITY_MULTIPLIERS[p.activity_level].factor)
  const formulaTarget = Math.max(activeBmr * 1.05, tdee * GOALS[p.goal].factor)
  const kcal = Math.round(formulaTarget)
  const macros = computeMacroTargets(p.weight_kg, p.activity_level, p.goal, kcal)
  return {
    bmrMifflin: mifflin,
    bmrKatch: katch,
    tdee,
    kcal,
    protein_g: macros.protein_g,
    fat_g: macros.fat_g,
    carbs_g: macros.carbs_g,
    water_l: 2.75,
    bmrSource: hasCustomBmr ? 'custom' : hasBodyFat ? 'katch' : 'mifflin',
    activeBmr,
  }
}

/* The original food brief totals 2,670 kcal. It remains the recipe reference,
   while the rendered portions and meal-level macro budget follow the live
   target. Keeping this derived avoids rewriting the user's Supabase meal rows
   every time an activity button is pressed. */
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

interface PortionScales {
  energy: number
  protein: number
  fat: number
  carbs: number
}

function portionedFoods(meal: Meal, scales: PortionScales): string {
  const key = meal.name.trim().toLowerCase()
  if (key === 'breakfast' && /nut mix/i.test(meal.foods)) {
    return `${Math.max(2, Math.round(4 * scales.protein))} eggs + ${stepped(35, scales.fat, 5, 15)} g nut mix. Zero-starch, protein-first morning.`
  }
  if (key === 'oat jar') {
    return [
      `${stepped(80, scales.carbs, 5, 35)} g oats`,
      `${stepped(200, scales.carbs, 25, 100)} ml milk`,
      `${stepped(100, scales.carbs, 10, 50)} g berries`,
      `${stepped(100, scales.carbs, 10, 50)} g banana`,
      `${stepped(75, scales.carbs, 10, 40)} g kiwi`,
      `${stepped(200, scales.protein, 25, 100)} g magerquark or chicken hearts`,
      `${stepped(15, scales.fat, 5, 5)} g seed mix`,
      `${stepped(5, scales.fat, 5, 5)} g EVOO`,
    ].join(' + ')
  }
  if (key === 'bulgur snack') {
    return `${stepped(70, scales.carbs, 5, 35)} g dry bulgur + ${stepped(200, scales.protein, 25, 100)} g cottage cheese + ${stepped(200, scales.carbs, 25, 100)} g vegetables. Full days only.`
  }
  if (key === 'dinner') {
    return `${stepped(300, scales.carbs, 25, 150)} g sweet potato + ${stepped(200, scales.protein, 25, 100)} g pollock or chicken + ${stepped(100, scales.fat, 10, 40)} g avocado + ${stepped(200, scales.carbs, 25, 100)} g vegetables.`
  }
  if (key === 'casein shake') {
    return `Casein isolate ${stepped(45, scales.protein, 5, 25)} g in water.`
  }
  return scaleQuantities(meal.foods, scales.energy)
}

function portionNote(meal: Meal, scales: PortionScales, dayLabel: string): string {
  const key = meal.name.trim().toLowerCase()
  if (key === 'oat jar') return `${dayLabel} day: oats ${stepped(80, scales.carbs, 5, 35)} g instead of 80 g.`
  if (key === 'bulgur snack') return `${dayLabel} day: dry bulgur ${stepped(70, scales.carbs, 5, 35)} g instead of 70 g.`
  if (key === 'dinner') return `${dayLabel} day: sweet potato ${stepped(300, scales.carbs, 25, 150)} g instead of 300 g.`
  if (key === 'breakfast' && /nut mix/i.test(meal.foods)) return `${dayLabel} day: protein stays pinned; nut mix adjusts to ${stepped(35, scales.fat, 5, 15)} g.`
  if (key === 'casein shake') return `${dayLabel} day: casein remains protein-led at ${stepped(45, scales.protein, 5, 25)} g.`
  return `${dayLabel} day: carbohydrate portions move first; protein moves last.`
}

/* Builds a complete target-aligned timeline. Integer allocation uses largest
   remainders, so every meal card adds back up to the exact targets shown at
   the top even after rounding. */
export function buildTargetMealPlan(meals: Meal[], targets: Targets, dayLabel = 'Adaptive'): TargetMeal[] {
  if (meals.length === 0) return []
  const referenceKcal = meals.reduce((sum, meal) => sum + meal.kcal, 0) || targets.kcal
  const referenceProtein = meals.reduce((sum, meal) => sum + meal.protein_g, 0) || targets.protein_g
  const referenceFat = meals.reduce((sum, meal) => sum + meal.fat_g, 0) || targets.fat_g
  const referenceCarbs = meals.reduce((sum, meal) => sum + meal.carbs_g, 0) || targets.carbs_g
  const scales: PortionScales = {
    energy: Math.min(1.35, Math.max(0.5, targets.kcal / referenceKcal)),
    protein: Math.min(1.25, Math.max(0.65, targets.protein_g / referenceProtein)),
    fat: Math.min(1.4, Math.max(0.45, targets.fat_g / referenceFat)),
    carbs: Math.min(1.6, Math.max(0.4, targets.carbs_g / referenceCarbs)),
  }
  const kcal = allocate(targets.kcal, meals.map((meal) => meal.kcal))
  const protein = allocate(targets.protein_g, meals.map((meal) => meal.protein_g))
  const fat = allocate(targets.fat_g, meals.map((meal) => meal.fat_g))
  const carbs = allocate(targets.carbs_g, meals.map((meal) => meal.carbs_g))

  return meals.map((meal, index) => ({
    ...meal,
    foods: portionedFoods(meal, scales),
    kcal: kcal[index],
    protein_g: protein[index],
    fat_g: fat[index],
    carbs_g: carbs[index],
    portioned: true,
    portionNote: portionNote(meal, scales, dayLabel),
  }))
}
