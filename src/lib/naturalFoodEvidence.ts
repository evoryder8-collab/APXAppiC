import naturalFoodEvidenceJSON from '../../shared/natural-food-evidence.json' with { type: 'json' }
import type { FoodRecord } from './food.ts'
import type { NutrientEvidenceObservation } from './nutrientEvidence.ts'

export interface NaturalFoodEvidenceFingerprint {
  kcal_100: number
  protein_100: number
  carbs_100: number
  fat_100: number
}

export interface NaturalFoodEvidenceAlias {
  kind: 'target' | 'donor'
  id: string
  provider_product_id: string
  nutrition_basis: FoodRecord['nutrition_basis']
  preparation_state: FoodRecord['preparation_state']
  fingerprint: NaturalFoodEvidenceFingerprint
}

export interface NaturalFoodEvidenceEntry {
  aliases: NaturalFoodEvidenceAlias[]
  category: string
  donor: {
    id: string
    name: string
    source_key: string
    source_record_id: string
  }
  evidence: NutrientEvidenceObservation[]
  target: {
    id: string
    name: string
    provider_product_id: string
  }
}

export interface NaturalFoodEvidenceBundle {
  schema_version: 1
  sources: Array<Record<string, unknown> & { key: string }>
  targets: NaturalFoodEvidenceEntry[]
}

export const naturalFoodEvidenceBundle = naturalFoodEvidenceJSON as NaturalFoodEvidenceBundle

const fingerprintFields = [
  ['kcal_100', 1],
  ['protein_100', 0.05],
  ['carbs_100', 0.05],
  ['fat_100', 0.05],
] as const satisfies ReadonlyArray<readonly [keyof NaturalFoodEvidenceFingerprint, number]>

const maximumEvidenceRows = 96
const maximumEvidenceBytes = 65_536
const observationStatuses = new Set([
  'measured', 'calculated', 'estimated', 'reported', 'trace',
  'below_detection', 'not_measured', 'missing',
])

function nonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function validFingerprint(value: NaturalFoodEvidenceFingerprint | null | undefined): boolean {
  return fingerprintFields.every(([field]) => Number.isFinite(value?.[field]))
}

function validEvidenceEntry(entry: NaturalFoodEvidenceEntry): boolean {
  if (
    !entry
    || !Array.isArray(entry.aliases)
    || entry.aliases.length !== 2
    || !Array.isArray(entry.evidence)
    || entry.evidence.length === 0
    || entry.evidence.length > maximumEvidenceRows
    || !nonEmptyString(entry.category)
    || !nonEmptyString(entry.donor?.id)
    || !nonEmptyString(entry.donor?.name)
    || !nonEmptyString(entry.donor?.source_key)
    || !nonEmptyString(entry.donor?.source_record_id)
    || !nonEmptyString(entry.target?.id)
    || !nonEmptyString(entry.target?.name)
    || !nonEmptyString(entry.target?.provider_product_id)
  ) return false

  let evidenceBytes: number
  try {
    evidenceBytes = new TextEncoder().encode(JSON.stringify(entry.evidence)).byteLength
  } catch {
    return false
  }
  if (evidenceBytes > maximumEvidenceBytes) return false

  const aliasKinds = new Set(entry.aliases.map((alias) => alias?.kind))
  if (aliasKinds.size !== 2 || !aliasKinds.has('target') || !aliasKinds.has('donor')) return false
  if (!entry.aliases.every((alias) => (
    nonEmptyString(alias?.id)
    && nonEmptyString(alias?.provider_product_id)
    && nonEmptyString(alias?.nutrition_basis)
    && nonEmptyString(alias?.preparation_state)
    && validFingerprint(alias?.fingerprint)
  ))) return false

  const targetAlias = entry.aliases.find((alias) => alias.kind === 'target')
  const donorAlias = entry.aliases.find((alias) => alias.kind === 'donor')
  if (
    targetAlias?.id !== entry.target.id
    || targetAlias?.provider_product_id !== entry.target.provider_product_id
    || donorAlias?.id !== entry.donor.id
    || donorAlias?.provider_product_id !== `corpus:${entry.donor.source_key}:${entry.donor.source_record_id}`
  ) return false

  return entry.evidence.every((observation) => (
    nonEmptyString(observation?.nutrient_code)
    && nonEmptyString(observation?.name)
    && nonEmptyString(observation?.unit)
    && typeof observation?.original_value_text === 'string'
    && observationStatuses.has(observation?.observation_status)
    && (observation?.value_per_100 === null || Number.isFinite(observation?.value_per_100))
    && observation?.source_key === entry.donor.source_key
    && nonEmptyString(observation?.source_reference)
  ))
}

