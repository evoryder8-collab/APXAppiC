import type { Goal } from './types'
import type { PersonaSlug } from './persona'

export type MealMacroKind = 'protein' | 'carbs' | 'fat'
export type MealMacroState = 'below' | 'reached' | 'above' | 'high'

export interface MealMacroStatus {
  state: MealMacroState
  completion: number
  overBy: number
  upperGuide: number
}

function upperMultiplier(persona: PersonaSlug, goal: Goal, macro: MealMacroKind): number {
  if (persona === 'constantine' && goal === 'recomp') {
    return macro === 'protein' ? 1.4 : 1.15
  }
  if (persona === 'june' && goal === 'bulk') {
    return macro === 'protein' ? 1.55 : 1.4
  }
  if (goal === 'bulk') return macro === 'protein' ? 1.5 : 1.35
  if (goal === 'recomp') return macro === 'protein' ? 1.4 : 1.2
  return macro === 'protein' ? 1.45 : 1.25
}

/**
 * Meal targets are distribution guides, not medical ceilings. The warning
 * threshold therefore depends on the person's goal: Constantine's recomp
 * keeps carbohydrate/fat distribution tighter, while June's lean bulk allows
 * a deliberately wider meal-to-meal range.
 */
export function mealMacroStatus(
  value: number,
  target: number,
  macro: MealMacroKind,
  persona: PersonaSlug,
  goal: Goal,
): MealMacroStatus {
  const safeTarget = Math.max(1, target)
  const completion = Math.max(0, value / safeTarget)
  const overBy = Math.max(0, Math.round((value - safeTarget) * 10) / 10)
  const upperGuide = Math.round(safeTarget * upperMultiplier(persona, goal, macro))
  const state: MealMacroState = completion < 0.85
    ? 'below'
    : value <= safeTarget
      ? 'reached'
      : value <= upperGuide
        ? 'above'
        : 'high'
  return { state, completion, overBy, upperGuide }
}
