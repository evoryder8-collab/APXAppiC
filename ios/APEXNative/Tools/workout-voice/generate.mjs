// Generates the guided-workout voice with ElevenLabs Eleven v4.
//   node generate.mjs voices [lang]                 list your voices and library voices for a language
//   node generate.mjs audition <out-dir> <lang> <voiceId…>  render the audition lines in one language with each voice
//   node generate.mjs build [lang…]                 render every line into APEX/Resources/WorkoutVoice
// The API key is read from the macOS Keychain (account fitr-max, service elevenlabs-api-key) and never printed.
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { elevenLanguageCode, linesFor, voiceLanguages } from './lines.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const resources = path.resolve(here, '../../APEX/Resources/WorkoutVoice')
const voicesFile = path.resolve(here, '../../../../supabase/functions/workout-voice/voices.json')
const model = 'eleven_v4'
// Expressive yet steady across ~300 separate clips; tuned by ear in the audition.
const voiceSettings = { stability: 0.45, similarity_boost: 0.8, use_speaker_boost: true }
const seed = 7_220

function apiKey() {
  try {
    return execFileSync('security', ['find-generic-password', '-a', 'fitr-max', '-s', 'elevenlabs-api-key', '-w'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
  } catch {
    throw new Error('No ElevenLabs key in the Keychain (account fitr-max, service elevenlabs-api-key).')
  }
}

async function api(route, { method = 'GET', body, query } = {}) {
  const url = new URL(`https://api.elevenlabs.io${route}`)
  for (const [k, v] of Object.entries(query ?? {})) if (v !== undefined) url.searchParams.set(k, String(v))
  for (let attempt = 1; ; attempt += 1) {
    let response
    try {
      response = await fetch(url, {
        method,
        headers: { 'xi-api-key': apiKey(), ...(body ? { 'content-type': 'application/json' } : {}) },
        body: body ? JSON.stringify(body) : undefined,
      })
    } catch (error) {
      // A dropped connection is retried like an outage.
      if (attempt >= 5) throw error
      await new Promise((resolve) => setTimeout(resolve, 1500 * attempt))
      continue
    }
    if (response.ok) return response
    const detail = (await response.text()).slice(0, 300)
    // Rate limits, brief outages and a library voice still being added on first use are retried.
    if ((response.status === 409 || response.status === 429 || response.status >= 500) && attempt < 5) {
      await new Promise((resolve) => setTimeout(resolve, 1500 * attempt))
      continue
    }
    throw new Error(`${method} ${route} → ${response.status}: ${detail}`)
  }
}

async function speak(voiceId, language, line) {
  const response = await api(`/v1/text-to-speech/${voiceId}`, {
    method: 'POST',
    query: { output_format: 'mp3_44100_128' },
    body: {
      text: line.text,
      model_id: model,
      language_code: elevenLanguageCode[language],
      voice_settings: voiceSettings,
      seed,
      ...(line.previousText ? { previous_text: line.previousText } : {}),
    },
  })
  return Buffer.from(await response.arrayBuffer())
}

// Silence before the word is trimmed so a count lands on the rep; mono AAC at 48 kbit/s keeps a voice clear at
// about 6 KB a second.
const trim = 'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.03,areverse,'
  + 'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.12,areverse'
function toAAC(mp3, destination) {
  const source = `${destination}.mp3`
  const trimmed = `${destination}.wav`
  fs.writeFileSync(source, mp3)
  execFileSync('ffmpeg', ['-y', '-v', 'error', '-i', source, '-af', trim, '-ar', '44100', '-ac', '1', trimmed])
  execFileSync('afconvert', ['-f', 'm4af', '-d', 'aac', '-b', '48000', '-c', '1', trimmed, destination], { stdio: 'ignore' })
  fs.rmSync(source)
  fs.rmSync(trimmed)
}

async function inBatches(items, size, work) {
  for (let index = 0; index < items.length; index += size) {
    await Promise.all(items.slice(index, index + size).map(work))
  }
}

const auditionLines = ['set.set.1.4', 'count.3', 'count.9.push', 'count.10.push', 'cue.rest', 'set.set.4.4', 'cue.complete',
  'boost.warm.1', 'boost.final.2', 'boost.finale.1', 'boost.done.3']

async function main() {
  const [command, ...args] = process.argv.slice(2)
  if (command === 'voices') {
    const language = args[0] ?? 'en'
    const mine = await (await api('/v2/voices', { query: { page_size: 100 } })).json()
    console.log('YOUR VOICES')
    for (const v of mine.voices ?? []) console.log(`${v.voice_id}  ${v.name}  [${v.category}]  ${JSON.stringify(v.labels ?? {})}`)
    const library = await (await api('/v1/shared-voices', {
      query: { page_size: 40, language: elevenLanguageCode[language], use_cases: 'characters_animation,informative_educational,conversational', sort: 'trending' },
    })).json()
    console.log(`LIBRARY (${language})`)
    for (const v of library.voices ?? []) {
      console.log(`${v.voice_id}  ${v.name}  ${v.gender ?? ''} ${v.age ?? ''} ${v.accent ?? ''}  public_owner=${v.public_owner_id}  ${(v.descriptive ?? '')}`)
    }
    const subscription = await (await api('/v1/user/subscription')).json()
    console.log(`PLAN ${subscription.tier}: ${subscription.character_count} of ${subscription.character_limit} characters used`)
    return
  }
  if (command === 'audition') {
    const [outDir, language, ...voiceIds] = args
    fs.mkdirSync(outDir, { recursive: true })
    const lines = linesFor(language).filter((line) => auditionLines.includes(line.id))
    for (const voiceId of voiceIds) {
      await inBatches(lines, 4, async (line) => {
        const file = path.join(outDir, `${language}.${voiceId}.${line.id}.mp3`)
        if (!fs.existsSync(file)) fs.writeFileSync(file, await speak(voiceId, language, line))
      })
      console.log(`auditioned ${language} ${voiceId}`)
    }
    return
  }
  if (command === 'build') {
    const voices = JSON.parse(fs.readFileSync(voicesFile, 'utf8'))
    const languages = args.length ? args : voiceLanguages
    const manifest = fs.existsSync(path.join(resources, 'manifest.json'))
      ? JSON.parse(fs.readFileSync(path.join(resources, 'manifest.json'), 'utf8')) : { model, languages: {} }
    for (const language of languages) {
      const voiceId = voices[language]
      if (!voiceId) throw new Error(`voices.json names no voice for ${language}`)
      const directory = path.join(resources, language)
      fs.mkdirSync(directory, { recursive: true })
      const lines = linesFor(language)
      const signature = (line) => createHash('sha256').update(JSON.stringify([model, voiceId, voiceSettings, seed, line])).digest('hex').slice(0, 16)
      const previous = manifest.languages[language]?.clips ?? {}
      let made = 0
      await inBatches(lines, 4, async (line) => {
        const file = path.join(directory, `${line.id}.m4a`)
        // A clip is remade only when its words, voice or settings changed.
        if (fs.existsSync(file) && previous[line.id] === signature(line)) return
        toAAC(await speak(voiceId, language, line), file)
        made += 1
      })
      manifest.languages[language] = { voice: voiceId, clips: Object.fromEntries(lines.map((line) => [line.id, signature(line)])) }
      fs.writeFileSync(path.join(resources, 'manifest.json'), JSON.stringify(manifest, null, 1))
      console.log(`${language}: ${lines.length} clips, ${made} made now`)
    }
    return
  }
  throw new Error('Usage: generate.mjs voices [lang] | audition <out> <lang> <voiceId…> | build [lang…]')
}

main().catch((error) => {
  console.error(error.message)
  process.exit(1)
})
