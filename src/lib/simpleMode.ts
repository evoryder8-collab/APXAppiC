import type { PersonaSlug } from './persona.ts'
import type { Goal, ProgramSlug, Settings } from './types.ts'

export type UiMode = 'simple' | 'advanced'
export type WeightUnit = 'kg' | 'lb'
export type SimpleMacroKey = 'protein_g' | 'carbs_g' | 'fat_g'

export interface SimpleMacroEntry {
  snapshot_name: string
  protein_g: number
  carbs_g: number
  fat_g: number
}

export interface SimpleMacroContributor {
  name: string
  amount: number
}

export interface SimpleDailyProgressInput {
  completedMeals: number
  totalMeals: number
  consumed: { kcal: number; protein_g: number; carbs_g: number; fat_g: number }
  target: { kcal: number; protein_g: number; carbs_g: number; fat_g: number }
  waterLitres: number
  waterTargetLitres: number
  workoutScheduled: boolean
  workoutCompleted: boolean
  activityProgress: number
  supplements: Array<{ name: string; taken: boolean }>
  goal: Goal
}

export function uiModeFromSettings(settings: Settings | null): UiMode {
  return settings?.addons.uiMode === 'advanced' ? 'advanced' : 'simple'
}

export function settingsForUiMode(settings: Settings, uiMode: UiMode): Pick<Settings, 'addons'> {
  return { addons: { ...settings.addons, uiMode } }
}

export function planBriefingExit(settings: Settings): { path: '/'; settings: Pick<Settings, 'addons'> } {
  return {
    path: '/',
    settings: settingsForUiMode(settings, 'simple'),
  }
}

export function simpleGuidedProgramSlug(
  persona: PersonaSlug | null | undefined,
  mainIsUsable: boolean,
  transitionIsUsable: boolean,
): ProgramSlug {
  const bespokeMain = persona === 'constantine' || persona === 'june'
  if (bespokeMain && mainIsUsable) return 'main'
  if (transitionIsUsable) return 'transition'
  if (mainIsUsable) return 'main'
  return bespokeMain ? 'main' : 'transition'
}

export function weightUnitFromSettings(settings: Settings | null): WeightUnit {
  return settings?.addons.weight_unit === 'lb' ? 'lb' : 'kg'
}

export function weightFromKg(weightKg: number, unit: WeightUnit): number {
  return unit === 'lb' ? weightKg * 2.2046226218 : weightKg
}

export function weightToKg(weight: number, unit: WeightUnit): number {
  return unit === 'lb' ? weight / 2.2046226218 : weight
}

/* Custom hydration accepts the way people naturally type it: `750`,
   `750 ml`, `.75 l`, or a decimal comma. A unit-less amount above 10 is
   treated as millilitres; smaller values are litres. */
export function parseWaterAmountToLitres(value: string): number | null {
  const normalized = value.trim().toLocaleLowerCase('en').replace(',', '.')
  const match = normalized.match(/^(\d*\.?\d+)\s*(ml|millilit(?:er|re)s?|l|lit(?:er|re)s?)?$/)
  if (!match) return null
  const amount = Number(match[1])
  if (!Number.isFinite(amount) || amount <= 0) return null
  const unit = match[2]
  const litres = unit?.startsWith('m') || (!unit && amount > 10) ? amount / 1000 : amount
  return litres > 0 && litres <= 6 ? Math.round(litres * 1000) / 1000 : null
}

export interface TimedSimpleAction {
  time: number
}

export interface SimpleSwipePoint {
  x: number
  y: number
}

const DAY_SWIPE_INTERACTIVE_SELECTOR = [
  'button',
  'a',
  'input',
  'textarea',
  'select',
  'option',
  'label',
  'summary',
  '[role="button"]',
  '[role="slider"]',
  '[contenteditable]:not([contenteditable="false"])',
  '[data-day-swipe-ignore]',
  '[data-simple-local-gesture]',
  '[data-nutrition-local-gesture]',
].join(', ')

