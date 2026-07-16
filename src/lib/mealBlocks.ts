import type { LoggedMeal, MealSlot } from './food'
import type { Meal } from './types'

export type MealBlockKind = 'breakfast' | 'lunch' | 'dinner' | 'snack' | 'post_workout'

export interface MealBlock {
  id: MealBlockKind
  kind: MealBlockKind
  time: string
  enabled: boolean
}

export interface MealBlockSettings {
  blocks: MealBlock[]
  preset_assignments: Record<string, MealBlockKind>
}

type PlannedMealReference = Pick<Meal, 'id' | 'name' | 'time'>

export interface MealBlockStatus<TMeal extends PlannedMealReference = Meal> {
  block: MealBlock
  completed: boolean
  loggedMeal: LoggedMeal | null
  plannedMeal: TMeal | null
}

export const DEFAULT_MEAL_BLOCKS: readonly MealBlock[] = [
  { id: 'breakfast', kind: 'breakfast', time: '07:00', enabled: true },
  { id: 'lunch', kind: 'lunch', time: '13:00', enabled: true },
  { id: 'dinner', kind: 'dinner', time: '19:00', enabled: true },
  { id: 'snack', kind: 'snack', time: '16:00', enabled: true },
  { id: 'post_workout', kind: 'post_workout', time: '21:00', enabled: true },
] as const

const BLOCK_IDS = new Set<MealBlockKind>(DEFAULT_MEAL_BLOCKS.map((block) => block.id))
const BLOCK_MARKER = 'apex-meal-block='

function validClock(value: unknown, fallback: string): string {
  if (typeof value !== 'string' || !/^\d{2}:\d{2}$/.test(value)) return fallback
  const [hours, minutes] = value.split(':').map(Number)
  return hours >= 0 && hours < 24 && minutes >= 0 && minutes < 60 ? value : fallback
}

export function normalizeMealBlockSettings(value: unknown): MealBlockSettings {
  const input = value && typeof value === 'object' ? value as Partial<MealBlockSettings> : {}
  const supplied = new Map(
    (Array.isArray(input.blocks) ? input.blocks : [])
      .filter((block): block is MealBlock => Boolean(block && BLOCK_IDS.has(block.id) && block.kind === block.id))
      .map((block) => [block.id, block]),
  )
  const blocks = DEFAULT_MEAL_BLOCKS.map((fallback) => {
    const block = supplied.get(fallback.id)
    return {
      ...fallback,
      time: validClock(block?.time, fallback.time),
      enabled: typeof block?.enabled === 'boolean' ? block.enabled : fallback.enabled,
    }
  })
  if (!blocks.some((block) => block.enabled)) blocks[0] = { ...blocks[0], enabled: true }

  const preset_assignments: Record<string, MealBlockKind> = {}
  if (input.preset_assignments && typeof input.preset_assignments === 'object') {
    for (const [presetId, blockId] of Object.entries(input.preset_assignments)) {
      if (presetId && BLOCK_IDS.has(blockId as MealBlockKind)) preset_assignments[presetId] = blockId as MealBlockKind
    }
  }
  return { blocks, preset_assignments }
}

export function mealBlockLabel(kind: MealBlockKind): string {
  if (kind === 'post_workout') return 'Post-workout'
  return `${kind[0].toUpperCase()}${kind.slice(1)}`
}

export function mealSlotForBlock(kind: MealBlockKind): MealSlot {
  return kind === 'post_workout' ? 'snack' : kind
}

export function mealBlockIdempotencyKey(base: string, blockId: MealBlockKind | null | undefined): string {
  if (!blockId) return base
  return `${base}|${BLOCK_MARKER}${blockId}`
}

export function mealBlockIdFromIdempotencyKey(value: string): MealBlockKind | null {
  const marker = value.lastIndexOf(BLOCK_MARKER)
  if (marker < 0) return null
  const blockId = value.slice(marker + BLOCK_MARKER.length).split('|')[0] as MealBlockKind
  return BLOCK_IDS.has(blockId) ? blockId : null
}

function minutes(clock: string): number {
  const [hours, mins] = clock.split(':').map(Number)
  return hours * 60 + mins
}

