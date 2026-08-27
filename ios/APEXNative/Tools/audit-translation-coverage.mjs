/*
 * Reports user-facing prose coverage for every language offered by APEX.
 *
 * This app translates at the point of display: a title is passed around as
 * English and resolved by language.text(...) when it is finally drawn. That is
 * a good pattern, but it means "is this literal wrapped?" is the wrong
 * question. GlanceMacroCard does call language.text(title), and "Protein" still
 * appeared in English inside a Romanian screen, because no table had the word.
 *
 * So this asks the question that matches the design: of every piece of prose in
 * the real runtime corpus (source literals, typed keys and table-only legacy
 * copy), which ones would fall through to English if a table were asked for
 * them right now?
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
  /* Protocol and export syntax, never rendered as interface copy. */
  'Access-Control-Allow-Origin',
  /* Names of people, which are not translated in any language. */
  'Constantine', 'June', 'Matthew Hua', 'Iulian-Andrei',
  /* Language names, written in their own language by definition. */
  'English', 'Deutsch', 'Schweizerdeutsch', 'Italiano', 'Español',
  'Português', 'Română',
])

/* Not interface: transport, storage and test scaffolding. */
const SKIP = [
  '/Core/Networking/', '/Core/Persistence/', 'APEXDebugFixture.swift',
  /* This file contains the translations as switch values. Its English typed
     keys are added explicitly below, so translations never become sources. */
  '/Core/DesignSystem/APEXLocalization.swift',
]

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return swiftFiles(path)
    return path.endsWith('.swift') ? [path] : []
  })
}

function stripSwiftInterpolations(source) {
  let output = ''
  let index = 0
  while (index < source.length) {
    if (source[index] !== '\\' || source[index + 1] !== '(') {
      output += source[index]
      index += 1
      continue
    }

    let depth = 1
    let inString = false
    index += 2
    while (index < source.length && depth > 0) {
      const character = source[index]
      if (character === '"' && source[index - 1] !== '\\') {
        inString = !inString
      } else if (!inString && character === '(') {
        depth += 1
      } else if (!inString && character === ')') {
        depth -= 1
      }
      index += 1
    }
    output += ' '
  }
  return output
}

