export type FitnessEvidenceAdmission = 'trusted' | 'user'
export type FitnessEvidenceConfidence = 'low' | 'medium' | 'high'

export type FitnessEvidenceMetric =
  | 'body_mass'
  | 'height'
  | 'body_fat_percentage'
  | 'resting_metabolic_rate'
  | 'vo2_max'
  | 'resting_heart_rate'
  | 'waist_circumference'
  | 'cardio_capacity_score'
  | 'upper_body_strength_score'
  | 'lower_body_strength_score'
  | 'flexibility_score'
  | 'joint_health_score'
  | 'balance_score'

export type FitnessEvidenceSource =
  | 'indirect_calorimetry'
  | 'dexa_measurement'
  | 'dexa_derived_estimate'
  | 'clinical_measurement'
  | 'supported_device'
  | 'guided_apex_field_test'
  | 'structured_self_report'
  | 'user_entered_external_result'
  | 'legacy_unverified'

export interface FitnessEvidenceDraft {
  user_id: string
  metric: string
  value: number
  unit: string
  source: string
  protocol?: string | null
  device?: string | null
  measured_at: string
  imported_at: string
  requested_confidence: string
  metadata: unknown
  supersedes_id?: string | null
  client_idempotency_key: string
}
export interface FitnessEvidencePredecessor {
  id: string
  user_id: string
  metric: string
}

export interface NormalizedFitnessEvidence {
  user_id: string
  metric: FitnessEvidenceMetric
  value: number
  unit: string
  source: FitnessEvidenceSource
  protocol: string | null
  device: string | null
  measured_at: string
  imported_at: string
  confidence: FitnessEvidenceConfidence
  metadata: Record<string, unknown>
  supersedes_id: string | null
  client_idempotency_key: string
}

export type FitnessEvidenceRejection =
  | 'invalid_owner'
  | 'unsupported_metric'
  | 'unsupported_source'
  | 'invalid_unit_or_range'
  | 'invalid_timestamp'
  | 'invalid_metadata'
  | 'invalid_idempotency_key'
  | 'invalid_confidence'
  | 'invalid_correction'
  | 'invalid_text_field'

export type FitnessEvidenceNormalizationResult =
  | { status: 'accepted'; evidence: NormalizedFitnessEvidence }
  | { status: 'rejected'; reason: FitnessEvidenceRejection }

export interface FitnessEvidenceNormalizationSummary {
  status: 'accepted'
  summary: {
    metric: FitnessEvidenceMetric
    value: number
    unit: string
    source: FitnessEvidenceSource
    confidence: FitnessEvidenceConfidence
    protocol: string | null
    device: string | null
    measured_at: string
    imported_at: string
    metadata_keys: string[]
    supersedes_id: string | null
    client_idempotency_key: string
  }
}

export interface FitnessEvidenceNormalizationScenario {
  name: string
  admission: FitnessEvidenceAdmission
  input: FitnessEvidenceDraft
  predecessor?: FitnessEvidencePredecessor
  expected:
    | FitnessEvidenceNormalizationSummary
    | { status: 'rejected'; reason: FitnessEvidenceRejection }
}

export interface FitnessEvidenceNormalizationFixture {
  reference_now: string
  scenarios: FitnessEvidenceNormalizationScenario[]
}

const metricAliases: Readonly<Record<string, FitnessEvidenceMetric>> = {
  body_mass: 'body_mass',
  body_weight: 'body_mass',
  weight: 'body_mass',
  weight_kg: 'body_mass',
  height: 'height',
  height_cm: 'height',
  body_fat: 'body_fat_percentage',
  body_fat_pct: 'body_fat_percentage',
  body_fat_percentage: 'body_fat_percentage',
  bmr: 'resting_metabolic_rate',
  rmr: 'resting_metabolic_rate',
  resting_metabolic_rate: 'resting_metabolic_rate',
  vo2_max: 'vo2_max',
  vo2max: 'vo2_max',
  resting_heart_rate: 'resting_heart_rate',
  resting_hr: 'resting_heart_rate',
  waist: 'waist_circumference',
  waist_circumference: 'waist_circumference',
  cardio_capacity_score: 'cardio_capacity_score',
  upper_body_strength_score: 'upper_body_strength_score',
  lower_body_strength_score: 'lower_body_strength_score',
  flexibility_score: 'flexibility_score',
  joint_health_score: 'joint_health_score',
  balance_score: 'balance_score',
}

