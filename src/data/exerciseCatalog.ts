import type { DayType, RepUnit } from '../lib/types'
import type { HoloMuscleGroup } from '../components/hologram/muscleMap'

export type ExerciseCategory = 'machine' | 'weights' | 'calisthenics' | 'street' | 'hiit' | 'mobility'

export interface ExerciseCatalogItem {
  id: string
  name: string
  category: ExerciseCategory
  equipment: string
  muscles: HoloMuscleGroup[]
  dayType: DayType
  sets: number
  reps: number
  rest: number
  unit: RepUnit
  perSide: boolean
}

export const EXERCISE_CATEGORIES: Array<{ id: 'all' | ExerciseCategory; label: string }> = [
  { id: 'all', label: 'All styles' },
  { id: 'machine', label: 'Gym machines' },
  { id: 'weights', label: 'Free weights' },
  { id: 'calisthenics', label: 'Calisthenics' },
  { id: 'street', label: 'Street workout' },
  { id: 'hiit', label: 'HIIT & conditioning' },
  { id: 'mobility', label: 'Mobility & recovery' },
]

type Row = [string, string, ExerciseCategory, string, HoloMuscleGroup[], DayType, number?, number?, number?, RepUnit?, boolean?]

const rows: Row[] = [
  ['leg-press', 'Leg Press', 'machine', 'Leg press', ['quads', 'glutes', 'hamstrings'], 'legs_b', 4, 10, 120],
  ['hack-squat', 'Hack Squat', 'machine', 'Hack squat machine', ['quads', 'glutes'], 'legs_b', 4, 8, 120],
  ['leg-extension', 'Leg Extension', 'machine', 'Leg extension', ['quads'], 'legs_b', 3, 12, 75],
  ['lying-leg-curl', 'Lying Leg Curl', 'machine', 'Leg curl', ['hamstrings'], 'legs_a', 3, 12, 75],
  ['seated-leg-curl', 'Seated Leg Curl', 'machine', 'Leg curl', ['hamstrings'], 'legs_a', 3, 12, 75],
  ['machine-chest-press', 'Machine Chest Press', 'machine', 'Chest press', ['chest', 'frontDelts', 'triceps'], 'push', 4, 10, 90],
  ['pec-deck', 'Pec Deck Fly', 'machine', 'Pec deck', ['chest', 'frontDelts'], 'push', 3, 12, 60],
  ['lat-pulldown', 'Lat Pulldown', 'machine', 'Cable stack', ['lats', 'upperBack', 'biceps'], 'pull', 4, 10, 90],
  ['seated-cable-row', 'Seated Cable Row', 'machine', 'Cable row', ['lats', 'upperBack', 'rearDelts', 'biceps'], 'pull', 4, 10, 90],
  ['machine-shoulder-press', 'Machine Shoulder Press', 'machine', 'Shoulder press', ['frontDelts', 'sideDelts', 'triceps'], 'push', 3, 10, 90],
  ['cable-lateral-raise', 'Cable Lateral Raise', 'machine', 'Cable stack', ['sideDelts'], 'push', 3, 15, 45, 'reps', true],
  ['face-pull-cable', 'Cable Face Pull', 'machine', 'Rope cable', ['rearDelts', 'upperBack', 'neckTraps'], 'pull', 3, 15, 60],
  ['triceps-pushdown', 'Triceps Pushdown', 'machine', 'Rope cable', ['triceps'], 'push', 3, 12, 60],
  ['cable-curl', 'Cable Biceps Curl', 'machine', 'Cable stack', ['biceps', 'forearms'], 'pull', 3, 12, 60],
  ['standing-calf-machine', 'Standing Calf Machine', 'machine', 'Calf machine', ['calves'], 'legs_b', 4, 15, 60],
  ['glute-kickback-machine', 'Glute Kickback Machine', 'machine', 'Glute machine', ['glutes', 'hamstrings'], 'legs_a', 3, 15, 60, 'reps', true],
  ['hip-abduction', 'Hip Abduction Machine', 'machine', 'Hip machine', ['glutes'], 'legs_a', 3, 15, 60],
  ['back-squat', 'Barbell Back Squat', 'weights', 'Barbell', ['quads', 'glutes', 'hamstrings', 'abs', 'lowerBack'], 'legs_b', 4, 8, 150],
  ['front-squat', 'Barbell Front Squat', 'weights', 'Barbell', ['quads', 'glutes', 'abs', 'upperBack'], 'legs_b', 4, 8, 150],
  ['goblet-squat', 'Goblet Squat', 'weights', 'Dumbbell or kettlebell', ['quads', 'glutes', 'abs'], 'legs_b', 3, 12, 90],
  ['conventional-deadlift', 'Conventional Deadlift', 'weights', 'Barbell', ['hamstrings', 'glutes', 'lowerBack', 'forearms', 'neckTraps'], 'legs_a', 3, 6, 180],
  ['romanian-deadlift', 'Romanian Deadlift', 'weights', 'Barbell or dumbbells', ['hamstrings', 'glutes', 'lowerBack', 'forearms'], 'legs_a', 4, 8, 120],
  ['hip-thrust', 'Barbell Hip Thrust', 'weights', 'Barbell and bench', ['glutes', 'hamstrings'], 'legs_a', 4, 10, 120],
  ['bulgarian-split-squat', 'Bulgarian Split Squat', 'weights', 'Dumbbells', ['quads', 'glutes', 'hamstrings'], 'legs_b', 3, 10, 90, 'reps', true],
  ['walking-lunge', 'Walking Dumbbell Lunge', 'weights', 'Dumbbells', ['quads', 'glutes', 'hamstrings'], 'legs_b', 3, 12, 90, 'reps', true],
  ['barbell-bench', 'Barbell Bench Press', 'weights', 'Barbell and bench', ['chest', 'frontDelts', 'triceps'], 'push', 4, 8, 150],
  ['incline-dumbbell-press', 'Incline Dumbbell Press', 'weights', 'Dumbbells and bench', ['chest', 'frontDelts', 'triceps'], 'push', 4, 10, 120],
  ['dumbbell-fly', 'Dumbbell Fly', 'weights', 'Dumbbells and bench', ['chest', 'frontDelts'], 'push', 3, 12, 60],
  ['overhead-press', 'Barbell Overhead Press', 'weights', 'Barbell', ['frontDelts', 'sideDelts', 'triceps', 'abs'], 'push', 4, 8, 120],
  ['arnold-press', 'Arnold Press', 'weights', 'Dumbbells', ['frontDelts', 'sideDelts', 'triceps'], 'push', 3, 10, 90],
  ['barbell-row', 'Barbell Row', 'weights', 'Barbell', ['lats', 'upperBack', 'rearDelts', 'biceps', 'lowerBack'], 'pull', 4, 8, 120],
  ['one-arm-row', 'One-Arm Dumbbell Row', 'weights', 'Dumbbell and bench', ['lats', 'upperBack', 'rearDelts', 'biceps'], 'pull', 3, 10, 75, 'reps', true],
  ['dumbbell-lateral-raise', 'Dumbbell Lateral Raise', 'weights', 'Dumbbells', ['sideDelts'], 'push', 3, 15, 45],
  ['rear-delt-fly', 'Rear-Delt Dumbbell Fly', 'weights', 'Dumbbells', ['rearDelts', 'upperBack'], 'pull', 3, 15, 45],
  ['barbell-curl', 'Barbell Curl', 'weights', 'Barbell', ['biceps', 'forearms'], 'pull', 3, 10, 60],
  ['hammer-curl', 'Hammer Curl', 'weights', 'Dumbbells', ['biceps', 'forearms'], 'pull', 3, 12, 60],
  ['skull-crusher', 'Dumbbell Skull Crusher', 'weights', 'Dumbbells and bench', ['triceps'], 'push', 3, 12, 60],
  ['farmer-carry', 'Farmer Carry', 'weights', 'Dumbbells or trap bar', ['forearms', 'neckTraps', 'abs', 'obliques'], 'upper', 4, 40, 60, 'seconds'],
  ['kettlebell-swing', 'Kettlebell Swing', 'weights', 'Kettlebell', ['glutes', 'hamstrings', 'lowerBack', 'abs', 'forearms'], 't25', 4, 15, 60],
  ['push-up', 'Push-Up', 'calisthenics', 'Bodyweight', ['chest', 'frontDelts', 'triceps', 'abs'], 'push', 4, 15, 60],
  ['diamond-push-up', 'Diamond Push-Up', 'calisthenics', 'Bodyweight', ['chest', 'frontDelts', 'triceps'], 'push', 3, 12, 60],
  ['decline-push-up', 'Decline Push-Up', 'calisthenics', 'Bench', ['chest', 'frontDelts', 'triceps'], 'push', 3, 12, 75],
  ['pike-push-up', 'Pike Push-Up', 'calisthenics', 'Bodyweight', ['frontDelts', 'sideDelts', 'triceps'], 'push', 3, 10, 75],
  ['pull-up', 'Pull-Up', 'calisthenics', 'Pull-up bar', ['lats', 'upperBack', 'biceps', 'forearms'], 'pull', 4, 8, 120],
  ['chin-up', 'Chin-Up', 'calisthenics', 'Pull-up bar', ['lats', 'upperBack', 'biceps', 'forearms'], 'pull', 4, 8, 120],
  ['parallel-dip', 'Parallel-Bar Dip', 'calisthenics', 'Dip bars', ['chest', 'frontDelts', 'triceps'], 'push', 4, 10, 90],
  ['inverted-row', 'Inverted Row', 'calisthenics', 'Low bar or rings', ['lats', 'upperBack', 'rearDelts', 'biceps'], 'pull', 4, 12, 75],
  ['pistol-squat', 'Pistol Squat', 'calisthenics', 'Bodyweight', ['quads', 'glutes', 'hamstrings', 'abs'], 'legs_b', 3, 8, 90, 'reps', true],
  ['nordic-curl', 'Nordic Hamstring Curl', 'calisthenics', 'Bodyweight anchor', ['hamstrings', 'glutes'], 'legs_a', 3, 6, 120],
  ['single-leg-glute-bridge', 'Single-Leg Glute Bridge', 'calisthenics', 'Floor', ['glutes', 'hamstrings'], 'legs_a', 3, 15, 60, 'reps', true],
  ['hanging-leg-raise', 'Hanging Leg Raise', 'calisthenics', 'Pull-up bar', ['abs', 'obliques', 'forearms'], 'upper', 3, 12, 60],
  ['hollow-hold', 'Hollow Body Hold', 'calisthenics', 'Floor', ['abs', 'obliques'], 'upper', 3, 30, 45, 'seconds'],
  ['side-plank', 'Side Plank', 'calisthenics', 'Floor', ['obliques', 'abs', 'glutes'], 'upper', 3, 35, 30, 'seconds', true],
  ['muscle-up', 'Bar Muscle-Up', 'street', 'High bar', ['lats', 'upperBack', 'biceps', 'forearms', 'chest', 'triceps'], 'upper', 5, 3, 150],
  ['front-lever-row', 'Front Lever Row', 'street', 'High bar or rings', ['lats', 'upperBack', 'rearDelts', 'biceps', 'abs'], 'pull', 4, 6, 120],
  ['human-flag', 'Human Flag Progression', 'street', 'Vertical bars', ['lats', 'sideDelts', 'obliques', 'abs', 'forearms'], 'upper', 4, 15, 90, 'seconds', true],
  ['handstand-push-up', 'Handstand Push-Up', 'street', 'Wall or freestanding', ['frontDelts', 'sideDelts', 'triceps', 'upperBack', 'abs'], 'push', 4, 6, 120],
  ['l-sit', 'L-Sit Hold', 'street', 'Parallettes or bars', ['abs', 'quads', 'triceps', 'frontDelts'], 'upper', 4, 20, 60, 'seconds'],
  ['bar-dip', 'Straight-Bar Dip', 'street', 'High bar', ['chest', 'frontDelts', 'triceps'], 'push', 4, 8, 90],
  ['burpee', 'Burpee', 'hiit', 'Bodyweight', ['chest', 'triceps', 'abs', 'glutes', 'quads', 'calves'], 't25', 5, 12, 30],
  ['mountain-climber', 'Mountain Climber', 'hiit', 'Bodyweight', ['abs', 'obliques', 'frontDelts', 'quads'], 't25', 4, 40, 20, 'seconds'],
  ['jump-squat', 'Jump Squat', 'hiit', 'Bodyweight', ['quads', 'glutes', 'hamstrings', 'calves'], 't25', 4, 15, 30],
  ['battle-rope-wave', 'Battle Rope Waves', 'hiit', 'Battle ropes', ['frontDelts', 'sideDelts', 'forearms', 'abs'], 't25', 6, 30, 30, 'seconds'],
  ['rowing-erg', 'Rowing Ergometer', 'hiit', 'Row ergometer', ['lats', 'upperBack', 'biceps', 'glutes', 'quads', 'hamstrings'], 't25', 5, 2, 90, 'minutes'],
  ['ski-erg', 'SkiErg Interval', 'hiit', 'SkiErg', ['lats', 'upperBack', 'triceps', 'abs', 'glutes'], 't25', 6, 60, 60, 'seconds'],
  ['assault-bike', 'Assault Bike Sprint', 'hiit', 'Air bike', ['quads', 'hamstrings', 'glutes', 'calves', 'frontDelts'], 't25', 8, 20, 70, 'seconds'],
  ['box-jump', 'Box Jump', 'hiit', 'Plyometric box', ['quads', 'glutes', 'hamstrings', 'calves'], 't25', 4, 8, 60],
  ['sled-push', 'Sled Push', 'hiit', 'Weighted sled', ['quads', 'glutes', 'calves', 'frontDelts', 'triceps'], 't25', 6, 30, 75, 'seconds'],
  ['jump-rope', 'Jump Rope', 'hiit', 'Skipping rope', ['calves', 'forearms', 'frontDelts'], 't25', 6, 60, 30, 'seconds'],
  ['world-greatest-stretch', "World's Greatest Stretch", 'mobility', 'Floor', ['glutes', 'hamstrings', 'obliques', 'lowerBack'], 'mobility', 2, 6, 15, 'reps', true],
  ['couch-stretch', 'Couch Stretch', 'mobility', 'Wall or bench', ['quads', 'glutes'], 'mobility', 2, 45, 15, 'seconds', true],
  ['thoracic-rotation', 'Thoracic Rotation', 'mobility', 'Floor', ['upperBack', 'obliques'], 'mobility', 2, 8, 15, 'reps', true],
  ['band-dislocate', 'Band Shoulder Dislocate', 'mobility', 'Resistance band', ['frontDelts', 'rearDelts', 'upperBack'], 'mobility', 2, 12, 15],
  ['cat-cow', 'Cat-Cow Flow', 'mobility', 'Floor', ['lowerBack', 'abs', 'upperBack'], 'mobility', 2, 10, 15],
  ['ninety-ninety', '90/90 Hip Switch', 'mobility', 'Floor', ['glutes', 'hamstrings'], 'mobility', 2, 10, 15],
  ['ankle-rock', 'Ankle Mobility Rock', 'mobility', 'Wall', ['calves'], 'mobility', 2, 12, 15, 'reps', true],
  ['dead-bug', 'Dead Bug', 'mobility', 'Floor', ['abs', 'obliques', 'lowerBack'], 'fix', 3, 10, 30, 'reps', true],
  ['bird-dog', 'Bird-Dog', 'mobility', 'Floor', ['abs', 'obliques', 'lowerBack', 'glutes'], 'fix', 3, 10, 30, 'reps', true],
  ['foam-roll-legs', 'Lower-Body Foam Roll', 'mobility', 'Foam roller', ['quads', 'hamstrings', 'glutes', 'calves'], 'mobility', 1, 8, 0, 'minutes'],
]

