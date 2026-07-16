import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

/*
 * When the env vars are absent the app runs in local mode: everything works
 * against localStorage only and the sync layer is disabled. Add the two env
 * vars (see README) to turn on auth + global sync without code changes.
 */
export const supabase: SupabaseClient | null =
  url && anonKey && url.startsWith('http') ? createClient(url, anonKey) : null

/**
 * Create a short-lived client whose requests stay bound to one captured
 * authenticated session. The shared client's auth state can change while an
 * offline queue is flushing (for example when switching accounts), so queue
 * writers must not read its bearer token at request time.
 */
export function createSessionBoundSupabase(accessToken: string): SupabaseClient | null {
  if (!url || !anonKey || !url.startsWith('http') || !accessToken) return null
  return createClient(url, anonKey, {
    accessToken: async () => accessToken,
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  })
}

export const isLocalMode = supabase === null
