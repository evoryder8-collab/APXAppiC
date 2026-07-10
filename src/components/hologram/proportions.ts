/*
 * Single source of truth for the hologram body. Tune the figure by editing
 * numbers here, nothing else. Units are world units, pelvis center = origin.
 * Canon: ~7.5 heads tall, V-taper mesomorph.
 */
export const BODY = {
  /* head */
  headRadius: 0.115,
  headY: 0.78,
  neckLen: 0.1,
  neckR: 0.048,

  /* torso: pelvis (y=0) to shoulder line */
  torsoLen: 0.52,
  shoulderY: 0.5,
  shoulderHalf: 0.23, // half biacromial width
  chestY: 0.36,
  chestR: 0.105,
  waistR: 0.135,
  hipR: 0.155,
  torsoDepthScale: 0.64, // flattens the lathe front-to-back

  /* torso lathe profile: [y, radius] pairs from pelvis upward */
  torsoProfile: [
    [0.0, 0.15],
    [0.08, 0.14],
    [0.16, 0.132],
    [0.26, 0.148],
    [0.36, 0.172],
    [0.44, 0.185],
    [0.5, 0.165],
    [0.53, 0.1],
  ] as Array<[number, number]>,

  /* pelvis lathe profile, downward from origin */
  pelvisProfile: [
    [0.02, 0.15],
    [-0.06, 0.158],
    [-0.14, 0.13],
    [-0.18, 0.095],
  ] as Array<[number, number]>,

  /* arms */
  deltR: 0.073,
  upperArmLen: 0.27,
  upperArmR: 0.047,
  forearmLen: 0.25,
  forearmR: 0.039,
  armAngle: 0.14, // radians outward from vertical
  handR: 0.038,

  /* legs */
  hipHalf: 0.095, // half stance width at hip sockets
  thighLen: 0.42,
  thighR: 0.088,
  calfLen: 0.4,
  shinR: 0.052,
  calfBulgeR: 0.062,
  footLen: 0.14,

  /* glutes */
  gluteR: 0.085,
} as const

export type RegionKey =
  | 'base'
  | 'traps'
  | 'chest'
  | 'front_delts'
  | 'side_delts'
  | 'lats'
  | 'biceps'
  | 'triceps'
  | 'forearms'
  | 'core'
  | 'spine'
  | 'glutes'
  | 'quads'
  | 'hamstrings'
  | 'calves'

import type { DayType } from '../../lib/types'

/* Which regions light up for a given session type */
export const MUSCLE_MAP: Record<DayType, RegionKey[]> = {
  legs_a: ['glutes', 'hamstrings', 'calves'],
  legs_b: ['quads', 'glutes', 'calves'],
  push: ['chest', 'front_delts', 'side_delts', 'triceps'],
  pull: ['lats', 'traps', 'biceps', 'forearms'],
  upper: ['chest', 'front_delts', 'side_delts', 'lats', 'traps', 'biceps', 'triceps'],
  mobility: ['spine', 'glutes'],
  fix: ['spine', 'traps', 'lats'],
  t25: [], // full-body wave handled by the sweep mode
}
