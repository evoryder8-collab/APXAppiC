import assert from 'node:assert/strict'
import test from 'node:test'
import { createUuidV4 } from '../src/lib/uuid.ts'

test('UUID fallback creates a standards-shaped version 4 identifier', () => {
  const uuid = createUuidV4((bytes) => {
    bytes.fill(0xab)
    return bytes
  })

  assert.equal(uuid, 'abababab-abab-4bab-abab-abababababab')
  assert.match(uuid, /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
})

test('UUID fallback does not reuse identifiers', () => {
  const identifiers = new Set(Array.from({ length: 100 }, () => createUuidV4()))
  assert.equal(identifiers.size, 100)
})
