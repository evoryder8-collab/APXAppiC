/*
 * Exports the web exercise catalogue as JSON for the native builder.
 *
 * Transcribing a hundred-plus movements into Swift by hand would drift from
 * the web the first time either side changed. Generating it keeps one source
 * of truth. Re-run after editing src/data/exerciseCatalog.ts:
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-exercise-catalog.mts
 */
import { writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  EXERCISE_CATALOG,
  EXERCISE_CATEGORIES,
  EXERCISE_CATEGORY_ORDERS,
} from '../../../src/data/exerciseCatalog.ts'

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, '..', 'APEX', 'Resources', 'exercise-catalog.json')

writeFileSync(out, JSON.stringify({
  generated_note: 'Generated from src/data/exerciseCatalog.ts. Do not edit by hand.',
  categories: EXERCISE_CATEGORIES,
  categoryOrders: EXERCISE_CATEGORY_ORDERS,
  exercises: EXERCISE_CATALOG,
}, null, 1))

console.log(`wrote ${EXERCISE_CATALOG.length} exercises, ${EXERCISE_CATEGORIES.length} categories`)
