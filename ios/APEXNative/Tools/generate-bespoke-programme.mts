/** Native delivery uses the same authored V8.5 programme as the web, not a second prescription. */
import { readFileSync, writeFileSync } from 'node:fs'
import { buildSeedData } from '../../../src/data/seed.ts'

const seed = buildSeedData('00000000-0000-4000-8000-000000000085', 'constantine')
const program = seed.programs.find(row => row.slug === 'main')!
const days = seed.program_days.filter(row => row.program_id === program.id)
const ids = new Set(days.map(row => row.id))
const manifest = {
  version: 85,
  program,
  days,
  exercises: seed.exercises.filter(row => ids.has(row.program_day_id)),
}
const output = new URL('../APEX/Resources/constantine-v85.json', import.meta.url)
const contents = JSON.stringify(manifest, null, 2) + '\n'
if (process.argv.includes('--check')) {
  if (readFileSync(output, 'utf8') !== contents) throw new Error('Native V8.5 manifest differs from the authored web programme')
} else {
  writeFileSync(output, contents)
}
console.log(`V8.5: ${days.length} sessions, ${manifest.exercises.length} Full/Light exercise definitions`)
