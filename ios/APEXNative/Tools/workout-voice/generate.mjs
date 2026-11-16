// Generates the guided-workout voice with ElevenLabs Eleven v4.
//   node generate.mjs voices [lang]                 list your voices and library voices for a language
//   node generate.mjs audition <out-dir> <lang> <voiceId…>  render the audition lines in one language with each voice
//   node generate.mjs build [lang…]                 render every line into APEX/Resources/WorkoutVoice
//   node generate.mjs retake <lang/id…>             re-record short clips said twice, trying other seeds
// The API key is read from the macOS Keychain (account fitr-max, service elevenlabs-api-key) and never printed.
import { execFileSync, spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import { elevenLanguageCode, linesFor, pepTalkLanguages, voiceLanguages } from './lines.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const resources = path.resolve(here, '../../APEX/Resources/WorkoutVoice')
const voicesFile = path.resolve(here, '../../../../supabase/functions/workout-voice/voices.json')
const model = 'eleven_v4'
// Expressive yet steady across ~300 separate clips; tuned by ear in the audition.
const voiceSettings = { stability: 0.45, similarity_boost: 0.8, use_speaker_boost: true }
const seed = 7_220

let key
function apiKey() {
  try {
    key ??= execFileSync('security', ['find-generic-password', '-a', 'fitr-max', '-s', 'elevenlabs-api-key', '-w'],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
    return key
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

// Clips that came out wrong with the shared seed keep the take that came out right: its seed, and whether it was cut
// from a counting run.
const retakesFile = path.join(here, 'retakes.json')
const retakes = fs.existsSync(retakesFile) ? JSON.parse(fs.readFileSync(retakesFile, 'utf8')) : {}
const takeFor = (language, id) => retakes[`${language}/${id}`] ?? seed
const seedFor = (language, id) => retakes[`${language}/${id}`]?.seed ?? seed

// A lone number is sometimes said twice whatever the seed, never inside a counting run: the number before it (zero
// before one), then this one ("Um. Dois."), of which only the last word is kept.
const zero = { en: 'Zero', de: 'Null', 'de-CH': 'Null', it: 'Zero', es: 'Cero', pt: 'Zero', ja: 'ゼロ', ro: 'Zero', th: 'ศูนย์' }
function countingRun(language, line) {
  const count = line.id.match(/^count\.(\d+)(\.push)?$/)
  if (!count) return undefined
  const words = line.text.match(/^(\[[^\]]+\]) (.*)$/)
  const before = Number(count[1]) > 1
    ? linesFor(language).find((candidate) => candidate.id === `count.${Number(count[1]) - 1}${count[2] ?? ''}`).text
    : `${words[1]} ${zero[language]}${count[2] ? '!' : '.'}`
  return { ...line, text: `${before} ${words[2]}` }
}

async function speak(voiceId, language, line, takeSeed = seedFor(language, line.id)) {
  const response = await api(`/v1/text-to-speech/${voiceId}`, {
    method: 'POST',
    query: { output_format: 'mp3_44100_128' },
    body: {
      text: line.text,
      model_id: model,
      language_code: elevenLanguageCode[language],
      voice_settings: voiceSettings,
      seed: takeSeed,
      ...(line.previousText ? { previous_text: line.previousText } : {}),
    },
  })
  return Buffer.from(await response.arrayBuffer())
}

// Silence before the word is trimmed so a count lands on the rep; mono AAC at 48 kbit/s keeps a voice clear at
// about 6 KB a second.
const trim = 'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.03,areverse,'
  + 'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.12,areverse'
function toAAC(mp3, destination, { lastWordOnly = false } = {}) {
  const source = `${destination}.mp3`
  const trimmed = `${destination}.wav`
  fs.writeFileSync(source, mp3)
  execFileSync('ffmpeg', ['-y', '-v', 'error', '-i', source, '-af', trim, '-ar', '44100', '-ac', '1', trimmed])
  if (lastWordOnly) {
    // Keep the last spoken word: the stretches of sound between pauses, ignoring blips shorter than a word.
    const { duration, pauses } = silences(trimmed, 0.12)
    const edges = [0, ...pauses.flatMap(([start, end]) => [start, Math.min(end, duration)]), duration]
    const words = []
    for (let i = 0; i < edges.length; i += 2) if (edges[i + 1] - edges[i] >= 0.15) words.push([edges[i], edges[i + 1]])
    const last = words.at(-1)
    if (last) {
      const [from, to] = [Math.max(0, last[0] - 0.03), Math.min(duration, last[1] + 0.12)]
      execFileSync('ffmpeg', ['-y', '-v', 'error', '-i', trimmed, '-af', `atrim=start=${from}:end=${to}`, `${trimmed}.cut.wav`])
      fs.renameSync(`${trimmed}.cut.wav`, trimmed)
    }
  }
  execFileSync('afconvert', ['-f', 'm4af', '-d', 'aac', '-b', '48000', '-c', '1', trimmed, destination], { stdio: 'ignore' })
  fs.rmSync(source)
  fs.rmSync(trimmed)
}

function silences(file, minimum) {
  const log = spawnSync('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-af', `silencedetect=noise=-38dB:d=${minimum}`, '-f', 'null', '-'],
    { encoding: 'utf8' }).stderr
  const [, h, m, s] = log.match(/Duration: (\d+):(\d+):([\d.]+)/)
  const starts = [...log.matchAll(/silence_start: ([\d.]+)/g)].map((x) => Number(x[1]))
  const ends = [...log.matchAll(/silence_end: ([\d.]+)/g)].map((x) => Number(x[1]))
  return { duration: Number(h) * 3600 + Number(m) * 60 + Number(s), pauses: starts.map((start, i) => [start, ends[i] ?? Infinity]) }
}

// A long pause in the middle of a short clip is the shape of a word said twice ("Dos. Dos."); a short or quiet one
// is a breath left over from a cut, not the word.
function soundsWrong(file) {
  const { duration, pauses } = silences(file, 0.2)
  const peak = Number(spawnSync('ffmpeg', ['-hide_banner', '-nostats', '-i', file, '-af', 'volumedetect', '-f', 'null', '-'],
    { encoding: 'utf8' }).stderr.match(/max_volume: ([-\d.]+)/)[1])
  return duration < 0.3 || peak < -12 || pauses.some(([start, end]) => start > 0.1 && end < duration - 0.08)
}

const signatureOf = (voiceId, take, line) =>
  createHash('sha256').update(JSON.stringify([model, voiceId, voiceSettings, take, line])).digest('hex').slice(0, 16)

async function inBatches(items, size, work, afterBatch) {
  for (let index = 0; index < items.length; index += size) {
    await Promise.all(items.slice(index, index + size).map(work))
    afterBatch?.()
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
    // The manifest stays with the tool, not in the app: it records what each clip was made from.
    const manifestFile = path.join(here, 'manifest.json')
    const manifest = fs.existsSync(manifestFile) ? JSON.parse(fs.readFileSync(manifestFile, 'utf8')) : { model, languages: {} }
    for (const language of languages) {
      const voiceId = voices[language]
      if (!voiceId) throw new Error(`voices.json names no voice for ${language}`)
      const directory = path.join(resources, language)
      fs.mkdirSync(directory, { recursive: true })
      const lines = linesFor(language).filter((line) => !line.id.startsWith('boost.') || pepTalkLanguages.includes(language))
      const signature = (line) => signatureOf(voiceId, takeFor(language, line.id), line)
      const previous = manifest.languages[language]?.clips ?? {}
      const ready = {}
      let made = 0
      // Saved after every batch, so a run cut short never pays for the same clip twice.
      await inBatches(lines, 4, async (line) => {
        const file = path.join(directory, `${line.id}.m4a`)
        // A clip is remade only when its words, voice or settings changed.
        if (!fs.existsSync(file) || previous[line.id] !== signature(line)) {
          const run = takeFor(language, line.id).run
          toAAC(await speak(voiceId, language, run ? countingRun(language, line) : line), file, { lastWordOnly: run })
          made += 1
        }
        ready[line.id] = signature(line)
      }, () => {
        manifest.languages[language] = { voice: voiceId, clips: { ...previous, ...ready } }
        fs.writeFileSync(manifestFile, JSON.stringify(manifest, null, 1))
      })
      manifest.languages[language] = { voice: voiceId, clips: ready }
      fs.writeFileSync(manifestFile, JSON.stringify(manifest, null, 1))
      console.log(`${language}: ${lines.length} clips, ${made} made now`)
    }
    return
  }
  if (command === 'retake') {
    const voices = JSON.parse(fs.readFileSync(voicesFile, 'utf8'))
    const manifestFile = path.join(here, 'manifest.json')
    const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'))
    for (const key of args) {
      const [language, id] = key.split('/')
      const line = linesFor(language).find((candidate) => candidate.id === id)
      if (!line) throw new Error(`No line ${key}`)
      const file = path.join(resources, language, `${id}.m4a`)
      // Two plain takes with other seeds, then counting runs.
      const runLine = countingRun(language, line)
      let fixed = false
      for (let attempt = 1; attempt <= 6 && !fixed; attempt += 1) {
        const takeSeed = seed + attempt * 101
        const candidate = `${file}.take.m4a`
        const run = Boolean(runLine) && attempt > 2
        toAAC(await speak(voices[language], language, run ? runLine : line, takeSeed), candidate, { lastWordOnly: run })
        if (soundsWrong(candidate)) { fs.rmSync(candidate); continue }
        fs.renameSync(candidate, file)
        retakes[key] = { seed: takeSeed, run }
        manifest.languages[language].clips[id] = signatureOf(voices[language], retakes[key], line)
        fs.writeFileSync(retakesFile, JSON.stringify(retakes, null, 1))
        fs.writeFileSync(manifestFile, JSON.stringify(manifest, null, 1))
        fixed = true
        console.log(`${key}: clean with seed ${takeSeed}${run ? ' from a counting run' : ''}`)
      }
      if (!fixed) console.log(`${key}: still doubled after 6 takes, kept the original`)
    }
    return
  }
  throw new Error('Usage: generate.mjs voices [lang] | audition <out> <lang> <voiceId…> | build [lang…] | retake <lang/id…>')
}

main().catch((error) => {
  console.error(error.message)
  process.exit(1)
})
