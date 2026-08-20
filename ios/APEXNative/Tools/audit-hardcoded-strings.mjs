/*
 * Fails if a user-facing string is written as a bare literal.
 *
 * This is the check that would have prevented the app spending months looking
 * half-translated: 301 strings were passed straight to Text, Label, Button and
 * the rest, so they never consulted the translation tables at all. Most of them
 * already had Romanian and Thai waiting unused.
 *
 * Run before adding a language, and in CI:
 *   node ios/APEXNative/Tools/audit-hardcoded-strings.mjs
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const ROOT = new URL('../APEX', import.meta.url).pathname

/* Brand names and machine identifiers are the same in every language. */
const ALLOWED = new Set(['APEX', 'Orbit', 'Europe/Zurich', 'kcal', 'km', 'kg'])

const CONSTRUCTORS = [
  [/\bText\(\s*"((?:[^"\\]|\\.)+)"\s*\)/g, 'Text'],
  [/\bLabel\(\s*"((?:[^"\\]|\\.)+)"\s*,\s*systemImage:/g, 'Label'],
  [/\bButton\(\s*"((?:[^"\\]|\\.)+)"\s*[,)]/g, 'Button'],
  [/\.navigationTitle\(\s*"((?:[^"\\]|\\.)+)"\s*\)/g, 'navigationTitle'],
  [/\bTextField\(\s*"((?:[^"\\]|\\.)+)"\s*,/g, 'TextField'],
  [/\bToggle\(\s*"((?:[^"\\]|\\.)+)"\s*,/g, 'Toggle'],
]

function swiftFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return swiftFiles(path)
    return path.endsWith('.swift') ? [path] : []
  })
}

/* A lowercase run with no spaces is an SF Symbol or an identifier, not prose. */
const isProse = (text) =>
  /[a-zA-Z]/.test(text) && !/^[a-z0-9._-]+$/.test(text) && !text.includes('\\(')

const findings = []
for (const file of swiftFiles(ROOT)) {
  const source = readFileSync(file, 'utf8')
  for (const [pattern, kind] of CONSTRUCTORS) {
    for (const match of source.matchAll(pattern)) {
      const text = match[1]
      if (!isProse(text) || ALLOWED.has(text)) continue
      const line = source.slice(0, match.index).split('\n').length
      findings.push(`${file.replace(ROOT, 'APEX')}:${line}  ${kind}("${text}")`)
    }
  }
}

if (findings.length > 0) {
  console.error(`${findings.length} user-facing strings bypass translation:\n`)
  for (const finding of findings.slice(0, 40)) console.error('  ' + finding)
  if (findings.length > 40) console.error(`  ... and ${findings.length - 40} more`)
  console.error('\nWrap each in language.text(...) so it reaches the tables.')
  process.exit(1)
}
console.log('no hardcoded user-facing strings')
