import type { Profile } from './types'
import { bespokeProtocolFor } from './profilePolicy.ts'
import type { SupabaseClient } from '@supabase/supabase-js'

export const avatarStatLabels = {
  health: 'Health',
  joint: 'Joint Health Balance',
  flexibility: 'Body Flexibility',
  endurance: 'Endurance',
  strength_upper: 'Upper Body Strength',
  strength_lower: 'Lower Body Strength',
} as const

export type AvatarStartingPoints = Record<keyof typeof avatarStatLabels, number>
export const avatarStatKeys = Object.keys(avatarStatLabels) as Array<keyof AvatarStartingPoints>
export const equalStartingPoints: AvatarStartingPoints = {
  health: 50, joint: 50, flexibility: 50, endurance: 50, strength_upper: 50, strength_lower: 50,
}

export function validStartingPoints(value: unknown): value is AvatarStartingPoints {
  if (!value || typeof value !== 'object' || Object.keys(value).length !== avatarStatKeys.length) return false
  let total = 0
  for (const [key, points] of Object.entries(value)) {
    if (!Object.hasOwn(avatarStatLabels, key) || typeof points !== 'number' || !Number.isInteger(points) || points < 0 || points > 100) return false
    total += points
  }
  return total === 300
}

export function needsStartingPoints(profile: Profile | null): boolean {
  return profile?.avatar_starting_points_required === true
    && !bespokeProtocolFor(profile) && !validStartingPoints(profile.avatar_starting_points)
}

export async function saveRemoteStartingPoints(client: SupabaseClient, owner: string, points: AvatarStartingPoints) {
  const { error } = await client.from('profile').update({ avatar_starting_points: points })
    .eq('user_id', owner).is('avatar_starting_points', null)
  if (error) throw error
  const { data, error: readError } = await client.from('profile').select('avatar_starting_points')
    .eq('user_id', owner).single()
  if (readError) throw readError
  if (!validStartingPoints(data?.avatar_starting_points)) throw new Error('Missing saved starting points')
  return data.avatar_starting_points
}
