/*
 * Exports the supplement catalogue for the native picker.
 *
 * Kept in one place because the summaries make factual claims about evidence,
 * and two hand-maintained copies would eventually disagree about what a
 * supplement does. Re-run after editing src/data/supplementCatalogue.ts:
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-supplement-catalogue.mts
 */
import { writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { SUPPLEMENT_CATALOGUE, SUPPLEMENT_CATEGORIES } from '../../../src/data/supplementCatalogue.ts'

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, '..', 'APEX', 'Resources', 'supplement-catalogue.json')

writeFileSync(out, JSON.stringify({
  generated_note: 'Generated from src/data/supplementCatalogue.ts. Do not edit by hand.',
  categories: SUPPLEMENT_CATEGORIES,
  supplements: SUPPLEMENT_CATALOGUE,
}, null, 1))

console.log(`wrote ${SUPPLEMENT_CATALOGUE.length} supplements`)
