/*
 * Exports the timings a guided session runs on, for the native player.
 *
 * The web player and the native one had drifted into the same defect from the
 * same source: side switches fired only for exercises whose *name* matched a
 * regex for split squats, and lasted a fixed three seconds. Fixing that needs
 * per-movement facts -- how long the kit takes to reposition, how hard the
 * movement is, how long the next one takes to set up -- so those facts have to
 * reach Swift rather than being guessed again on the other side.
 *
 * Re-run after editing tools/movement-library.py and regenerating movements.ts:
 *
 *   node --experimental-strip-types ios/APEXNative/Tools/generate-movement-timing.mts
 */
import { writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { MOVEMENTS, MOVEMENT_ALIASES } from '../../../src/data/movements.ts'

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, '..', 'APEX', 'Resources', 'movement-timing.json')

/* Kit that has to be moved, re-pinned or walked around before the second side
 * can start. Kept in step with sessionShape.ts. */
const REPOSITIONING = new Set([
  'bench', 'adjustable_bench', 'plyo_box', 'step', 'cable_stack', 'rack',
  'smith_machine', 'landmine', 'reformer', 'chair', 'anchor_point',
])

const movements = MOVEMENTS.map((m) => ({
  id: m.id,
  name: m.name,
  setup_seconds: m.setupSeconds,
  fatigue_cost: m.fatigueCost,
  unilateral: m.unilateral,
  repositioning: [...m.equipment, ...m.equipmentAnyOf.flat()]
    .some((item) => REPOSITIONING.has(item)),
  tempo_down_s: m.tempoApplies ? null : 0,
}))

writeFileSync(out, JSON.stringify({
  generated_note: 'Generated from src/data/movements.ts. Do not edit by hand.',
  movements,
  aliases: MOVEMENT_ALIASES,
}, null, 1))

console.log(`wrote ${movements.length} movements, ${Object.keys(MOVEMENT_ALIASES).length} aliases`)
