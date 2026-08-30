import type { PersonaSlug } from './persona'

export type ProfileKind = 'standard' | 'bespoke'
export type BespokeProtocolID =
  | 'constantine-v8.5'
  | 'june-v8.4'
  | 'matthew-v1'
  | 'iulian-v2'
export type BodyFatSource =
  | 'dexa'
  | 'bia_scale'
  | 'calipers'
  | 'professional_estimate'
  | 'self_estimate'
  | 'legacy_unverified'

export interface ProfilePolicyInput {
  user_id?: string | null
  persona: PersonaSlug
  profile_kind?: ProfileKind | null
  bespoke_protocol_id?: string | null
}

export interface BodyFatPolicyInput {
  body_fat_pct: number | null
  body_fat_source?: BodyFatSource | null
}

export interface ResolvedProfilePolicy {
  kind: ProfileKind
  bespokeProtocolID: BespokeProtocolID | null
}

const BODY_FAT_SOURCES = new Set<BodyFatSource>([
  'dexa',
  'bia_scale',
  'calipers',
  'professional_estimate',
  'self_estimate',
  'legacy_unverified',
])

const ENERGY_ELIGIBLE_BODY_FAT_SOURCES = new Set<BodyFatSource>([
  'dexa',
  'bia_scale',
  'calipers',
  'professional_estimate',
])

export function normalizeBodyFatSource(value: unknown): BodyFatSource | null {
  return typeof value === 'string' && BODY_FAT_SOURCES.has(value as BodyFatSource)
    ? value as BodyFatSource
    : null
}

export function bespokeProtocolFor(profile: ProfilePolicyInput): BespokeProtocolID | null {
  if (profile.profile_kind !== 'bespoke') return null
  if (
    profile.user_id?.toLowerCase() === '9a0fffbc-bb02-40ac-834a-d4e339b32574' &&
    profile.persona === 'constantine' &&
    profile.bespoke_protocol_id === 'constantine-v8.5'
  ) return 'constantine-v8.5'
  if (
    profile.user_id?.toLowerCase() === 'f1cc8158-0480-47c9-a2f1-bd03890182f9' &&
    profile.persona === 'june' &&
    profile.bespoke_protocol_id === 'june-v8.4'
  ) return 'june-v8.4'
  if (
    profile.user_id?.toLowerCase() === 'ed1fa9d3-9d39-4d39-9b66-a51f2d140492' &&
    profile.persona === 'matthew' &&
    profile.bespoke_protocol_id === 'matthew-v1'
  ) return 'matthew-v1'
  if (
    profile.user_id?.toLowerCase() === 'ce883869-fe72-4371-9788-5723d76f07b5' &&
    profile.persona === 'iulian' &&
    profile.bespoke_protocol_id === 'iulian-v2'
  ) return 'iulian-v2'
  return null
}

export function resolveProfilePolicy(profile: ProfilePolicyInput): ResolvedProfilePolicy {
  const bespokeProtocolID = bespokeProtocolFor(profile)
  return bespokeProtocolID
    ? { kind: 'bespoke', bespokeProtocolID }
    : { kind: 'standard', bespokeProtocolID: null }
}

export function bodyFatIsEnergyEligible(profile: BodyFatPolicyInput): boolean {
  return typeof profile.body_fat_pct === 'number'
    && Number.isFinite(profile.body_fat_pct)
    && profile.body_fat_pct >= 2
    && profile.body_fat_pct <= 70
    && ENERGY_ELIGIBLE_BODY_FAT_SOURCES.has(profile.body_fat_source ?? 'legacy_unverified')
}

export function bodyFatBaselineClause(profile: BodyFatPolicyInput): string {
  return typeof profile.body_fat_pct === 'number' && Number.isFinite(profile.body_fat_pct)
    ? `, ${profile.body_fat_pct}% body fat`
    : ''
}