const sourceAliases: Readonly<Record<string, FitnessEvidenceSource>> = {
  indirect_calorimetry: 'indirect_calorimetry',
  metabolic_cart: 'indirect_calorimetry',
  dexa: 'dexa_measurement',
  dexa_scan: 'dexa_measurement',
  dexa_measurement: 'dexa_measurement',
  dexa_derived: 'dexa_derived_estimate',
  dexa_derived_estimate: 'dexa_derived_estimate',
  clinical: 'clinical_measurement',
  clinical_measurement: 'clinical_measurement',
  supported_device: 'supported_device',
  apple_health: 'supported_device',
  apple_watch: 'supported_device',
  healthkit: 'supported_device',
  guided_apex_field_test: 'guided_apex_field_test',
  apex_field_test: 'guided_apex_field_test',
  structured_self_report: 'structured_self_report',
  self_report: 'structured_self_report',
  user_entered_external_result: 'user_entered_external_result',
  external_result: 'user_entered_external_result',
  legacy_unverified: 'legacy_unverified',
  legacy: 'legacy_unverified',
}

const unitAliases: Readonly<Record<string, string>> = {
  kg: 'kg',
  cm: 'cm',
  percent: 'percent',
  pct: 'percent',
  '%': 'percent',
  kcal_per_day: 'kcal_per_day',
  'kcal/day': 'kcal_per_day',
  ml_per_kg_min: 'ml_per_kg_min',
  'ml/kg/min': 'ml_per_kg_min',
  bpm: 'bpm',
  beats_per_minute: 'bpm',
  score_0_100: 'score_0_100',
}

const trustedSources = new Set<FitnessEvidenceSource>([
  'indirect_calorimetry',
  'dexa_measurement',
  'dexa_derived_estimate',
  'clinical_measurement',
  'supported_device',
  'guided_apex_field_test',
])

const confidenceRank: Readonly<Record<FitnessEvidenceConfidence, number>> = {
  low: 0,
  medium: 1,
  high: 2,
}

const confidenceCeiling: Readonly<Record<FitnessEvidenceSource, FitnessEvidenceConfidence>> = {
  indirect_calorimetry: 'high',
  dexa_measurement: 'high',
  dexa_derived_estimate: 'medium',
  clinical_measurement: 'high',
  supported_device: 'medium',
  guided_apex_field_test: 'medium',
  structured_self_report: 'low',
  user_entered_external_result: 'low',
  legacy_unverified: 'low',
}

function token(value: string): string {
  return value.trim().toLowerCase().replace(/[^a-z0-9%]+/g, '_').replace(/^_+|_+$/g, '')
}

function normalizeMetric(value: string): FitnessEvidenceMetric | null {
  return metricAliases[token(value)] ?? null
}

function normalizeSource(value: string): FitnessEvidenceSource | null {
  return sourceAliases[token(value)] ?? null
}

function normalizeUnit(value: string): string | null {
  const raw = value.trim().toLowerCase()
  return unitAliases[raw] ?? unitAliases[token(raw)] ?? null
}

function validMetricUnitRange(metric: FitnessEvidenceMetric, unit: string, value: number): boolean {
  if (!Number.isFinite(value)) return false
  switch (metric) {
    case 'body_mass': return unit === 'kg' && value >= 10 && value <= 500
    case 'height': return unit === 'cm' && value >= 50 && value <= 260
    case 'body_fat_percentage': return unit === 'percent' && value >= 2 && value <= 70
    case 'resting_metabolic_rate': return unit === 'kcal_per_day' && value >= 400 && value <= 8000
    case 'vo2_max': return unit === 'ml_per_kg_min' && value >= 5 && value <= 120
    case 'resting_heart_rate': return unit === 'bpm' && value >= 20 && value <= 250
    case 'waist_circumference': return unit === 'cm' && value >= 30 && value <= 300
    case 'cardio_capacity_score':
    case 'upper_body_strength_score':
    case 'lower_body_strength_score':
    case 'flexibility_score':
    case 'joint_health_score':
    case 'balance_score':
      return unit === 'score_0_100' && value >= 0 && value <= 100
  }
}

function normalizedDate(value: string): { date: Date; iso: string } | null {
  const date = new Date(value)
  if (!Number.isFinite(date.getTime())) return null
  return { date, iso: date.toISOString() }
}

function optionalText(value: string | null | undefined, maximum: number): string | null | undefined {
  if (value == null) return null
  const result = value.trim()
  if (!result) return null
  return result.length <= maximum ? result : undefined
}

