// Voices an exercise name for the guided-workout coach with ElevenLabs Eleven v4, once per name and language.
// The clip is kept in the private `workout-voice` bucket and served to every phone after that.
// Only names in the caller's own plan are voiced, and each account can make a limited number per day.
import { createClient } from 'jsr:@supabase/supabase-js@2'
import voices from './voices.json' with { type: 'json' }

const elevenLanguage: Record<string, string> = {
  en: 'en', de: 'de', 'de-CH': 'de', it: 'it', es: 'es', pt: 'pt', ja: 'ja', ro: 'ro', th: 'th',
}
// The same model, settings and seed as the recorded lines (ios/APEXNative/Tools/workout-voice/generate.mjs).
const model = 'eleven_v4'
const voiceSettings = { stability: 0.45, similarity_boost: 0.8, use_speaker_boost: true }
const seed = 7_220
// Each account can voice its own plan's names many times over; the shared cap bounds what the whole app can spend in a
// day, since the spoken text (the name in the reader's language) cannot be checked against a translation here.
const dailyLimit = 100
const sharedDailyLimit = 400
// Said before the name but not spoken, as for the recorded set calls (`setLead` in lines.mjs): alone, a short name
// like "Plank" is sometimes said twice.
const lead: Record<string, string> = {
  en: 'Next exercise coming up.', de: 'Gleich geht es weiter.', 'de-CH': 'Gleich geht es weiter.', it: 'Si riparte tra poco.',
  es: 'Seguimos enseguida.', pt: 'Já vamos continuar.', ja: 'まもなく次にいきます。', ro: 'Continuăm imediat.', th: 'เดี๋ยวไปต่อกัน',
}

function reply(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json; charset=utf-8' } })
}

function audio(bytes: Blob | Uint8Array): Response {
  return new Response(bytes, { headers: { 'Content-Type': 'audio/mpeg', 'Cache-Control': 'private, max-age=31536000' } })
}

async function digest(text: string): Promise<string> {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, '0')).join('').slice(0, 40)
}

/** The spoken line for a name, acted like the recorded set calls. */
function nameLine(spoken: string): string {
  return `[clear, confident] ${spoken.trim().replace(/[.。]+$/u, '')}.`
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return reply({ state: 'invalid', message: 'POST required' }, 405)
  const authorization = request.headers.get('authorization')
  if (!authorization?.toLowerCase().startsWith('bearer ')) return reply({ state: 'invalid', message: 'Authentication required' }, 401)
  const url = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const elevenKey = Deno.env.get('ELEVENLABS_API_KEY')
  if (!url || !anonKey || !serviceKey || !elevenKey) return reply({ state: 'unavailable', message: 'Voice is not set up' }, 503)

  let name = ''
  let spoken = ''
  let language = ''
  try {
    const body = await request.json() as { name?: unknown; spoken?: unknown; language?: unknown }
    name = String(body.name ?? '').trim()
    spoken = String(body.spoken ?? '').trim()
    language = String(body.language ?? '')
  } catch {
    return reply({ state: 'invalid', message: 'Invalid JSON body' }, 400)
  }
  const voice = Object.hasOwn(voices, language) ? (voices as Record<string, string>)[language] : undefined
  if (!Object.hasOwn(elevenLanguage, language) || !voice) return reply({ state: 'invalid', message: 'Unsupported language' }, 400)
  if (name.length < 1 || name.length > 80 || spoken.length < 1 || spoken.length > 80) {
    return reply({ state: 'invalid', message: 'Name must be 1 to 80 characters' }, 400)
  }

  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } })
  const { data: userData, error: authError } = await caller.auth.getUser(authorization.slice(7))
  if (authError || !userData.user) return reply({ state: 'invalid', message: 'Invalid session' }, 401)
  // Row security limits this to the caller's own exercises; the exact name, so no pattern can match them all.
  const { data: owned } = await caller.from('exercises').select('id').eq('name', name).limit(1)
  if (!owned?.length) return reply({ state: 'invalid', message: 'Not an exercise in your plan' }, 403)

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const path = `${language}/${await digest(`${model}|${voice}|${seed}|${language}|${lead[language]}|${nameLine(spoken)}`)}.mp3`
  const cached = await admin.storage.from('workout-voice').download(path)
  if (cached.data) return audio(cached.data)

  const since = new Date(Date.now() - 86_400_000).toISOString()
  const { count } = await admin.from('workout_voice_generations').select('id', { count: 'exact', head: true })
    .eq('user_id', userData.user.id).gte('created_at', since)
  const { count: shared } = await admin.from('workout_voice_generations').select('id', { count: 'exact', head: true })
    .gte('created_at', since)
  if ((count ?? 0) >= dailyLimit || (shared ?? 0) >= sharedDailyLimit) {
    return reply({ state: 'limited', message: 'Daily voice limit reached' }, 429)
  }

  const generated = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voice}?output_format=mp3_44100_64`, {
    method: 'POST',
    headers: { 'xi-api-key': elevenKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      text: nameLine(spoken), previous_text: lead[language], model_id: model, language_code: elevenLanguage[language],
      voice_settings: voiceSettings, seed,
    }),
  })
  if (!generated.ok) {
    console.error('elevenlabs', generated.status, (await generated.text()).slice(0, 200))
    return reply({ state: 'provider_error', message: 'The voice could not be made right now' }, 502)
  }
  const bytes = new Uint8Array(await generated.arrayBuffer())
  await admin.storage.from('workout-voice').upload(path, bytes, { contentType: 'audio/mpeg', upsert: true })
  await admin.from('workout_voice_generations').insert({ user_id: userData.user.id, language, characters: spoken.length })
  return audio(bytes)
})
