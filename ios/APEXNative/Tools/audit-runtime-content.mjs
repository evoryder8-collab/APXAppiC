import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url))
const repository = path.resolve(toolsDirectory, '../../..')
const stringsFile = path.join(repository, 'ios/APEXNative/APEX/Resources/ro.lproj/Localizable.strings')

const localized = new Set()
for (const line of fs.readFileSync(stringsFile, 'utf8').split('\n')) {
  const match = line.match(/^"((?:\\.|[^"\\])*)"\s*=/)
  if (match) localized.add(match[1].replaceAll('\\"', '"').replaceAll('\\n', '\n').replaceAll('\\\\', '\\'))
}

function stringsFromTypeScript(file) {
  const source = fs.readFileSync(file, 'utf8')
  const values = new Set()

  for (let index = 0; index < source.length;) {
    if (source[index] === '/' && source[index + 1] === '/') {
      index = source.indexOf('\n', index + 2)
      if (index < 0) break
      continue
    }
    if (source[index] === '/' && source[index + 1] === '*') {
      const end = source.indexOf('*/', index + 2)
      index = end < 0 ? source.length : end + 2
      continue
    }

    const quote = source[index]
    if (quote !== '"' && quote !== "'" && quote !== '`') {
      index += 1
      continue
    }

    let value = ''
    let interpolated = false
    let cursor = index + 1
    for (; cursor < source.length; cursor += 1) {
      const character = source[cursor]
      if (character === '\\') {
        const escaped = source[cursor + 1]
        const replacements = { n: '\n', r: '\r', t: '\t', b: '\b', f: '\f', v: '\v' }
        value += replacements[escaped] ?? escaped ?? ''
        cursor += 1
      } else if (character === quote) {
        break
      } else {
        if (quote === '`' && character === '$' && source[cursor + 1] === '{') interpolated = true
        value += character
      }
    }
    if (cursor < source.length && !interpolated) values.add(value)
    index = cursor + 1
  }
  return values
}

const ignored = new Set([
  'male', 'female', 'clock', 'training', 'main', 'transition', 'recomp', 'bulk', 'moderate', 'very', 'extra',
  'legs_a', 'legs_b', 'push', 'pull', 'upper', 'mobility', 'fix', 't25', 'full', 'lite', 'max', 'reps',
  'minutes', 'seconds', 'advanced', 'constantine', 'june', 'matthew', 'programs', 'program_days', 'exercises',
  'Constantine', 'June', 'Matthew Hua',
])

function looksVisible(value) {
  if (value.length < 3 || localized.has(value) || ignored.has(value)) return false
  if (value.startsWith('../') || value.startsWith('./')) return false
  if (/^[0-9.:+~–-]+(?:\s*(?:g|mg|ml|IU|kg))?$/.test(value)) return false
  if (/^[a-z0-9_:-]+$/.test(value) && !value.includes(' ')) return false
  if (/^[0-9a-f-]{16,}$/i.test(value)) return false
  if (/^#[0-9a-f]{3,8}$/i.test(value) || /^rgba?\(/i.test(value)) return false
  return /[A-Za-z]/.test(value)
}

const files = ['src/data/seed.ts', 'src/data/personaSeeds.ts', 'src/lib/activity.ts']
const values = new Set(files.flatMap((file) => [...stringsFromTypeScript(path.join(repository, file))]))
const missing = [...values].filter(looksVisible).sort((a, b) => a.localeCompare(b, 'en'))

console.log(`Runtime seed strings without an exact native translation: ${missing.length}`)
for (const value of missing) console.log(`- ${JSON.stringify(value)}`)
