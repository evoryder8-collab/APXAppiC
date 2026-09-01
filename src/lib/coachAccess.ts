import type { CoachAccountContext } from './coachPlatform'
import { coachClientPolicy, type CoachClientPolicy } from './coachPlatform'
import type { Profile } from './types'

function futureOrUnbounded(expiresAt: string | null | undefined, now = Date.now()): boolean {
  if (!expiresAt) return true
  const timestamp = Date.parse(expiresAt)
  return Number.isFinite(timestamp) && timestamp > now
}

export function profileHasIndividualAccess(profile: Profile | null | undefined): boolean {
  if (!profile) return false
  if (profile.founding_member || profile.beta_code_redeemed) return true
  return profile.subscription_tier === 'premium' && futureOrUnbounded(profile.subscription_expires_at)
}

export function clientPolicyForAccount(
  profile: Profile | null | undefined,
  context: CoachAccountContext,
): CoachClientPolicy {
  return coachClientPolicy({
    relationship_status: context.sponsorship?.relationship_status ?? null,
    seat_state: context.sponsorship?.seat_state ?? null,
    consented_scopes: context.sponsorship?.consented_scopes ?? [],
    individual_access: profileHasIndividualAccess(profile),
  })
}
