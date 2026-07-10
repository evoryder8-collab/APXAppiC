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

export const isLocalMode = supabase === null
