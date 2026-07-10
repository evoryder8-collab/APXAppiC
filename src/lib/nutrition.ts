import { differenceInYears } from 'date-fns'
import type { ActivityLevel, Goal, Profile } from './types'

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