function cappedConfidence(
  requested: string,
  source: FitnessEvidenceSource,
): FitnessEvidenceConfidence | null {
  if (requested !== 'low' && requested !== 'medium' && requested !== 'high') return null
  const ceiling = confidenceCeiling[source]
  return confidenceRank[requested] <= confidenceRank[ceiling] ? requested : ceiling
}

function rejected(reason: FitnessEvidenceRejection): FitnessEvidenceNormalizationResult {
  return { status: 'rejected', reason }
}

export function normalizeFitnessEvidence(
  input: FitnessEvidenceDraft,
  admission: FitnessEvidenceAdmission,
  referenceNow: string,
  predecessor: FitnessEvidencePredecessor | null = null,
): FitnessEvidenceNormalizationResult {
  const userID = input.user_id.trim()
  if (!userID) return rejected('invalid_owner')

  const metric = normalizeMetric(input.metric)
  if (!metric) return rejected('unsupported_metric')

  const submittedSource = normalizeSource(input.source)
  if (!submittedSource) return rejected('unsupported_source')

  const unit = normalizeUnit(input.unit)
  if (!unit || !validMetricUnitRange(metric, unit, input.value)) {
    return rejected('invalid_unit_or_range')
  }

  if (input.metadata == null || typeof input.metadata !== 'object' || Array.isArray(input.metadata)) {
    return rejected('invalid_metadata')
  }

  const measured = normalizedDate(input.measured_at)
  const imported = normalizedDate(input.imported_at)
  const reference = normalizedDate(referenceNow)
  if (!measured || !imported || !reference) return rejected('invalid_timestamp')
  const oneDay = 24 * 60 * 60 * 1000
  const earliest = Date.parse('1900-01-01T00:00:00Z')
  if (
    measured.date.getTime() < earliest
    || measured.date.getTime() > imported.date.getTime() + oneDay
    || imported.date.getTime() > reference.date.getTime() + oneDay
  ) {
    return rejected('invalid_timestamp')
  }

  const clientKey = input.client_idempotency_key.trim()
  if (!clientKey || clientKey.length > 160) return rejected('invalid_idempotency_key')

  const normalizedProtocol = optionalText(input.protocol, 160)
  const normalizedDevice = optionalText(input.device, 200)
  if (normalizedProtocol === undefined || normalizedDevice === undefined) {
    return rejected('invalid_text_field')
  }

  let source = submittedSource
  let protocol = normalizedProtocol
  if (admission === 'user' && trustedSources.has(submittedSource)) {
    source = 'user_entered_external_result'
    protocol = protocol ?? `reported:${submittedSource}`
  } else if (admission === 'user' && submittedSource === 'legacy_unverified') {
    source = 'user_entered_external_result'
    protocol = protocol ?? 'reported:legacy_unverified'
  }

  const confidence = cappedConfidence(input.requested_confidence, source)
  if (!confidence) return rejected('invalid_confidence')

  const supersedesID = input.supersedes_id?.trim() || null
  if (supersedesID) {
    const predecessorMetric = predecessor ? normalizeMetric(predecessor.metric) : null
    if (
      !predecessor
      || predecessor.id !== supersedesID
      || predecessor.user_id !== userID
      || predecessorMetric !== metric
    ) {
      return rejected('invalid_correction')
    }
  }

  return {
    status: 'accepted',
    evidence: {
      user_id: userID,
      metric,
      value: input.value,
      unit,
      source,
      protocol,
      device: normalizedDevice,
      measured_at: measured.iso,
      imported_at: imported.iso,
      confidence,
      metadata: { ...(input.metadata as Record<string, unknown>) },
      supersedes_id: supersedesID,
      client_idempotency_key: clientKey,
    },
  }
}

export function summarizeFitnessEvidenceNormalization(
  result: FitnessEvidenceNormalizationResult,
): FitnessEvidenceNormalizationSummary | { status: 'rejected'; reason: FitnessEvidenceRejection } {
  if (result.status === 'rejected') return result
  const evidence = result.evidence
  return {
    status: 'accepted',
    summary: {
      metric: evidence.metric,
      value: evidence.value,
      unit: evidence.unit,
      source: evidence.source,
      confidence: evidence.confidence,
      protocol: evidence.protocol,
      device: evidence.device,
      measured_at: evidence.measured_at,
      imported_at: evidence.imported_at,
      metadata_keys: Object.keys(evidence.metadata).sort(),
      supersedes_id: evidence.supersedes_id,
      client_idempotency_key: evidence.client_idempotency_key,
    },
  }
}