function aliasKey(id: string, providerProductID: string): string {
  return `${id}\u0000${providerProductID}`
}

function buildAliasIndex(bundle: NaturalFoodEvidenceBundle): Map<string, NaturalFoodEvidenceEntry[]> {
  const index = new Map<string, NaturalFoodEvidenceEntry[]>()
  if (bundle.schema_version !== 1 || !Array.isArray(bundle.targets)) return index
  for (const entry of bundle.targets) {
    if (!validEvidenceEntry(entry)) continue
    for (const alias of entry.aliases) {
      if (!alias.id?.trim() || !alias.provider_product_id?.trim()) continue
      const key = aliasKey(alias.id, alias.provider_product_id)
      index.set(key, [...(index.get(key) ?? []), entry])
    }
  }
  return index
}

const canonicalAliasIndex = buildAliasIndex(naturalFoodEvidenceBundle)

function matchingAlias(food: FoodRecord, entry: NaturalFoodEvidenceEntry): NaturalFoodEvidenceAlias | null {
  const providerProductID = food.provider_product_id
  if (
    !food.id.trim()
    || providerProductID == null
    || !providerProductID.trim()
    || food.owner_user_id !== null
    || food.brand !== null
    || food.barcode !== null
    || food.source !== 'apex_cache'
  ) return null
  const aliases = entry.aliases.filter((alias) => (
    alias.id === food.id
    && alias.provider_product_id === providerProductID
    && alias.nutrition_basis === food.nutrition_basis
    && alias.preparation_state === food.preparation_state
  ))
  if (aliases.length !== 1) return null
  const alias = aliases[0]
  const fingerprintMatches = fingerprintFields.every(([field, absoluteTolerance]) => {
    const actual = food[field]
    const reviewed = alias.fingerprint[field]
    return typeof actual === 'number'
      && Number.isFinite(actual)
      && Number.isFinite(reviewed)
      && Math.abs(actual - reviewed) <= Math.max(absoluteTolerance, Math.abs(reviewed) * 0.02)
  })
  return fingerprintMatches ? alias : null
}

/**
 * Applies a checksum-generated whole official evidence record to either exact
 * reviewed alias. Names never authorize a match, and an explicit target array
 * always wins without donor gap-filling.
 */
export function overlayNaturalFoodEvidence(
  foods: FoodRecord[],
  bundle: NaturalFoodEvidenceBundle = naturalFoodEvidenceBundle,
): FoodRecord[] {
  const index = bundle === naturalFoodEvidenceBundle ? canonicalAliasIndex : buildAliasIndex(bundle)
  return foods.map((food) => {
    if ((food.nutrient_evidence?.length ?? 0) > 0) return food
    const providerProductID = food.provider_product_id
    if (!food.id.trim() || providerProductID == null || !providerProductID.trim()) return food
    const candidates = index.get(aliasKey(food.id, providerProductID)) ?? []
    if (candidates.length !== 1 || !matchingAlias(food, candidates[0])) return food
    return {
      ...food,
      nutrient_evidence: candidates[0].evidence.map((observation) => ({ ...observation })),
    }
  })
}