export function isDaySwipeInteractiveTarget(target: EventTarget | null): boolean {
  if (typeof Element === 'undefined' || !(target instanceof Element)) return false
  return Boolean(target.closest(DAY_SWIPE_INTERACTIVE_SELECTOR))
}

export function canStartDaySwipe(activeTouchCount: number, interactiveTarget: boolean): boolean {
  return activeTouchCount === 1 && !interactiveTarget
}

export function daySwipeHasSingleTrackedTouch(activeTouchIds: readonly number[], trackedTouchId: number): boolean {
  return activeTouchIds.length === 1 && activeTouchIds[0] === trackedTouchId
}

export function canFinishDaySwipe(
  remainingTouchCount: number,
  changedTouchIds: readonly number[],
  trackedTouchId: number,
): boolean {
  return remainingTouchCount === 0 && changedTouchIds.length === 1 && changedTouchIds[0] === trackedTouchId
}

export function floatingActiveDateVisible(scrollY: number, revealAfter = 220): boolean {
  return Number.isFinite(scrollY) && scrollY > Math.max(0, revealAfter)
}

/* Horizontal gestures that begin inside a component-owned gesture zone must
   never escape into Simple Mode's day navigation. */
export function simpleDaySwipeOffset(
  start: SimpleSwipePoint,
  end: SimpleSwipePoint,
  blockedByLocalGesture = false,
): -1 | 0 | 1 {
  if (blockedByLocalGesture) return 0
  const dx = end.x - start.x
  const dy = end.y - start.y
  if (Math.abs(dx) < 55 || Math.abs(dx) < Math.abs(dy) * 1.35) return 0
  return dx < 0 ? 1 : -1
}

/* Prefer the most recently due unfinished action. If nothing is due yet,
   surface the earliest upcoming action. This avoids nagging users about a
   05:30 item at dinner while still keeping the next decision obvious. */
export function selectNextSimpleAction<T extends TimedSimpleAction>(candidates: T[], nowMinutes: number): T | null {
  const ordered = [...candidates].sort((a, b) => a.time - b.time)
  const due = ordered.filter((candidate) => candidate.time <= nowMinutes)
  return due.at(-1) ?? ordered[0] ?? null
}

export function simpleCompletion(completed: number, total: number): number {
  if (total <= 0) return 100
  return Math.max(0, Math.min(100, Math.round((completed / total) * 100)))
}

function boundedRatio(value: number, target: number): number | null {
  if (!Number.isFinite(target) || target <= 0) return null
  const resolved = Number.isFinite(value) ? value : 0
  return Math.max(0, Math.min(1, resolved / target))
}

export function isPrimaryDailySupplement(name: string): boolean {
  const normalized = name.normalize('NFKD').replace(/\p{Diacritic}/gu, '').toLocaleLowerCase('en')
  return [
    'creatin', 'kreatin', 'protein', 'whey', 'casein', 'cazein', 'eiweiss',
    'โปรตีน', 'ครีเอทีน', 'プロテイン', 'クレアチン',
  ].some((token) => normalized.includes(token))
}

export function simpleActivityProgress(
  persona: PersonaSlug,
  goal: Goal,
  steps: number,
  activeCalories: number,
  exerciseMinutes: number,
): number {
  const isJune = persona === 'june'
  const moderateTarget = goal === 'recomp'
  const stepTarget = moderateTarget ? (isJune ? 7_000 : 7_500) : 4_000
  const calorieTarget = moderateTarget ? (isJune ? 350 : 500) : (isJune ? 180 : 250)
  const exerciseTarget = moderateTarget ? 25 : 10
  return Math.max(
    boundedRatio(steps, stepTarget) ?? 0,
    boundedRatio(activeCalories, calorieTarget) ?? 0,
    boundedRatio(exerciseMinutes, exerciseTarget) ?? 0,
  )
}

