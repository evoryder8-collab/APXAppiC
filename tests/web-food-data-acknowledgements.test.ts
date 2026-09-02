import assert from 'node:assert/strict'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import test from 'node:test'

import { LANGUAGE_OPTIONS } from '../src/lib/introLanguage.ts'
import { UI_TRANSLATIONS } from '../src/lib/translations.ts'

const root = new URL('../src/', import.meta.url)
const source = (path: string): string => readFileSync(new URL(path, root), 'utf8')

const citation = 'Marija Langwagen, Jette Jakobsen and Anders Poulsen: The Danish Food Composition Database, version 6.1, May 2026, National Food Institute, Technical University of Denmark.'
const adaptation = 'APEX extracted, normalized and mapped selected source records to reviewed APEX food entries. These changes are by APEX; DTU does not endorse APEX.'

function sourcesBelow(path: string): string[] {
  return readdirSync(path).flatMap((name) => {
    const entry = join(path, name)
    return statSync(entry).isDirectory() ? sourcesBelow(entry) : entry.endsWith('.tsx') ? [readFileSync(entry, 'utf8')] : []
  })
}

test('web Settings exposes the centralized DTU food-data acknowledgement and safe source links', () => {
  const settings = source('pages/Settings.tsx')

  assert.match(settings, /<details[^>]*data-food-data-acknowledgement/)
  assert.match(settings, new RegExp(citation.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  assert.match(settings, new RegExp(adaptation.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')))
  for (const url of [
    'https://doi.org/10.11583/DTU.32312844',
    'https://creativecommons.org/licenses/by/4.0/',
    'https://fcdb.fooddata.dk/disclaimer',
  ]) {
    assert.match(settings, new RegExp(`href="${url.replace(/[./]/g, '\\$&')}"`))
  }
  assert.equal((settings.match(/target="_blank"/g) ?? []).length >= 3, true)
  assert.equal((settings.match(/rel="noreferrer"/g) ?? []).length >= 3, true)
})

test('food-data acknowledgement copy is authored in every offered web language', () => {
  assert.deepEqual(LANGUAGE_OPTIONS.map(({ value }) => value).sort(), ['en', 'ro', 'th'])

  const expected: Record<string, { ro: string; th: string }> = {
    'Legal & data': { ro: 'Juridic și date', th: 'กฎหมายและข้อมูล' },
    'Food data acknowledgements': { ro: 'Mențiuni privind datele alimentare', th: 'คำขอบคุณและแหล่งที่มาของข้อมูลอาหาร' },
    'See where APEX food data comes from and how it is adapted.': { ro: 'Vezi de unde provin datele alimentare APEX și cum sunt adaptate.', th: 'ดูว่าข้อมูลอาหารของ APEX มาจากที่ใดและได้รับการปรับใช้อย่างไร' },
    'APEX uses adapted data from:': { ro: 'APEX folosește date adaptate din:', th: 'APEX ใช้ข้อมูลที่ปรับมาจาก:' },
    [citation]: { ro: citation, th: citation },
    [adaptation]: {
      ro: 'APEX a extras, normalizat și mapat anumite înregistrări-sursă în fișe alimentare APEX verificate. Aceste modificări aparțin APEX; DTU nu susține APEX.',
      th: 'APEX คัดแยก ปรับรูปแบบ และเชื่อมโยงระเบียนต้นทางบางรายการเข้ากับรายการอาหาร APEX ที่ผ่านการตรวจทาน การเปลี่ยนแปลงเหล่านี้เป็นของ APEX และ DTU ไม่ได้รับรอง APEX',
    },
    'Dataset DOI': { ro: 'DOI-ul setului de date', th: 'DOI ของชุดข้อมูล' },
    'DTU disclaimer': { ro: 'Declinarea răspunderii DTU', th: 'ข้อจำกัดความรับผิดชอบของ DTU' },
  }

  for (const [english, translations] of Object.entries(expected)) {
    assert.deepEqual(UI_TRANSLATIONS[english], translations, `missing authored web acknowledgement copy: ${english}`)
  }
})

test('centralized food-data legal links stay out of nutrient rows and sheets', () => {
  const nutrientSources = [
    source('pages/Nutrition.tsx'),
    ...sourcesBelow(new URL('../src/components/food/', import.meta.url).pathname),
  ].join('\n')

  assert.doesNotMatch(nutrientSources, /doi\.org\/10\.11583\/DTU\.32312844/)
  assert.doesNotMatch(nutrientSources, /creativecommons\.org\/licenses\/by\/4\.0/)
  assert.doesNotMatch(nutrientSources, /fcdb\.fooddata\.dk\/disclaimer/)
})