export const EXERCISE_CATALOG: ExerciseCatalogItem[] = rows.map(([
  id, name, category, equipment, muscles, dayType, sets = 3, reps = 10, rest = 60, unit = 'reps', perSide = false,
]) => ({ id, name, category, equipment, muscles, dayType, sets, reps, rest, unit, perSide }))

export function catalogExerciseByName(name: string): ExerciseCatalogItem | null {
  const normalized = name.trim().toLocaleLowerCase('en')
  return EXERCISE_CATALOG.find((item) => item.name.toLocaleLowerCase('en') === normalized) ?? null
}

export function searchExerciseCatalog(query: string, category: 'all' | ExerciseCategory): ExerciseCatalogItem[] {
  const terms = query.trim().toLocaleLowerCase('en').split(/\s+/).filter(Boolean)
  return EXERCISE_CATALOG
    .filter((item) => category === 'all' || item.category === category)
    .map((item) => {
      const haystack = `${item.name} ${item.equipment} ${item.muscles.join(' ')}`.toLocaleLowerCase('en')
      if (!terms.every((term) => haystack.includes(term))) return null
      const exactStart = terms.length > 0 && item.name.toLocaleLowerCase('en').startsWith(terms.join(' '))
      const nameHits = terms.filter((term) => item.name.toLocaleLowerCase('en').includes(term)).length
      return { item, score: (exactStart ? 100 : 0) + nameHits * 10 - item.name.length / 100 }
    })
    .filter((value): value is { item: ExerciseCatalogItem; score: number } => value != null)
    .sort((a, b) => b.score - a.score || a.item.name.localeCompare(b.item.name))
    .map(({ item }) => item)
}
