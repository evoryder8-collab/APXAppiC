import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url))
const nativeRoot = path.resolve(toolsDirectory, '..')
const repository = path.resolve(nativeRoot, '../..')

function files(directory, extensions) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const location = path.join(directory, entry.name)
    if (entry.isDirectory()) return files(location, extensions)
    return extensions.some((extension) => entry.name.endsWith(extension)) ? [location] : []
  })
}

function source(directory, extensions) {
  return files(directory, extensions).map((file) => fs.readFileSync(file, 'utf8')).join('\n')
}

function matches(body, patterns) {
  const result = new Set()
  for (const pattern of patterns) {
    for (const match of body.matchAll(pattern)) result.add(match[1])
  }
  return result
}

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

const nativeSourceRoot = path.join(nativeRoot, 'APEX')
const nativeSwiftFiles = files(nativeSourceRoot, ['.swift']).map((file) => ({
  file,
  relative: path.relative(nativeRoot, file),
  body: fs.readFileSync(file, 'utf8'),
}))
const nativeSource = nativeSwiftFiles.map(({ body }) => body).join('\n')
const webSource = source(path.join(repository, 'src'), ['.ts', '.tsx'])
const migrationFiles = files(path.join(repository, 'supabase/migrations'), ['.sql'])
const migrations = migrationFiles.map((file) => ({ file, body: fs.readFileSync(file, 'utf8') }))
const migrationSource = migrations.map(({ body }) => body).join('\n')

const nativeReadTables = matches(nativeSource, [/\.from\("([a-z0-9_]+)"\)/g])
const nativeMutationTables = matches(nativeSource, [/table:\s*"([a-z0-9_]+)"/g])
const nativeTables = new Set([...nativeReadTables, ...nativeMutationTables])
const webTables = matches(webSource, [
  /\.from\(['"]([a-z0-9_]+)['"]\)/g,
  /\|\s*['"]([a-z0-9_]+)['"]/g,
  /:\s*['"]([a-z][a-z0-9_]+)['"]/g,
])
const createdTables = matches(migrationSource, [
  /create\s+table\s+if\s+not\s+exists\s+(?:public\.)?([a-z0-9_]+)/gi,
])

for (const table of nativeTables) {
  assert(createdTables.has(table), `Native client references ${table}, but no idempotent CREATE TABLE migration exists.`)
}

const sharedTables = new Set(['activity_types', 'foods'])
for (const table of nativeTables) {
  if (sharedTables.has(table)) continue
  const policyMigration = migrations.find(({ body }) =>
    body.includes(table) &&
    /enable\s+row\s+level\s+security/i.test(body) &&
    /auth\.uid\(\)/i.test(body)
  )
  assert(policyMigration, `${table} is used by native APEX without a migration containing RLS and auth.uid() ownership.`)
}

const activityMigration = migrations.find(({ body }) => /create\s+table\s+if\s+not\s+exists\s+activity_types/i.test(body))?.body ?? ''
assert(/create\s+policy\s+"authenticated_read"\s+on\s+activity_types/i.test(activityMigration), 'activity_types must keep its authenticated read policy.')
assert(/grant\s+select\s+on\s+table\s+activity_types\s+to\s+authenticated/i.test(activityMigration), 'activity_types must remain readable by authenticated clients.')
assert(!/grant\s+(?:insert|update|delete|all)[^;]*activity_types[^;]*authenticated/i.test(activityMigration), 'activity_types must remain read-only for authenticated clients.')

const foodsMigration = migrations.find(({ body }) => /create\s+table\s+if\s+not\s+exists\s+foods/i.test(body))?.body ?? ''
assert(/alter\s+table\s+foods\s+enable\s+row\s+level\s+security/i.test(foodsMigration), 'foods must keep RLS enabled.')
assert(/visible_foods/i.test(foodsMigration) && /auth\.uid\(\)/i.test(foodsMigration), 'foods must keep its public-cache/private-owner visibility boundary.')

const missingWebAwareness = [...nativeMutationTables].filter((table) => !webTables.has(table))
assert(
  missingWebAwareness.length === 0,
  `Native mutations are not represented in the browser client: ${missingWebAwareness.join(', ')}`
)

/* The native app has four deliberately bounded WebKit files. They render only
   bundled hydration and muscle-map assets; widening this fence is a reviewed
   architecture decision, never evidence that the app may become a web shell. */
const allowedWebKitFiles = new Set([
  'APEX/Features/Portal/HydrationFigureWebView.swift',
  'APEX/Features/Training/MuscleMapAssetHandler.swift',
  'APEX/Features/Training/MuscleMapCard.swift',
  'APEX/Features/Training/MuscleMapView.swift',
])
const actualWebKitFiles = new Set(
  nativeSwiftFiles
    .filter(({ body }) => body.split(/\r?\n/).some((line) => line.trim() === 'import WebKit'))
    .map(({ relative }) => relative)
)
assert(
  actualWebKitFiles.size === allowedWebKitFiles.size
    && [...actualWebKitFiles].every((file) => allowedWebKitFiles.has(file)),
  `Native WebKit boundary changed. Expected ${[...allowedWebKitFiles].sort().join(', ')}; found ${[...actualWebKitFiles].sort().join(', ')}.`
)
const remoteWebKitNavigation = nativeSwiftFiles
  .filter(({ relative }) => allowedWebKitFiles.has(relative))
  .filter(({ body }) => /URL\s*\(\s*string:\s*"https?:\/\//.test(body))
  .map(({ relative }) => relative)
assert(
  remoteWebKitNavigation.length === 0,
  `Native WebKit renderers must not navigate to remote web apps: ${remoteWebKitNavigation.join(', ')}`
)
const hydrationRenderer = nativeSwiftFiles.find(({ relative }) => relative.endsWith('HydrationFigureWebView.swift'))?.body ?? ''
assert(
  hydrationRenderer.includes('Bundle.main.url') && hydrationRenderer.includes('loadFileURL'),
  'Hydration WebKit must remain a bundled-file renderer.'
)
const muscleRenderer = nativeSwiftFiles.find(({ relative }) => relative.endsWith('MuscleMapAssetHandler.swift'))?.body ?? ''
assert(
  muscleRenderer.includes('static let scheme = "apexasset"') && muscleRenderer.includes('Bundle.main.url'),
  'Muscle-map WebKit must remain on the bundled apexasset scheme.'
)
assert(!nativeSource.includes('service_role'), 'A service-role credential must never ship in the iOS client.')

console.log(`Native Supabase tables: ${nativeTables.size}`)
console.log(`Native mutation tables mirrored by web: ${nativeMutationTables.size}`)
console.log(`Idempotent migrations checked: ${migrationFiles.length}`)
console.log('RLS owner boundaries: PASS')
console.log('Shared activity catalog read-only boundary: PASS')
console.log('Web/native data-contract compatibility: PASS')