function strip(source) {
  const stripped = source
    .replace(/#if\s+DEBUG[\s\S]*?#endif/g, ' ')
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
    /* Country-code and other private lookup sets are storage, not labels. */
    .replace(/private\s+static\s+let\s+\w+\s*:\s*Set<String>\s*=\s*\[[\s\S]*?\]\s*/g, ' ')
    .replace(/#"(?:[^"\\\n]|\\.)*"#/g, ' ')
    /* Scripts injected into the figure's web view are code, not copy. */
    .replace(/"[^"\n]*(?:document\.|window\.|getElementById|style\.)[^"\n]*"/g, ' ')
    /* Date and time format patterns are read by the formatter, not by a person. */
    .replace(/"[^"\n]*(?:EEEE|LLLL|MMM|HH:mm|yyyy)[^"\n]*"/g, ' ')
  return stripSwiftInterpolations(stripped)
}

function isProse(text) {
  const candidate = text.trim()
  if (ALLOWED.has(candidate) || candidate.length < 3) return false
  if (/^[0-9A-F]{8}(?:-[0-9A-F]{4}){3}-[0-9A-F]{12}$/i.test(candidate)) return false
  if (/\\\(/.test(candidate)) return false
  if (/^[a-z0-9._\-/:]+$/.test(candidate)) return false
  if (/^(?:apex[.:_-]|ios-|activity-log:|legacy:|food:|healthkit:|imported:)/i.test(candidate)) return false
  if (/\.(?:gpx|jpe?g|png|json|csv)$/i.test(candidate)) return false
  if (/^<[^>]+>/.test(candidate)) return false
  if (/^MuscleMap\.(?:facing|spin|xray)\(/.test(candidate)) return false
  /* Thai script or Romanian diacritics mean this string IS a translation, sitting
     in Swift as a value. Counting a translation as an untranslated key was most
     of the first run's noise. */
  if (/[\u0E00-\u0E7F]/.test(candidate)) return false
  if (/[ăâîșțĂÂÎȘȚ]/.test(candidate)) return false
  /* Matching patterns, not copy. */
  if (/\\\\b|\.\*|\[\^[a-z]/.test(candidate)) return false
  if (/^_*[A-Z0-9]+(?:_[A-Z0-9]+)+_*$/.test(candidate)) return false
  if (/^[A-Z0-9_]+$/.test(candidate) && !candidate.includes(' ')) return true
  if (!/[a-zA-Z]/.test(candidate.replace(/\\[nrt]/g, ''))) return false
  return /\s/.test(candidate) || /^[A-Z]/.test(candidate)
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
  const entries = new Map()
  for (const match of source.matchAll(/^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;/gm)) {
    entries.set(match[1], match[2])
  }
  return entries
}

const languages = ['en', 'de', 'de-CH', 'it', 'es', 'pt', 'ja', 'ro', 'th']
const translatedLanguages = languages.filter((code) => code !== 'en')
const tables = Object.fromEntries(translatedLanguages.map((code) => [code, table(code)]))
const typedKeys = typedKeyEnglish()
const exerciseCatalog = JSON.parse(
  readFileSync(join(ROOT, 'Resources/exercise-catalog.json'), 'utf8'),
)
const exerciseNames = new Set(exerciseCatalog.exercises.map((exercise) => exercise.name))

function hasTranslation(language, text) {
  if (language === 'en') return true
  if (tables[language].has(text)) return true
  /* Romanian and Thai are authored inline for the original typed-key API.
     Every later language must carry its own table entry for the English key. */
  return (language === 'ro' || language === 'th') && typedKeys.has(text)
}

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
for (const text of typedKeys) {
  if (!prose.has(text)) prose.set(text, 'APEX/Core/DesignSystem/APEXLocalization.swift')
}

/* Runtime tables contain copy from older screens and server-authored plans that
   does not appear as a literal in the current Swift tree. It is still visible
   to a person and therefore belongs in the denominator. Exercise names are the
   sole policy-owned exception: every one is classified and sourced separately
   in docs/localisation/policies and exercise-catalog.json. */
const corpus = new Map(prose)
for (const [language, entries] of Object.entries(tables)) {
  for (const text of entries.keys()) {
    if (!isProse(text) || exerciseNames.has(text)) continue
    if (!corpus.has(text)) corpus.set(text, `APEX/Resources/${language}.lproj/Localizable.strings`)
  }
}

const gaps = []
for (const [text, file] of corpus) {
  const missing = translatedLanguages.filter((code) => !hasTranslation(code, text))
  if (missing.length > 0) gaps.push({ text, file, missing })
}

const coverage = Object.fromEntries(languages.map((code) => {
  const covered = [...corpus.keys()].filter((text) => hasTranslation(code, text)).length
  return [code, { covered, total: corpus.size, percent: Number(((covered / corpus.size) * 100).toFixed(1)) }]
}))

if (process.argv.includes('--json')) {
  process.stdout.write(`${JSON.stringify({
    corpusCount: corpus.size,
    sourceLiteralCount: prose.size,
    excludedExerciseCount: exerciseNames.size,
    coverage,
    gaps,
  }, null, 2)}\n`)
  process.exitCode = gaps.length > 0 ? 1 : 0
} else {
  console.log(`${corpus.size} distinct user-facing strings in runtime corpus`)
  for (const code of languages) {
    const { covered, total, percent } = coverage[code]
    console.log(`  ${code}: ${covered}/${total} translated (${percent.toFixed(1)}%)`)
  }

  if (process.argv.includes('--list')) {
    console.log('\nUntranslated:')
    for (const gap of gaps) console.log(`  [${gap.missing.join(',')}] ${gap.file}  "${gap.text}"`)
  }
  process.exitCode = gaps.length > 0 ? 1 : 0
}
