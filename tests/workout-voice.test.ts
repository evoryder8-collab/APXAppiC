import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

// @ts-expect-error plain ES module without type declarations
import { boostKinds, groupLetters, linesFor, maxCount, maxGroupPosition, maxSets, setNouns, voiceLanguages } from '../ios/APEXNative/Tools/workout-voice/lines.mjs'

const read = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8')
const player = read('../ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift')
const voice = read('../ios/APEXNative/APEX/Features/Training/WorkoutVoice.swift')
const generator = read('../ios/APEXNative/Tools/workout-voice/generate.mjs')
const server = read('../supabase/functions/workout-voice/index.ts')

test('every language records the same lines, each once, with an acting tag', () => {
  const english = linesFor('en').map((line: { id: string }) => line.id)
  assert.equal(new Set(english).size, english.length)
  for (const language of voiceLanguages) {
    const lines = linesFor(language) as { id: string; text: string }[]
    assert.deepEqual(lines.map((line) => line.id), english, language)
    for (const line of lines) {
      assert.match(line.text, /^\[[a-z ,-]+\] \S/u, `${language} ${line.id} starts with one tag`)
      assert.doesNotMatch(line.text.replace(/^\[[^\]]+\]/u, ''), /[[\]<>]|\d/u, `${language} ${line.id} has no stray tag, markup or digit`)
    }
  }
})

test('every line the player can ask for is recorded', () => {
  const ids = new Set(linesFor('en').map((line: { id: string }) => line.id))
  for (const [, id] of player.matchAll(/\.line\("([a-z.]+)"/g)) assert.ok(ids.has(id), id)
  for (let n = 1; n <= maxCount; n += 1) {
    assert.ok(ids.has(`count.${n}`) && ids.has(`count.${n}.push`), `count ${n}`)
  }
  for (const noun of setNouns) {
    for (let total = 1; total <= maxSets; total += 1) {
      for (let n = 1; n <= total; n += 1) assert.ok(ids.has(`set.${noun}.${n}.${total}`))
    }
  }
  for (const letter of groupLetters) {
    for (let n = 1; n <= maxGroupPosition; n += 1) assert.ok(ids.has(`group.${letter}${n}`))
  }
  // The app's own limits match what was recorded.
  assert.match(voice, /\["set", "hold", "round", "exercise"\]\.contains\(noun\) && \(1\.\.\.total\)\.contains\(number\) && total <= 10/)
  assert.match(player, new RegExp(`if voiceOn, rep <= ${maxCount} \\{`))
})

test('every pep talk the player asks for is recorded, acted the same way in every language', () => {
  const english = new Map(linesFor('en').map((line: { id: string; text: string }) => [line.id, line.text]))
  const tagOf = (text: string) => text.match(/^\[[^\]]+\]/u)?.[0]
  for (const language of voiceLanguages) {
    for (const line of linesFor(language) as { id: string; text: string }[]) {
      if (line.id.startsWith('boost.')) assert.equal(tagOf(line.text), tagOf(english.get(line.id) ?? ''), `${language} ${line.id}`)
    }
  }
  const choice = player.slice(player.indexOf('func boostKind'), player.indexOf('func endCurrentSet'))
  const asked = new Set([...choice.matchAll(/return "([a-z]+)"/g), ...player.matchAll(/VoicePart\.boost\("([a-z]+)"\)/g)].map((m) => m[1]))
  assert.deepEqual([...asked].sort(), [...boostKinds].sort())
  for (const kind of boostKinds) assert.ok(english.has(`boost.${kind}.20`), `${kind} has at least twenty takes`)
})

test('names voiced on the server sound like the recorded lines', () => {
  for (const setting of ["model = 'eleven_v4'", 'stability: 0.45, similarity_boost: 0.8, use_speaker_boost: true', 'seed = 7_220']) {
    assert.ok(generator.includes(setting), `generator: ${setting}`)
    assert.ok(server.includes(setting), `server: ${setting}`)
  }
  // The key stays in the Keychain and in the function's secrets, never in the repository.
  assert.match(generator, /find-generic-password/)
  assert.match(server, /Deno\.env\.get\('ELEVENLABS_API_KEY'\)/)
  assert.doesNotMatch(generator + server, /sk_[A-Za-z0-9]{20,}/)
})
