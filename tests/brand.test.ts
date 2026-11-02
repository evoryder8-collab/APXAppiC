import assert from 'node:assert/strict'
import test from 'node:test'
import { displayBrand } from '../src/lib/brand.ts'

test('legacy display copy resolves to the single commercial name', () => {
  for (const old of ['APEX', 'FitDee', 'FITR-D', 'FITR-MAX']) {
    assert.equal(displayBrand(`Open ${old} to continue.`), 'Open FITR MAX to continue.')
  }
})

test('branding does not rewrite bundle identifiers, storage keys or URLs', () => {
  for (const stable of ['ch.apexperformance.APEX', 'group.ch.apexperformance.APEX', 'APEX_EVENT', 'https://example.com/APEX']) {
    assert.equal(displayBrand(stable), stable)
  }
})

test('sentence punctuation and localized compounds still display the commercial name', () => {
  for (const text of ['APEX.', 'APEX-Auswertung', 'APEX評価', 'APEXは水を記録します。']) {
    assert.equal(displayBrand(text), text.replace('APEX', 'FITR MAX'))
  }
})
