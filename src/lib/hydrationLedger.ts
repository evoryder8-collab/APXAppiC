export const HYDRATION_KINDS = [
  'water', 'coffee', 'tea', 'juice', 'shake', 'other', 'food', 'external', 'legacy',
] as const

export type HydrationKind = typeof HYDRATION_KINDS[number]
export type HydrationSource = 'iphone' | 'watch' | 'web' | 'food' | 'healthkit_external' | 'legacy'

export interface HydrationEvent {
  id: string
  user_id: string
  client_idempotency_key: string
  local_date: string
  occurred_at: string
  amount_ml: number
  kind: HydrationKind
  palette_token: string
  icon_token: string
  source: HydrationSource
  healthkit_sample_id: string | null
  created_at: string
  updated_at: string
}

export interface HydrationPresetTemplate {
  id: string
  name: string
  amount_ml: number
  kind: Exclude<HydrationKind, 'food' | 'external' | 'legacy'>
  palette_token: string
  icon_token: string
  sort_order: number
  enabled: boolean
}

export interface HydrationPreset extends HydrationPresetTemplate {
  user_id: string
  created_at: string
  updated_at: string
}

export interface HydrationPreferences {
  user_id: string
  target_ml: number
  target_mode?: 'automatic' | 'custom' | null
  display_unit: 'liters' | 'gallons'
  reminders_enabled: boolean
  reminder_interval_minutes: 60 | 90 | 120
  quiet_hours_start_minutes: number
  quiet_hours_end_minutes: number
  shows_preset_names: boolean
  confirmation_haptics: boolean
  motion_intensity: 'off' | 'subtle' | 'full'
  created_at: string
  updated_at: string
}

export interface HydrationCompositionBand {
  kind: HydrationKind
  paletteToken: string
  iconToken: string
  milliliters: number
}

export interface HydrationDayResolution {
  drinkML: number
  foodML: number
  totalML: number
  composition: HydrationCompositionBand[]
  usesLegacyAggregate: boolean
}

export const DEFAULT_HYDRATION_PRESETS: readonly HydrationPresetTemplate[] = [
  { id: '00000000-0000-4000-8000-000000000251', name: 'Glass', amount_ml: 250, kind: 'water', palette_token: 'aqua', icon_token: 'drop.fill', sort_order: 0, enabled: true },
  { id: '00000000-0000-4000-8000-000000000500', name: 'Bottle', amount_ml: 500, kind: 'water', palette_token: 'blue', icon_token: 'waterbottle.fill', sort_order: 1, enabled: true },
  { id: '00000000-0000-4000-8000-000000000190', name: 'Coffee', amount_ml: 190, kind: 'coffee', palette_token: 'espresso', icon_token: 'cup.and.saucer.fill', sort_order: 2, enabled: true },
  { id: '00000000-0000-4000-8000-000000000252', name: 'Tea', amount_ml: 250, kind: 'tea', palette_token: 'tea', icon_token: 'mug.fill', sort_order: 3, enabled: true },
  { id: '00000000-0000-4000-8000-000000000253', name: 'Juice', amount_ml: 250, kind: 'juice', palette_token: 'citrus', icon_token: 'takeoutbag.and.cup.and.straw.fill', sort_order: 4, enabled: true },
  { id: '00000000-0000-4000-8000-000000000350', name: 'Shake', amount_ml: 350, kind: 'shake', palette_token: 'cocoa', icon_token: 'waterbottle.fill', sort_order: 5, enabled: true },
] as const

const roundedML = (value: number): number => Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0

function eventKey(event: HydrationEvent): string {
  return `${event.user_id}\u0000${event.client_idempotency_key}`
}

export function mergeHydrationEvents(
  current: readonly HydrationEvent[],
  incoming: readonly HydrationEvent[],
): HydrationEvent[] {
  const byKey = new Map<string, HydrationEvent>()
  for (const candidate of [...current, ...incoming]) {
    const key = eventKey(candidate)
    const existing = byKey.get(key)
    if (!existing || candidate.updated_at >= existing.updated_at) byKey.set(key, candidate)
  }
  return [...byKey.values()].sort((a, b) => b.occurred_at.localeCompare(a.occurred_at))
}

export function resolveHydrationDay(input: {
  ownerID: string
  date: string
  events: readonly HydrationEvent[]
  legacyDrinkLiters: number
}): HydrationDayResolution {
  const facts = mergeHydrationEvents([], input.events).filter(
    (event) => event.user_id === input.ownerID && event.local_date === input.date && event.amount_ml > 0,
  )
  const hasDrinkFacts = facts.some((event) => event.kind !== 'food')
  const legacyML = hasDrinkFacts ? 0 : roundedML(input.legacyDrinkLiters * 1_000)
  const factsWithLegacy: Array<Pick<HydrationEvent, 'kind' | 'palette_token' | 'icon_token' | 'amount_ml'>> = [
    ...facts,
    ...(legacyML > 0 ? [{ kind: 'legacy' as const, palette_token: 'legacy', icon_token: 'drop.circle', amount_ml: legacyML }] : []),
  ]

  const bands = new Map<string, HydrationCompositionBand>()
  for (const fact of factsWithLegacy) {
    const key = `${fact.kind}\u0000${fact.palette_token}\u0000${fact.icon_token}`
    const existing = bands.get(key)
    const milliliters = roundedML(fact.amount_ml)
    if (milliliters === 0) continue
    bands.set(key, {
      kind: fact.kind,
      paletteToken: fact.palette_token,
      iconToken: fact.icon_token,
      milliliters: (existing?.milliliters ?? 0) + milliliters,
    })
  }

  const displayOrder: Record<HydrationKind, number> = {
    water: 0, coffee: 1, tea: 2, juice: 3, shake: 4, other: 5,
    external: 6, food: 7, legacy: 8,
  }
  const composition = [...bands.values()].sort((a, b) => displayOrder[a.kind] - displayOrder[b.kind])
  const foodML = composition.filter((band) => band.kind === 'food').reduce((sum, band) => sum + band.milliliters, 0)
  const drinkML = composition.filter((band) => band.kind !== 'food').reduce((sum, band) => sum + band.milliliters, 0)
  return {
    drinkML,
    foodML,
    totalML: drinkML + foodML,
    composition,
    usesLegacyAggregate: legacyML > 0,
  }
}
