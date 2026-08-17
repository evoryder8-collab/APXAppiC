import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url))
const nativeRoot = path.resolve(toolsDirectory, '..')
const sourceRoot = path.join(nativeRoot, 'APEX')
const stringsPath = path.join(sourceRoot, 'Resources/ro.lproj/Localizable.strings')

function files(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const location = path.join(directory, entry.name)
    return entry.isDirectory() ? files(location) : entry.name.endsWith('.swift') ? [location] : []
  })
}

const localized = new Set()
for (const line of fs.readFileSync(stringsPath, 'utf8').split('\n')) {
  const match = line.match(/^"((?:\\.|[^"\\])*)"\s*=/)
  if (match) localized.add(match[1].replaceAll('\\"', '"').replaceAll('\\n', '\n').replaceAll('\\\\', '\\'))
}

const ignoredExact = new Set([
  'Matthew Hua', 'Constantine', 'June', 'Apple Health', 'APEX',
  'Supabase', 'Open Food Facts', 'FocusT25', 'SkiErg', 'APEX Orbit',
  'APEX plan', 'oat jar', 'nut mix', 'bulgur snack', 'sweet potato',
  'casein shake', ', with: ',
])

const ignoredFiles = new Set([
  // Deterministic English-only XCTest data, excluded from Release builds.
  'APEX/App/APEXDebugFixture.swift',
  'APEX/Core/DesignSystem/APEXLocalization.swift',
  'APEX/Features/Orbit/OrbitGPXService.swift',
  // Greeting variants are selected explicitly for all three languages.
  'APEX/Features/Portal/PortalHomeView.swift',
])

function potentiallyVisible(value) {
  if (value.length < 3 || localized.has(value) || ignoredExact.has(value)) return false
  // The lightweight scanner can begin inside a Swift interpolation and emit
  // only its trailing source fragment; such fragments are never UI copy.
  if (value.startsWith(')')) return false
  if (/^[a-z0-9_.:/-]+$/i.test(value)) return false
  if (/^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+$/.test(value)) return false
  if (/^(GET|POST|PATCH|DELETE|Bearer|Prefer|Content-Type|application\/json)/.test(value)) return false
  if (value.includes('\\(')) return false
  if (/^[0-9 .,:+%–—-]+$/.test(value)) return false
  return /[A-Za-z]/.test(value) && /\s/.test(value)
}

const missing = new Map()
for (const file of files(sourceRoot)) {
  const relative = path.relative(nativeRoot, file)
  if (ignoredFiles.has(relative)) continue
  const source = fs.readFileSync(file, 'utf8')
  for (const match of source.matchAll(/"((?:\\.|[^"\\])*)"/g)) {
    const value = match[1].replaceAll('\\"', '"').replaceAll('\\n', '\n')
    if (!potentiallyVisible(value)) continue
    const rows = missing.get(value) ?? []
    rows.push(relative)
    missing.set(value, rows)
  }
}

console.log(`Potential runtime Swift phrases without an exact native translation: ${missing.size}`)
for (const [value, locations] of [...missing].sort(([a], [b]) => a.localeCompare(b, 'en'))) {
  console.log(`- ${JSON.stringify(value)} :: ${[...new Set(locations)].join(', ')}`)
}
