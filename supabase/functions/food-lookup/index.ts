import { createClient } from 'jsr:@supabase/supabase-js@2'
import {
  OPEN_FOOD_FACTS_FIELDS,
  normalizeBarcode,
  normalizeOpenFoodFactsProduct,
  openFoodFactsUrl,
} from '../../../shared/openFoodFacts.ts'

const allowedOrigins = new Set([
  'https://evoryder8-collab.github.io',
  'http://localhost:5174',
  'http://127.0.0.1:5174',
])

function cors(origin: string | null): HeadersInit {
  const safeOrigin = origin && allowedOrigins.has(origin) ? origin : 'https://evoryder8-collab.github.io'
  return {
    'Access-Control-Allow-Origin': safeOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  }
}

function json(origin: string | null, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(origin), 'Content-Type': 'application/json; charset=utf-8' },
  })
}

function extendedSearchScore(query: string, food: { name?: string; brand?: string | null }): number {
  const needle = query.toLocaleLowerCase()
  const text = `${food.brand ?? ''} ${food.name ?? ''}`.toLocaleLowerCase()
  const plainPotato = /potato|cartof|มันฝรั่ง/.test(needle) && !/sweet|dulce|มันหวาน/.test(needle)
  if (!plainPotato) return 0
  if (/pringles|lays|chips|crisps|potato snack/.test(text)) return -1000
  if (/raw|boiled|baked|air fryer|whole potato/.test(text)) return 300
  return 0
}

Deno.serve(async (request) => {
  const origin = request.headers.get('origin')
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors(origin) })
  if (request.method !== 'POST') return json(origin, { state: 'invalid', message: 'POST required' }, 405)

  const authorization = request.headers.get('authorization')
  if (!authorization?.toLowerCase().startsWith('bearer ')) {
    return json(origin, { state: 'invalid', message: 'Authentication required' }, 401)
  }
  const url = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !anonKey || !serviceKey) {
    return json(origin, { state: 'provider_error', message: 'Function environment is incomplete' }, 500)
  }
  const token = authorization.slice(7)
  const authClient = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } })
  const { data: userData, error: authError } = await authClient.auth.getUser(token)
  if (authError || !userData.user) return json(origin, { state: 'invalid', message: 'Invalid session' }, 401)

  let rawBarcode = ''
  let rawQuery = ''
  try {
    const body = await request.json() as { barcode?: unknown; query?: unknown }
    rawBarcode = String(body.barcode ?? '')
    rawQuery = String(body.query ?? '').trim()
  } catch {
    return json(origin, { state: 'invalid', message: 'Invalid JSON body' }, 400)
  }

  if (!rawBarcode && rawQuery) {
    if (rawQuery.length < 2 || rawQuery.length > 80) {
      return json(origin, { state: 'invalid', message: 'Search must be between 2 and 80 characters' }, 400)
    }
    const searchUrl = new URL('https://world.openfoodfacts.org/cgi/search.pl')
    searchUrl.searchParams.set('search_terms', rawQuery)
    searchUrl.searchParams.set('search_simple', '1')
    searchUrl.searchParams.set('action', 'process')
    searchUrl.searchParams.set('json', '1')
    searchUrl.searchParams.set('page_size', '15')
    searchUrl.searchParams.set('fields', OPEN_FOOD_FACTS_FIELDS)
    try {
      const response = await fetch(searchUrl, {
        headers: { Accept: 'application/json', 'User-Agent': 'APEX private performance app/1.0' },
        signal: AbortSignal.timeout(8000),
      })
      if (!response.ok) return json(origin, { state: 'provider_error', message: 'Extended search is temporarily unavailable' })
      const payload = await response.json() as { products?: Array<Record<string, unknown>> }
      const results = (payload.products ?? []).flatMap((product) => {
        const code = normalizeBarcode(String(product.code ?? ''))
        if (!code) return []
        const normalized = normalizeOpenFoodFactsProduct({ status: 1, product } as never, code)
        return normalized ? [{ id: `off:${code}`, owner_user_id: null, barcode: code, ...normalized }] : []
      }).sort((a, b) => extendedSearchScore(rawQuery, b) - extendedSearchScore(rawQuery, a))
      return json(origin, { state: 'results', query: rawQuery, results })
    } catch {
      return json(origin, { state: 'provider_error', message: 'Extended search is temporarily unavailable' })
    }
  }
  const barcode = normalizeBarcode(rawBarcode)
  if (!barcode) return json(origin, { state: 'invalid', message: 'Invalid EAN or UPC barcode' }, 400)

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data: cached, error: cachedError } = await admin
    .from('foods')
    .select('*')
    .is('owner_user_id', null)
    .eq('barcode', barcode)
    .maybeSingle()
  if (cachedError) return json(origin, { state: 'provider_error', message: 'APEX food cache is unavailable' }, 503)
  if (cached) return json(origin, { state: 'found', source: 'cache', food: cached })

  const providerUrl = openFoodFactsUrl(barcode)
  if (!providerUrl) return json(origin, { state: 'invalid', message: 'Invalid barcode' }, 400)
  let providerResponse: Response
  try {
    providerResponse = await fetch(providerUrl, {
      headers: { Accept: 'application/json', 'User-Agent': 'APEX private performance app/1.0' },
      signal: AbortSignal.timeout(8000),
    })
  } catch {
    return json(origin, { state: 'provider_error', message: 'Open Food Facts did not respond' }, 502)
  }
  if (providerResponse.status === 404) return json(origin, { state: 'not_found', barcode }, 404)
  if (!providerResponse.ok) {
    return json(origin, { state: 'provider_error', message: `Open Food Facts returned ${providerResponse.status}` }, 502)
  }
  let providerPayload: unknown
  try {
    providerPayload = await providerResponse.json()
  } catch {
    return json(origin, { state: 'provider_error', message: 'Open Food Facts returned invalid data' }, 502)
  }
  const normalized = normalizeOpenFoodFactsProduct(providerPayload as never, barcode)
  if (!normalized) {
    const providerState = (providerPayload as { status?: number })?.status === 0 ? 'not_found' : 'incomplete'
    return json(origin, { state: providerState, barcode }, providerState === 'not_found' ? 404 : 422)
  }
  const compact = {
    id: crypto.randomUUID(),
    owner_user_id: null,
    ...normalized,
    serving_unit: normalized.serving_unit,
    piece_grams_or_ml: null,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }
  const { data: inserted, error: insertError } = await admin.from('foods').insert(compact).select('*').single()
  if (!insertError && inserted) return json(origin, { state: 'found', source: 'provider', food: inserted })
  if (insertError?.code === '23505') {
    const { data: raced } = await admin.from('foods').select('*').is('owner_user_id', null).eq('barcode', barcode).maybeSingle()
    if (raced) return json(origin, { state: 'found', source: 'cache', food: raced })
  }
  return json(origin, { state: 'provider_error', message: 'Product was found but could not be cached' }, 503)
})