export function simpleDailyProgress(input: SimpleDailyProgressInput): number {
  const pillars: Array<{ progress: number; weight: number }> = []
  const meals = boundedRatio(input.completedMeals, input.totalMeals)
  if (meals != null) pillars.push({ progress: meals, weight: 1 })

  const nutritionParts = [
    boundedRatio(input.consumed.kcal, input.target.kcal),
    boundedRatio(input.consumed.protein_g, input.target.protein_g),
    boundedRatio(input.consumed.carbs_g, input.target.carbs_g),
    boundedRatio(input.consumed.fat_g, input.target.fat_g),
  ].filter((part): part is number => part != null)
  if (nutritionParts.length > 0) {
    pillars.push({
      progress: nutritionParts.reduce((sum, part) => sum + part, 0) / nutritionParts.length,
      weight: 1,
    })
  }

  const water = boundedRatio(input.waterLitres, input.waterTargetLitres * 0.9)
  if (water != null) pillars.push({ progress: water, weight: 1 })
  if (input.workoutScheduled) {
    pillars.push({ progress: input.workoutCompleted ? 1 : 0, weight: 1 })
  }
  pillars.push({
    progress: Math.max(0, Math.min(1, input.activityProgress)),
    weight: input.goal === 'recomp' ? 2 : 1,
  })

  const primarySupplements = input.supplements.filter((supplement) => isPrimaryDailySupplement(supplement.name))
  if (primarySupplements.length > 0) {
    pillars.push({
      progress: primarySupplements.filter((supplement) => supplement.taken).length / primarySupplements.length,
      weight: 1,
    })
  }

  const totalWeight = pillars.reduce((sum, pillar) => sum + pillar.weight, 0)
  if (totalWeight <= 0) return 0
  const weightedProgress = pillars.reduce((sum, pillar) => sum + pillar.progress * pillar.weight, 0) / totalWeight
  return Math.max(0, Math.min(100, Math.round(weightedProgress * 100)))
}

export function simpleWaterTargetComplete(waterLitres: number, targetLitres: number): boolean {
  const target = Math.max(0, targetLitres)
  return target > 0 && Math.max(0, waterLitres) >= target * 0.9
}

/* The checklist is a binary promise, while the hydration action remains a
   250 ml stepper. Checking sets today's target once; unchecking clears it. */
export function toggleSimpleWaterTarget(waterLitres: number, targetLitres: number): number {
  if (simpleWaterTargetComplete(waterLitres, targetLitres)) return 0
  return Math.round(Math.max(0, targetLitres) * 100) / 100
}

/* A copied calendar day can be pasted anywhere except back onto itself. Keeping
   this rule pure makes the highlighted target state and the eventual action use
   exactly the same condition. */
export function canPasteSimpleDay(sourceDate: string | null, targetDate: string): boolean {
  return Boolean(sourceDate && /^\d{4}-\d{2}-\d{2}$/.test(sourceDate) && /^\d{4}-\d{2}-\d{2}$/.test(targetDate) && sourceDate !== targetDate)
}

/**
 * Both calendar surfaces copy the same structured meal history. A shared,
 * stable namespace keeps the operation idempotent when it is repeated from
 * the other interface.
 */
export function dayMealCopyIdempotencyKey(
  userId: string,
  sourceDate: string,
  targetDate: string,
  sourceMealId: string,
): string {
  return `simple-day-copy:${userId}:${sourceDate}:${targetDate}:${sourceMealId}`
}

/* Food rows are snapshots, so repeated foods can be safely combined without
   consulting a mutable food catalogue. The result is deliberately ranked by
   contribution to answer the useful question: what drove this macro today? */
export function rankSimpleMacroContributors(
  entries: SimpleMacroEntry[],
  macro: SimpleMacroKey,
  limit = 6,
): SimpleMacroContributor[] {
  const totals = new Map<string, number>()
  for (const entry of entries) {
    const name = entry.snapshot_name.trim()
    const amount = Number(entry[macro])
    if (!name || !Number.isFinite(amount) || amount <= 0) continue
    totals.set(name, (totals.get(name) ?? 0) + amount)
  }
  return [...totals.entries()]
    .map(([name, amount]) => ({ name, amount: Math.round(amount * 10) / 10 }))
    .sort((left, right) => right.amount - left.amount || left.name.localeCompare(right.name))
    .slice(0, Math.max(0, limit))
}
