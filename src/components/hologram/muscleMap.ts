import type { DayType } from '../../lib/types.ts'

export type HoloMuscleGroup =
  | 'chest' | 'frontDelts' | 'sideDelts' | 'rearDelts' | 'biceps' | 'triceps'
  | 'forearms' | 'upperBack' | 'lats' | 'lowerBack' | 'abs' | 'obliques'
  | 'glutes' | 'quads' | 'hamstrings' | 'calves' | 'neckTraps'

export const DAY_MUSCLES: Record<DayType, HoloMuscleGroup[]> = {
  legs_a: ['glutes', 'hamstrings', 'calves', 'lowerBack', 'abs'],
  legs_b: ['quads', 'glutes', 'hamstrings', 'calves', 'abs'],
  push: ['chest', 'frontDelts', 'sideDelts', 'triceps'],
  pull: ['lats', 'upperBack', 'rearDelts', 'biceps', 'forearms', 'neckTraps'],
  upper: ['chest', 'frontDelts', 'sideDelts', 'rearDelts', 'lats', 'upperBack', 'biceps', 'triceps', 'forearms'],
  mobility: ['lowerBack', 'obliques', 'glutes', 'hamstrings', 'neckTraps'],
  fix: ['upperBack', 'rearDelts', 'neckTraps', 'lowerBack', 'abs'],
  t25: ['chest', 'frontDelts', 'triceps', 'abs', 'obliques', 'glutes', 'quads', 'hamstrings', 'calves'],
}

const EXERCISE_MUSCLES: Array<[RegExp, HoloMuscleGroup[]]> = [
  [/push[- ]?up|bench press|chest press|dip\b/i, ['chest', 'frontDelts', 'triceps']],
  [/overhead press|shoulder press|pike push/i, ['frontDelts', 'sideDelts', 'triceps']],
  [/lateral raise/i, ['sideDelts']],
  [/pull[- ]?apart|face pull|y[- ]?raise|reverse fly/i, ['rearDelts', 'upperBack', 'neckTraps']],
  [/pull[- ]?up|chin[- ]?up|dead hang|muscle[- ]?up/i, ['lats', 'upperBack', 'biceps', 'forearms']],
  [/\brow\b|rows|ski\s?erg/i, ['lats', 'upperBack', 'rearDelts', 'biceps']],
  [/curl/i, ['biceps', 'forearms']],
  [/tricep|skull crusher|extension/i, ['triceps']],
  [/hammer loop|hammer swing/i, ['forearms', 'sideDelts', 'upperBack', 'obliques', 'abs']],
  [/bulgarian|split squat|goblet squat|\bsquat|lunge|step[- ]?up/i, ['quads', 'glutes', 'hamstrings']],
  [/romanian deadlift|\brdl\b|deadlift|good morning/i, ['hamstrings', 'glutes', 'lowerBack', 'forearms']],
  [/leg curl/i, ['hamstrings']],
  [/hip thrust|glute bridge|kickback/i, ['glutes', 'hamstrings']],
  [/calf raise|calves/i, ['calves']],
  [/plank|bird[- ]?dog|dead bug|ab\b|abs|core|crunch/i, ['abs', 'obliques', 'lowerBack']],
  [/mobility|stretch|thoracic|couch stretch/i, ['lowerBack', 'obliques', 'hamstrings', 'glutes']],
]

export function musclesForWorkout(dayType: DayType | null, exerciseNames: string[] = []): HoloMuscleGroup[] {
  const matched = new Set<HoloMuscleGroup>()
  for (const name of exerciseNames) {
    for (const [pattern, muscles] of EXERCISE_MUSCLES) {
      if (!pattern.test(name)) continue
      for (const muscle of muscles) matched.add(muscle)
    }
  }
  if (matched.size > 0) return [...matched]
  return dayType ? DAY_MUSCLES[dayType] : []
}

export function readableMuscleName(muscle: HoloMuscleGroup): string {
  return muscle.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/^./, (value) => value.toUpperCase())
}
