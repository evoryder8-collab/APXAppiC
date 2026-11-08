import { EXERCISE_CATALOG } from '../data/exerciseCatalog.ts'
import { isFocusT25Name } from './focusT25.ts'
import rules from '../../ios/APEXNative/APEX/Resources/GuidedArtwork/lookup.json' with { type: 'json' }

const key = (value: string) => value.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim()
const ids = new Set(EXERCISE_CATALOG.map(item => item.movementID))
const excluded = new Set(rules.excluded.map(key))
const names = new Map<string, string | null>()
function register(label: string, id: string) {
  const name = key(label)
  names.set(name, !names.has(name) || names.get(name) === id ? id : null)
}
for (const item of EXERCISE_CATALOG) {
  for (const label of [item.name, item.name + 's', ...Object.values(item.names)]) register(label, item.movementID)
}
for (const [label, id] of Object.entries(rules.aliases)) register(label, id)

export function previewPhotoID(exercise: { name: string; movement_id?: string | null }) {
  if (isFocusT25Name(exercise.name) || excluded.has(key(exercise.name))) return null
  if (exercise.movement_id) return ids.has(exercise.movement_id) ? exercise.movement_id : null
  return ids.has(exercise.name) ? exercise.name : names.get(key(exercise.name)) ?? null
}
