import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface GeoPoint { lat: number; lng: number }

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  try {
    const authorization = request.headers.get('Authorization')
    if (!authorization?.startsWith('Bearer ')) return json({ error: 'Authentication required' }, 401)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')
    if (!supabaseUrl || !supabaseAnonKey) return json({ error: 'Function authentication is not configured' }, 503)
    const authClient = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authorization } } })
    const { data: auth, error: authError } = await authClient.auth.getUser()
    if (authError || !auth.user) return json({ error: 'Authentication required' }, 401)
    const body = await request.json() as { operation?: string; payload?: Record<string, unknown> }
    if (body.operation === 'geocode') {
      const query = String(body.payload?.query ?? '').trim().slice(0, 160)
      if (query.length < 3) return json([])
      const params = new URLSearchParams({ q: query, format: 'jsonv2', limit: '5' })
      const upstream = await fetch(`https://nominatim.openstreetmap.org/search?${params}`, {
        headers: { Accept: 'application/json', 'User-Agent': 'APEX-Orbit-private-prototype/1.0' },
      })
      return proxy(upstream)
    }
    if (body.operation === 'route') {
      const points = Array.isArray(body.payload?.waypoints) ? body.payload!.waypoints as GeoPoint[] : []
      if (points.length < 2 || points.length > 12 || points.some((point) => !Number.isFinite(point.lat) || !Number.isFinite(point.lng))) {
        return json({ error: 'Invalid waypoints' }, 400)
      }
      const params = new URLSearchParams({
        lonlats: points.map((point) => `${point.lng.toFixed(6)},${point.lat.toFixed(6)}`).join('|'),
        profile: 'trekking', alternativeidx: '0', format: 'geojson',
      })
      const upstream = await fetch(`https://brouter.de/brouter?${params}`, { headers: { Accept: 'application/geo+json' } })
      if (!upstream.ok) return proxy(upstream)
      const data = await upstream.json() as { features?: Array<{ geometry?: { coordinates?: number[][] }; properties?: Record<string, unknown> }> }
      const feature = data.features?.[0]
      const routePoints = (feature?.geometry?.coordinates ?? []).map((coordinate) => ({
        lng: Number(coordinate[0]), lat: Number(coordinate[1]), elevation_m: coordinate[2] == null ? null : Number(coordinate[2]),
      }))
      const gain = Number(feature?.properties?.['filtered ascend'] ?? feature?.properties?.ascend)
      return json({ points: routePoints, elevationGainM: Number.isFinite(gain) ? Math.round(gain) : null })
    }
    return json({ error: 'Unsupported operation' }, 400)
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Orbit geographic provider failed' }, 500)
  }
})

async function proxy(response: Response): Promise<Response> {
  return new Response(await response.text(), {
    status: response.status,
    headers: { ...corsHeaders, 'Content-Type': response.headers.get('Content-Type') ?? 'application/json' },
  })
}

function json(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