function plannedKind(meal: Pick<Meal, 'name' | 'time'>): MealBlockKind {
  const name = meal.name.toLocaleLowerCase()
  if (/post[ -]?workout|after training|recovery|după antrenament|หลังฝึก/.test(name)) return 'post_workout'
  if (/snack|gustare|shake/.test(name)) return 'snack'
  const hour = Number(meal.time.slice(0, 2))
  if (hour < 11) return 'breakfast'
  if (hour < 16) return 'lunch'
  return 'dinner'
}

function loggedKind(meal: LoggedMeal): MealBlockKind {
  const name = meal.display_name.toLocaleLowerCase()
  if (/post[ -]?workout|after training|recovery|după antrenament|หลังฝึก/.test(name)) return 'post_workout'
  return meal.meal_slot
}

function nearestAvailableBlock(
  blocks: MealBlock[],
  preferred: MealBlockKind,
  occupied: Set<MealBlockKind>,
  at?: string,
  allowSnackToPostWorkout = false,
): MealBlock | null {
  const candidates = blocks.filter((block) => !occupied.has(block.id) && (
    block.kind === preferred || (allowSnackToPostWorkout && preferred === 'snack' && block.kind === 'post_workout')
  ))
  if (!candidates.length) return null
  if (!at) return candidates[0]
  return candidates.slice().sort((left, right) => (
    Math.abs(minutes(left.time) - minutes(at)) - Math.abs(minutes(right.time) - minutes(at))
  ))[0]
}

/** Reconcile the durable food ledger with the user's configured meal blocks. */
export function resolveMealBlockStatuses<TMeal extends PlannedMealReference>(input: {
  settings: MealBlockSettings
  loggedMeals: LoggedMeal[]
  plannedMeals?: TMeal[]
  checkedPlannedMealIds?: ReadonlySet<string>
}): MealBlockStatus<TMeal>[] {
  const blocks = input.settings.blocks.filter((block) => block.enabled)
  const status = new Map<MealBlockKind, { loggedMeal: LoggedMeal | null; plannedMeal: TMeal | null; completed: boolean }>()
  const occupied = new Set<MealBlockKind>()
  for (const block of blocks) status.set(block.id, { loggedMeal: null, plannedMeal: null, completed: false })

  const plannedToBlock = new Map<string, MealBlockKind>()
  const plannedOccupied = new Set<MealBlockKind>()
  for (const meal of (input.plannedMeals ?? []).slice().sort((a, b) => a.time.localeCompare(b.time))) {
    const block = nearestAvailableBlock(blocks, plannedKind(meal), plannedOccupied, meal.time, true)
    if (!block) continue
    plannedOccupied.add(block.id)
    plannedToBlock.set(meal.id, block.id)
    const current = status.get(block.id)
    if (current) current.plannedMeal = meal
  }

  const pending = input.loggedMeals.slice().sort((a, b) => a.logged_at.localeCompare(b.logged_at))
  const assignedMealIds = new Set<string>()
  const assign = (meal: LoggedMeal, blockId: MealBlockKind | null): boolean => {
    if (!blockId || occupied.has(blockId)) return false
    const current = status.get(blockId)
    if (!current) return false
    current.loggedMeal = meal
    current.completed = true
    occupied.add(blockId)
    assignedMealIds.add(meal.id)
    return true
  }

  /* A structured planned-meal link is the strongest identity. It must win over
     stale preset or idempotency metadata so one logged meal can never complete
     two blocks after an edit or an old client migration. */
  for (const meal of pending) {
    assign(meal, meal.source_planned_meal_id ? plannedToBlock.get(meal.source_planned_meal_id) ?? null : null)
  }
  for (const meal of pending) {
    if (assignedMealIds.has(meal.id)) continue
    assign(meal, mealBlockIdFromIdempotencyKey(meal.client_idempotency_key))
  }
  for (const meal of pending) {
    if (assignedMealIds.has(meal.id)) continue
    assign(meal, meal.source_preset_id ? input.settings.preset_assignments[meal.source_preset_id] ?? null : null)
  }
  for (const meal of pending) {
    if (assignedMealIds.has(meal.id)) continue
    const block = nearestAvailableBlock(blocks, loggedKind(meal), occupied)
    assign(meal, block?.id ?? null)
  }

  for (const mealId of input.checkedPlannedMealIds ?? []) {
    const blockId = plannedToBlock.get(mealId)
    if (!blockId) continue
    const current = status.get(blockId)
    if (current) current.completed = true
  }

  return blocks.map((block) => ({ block, ...(status.get(block.id) ?? { loggedMeal: null, plannedMeal: null, completed: false }) }))
}
