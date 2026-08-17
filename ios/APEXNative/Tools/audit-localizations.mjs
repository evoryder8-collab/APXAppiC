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

const patterns = [
  /\bText\("((?:\\.|[^"\\])*)"/g,
  /\bButton\("((?:\\.|[^"\\])*)"/g,
  /\bLabel\("((?:\\.|[^"\\])*)"/g,
  /\bNavigationLink\("((?:\\.|[^"\\])*)"/g,
  /\bTextField\("((?:\\.|[^"\\])*)"/g,
  /\bPicker\("((?:\\.|[^"\\])*)"/g,
  /\bSection\("((?:\\.|[^"\\])*)"/g,
  /\.navigationTitle\("((?:\\.|[^"\\])*)"/g,
  /\.confirmationDialog\("((?:\\.|[^"\\])*)"/g,
  /\bContentUnavailableView\("((?:\\.|[^"\\])*)"/g,
  /(?:\blanguage|LanguageState\.shared)\.(?:text|format)\("((?:\\.|[^"\\])*)"/g,
]

const missing = new Map()
const interpolated = new Map()
for (const file of files(sourceRoot)) {
  const source = fs.readFileSync(file, 'utf8')
  for (const pattern of patterns) {
    for (const match of source.matchAll(pattern)) {
      const value = match[1].replaceAll('\\"', '"').replaceAll('\\n', '\n')
      const target = value.includes('\\(') ? interpolated : missing
      if (target === missing && localized.has(value)) continue
      const locations = target.get(value) ?? []
      locations.push(path.relative(nativeRoot, file))
      target.set(value, locations)
    }
  }
}

console.log(`Missing static keys: ${missing.size}`)
for (const [value, locations] of [...missing].sort(([a], [b]) => a.localeCompare(b))) {
  console.log(`- ${JSON.stringify(value)} :: ${[...new Set(locations)].join(', ')}`)
}
console.log(`\nInterpolated literals needing an explicit native translation path: ${interpolated.size}`)
for (const [value, locations] of [...interpolated].sort(([a], [b]) => a.localeCompare(b))) {
  console.log(`- ${JSON.stringify(value)} :: ${[...new Set(locations)].join(', ')}`)
}
