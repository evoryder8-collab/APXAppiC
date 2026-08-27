import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import { fileURLToPath } from 'node:url'

import {
  authoredVoiceLocales,
  authoredVoiceRows,
} from '../ios/APEXNative/Tools/native-voice-copy.mjs'

const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const resources = path.join(repository, 'ios/APEXNative/APEX/Resources')
const offeredLocales = ['en', 'de', 'de-CH', 'it', 'es', 'pt', 'ja', 'ro', 'th']

function stringsTable(locale: string) {
  if (locale === 'en') return new Map<string, string>()
  const body = fs.readFileSync(
    path.join(resources, `${locale}.lproj/Localizable.strings`),
    'utf8',
  )
  const rows = new Map<string, string>()
  const expression = /^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";$/gm
  for (const match of body.matchAll(expression)) {
    const decode = (value: string) => JSON.parse(`"${value}"`) as string
    rows.set(decode(match[1]), decode(match[2]))
  }
  return rows
}

test('authored voice copy covers every offered language from meaning and screen context', () => {
  assert.deepEqual(authoredVoiceLocales, offeredLocales)
  assert.ok(authoredVoiceRows.length >= 60, 'The first voice corpus must cover whole surfaces, not samples.')

  for (const row of authoredVoiceRows) {
    assert.ok(row.key.length > 0)
    assert.ok(row.context.length > 20, `Missing screen context for ${row.key}`)
    assert.ok(row.meaning.length > 20, `Missing intended meaning for ${row.key}`)
    assert.deepEqual(Object.keys(row.copy), offeredLocales, `Incomplete locale set for ${row.key}`)
    assert.equal(row.copy.en, row.key, `English runtime key drifted for ${row.key}`)
    for (const locale of offeredLocales) {
      assert.ok(row.copy[locale].trim().length > 0, `Blank ${locale} voice copy for ${row.key}`)
    }
  }
})

