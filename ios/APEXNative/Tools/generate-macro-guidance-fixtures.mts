/*
 * Golden parity fixtures for MealMacroGuidance.
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-macro-guidance-fixtures.mts
 */
import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { mealMacroStatus, type MealMacroKind } from '../../../src/lib/mealMacroGuidance.ts'
import type { Goal } from '../../../src/lib/types.ts'
import type { PersonaSlug } from '../../../src/lib/persona.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const OUT = join(HERE, '..', 'APEXTests', 'Fixtures', 'macro-guidance-parity.json')

const macros: MealMacroKind[] = ['protein', 'carbs', 'fat']
const personas: PersonaSlug[] = ['constantine', 'june', 'matthew', 'iulian']
const goals: Goal[] = ['recomp', 'bulk', 'maintain']
/* Values chosen to land on every side of every threshold, including the
   exact boundaries, plus the degenerate targets. */
const pairs: Array<[number, number]> = [
  [0, 40], [33.9, 40], [34, 40], [39.9, 40], [40, 40],
  [44, 40], [56, 40], [57, 40], [70, 40],
  [10, 0], [10, -5], [9.94, 12], [9.95, 12],
]

const cases = []
for (const macro of macros) {
  for (const persona of personas) {
    for (const goal of goals) {
      for (const [value, target] of pairs) {
        cases.push({
          macro, persona, goal, value, target,
          expected: mealMacroStatus(value, target, macro, persona, goal),
        })
      }
    }
  }
}

mkdirSync(dirname(OUT), { recursive: true })
writeFileSync(OUT, `${JSON.stringify({ cases }, null, 2)}\n`)
console.log(`wrote ${OUT} (${cases.length} cases)`)
