import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import assert from 'node:assert/strict'
import { describe, it } from 'node:test'

const root = process.cwd()
const resources = join(root, 'ios/APEXNative/APEX/Resources')
const locales = ['de', 'de-CH', 'es', 'it', 'pt', 'ro', 'th', 'ja'] as const

const keys = [
  'What this session trains',
  'For this session',
  'Worth knowing',
  'Strength and bodyweight work improve when the same positions stay repeatable. Load, leverage, range and tempo can all progress the exercise; a grinding rep is not required for every useful set.',
  'Mobility work can change what range feels available now, often through tolerance and stiffness. Range that lasts also needs repeated exposure and strength near the edge you can control.',
  'Static holds, dynamic repetitions, PNF and loaded end-range work are different tools. For a prescribed static stretch, roughly 30–60 seconds is a useful working range; dynamic work fits the warm-up better.',
  'A pinch or hard joint block is not a cue to pull harder. Bone shape, the joint and its capsule can limit a position as well as muscle tolerance.',
  'Yoga here is practice, not a contest for the deepest pose. Use steady breathing and a position you can control.',
  'An isometric builds strength most strongly around the angle and task you hold. End the hold when the position or normal breathing gives way.',
  'A carry links grip, trunk control and gait under load. Reduce the load if you have to lean or shorten your steps to keep moving.',
  'Steady cardio is its own aerobic session, not a failed interval workout. Keep the prescribed effort sustainable instead of turning every session into a time trial.',
  'Recovery makes hard intervals repeatable. Start at a pace that lets the later work bouts still look like the first ones.',
  'Easy recovery work may change short-term range or soreness, but it does not break fascia, clear lactate to prevent next-day soreness, or erase training stress. Finish fresher than you started.',
  'With only a small amount of logged history, make repeatable technique the baseline today. Leave room to learn what normal effort feels like.',
  'Your recent sessions are the useful comparison. Match their clean repetitions or steady pace before you add difficulty.',
  'You have enough history to compare this session with your own pattern. Use that pattern, not somebody else’s standard, to judge today’s work.',
  'This session is already complete. Use the briefing to understand what you trained; it is not a prompt to add bonus work.',
  'You reported pain or irritation during setup. Pain is not a mobility target: reduce or stop a movement that reproduces it, and get qualified help if it persists or worsens.',
  'Your latest joint check-in was elevated. Keep the affected area away from sharp or worsening pain and adjust the session instead of testing the symptom.',
  'More range is not the goal when you already have it. Stay short of a passive end position and train control there.',
  'A broad muscle pull can be part of a stretch; tingling, burning, numbness or an electric line is not a cue to push farther. Back off and seek assessment if it persists.',
  'Pregnancy, glaucoma, fragile bones and some other conditions can require yoga modifications, especially for heat, long supine holds, inversions or forceful breath work. Use qualified guidance when any of these applies.',
] as const

function escapedForRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function decodeStringsValue(value: string): string {
  return value
    .replace(/\\n/g, '\n')
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, '\\')
}

function table(locale: typeof locales[number]): { source: string, values: Map<string, string> } {
  const source = readFileSync(join(resources, `${locale}.lproj/Localizable.strings`), 'utf8')
  const values = new Map<string, string>()
  const entry = /^"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";\s*$/gm
  for (const match of source.matchAll(entry)) {
    values.set(decodeStringsValue(match[1]), decodeStringsValue(match[2]))
  }
  return { source, values }
}

describe('session briefing copy structural and calibration contract', () => {
  it('keeps every authored briefing key present exactly once in every translated locale', () => {
    for (const locale of locales) {
      const parsed = table(locale)
      for (const key of keys) {
        const occurrences = parsed.source.match(
          new RegExp(`^"${escapedForRegex(key)}"\\s*=`, 'gm'),
        )?.length ?? 0
        assert.equal(occurrences, 1, `${locale}: ${key}`)
        const value = parsed.values.get(key)
        assert.ok(value, `${locale}: ${key}`)
        assert.notEqual(value, key, `${locale}: ${key}`)
      }
    }
  })

  it('keeps the English keys connected to the Swift source and sheet', () => {
    const engine = readFileSync(
      join(root, 'ios/APEXNative/APEX/Core/Engine/SessionBriefingKnowledge.swift'),
      'utf8',
    )
    const sheet = readFileSync(
      join(root, 'ios/APEXNative/APEX/Features/Training/SessionBriefingSheet.swift'),
      'utf8',
    )
    for (const key of keys.slice(0, 3)) assert.ok(sheet.includes(`"${key}"`))
    for (const key of keys.slice(3)) assert.ok(engine.includes(`"${key}"`))
  })

  it('keeps focused native-language calibration and myth negation intact', () => {
    const recoveryKey = keys[12]
    const expectedNegation: Record<typeof locales[number], RegExp> = {
      de: /nicht|keine/iu,
      'de-CH': /nicht|keine/iu,
      es: /\bno\b/iu,
      it: /\bnon\b/iu,
      pt: /\bnão\b/iu,
      ro: /\bnu\b/iu,
      th: /ไม่ได้/u,
      ja: /ありません|でもありません/u,
    }
    for (const locale of locales) {
      assert.match(table(locale).values.get(recoveryKey) ?? '', expectedNegation[locale])
    }

    const romanian = table('ro').values
    assert.ok(romanian.get(keys[9])?.includes('lucrează'))
    assert.ok(!romanian.get(keys[3])?.includes('funcționează'))

    const swissValues = keys.map(key => table('de-CH').values.get(key) ?? '').join('\n')
    assert.doesNotMatch(swissValues, /ß/u)
  })
})
