/*
 * Fails if user-facing prose is written as a bare literal.
 *
 * The first version of this only matched a literal that was the whole argument,
 * as in Text("Save"). That let through every other shape prose actually takes:
 *
 *   Text(isLogged ? "LOGGED" : "SCHEDULED")   a ternary inside the call
 *   alertMessage = "Food saved on this iPhone"  a string assigned, then shown
 *   let options = [("muscle", "Build muscle")]  labels in a table
 *   header("Wearable activity")                 prose passed to a helper
 *
 * So the app passed this check while still showing English inside a Romanian
 * interface. This version works the other way round: it strips out everything
 * that is provably fine, then treats whatever prose remains as suspect. That
 * produces the occasional false positive, which is the right direction for a
 * check whose whole job is to stop a class of bug from coming back.
 *
 * Run before adding a language, and in CI:
 *   node ios/APEXNative/Tools/audit-hardcoded-strings.mjs
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = new URL('../APEX', import.meta.url).pathname

/* Brand names, units and machine identifiers read the same in every language. */
const ALLOWED = new Set([
  'APEX', 'Orbit', 'Europe/Zurich', 'kcal', 'km', 'kg', 'g', 'ml', 'CHF',
  'Apple Health', 'HealthKit', 'Apple', 'Localizable', 'lproj',
])

/* Files that hold no interface. Engines and models carry identifiers, database
   column names and evidence citations, none of which are shown as prose. */
const SKIP_DIRECTORIES = ['/Core/Networking/', '/Core/Persistence/']
const SKIP_FILES = ['APEXDebugFixture.swift']

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return swiftFiles(path)
    return path.endsWith('.swift') ? [path] : []
  })
}

/* Remove what cannot be a hardcoded user-facing string, in this order, so the
   only literals left are ones nobody has routed through the tables. */
function strip(source) {
  return source
    /* Multi-line literals first. They are the only place a newline can sit
       inside a string, and leaving them in makes every later quote pair up
       with the wrong partner. */
    .replace(/"""[\s\S]*?"""/g, ' ')
    /* Comments next: they are full of prose by design. */
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ')
    /* Anything already going through the translation layer. */
    .replace(/language\.(?:text|format)\(\s*"(?:[^"\\]|\\.)*"/g, ' ')
    /* Accessibility identifiers are for tests, never read by a person. */
    .replace(/\.accessibilityIdentifier\(\s*"(?:[^"\\]|\\.)*"\s*\)/g, ' ')
    /* Keys, not copy: dictionary lookups, decoding, database columns. */
    .replace(/\.(?:from|eq|order|upsert|select|onConflict|forKey|value)\(\s*"(?:[^"\\]|\\.)*"/g, ' ')
    .replace(/case\s+\w+\s*=\s*"(?:[^"\\]|\\.)*"/g, ' ')
    .replace(/(?:UserDefaults|defaults)\.\w+\([^)]*"(?:[^"\\]|\\.)*"/g, ' ')
    .replace(/forResource:\s*"(?:[^"\\]|\\.)*"/g, ' ')
    .replace(/systemImage:\s*"(?:[^"\\]|\\.)*"/g, ' ')
    .replace(/systemName:\s*"(?:[^"\\]|\\.)*"/g, ' ')
    .replace(/String\(format:\s*"(?:[^"\\]|\\.)*"/g, ' ')
    .replace(/#"(?:[^"\\]|\\.)*"#/g, ' ')
}

/* Prose is something a person reads: it has a space, or it is a capitalised
   word. An identifier like "pull_day" or an SF Symbol like "bell.badge" is not. */
function isProse(text) {
  if (ALLOWED.has(text) || text.length < 3) return false
  if (/\\\(/.test(text)) return false                 // interpolation, checked elsewhere
  if (/^[a-z0-9._\-/:]+$/.test(text)) return false    // identifier or symbol name
  if (/^[A-Z0-9_]+$/.test(text) && !text.includes(' ')) {
    return true                                       // SHOUTED labels are prose
  }
  if (!/[a-zA-Z]/.test(text)) return false
  return /\s/.test(text) || /^[A-Z]/.test(text)
}

const findings = []
for (const file of swiftFiles(ROOT)) {
  if (SKIP_DIRECTORIES.some((part) => file.includes(part))) continue
  if (SKIP_FILES.some((name) => file.endsWith(name))) continue

  const source = readFileSync(file, 'utf8')
  const stripped = strip(source)
  for (const match of stripped.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)) {
    const text = match[1]
    if (!isProse(text)) continue
    const line = stripped.slice(0, match.index).split('\n').length
    findings.push(`${file.replace(ROOT, 'APEX')}:${line}  "${text}"`)
  }
}

if (findings.length > 0) {
  console.error(`${findings.length} user-facing strings bypass translation:\n`)
  const limit = process.env.AUDIT_FULL ? findings.length : 60
  for (const finding of findings.slice(0, limit)) console.error('  ' + finding)
  if (findings.length > limit) console.error(`  ... and ${findings.length - limit} more`)
  console.error('\nWrap each in language.text(...) so it reaches the tables.')
  process.exit(1)
}
console.log('no hardcoded user-facing strings')
