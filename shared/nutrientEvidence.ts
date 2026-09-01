export type ProviderNutrientObservationStatus =
  | 'measured'
  | 'calculated'
  | 'estimated'
  | 'reported'
  | 'trace'
  | 'below_detection'
  | 'not_measured'
  | 'missing'

export interface ProviderNutrientEvidenceObservation {
  nutrient_code: string
  name: string
  value_per_100: number | null
  unit: string
  observation_status: ProviderNutrientObservationStatus
  original_value_text: string
  derivation_method: string | null
  source_key: string | null
  source_reference: string | null
}
