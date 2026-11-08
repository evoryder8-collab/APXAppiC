import test from 'node:test'
import assert from 'node:assert/strict'
import { existsSync } from 'node:fs'
import { EXERCISE_CATALOG } from '../src/data/exerciseCatalog.ts'
import { previewPhotoID } from '../src/lib/guidedPreviewPhoto.ts'

test('all catalog movements map to shipped artwork; legacy names, substitutions and custom movements stay distinct', () => {
  const folder = '../ios/APEXNative/APEX/Resources/GuidedArtwork/'
  for (const exercise of EXERCISE_CATALOG) {
    const id = previewPhotoID({ name: exercise.name, movement_id: exercise.movementID })
    assert.ok(id && ['', '-1'].some(suffix => existsSync(new URL(folder + id + suffix + '.webp', import.meta.url))), exercise.name)
  }
  assert.equal(previewPhotoID({ name: 'Weighted Dumbbell Hip Thrust' }), 'hip_thrust_dumbbell')
  assert.equal(previewPhotoID({ name: 'Any 10-min HIIT video', movement_id: 'burpee' }), null)
  assert.equal(previewPhotoID({ name: 'My custom exercise' }), null)
})
