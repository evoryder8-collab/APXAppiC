/*
 * Reports user-facing prose that has no Romanian or Thai translation.
 *
 * This app translates at the point of display: a title is passed around as
 * English and resolved by language.text(...) when it is finally drawn. That is
 * a good pattern, but it means "is this literal wrapped?" is the wrong
 * question. GlanceMacroCard does call language.text(title), and "Protein" still
 * appeared in English inside a Romanian screen, because no table had the word.
 *
 * So this asks the question that matches the design: of every piece of prose in
 * the source, which ones would fall through to English if a table were asked
 * for them right now?
 *
 * Usage:
 *   node ios/APEXNative/Tools/audit-translation-coverage.mjs          summary
 *   node ios/APEXNative/Tools/audit-translation-coverage.mjs --list   every gap
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = new URL('../APEX', import.meta.url).pathname

const ALLOWED = new Set([
  'APEX', 'Orbit', 'Europe/Zurich', 'kcal', 'km', 'kg', 'g', 'ml', 'CHF',
  'HealthKit', 'Apple', 'Localizable', 'lproj',
  /* Names of people, which are not translated in any language. */
  'Constantine', 'June', 'Matthew Hua', 'Iulian-Andrei',
  /* Language names, written in their own language by definition. */
  'English', 'Deutsch', 'Schweizerdeutsch', 'Italiano', 'Español',
  'Português', 'Română',
])

/* Not interface: transport, storage and test scaffolding. */
const SKIP = ['/Core/Networking/', '/Core/Persistence/', 'APEXDebugFixture.swift']

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return swiftFiles(path)
    return path.endsWith('.swift') ? [path] : []
  })
}

function strip(source) {
  return source
    .replace(/"""[\s\S]*?"""/g, ' ')
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ')
    .replace(/\.accessibilityIdentifier\(\s*"(?:[^"\\\n]|\\.)*"\s*\)/g, ' ')
    .replace(/\.(?:from|eq|order|upsert|select|onConflict|forKey|value)\(\s*"(?:[^"\\\n]|\\.)*"/g, ' ')
    .replace(/case\s+\w+\s*=\s*"(?:[^"\\\n]|\\.)*"/g, ' ')
    .replace(/(?:UserDefaults|defaults)\.\w+\([^)]*"(?:[^"\\\n]|\\.)*"/g, ' ')
    .replace(/forResource:\s*"(?:[^"\\\n]|\\.)*"/g, ' ')
    .replace(/system(?:Image|Name):\s*"(?:[^"\\\n]|\\.)*"/g, ' ')
    .replace(/String\(format:\s*"(?:[^"\\\n]|\\.)*"/g, ' ')
    .replace(/#"(?:[^"\\\n]|\\.)*"#/g, ' ')
    /* Scripts injected into the figure's web view are code, not copy. */
    .replace(/"[^"\n]*(?:document\.|window\.|getElementById|style\.)[^"\n]*"/g, ' ')
    /* Date and time format patterns are read by the formatter, not by a person. */
    .replace(/"[A-Za-z]{0,6}(?:EEEE|LLLL|MMM|HH:mm|yyyy)[A-Za-z ,:.]*"/g, ' ')
}

function isProse(text) {
  if (ALLOWED.has(text) || text.length < 3) return false
  if (/\\\(/.test(text)) return false
  if (/^[a-z0-9._\-/:]+$/.test(text)) return false
  /* Thai script or Romanian diacritics mean this string IS a translation, sitting
     in Swift as a value. Counting a translation as an untranslated key was most
     of the first run's noise. */
  if (/[\u0E00-\u0E7F]/.test(text)) return false
  if (/[ăâîșțĂÂÎȘȚ]/.test(text)) return false
  /* Matching patterns, not copy. */
  if (/\\\\b|\.\*/.test(text)) return false
  if (/^[A-Z0-9_]+$/.test(text) && !text.includes(' ')) return true
  if (!/[a-zA-Z]/.test(text)) return false
  return /\s/.test(text) || /^[A-Z]/.test(text)
}

/* The typed keys translate inside Swift rather than through a table: a
   LocalizedKey case carries its own English, Thai and Romanian. Those English
   values are already covered and must not be reported as gaps. */
function typedKeyEnglish() {
  const source = readFileSync(join(ROOT, 'Core/DesignSystem/APEXLocalization.swift'), 'utf8')
  const byCase = new Map()
  for (const match of source.matchAll(/case\s*\(\.(\w+),\s*\.(\w+)\):\s*"((?:[^"\\\n]|\\.)*)"/g)) {
    const [, key, language, value] = match
    if (!byCase.has(key)) byCase.set(key, {})
    byCase.get(key)[language] = value
  }
  const covered = new Set()
  for (const languages of byCase.values()) {
    if (languages.english && languages.thai && languages.romanian) covered.add(languages.english)
  }
  return covered
}

/* The .strings tables, read as key/value pairs. */
function table(language) {
  const path = join(ROOT, 'Resources', `${language}.lproj`, 'Localizable.strings')
  const source = readFileSync(path, 'utf8')
  const keys = new Set()
  for (const match of source.matchAll(/^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;/gm)) {
    keys.add(match[1])
  }
  return keys
}

const languages = ['ro', 'th']
const tables = Object.fromEntries(languages.map((code) => [code, table(code)]))
const typedKeys = typedKeyEnglish()

const prose = new Map()
for (const file of swiftFiles(ROOT)) {
  if (SKIP.some((part) => file.includes(part))) continue
  const stripped = strip(readFileSync(file, 'utf8'))
  for (const match of stripped.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)) {
    const text = match[1]
    if (!isProse(text)) continue
    if (!prose.has(text)) prose.set(text, file.replace(ROOT, 'APEX'))
  }
}

const gaps = []
for (const [text, file] of prose) {
  if (typedKeys.has(text)) continue
  const missing = languages.filter((code) => !tables[code].has(text))
  if (missing.length > 0) gaps.push({ text, file, missing })
}

console.log(`${prose.size} distinct user-facing strings in source`)
for (const code of languages) {
  const covered = [...prose.keys()]
    .filter((text) => tables[code].has(text) || typedKeys.has(text)).length
  const percent = ((covered / prose.size) * 100).toFixed(1)
  console.log(`  ${code}: ${covered}/${prose.size} translated (${percent}%)`)
}

if (process.argv.includes('--list')) {
  console.log('\nUntranslated:')
  for (const gap of gaps) console.log(`  [${gap.missing.join(',')}] ${gap.file}  "${gap.text}"`)
}
process.exit(gaps.length > 0 ? 1 : 0)