test('reviewed calibration phrases stay authored in each language', () => {
  const calibration = {
    'Also involved': {
      de: 'Unterstützende Muskeln',
      'de-CH': 'Unterstützende Muskeln',
      it: 'Muscoli di supporto',
      es: 'También participan',
      pt: 'Também recrutados',
      ja: '補助で使う部位',
      ro: 'Alți mușchi implicați',
      th: 'กล้ามเนื้อที่ช่วยทำงาน',
    },
    'Range you can control is the range you keep. This works the hips and the upper back through positions that sitting takes away, holding them long enough for the nervous system to accept them.': {
      de: 'Beweglichkeit bleibt nur, wenn du sie kontrollieren kannst. Langes Sitzen nimmt dir Beweglichkeit in Hüfte und oberem Rücken. Diese Einheit bringt dich bewusst in genau diese Positionen und gibt deinem Nervensystem Zeit, sie wieder zuzulassen.',
      'de-CH': 'Beweglichkeit bleibt nur, wenn du sie kontrollieren kannst. Langes Sitzen nimmt dir Beweglichkeit in Hüfte und oberem Rücken. Diese Einheit bringt dich bewusst in genau diese Positionen und gibt deinem Nervensystem Zeit, sie wieder zuzulassen.',
      it: 'La mobilità utile è quella che riesci a controllare. Qui le anche e la parte alta della schiena ritrovano le posizioni perse stando tanto seduti, mantenendole abbastanza a lungo da renderle di nuovo naturali.',
      es: 'La movilidad útil es la que puedes controlar. Esta sesión devuelve a las caderas y la espalda alta las posiciones que pierdes al pasar tantas horas sentado, manteniéndolas hasta que vuelvan a sentirse naturales.',
      pt: 'Só conservas a mobilidade que consegues controlar. Esta sessão devolve à anca e à parte superior das costas as posições que perdes ao passar tantas horas sentado, mantendo-as até voltarem a ser naturais.',
      ja: '自分でコントロールできる可動域こそ、実際に使える可動域です。座り続けると動きにくくなる股関節と上背部を無理なく動かし、ゆっくり保って身体をその位置に慣らします。',
      ro: 'Controlul contează mai mult decât amplitudinea. Sesiunea mobilizează șoldurile și partea superioară a spatelui în poziții pe care statul prelungit pe scaun le limitează, fără să forțeze capătul mișcării.',
      th: 'ช่วงที่คุณควบคุมได้คือช่วงการเคลื่อนไหวที่ใช้งานได้จริง เซสชันนี้ฝึกสะโพกและหลังส่วนบนในช่วงที่มักติดขัดจากการนั่งนาน ๆ แล้วค้างอย่างผ่อนคลายให้ร่างกายคุ้นกับช่วงนั้น',
    },
    'Breathe out at the end of each position. Holding your breath keeps the tension you came to release.': {
      de: 'Atme in jeder Endposition aus. Musst du dafür die Luft anhalten, geh etwas aus der Dehnung heraus – Spannung loszulassen ist heute das Ziel.',
      'de-CH': 'Atme in jeder Endposition aus. Musst du dafür die Luft anhalten, geh etwas aus der Dehnung heraus – Spannung loszulassen ist heute das Ziel.',
      it: 'Espira quando arrivi a fine corsa. Se devi trattenere il fiato, riduci l’ampiezza: sei qui per lasciare andare la tensione.',
      es: 'Suelta el aire al final de cada posición. Si tienes que aguantar la respiración, reduce el recorrido: vienes a soltar tensión, no a pelearte con ella.',
      pt: 'Expira no fim de cada posição. Se tiveres de prender a respiração, reduz a amplitude: vieste libertar tensão, não lutar contra ela.',
      ja: '各ポジションの終わりで、ゆっくり息を吐きます。息を止めないと保てないなら、無理に粘らず可動域を少し狭めましょう。',
      ro: 'Expiră lent la capătul fiecărei mișcări și păstrează respirația relaxată. Dacă trebuie să-ți ții respirația, redu amplitudinea.',
      th: 'ผ่อนลมหายใจออกเมื่อสุดแต่ละท่า ถ้าต้องกลั้นหายใจเพื่อค้างไว้ ให้ลดระยะลงแทนการฝืน',
    },
  }

  for (const [key, expectedByLocale] of Object.entries(calibration)) {
    const row = authoredVoiceRows.find(candidate => candidate.key === key)
    assert.ok(row, `missing reviewed calibration row: ${key}`)
    for (const [locale, expected] of Object.entries(expectedByLocale)) {
      assert.equal(row.copy[locale], expected, `${locale} reviewed calibration drifted: ${key}`)
    }
  }
})

test('runtime string tables contain the reviewed authored voice corpus exactly', () => {
  const tables = new Map(
    offeredLocales.filter((locale) => locale !== 'en').map((locale) => [locale, stringsTable(locale)]),
  )

  for (const row of authoredVoiceRows) {
    for (const locale of offeredLocales.filter((value) => value !== 'en')) {
      assert.equal(
        tables.get(locale)?.get(row.key),
        row.copy[locale],
        `${locale} runtime copy drifted from the authored voice corpus: ${row.key}`,
      )
    }
  }
})

test('the localisation generator applies authored prose after mechanical sources', () => {
  const generator = fs.readFileSync(
    path.join(repository, 'ios/APEXNative/Tools/generate-localizations.mjs'),
    'utf8',
  )
  const importAt = generator.indexOf("from './native-voice-copy.mjs'")
  const mechanicalAt = generator.indexOf('for (const [english, romanian, thai] of nativeRuntimeMarathonRows)')
  const authoredAt = generator.indexOf('for (const row of authoredVoiceRows)')

  assert.ok(importAt >= 0, 'The generator must import the authored voice corpus.')
  assert.ok(authoredAt > mechanicalAt, 'Authored prose must be the final translation override.')
})
