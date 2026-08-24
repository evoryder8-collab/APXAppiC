import type { DayType, RepUnit } from '../lib/types'
import type { HoloMuscleGroup } from '../components/hologram/muscleMap'
import type { IntroLanguage } from '../lib/introLanguage'
import {
  CARDIO_ALIASES,
  CARDIO_MODALITIES,
  MOVEMENT_ALIASES,
  MOVEMENTS,
  type CardioModality,
  type Movement,
} from './movements.ts'
import { HYROX_STATIONS } from '../lib/eventCampaign.ts'

export type ExerciseCategory =
  | 'hyrox' | 'crossfit' | 'olympic_weightlifting' | 'powerlifting'
  | 'kettlebell_sport' | 'strongman' | 'strength'
  | 'machine' | 'weights' | 'calisthenics' | 'street' | 'hiit'
  | 'cardio' | 'mobility' | 'yoga' | 'pilates' | 'balance'

export interface ExerciseCatalogItem {
  id: string
  movementID: string
  name: string
  category: ExerciseCategory
  categories: ExerciseCategory[]
  equipment: string
  muscles: HoloMuscleGroup[]
  dayType: DayType
  sets: number
  reps: number
  rest: number
  unit: RepUnit
  perSide: boolean
  loadable: boolean
  incrementKG: number
  names: Record<IntroLanguage, string>
  aliases: Record<IntroLanguage, string[]>
}

export const EXERCISE_CATEGORIES: Array<{ id: 'all' | ExerciseCategory; label: string }> = [
  { id: 'all', label: 'All styles' },
  { id: 'hyrox', label: 'HYROX' },
  { id: 'crossfit', label: 'CrossFit' },
  { id: 'olympic_weightlifting', label: 'Olympic weightlifting' },
  { id: 'powerlifting', label: 'Powerlifting' },
  { id: 'kettlebell_sport', label: 'Kettlebell sport' },
  { id: 'strongman', label: 'Strongman' },
  { id: 'strength', label: 'Strength' },
  { id: 'machine', label: 'Gym machines' },
  { id: 'weights', label: 'Free weights' },
  { id: 'calisthenics', label: 'Calisthenics' },
  { id: 'street', label: 'Street workout' },
  { id: 'hiit', label: 'HIIT & conditioning' },
  { id: 'cardio', label: 'Cardio' },
  { id: 'mobility', label: 'Mobility & prehab' },
  { id: 'yoga', label: 'Yoga' },
  { id: 'pilates', label: 'Pilates' },
  { id: 'balance', label: 'Balance' },
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
  ['chest-supported-machine-row', 'Chest-Supported Machine Row', 'machine', 'Plate-loaded or selectorized row', ['lats', 'upperBack', 'rearDelts', 'biceps'], 'pull', 4, 10, 90],
  ['machine-shoulder-press', 'Machine Shoulder Press', 'machine', 'Shoulder press', ['frontDelts', 'sideDelts', 'triceps'], 'push', 3, 10, 90],
  ['cable-lateral-raise', 'Cable Lateral Raise', 'machine', 'Cable stack', ['sideDelts'], 'push', 3, 15, 45, 'reps', true],
  ['face-pull-cable', 'Cable Face Pull', 'machine', 'Rope cable', ['rearDelts', 'upperBack', 'neckTraps'], 'pull', 3, 15, 60],
  ['triceps-pushdown', 'Triceps Pushdown', 'machine', 'Rope cable', ['triceps'], 'push', 3, 12, 60],
  ['cable-curl', 'Cable Biceps Curl', 'machine', 'Cable stack', ['biceps', 'forearms'], 'pull', 3, 12, 60],
  ['standing-calf-machine', 'Standing Calf Machine', 'machine', 'Calf machine', ['calves'], 'legs_b', 4, 15, 60],
  ['seated-calf-raise', 'Seated Calf Raise', 'machine', 'Seated calf machine', ['calves'], 'legs_b', 4, 15, 60],
  ['calf-press-leg-press', 'Calf Press on Leg Press', 'machine', 'Leg press', ['calves'], 'legs_b', 4, 15, 60],
  ['hip-adduction', 'Hip Adduction Machine', 'machine', 'Hip adduction machine', ['adductors'], 'legs_a', 3, 15, 60],
  ['cable-hip-adduction', 'Cable Hip Adduction', 'machine', 'Cable stack and ankle strap', ['adductors'], 'legs_a', 3, 15, 45, 'reps', true],
  ['ab-crunch-machine', 'Ab Crunch Machine', 'machine', 'Abdominal machine', ['abs'], 'upper', 3, 12, 60],
  ['cable-crunch', 'Cable Crunch', 'machine', 'Rope cable', ['abs', 'obliques'], 'upper', 3, 12, 60],
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
  ['reverse-lunge', 'Reverse Dumbbell Lunge', 'weights', 'Dumbbells', ['quads', 'glutes', 'hamstrings'], 'legs_b', 3, 10, 90, 'reps', true],
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
  ['preacher-curl-barbell', 'Straight-Bar Preacher Curl', 'weights', 'Straight bar and preacher bench', ['biceps', 'forearms'], 'pull', 3, 10, 75],
  ['barbell-shrug', 'Barbell Shrug', 'weights', 'Barbell', ['neckTraps', 'forearms'], 'pull', 4, 12, 75],
  ['skull-crusher', 'Dumbbell Skull Crusher', 'weights', 'Dumbbells and bench', ['triceps'], 'push', 3, 12, 60],
  ['farmer-carry', 'Farmer Carry', 'weights', 'Dumbbells or trap bar', ['forearms', 'neckTraps', 'abs', 'obliques'], 'upper', 4, 40, 60, 'seconds'],
  ['kettlebell-swing', 'Kettlebell Swing', 'weights', 'Kettlebell', ['glutes', 'hamstrings', 'lowerBack', 'abs', 'forearms'], 't25', 4, 15, 60],
  ['elevated-calf-raise', 'Elevated Calf Raise', 'weights', 'Step and dumbbells', ['calves'], 'legs_b', 4, 15, 60],
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
  ['decline-sit-up', 'Decline Sit-Up', 'calisthenics', 'Decline bench', ['abs', 'obliques'], 'upper', 3, 12, 60],
  ['reverse-crunch', 'Reverse Crunch', 'calisthenics', 'Floor or bench', ['abs'], 'upper', 3, 15, 45],
  ['ab-wheel-rollout', 'Ab-Wheel Rollout', 'calisthenics', 'Ab wheel', ['abs', 'obliques', 'lowerBack'], 'upper', 3, 10, 60],
  ['copenhagen-plank', 'Copenhagen Plank', 'calisthenics', 'Bench', ['adductors', 'abs', 'obliques'], 'legs_a', 3, 30, 45, 'seconds', true],
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
  ['treadmill-walk', 'Treadmill Walk', 'cardio', 'Treadmill', ['quads', 'hamstrings', 'glutes', 'calves'], 't25', 1, 25, 0, 'minutes'],
  ['treadmill-run', 'Treadmill Run', 'cardio', 'Treadmill', ['quads', 'hamstrings', 'glutes', 'calves'], 't25', 1, 25, 0, 'minutes'],
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

interface ExerciseLocalization {
  ro: string
  th: string
  enAliases?: string[]
  roAliases?: string[]
  thAliases?: string[]
}

/* Canonical names stay English in workout logs so progress history remains
   stable. Native names and aliases power display and discovery. */
const LOCALIZED_EXERCISES: Record<string, ExerciseLocalization> = {
  'leg-press': { ro: 'Presă pentru picioare', th: 'เลกเพรส' },
  'hack-squat': { ro: 'Genuflexiuni la hack squat', th: 'แฮ็กสควอต' },
  'leg-extension': { ro: 'Extensii pentru picioare', th: 'เหยียดขาด้วยเครื่อง' },
  'lying-leg-curl': { ro: 'Flexii femurali din culcat', th: 'นอนงอขาด้วยเครื่อง' },
  'seated-leg-curl': { ro: 'Flexii femurali din șezut', th: 'นั่งงอขาด้วยเครื่อง' },
  'machine-chest-press': { ro: 'Împins la piept la aparat', th: 'เครื่องดันอก' },
  'pec-deck': { ro: 'Fluturări la pec deck', th: 'เครื่องบริหารอกเพ็กเด็ค' },
  'lat-pulldown': { ro: 'Tracțiuni la helcometru', th: 'ดึงข้อด้วยสายเคเบิล' },
  'seated-cable-row': { ro: 'Ramat la cablu din șezut', th: 'นั่งพายเคเบิล', enAliases: ['machine row'], roAliases: ['ramat', 'ramat cablu'] },
  'chest-supported-machine-row': { ro: 'Ramat la aparat cu pieptul sprijinit', th: 'เครื่องพายพิงอก', enAliases: ['back machine rows', 'machine rows'], roAliases: ['ramat', 'ramat aparat', 'ramat spate'] },
  'machine-shoulder-press': { ro: 'Împins pentru umeri la aparat', th: 'เครื่องดันไหล่' },
  'cable-lateral-raise': { ro: 'Ridicări laterale la cablu', th: 'ยกแขนข้างด้วยเคเบิล' },
  'face-pull-cable': { ro: 'Trageri la față la cablu', th: 'เฟซพูลด้วยเคเบิล', roAliases: ['trapez cablu', 'umeri posteriori'] },
  'triceps-pushdown': { ro: 'Extensii triceps la scripete', th: 'กดไตรเซ็ปส์ด้วยเคเบิล' },
  'cable-curl': { ro: 'Flexii biceps la cablu', th: 'เคเบิลเคิร์ล' },
  'standing-calf-machine': { ro: 'Gambe la aparat din picioare', th: 'เครื่องยืนเขย่งน่อง', enAliases: ['calves', 'calf raise'], roAliases: ['gambe', 'ridicari pe varfuri', 'gamba'] },
  'seated-calf-raise': { ro: 'Gambe din șezut la aparat', th: 'นั่งเขย่งน่องด้วยเครื่อง', enAliases: ['calves', 'seated calves'], roAliases: ['gambe', 'gambe sezut', 'gambe la aparat'] },
  'calf-press-leg-press': { ro: 'Gambe la presă', th: 'เขย่งน่องบนเลกเพรส', enAliases: ['calves', 'leg press calf raise'], roAliases: ['gambe', 'gambe presa', 'gambe la presa'] },
  'hip-adduction': { ro: 'Aductori la aparat', th: 'เครื่องหุบสะโพก', enAliases: ['adductors', 'inner thigh'], roAliases: ['aductori', 'adductori', 'interior coapse'] },
  'cable-hip-adduction': { ro: 'Aductori la cablu', th: 'หุบขาด้วยเคเบิล', enAliases: ['adductors', 'inner thigh cable'], roAliases: ['aductori', 'adductori', 'aductori cablu'] },
  'ab-crunch-machine': { ro: 'Abdomene la aparat', th: 'ครันช์หน้าท้องด้วยเครื่อง', enAliases: ['abs', 'abdominals'], roAliases: ['abdomene', 'abdomen', 'abdominali'] },
  'cable-crunch': { ro: 'Abdomene la cablu', th: 'ครันช์หน้าท้องด้วยเคเบิล', enAliases: ['abs', 'abdominals'], roAliases: ['abdomene', 'abdomen', 'abdominali', 'abdomene cablu'] },
  'glute-kickback-machine': { ro: 'Extensii pentru fesieri la aparat', th: 'เครื่องเตะขาไปด้านหลัง' },
  'hip-abduction': { ro: 'Abducții de șold la aparat', th: 'เครื่องกางสะโพก' },
  'back-squat': { ro: 'Genuflexiuni cu bara la spate', th: 'แบ็กสควอตด้วยบาร์เบล' },
  'front-squat': { ro: 'Genuflexiuni cu bara în față', th: 'ฟรอนต์สควอตด้วยบาร์เบล' },
  'goblet-squat': { ro: 'Genuflexiuni goblet', th: 'กอบเล็ตสควอต' },
  'conventional-deadlift': { ro: 'Îndreptări convenționale', th: 'เดดลิฟต์แบบปกติ' },
  'romanian-deadlift': { ro: 'Îndreptări românești', th: 'โรมาเนียนเดดลิฟต์' },
  'hip-thrust': { ro: 'Hip thrust cu bara', th: 'ฮิปทรัสต์ด้วยบาร์เบล' },
  'bulgarian-split-squat': { ro: 'Genuflexiuni bulgărești', th: 'บัลแกเรียนสปลิตสควอต', roAliases: ['fandari bulgaresti'] },
  'walking-lunge': { ro: 'Fandări din mers cu gantere', th: 'เดินลันจ์ด้วยดัมเบล', roAliases: ['fandari', 'fandari mers'] },
  'reverse-lunge': { ro: 'Fandări inverse cu gantere', th: 'ลันจ์ถอยหลังด้วยดัมเบล', roAliases: ['fandari', 'fandari inverse'] },
  'barbell-bench': { ro: 'Împins la piept cu bara', th: 'เบนช์เพรสด้วยบาร์เบล' },
  'incline-dumbbell-press': { ro: 'Împins înclinat cu gantere', th: 'อินไคลน์ดัมเบลเพรส' },
  'dumbbell-fly': { ro: 'Fluturări cu gantere', th: 'ดัมเบลฟลาย' },
  'overhead-press': { ro: 'Împins deasupra capului cu bara', th: 'โอเวอร์เฮดเพรสด้วยบาร์เบล' },
  'arnold-press': { ro: 'Împins Arnold', th: 'อาร์โนลด์เพรส' },
  'barbell-row': { ro: 'Ramat cu bara', th: 'บาร์เบลโรว์', roAliases: ['ramat', 'ramat bara'] },
  'one-arm-row': { ro: 'Ramat cu o ganteră', th: 'ดัมเบลโรว์ข้างเดียว', roAliases: ['ramat', 'ramat gantera'] },
  'dumbbell-lateral-raise': { ro: 'Ridicări laterale cu gantere', th: 'ยกแขนข้างด้วยดัมเบล' },
  'rear-delt-fly': { ro: 'Fluturări pentru deltoid posterior', th: 'รีเวิร์สดัมเบลฟลาย' },
  'barbell-curl': { ro: 'Flexii cu bara pentru biceps', th: 'บาร์เบลเคิร์ล' },
  'hammer-curl': { ro: 'Flexii ciocan', th: 'แฮมเมอร์เคิร์ล', roAliases: ['ciocane', 'flexii ciocane'] },
  'preacher-curl-barbell': { ro: 'Flexii la banca Scott cu bara dreaptă', th: 'พรีชเชอร์เคิร์ลด้วยบาร์ตรง', enAliases: ['preacher curls straight barbell'], roAliases: ['flexii scott', 'biceps banca scott'] },
  'barbell-shrug': { ro: 'Ridicări din umeri cu bara', th: 'ยักไหล่ด้วยบาร์เบล', enAliases: ['trap shrug'], roAliases: ['trapez', 'ridicari trapez'] },
  'skull-crusher': { ro: 'Extensii triceps culcat cu gantere', th: 'ดัมเบลสกัลครัชเชอร์' },
  'farmer-carry': { ro: 'Mersul fermierului', th: 'ฟาร์เมอร์แคร์รี', roAliases: ['trapez', 'mers fermier'] },
  'kettlebell-swing': { ro: 'Balans cu kettlebell', th: 'เคตเทิลเบลสวิง' },
  'elevated-calf-raise': { ro: 'Gambe cu elevație', th: 'ยืนเขย่งน่องบนแท่น', enAliases: ['calves', 'calf raise on step'], roAliases: ['gambe', 'gambe elevatie', 'ridicari pe varfuri cu elevatie'] },
  'push-up': { ro: 'Flotări', th: 'วิดพื้น' },
  'diamond-push-up': { ro: 'Flotări diamant', th: 'วิดพื้นไดมอนด์' },
  'decline-push-up': { ro: 'Flotări declinate', th: 'วิดพื้นยกเท้า' },
  'pike-push-up': { ro: 'Flotări pike', th: 'ไพก์พุชอัพ' },
  'pull-up': { ro: 'Tracțiuni la bară', th: 'ดึงข้อ', roAliases: ['tractiuni', 'tractiuni pronatie'] },
  'chin-up': { ro: 'Tracțiuni cu priză inversă', th: 'ชินอัพ', roAliases: ['tractiuni', 'tractiuni supinatie'] },
  'parallel-dip': { ro: 'Flotări la paralele', th: 'ดิพบนบาร์คู่' },
  'inverted-row': { ro: 'Ramat invers', th: 'อินเวิร์ทโรว์', roAliases: ['ramat', 'ramat la bara'] },
  'pistol-squat': { ro: 'Genuflexiuni pistol', th: 'พิสตอลสควอต' },
  'nordic-curl': { ro: 'Flexii nordice pentru femurali', th: 'นอร์ดิกแฮมสตริงเคิร์ล' },
  'single-leg-glute-bridge': { ro: 'Podul fesier pe un picior', th: 'สะพานก้นขาเดียว' },
  'hanging-leg-raise': { ro: 'Ridicări de picioare la bară', th: 'ยกขาห้อยบาร์' },
  'hollow-hold': { ro: 'Menținere hollow body', th: 'ฮอลโลว์บอดี้โฮลด์' },
  'side-plank': { ro: 'Planșă laterală', th: 'แพลงก์ด้านข้าง' },
  'decline-sit-up': { ro: 'Abdomene pe bancă declinată', th: 'ซิตอัพบนม้านั่งลาด', enAliases: ['abs', 'abdominals'], roAliases: ['abdomene', 'abdomen', 'abdomene banca'] },
  'reverse-crunch': { ro: 'Abdomene inverse', th: 'รีเวิร์สครันช์', enAliases: ['abs', 'abdominals'], roAliases: ['abdomene', 'abdomen', 'abdomene inverse'] },
  'ab-wheel-rollout': { ro: 'Abdomene cu roata abdominală', th: 'ลูกกลิ้งหน้าท้อง', enAliases: ['abs', 'abdominals'], roAliases: ['abdomene', 'abdomen', 'roata abdominala'] },
  'copenhagen-plank': { ro: 'Planșă Copenhagen pentru aductori', th: 'โคเปนเฮเกนแพลงก์', enAliases: ['adductors', 'inner thigh'], roAliases: ['aductori', 'adductori', 'plansa aductori'] },
  'muscle-up': { ro: 'Muscle-up la bară', th: 'บาร์มัสเซิลอัพ' },
  'front-lever-row': { ro: 'Ramat în front lever', th: 'ฟรอนต์ลีเวอร์โรว์', roAliases: ['ramat front lever'] },
  'human-flag': { ro: 'Progresie steagul uman', th: 'ฝึกฮิวแมนแฟลก' },
  'handstand-push-up': { ro: 'Flotări în stând pe mâini', th: 'วิดพื้นแฮนด์สแตนด์' },
  'l-sit': { ro: 'Menținere L-sit', th: 'แอลซิตโฮลด์' },
  'bar-dip': { ro: 'Flotări la bară dreaptă', th: 'ดิพบนบาร์เดี่ยว' },
  'burpee': { ro: 'Burpee', th: 'เบอร์พี' },
  'mountain-climber': { ro: 'Cățărătorul', th: 'เมาน์เทนไคลม์เบอร์' },
  'jump-squat': { ro: 'Genuflexiuni cu săritură', th: 'จัมป์สควอต' },
  'battle-rope-wave': { ro: 'Valuri cu frânghiile', th: 'แบทเทิลโรปเวฟ' },
  'rowing-erg': { ro: 'Ergometru de vâslit', th: 'เครื่องกรรเชียงบก' },
  'ski-erg': { ro: 'Intervale la SkiErg', th: 'สกีเอิร์กอินเทอร์วัล' },
  'assault-bike': { ro: 'Sprint la bicicleta Assault', th: 'สปรินต์แอร์ไบค์' },
  'box-jump': { ro: 'Sărituri pe cutie', th: 'บ็อกซ์จัมป์' },
  'sled-push': { ro: 'Împins sania', th: 'ดันสเลด' },
  'jump-rope': { ro: 'Sărit coarda', th: 'กระโดดเชือก' },
  'treadmill-walk': { ro: 'Mers la bandă', th: 'เดินบนลู่วิ่ง', enAliases: ['treadmill walking'], roAliases: ['banda', 'mers banda', 'mers pe banda'], thAliases: ['ลู่วิ่ง', 'เดินลู่วิ่ง'] },
  'treadmill-run': { ro: 'Alergare la bandă', th: 'วิ่งบนลู่วิ่ง', enAliases: ['treadmill running'], roAliases: ['banda', 'alergat la banda', 'alergare banda'], thAliases: ['ลู่วิ่ง', 'วิ่งลู่วิ่ง'] },
  'world-greatest-stretch': { ro: 'Întinderea completă a corpului', th: 'เวิลด์เกรเทสต์สเตรตช์' },
  'couch-stretch': { ro: 'Întindere couch', th: 'คาวช์สเตรตช์' },
  'thoracic-rotation': { ro: 'Rotație toracică', th: 'หมุนกระดูกสันหลังช่วงอก' },
  'band-dislocate': { ro: 'Mobilizare umeri cu banda', th: 'หมุนไหล่ด้วยยางยืด' },
  'cat-cow': { ro: 'Mobilizare pisică-vacă', th: 'ท่าแมวสลับวัว' },
  'ninety-ninety': { ro: 'Schimbare de șold 90/90', th: 'สลับสะโพก 90/90' },
  'ankle-rock': { ro: 'Mobilizare de gleznă', th: 'โยกข้อเท้าเพิ่มความคล่องตัว' },
  'dead-bug': { ro: 'Dead bug', th: 'เดดบั๊ก' },
  'bird-dog': { ro: 'Bird dog', th: 'เบิร์ดด็อก' },
  'foam-roll-legs': { ro: 'Foam rolling pentru partea inferioară', th: 'โฟมโรลช่วงล่าง' },
}

const LEGACY_EXERCISE_CATALOG = rows.map(([
  id, name, category, equipment, muscles, dayType, sets = 3, reps = 10, rest = 60, unit = 'reps', perSide = false,
]) => {
  const localized = LOCALIZED_EXERCISES[id] ?? { ro: name, th: name }
  return {
    id, name, category, equipment, muscles, dayType, sets, reps, rest, unit, perSide,
    names: { en: name, ro: localized.ro, th: localized.th },
    aliases: {
      en: localized.enAliases ?? [],
      ro: localized.roAliases ?? [],
      th: localized.thAliases ?? [],
    },
  }
})

const normalise = (value: string): string => value
  .normalize('NFD')
  .replace(/\p{Diacritic}/gu, '')
  .toLocaleLowerCase('en')
  .replace(/[^\p{Letter}\p{Number}]+/gu, '')

const canonicalByID = new Map<string, Movement | CardioModality>([
  ...MOVEMENTS.map((movement) => [movement.id, movement] as const),
  ...CARDIO_MODALITIES.map((modality) => [modality.id, modality] as const),
])
const canonicalByName = new Map(
  [...MOVEMENTS, ...CARDIO_MODALITIES].map((item) => [normalise(item.name), item] as const),
)

function canonicalIDForLegacy(item: (typeof LEGACY_EXERCISE_CATALOG)[number]): string | null {
  const authoredAlias = MOVEMENT_ALIASES[item.name]
  if (authoredAlias) return authoredAlias
  const cardioAlias = CARDIO_ALIASES[item.name]?.modality
  if (cardioAlias) return cardioAlias
  const slug = item.id.replaceAll('-', '_')
  if (canonicalByID.has(slug)) return slug
  return canonicalByName.get(normalise(item.name))?.id ?? null
}

const legacyByCanonicalID = new Map<string, (typeof LEGACY_EXERCISE_CATALOG)[number][]>()
for (const item of LEGACY_EXERCISE_CATALOG) {
  const canonicalID = canonicalIDForLegacy(item)
  if (!canonicalID) continue
  const matches = legacyByCanonicalID.get(canonicalID) ?? []
  matches.push(item)
  legacyByCanonicalID.set(canonicalID, matches)
}

const authoredAliasesByCanonicalID = new Map<string, string[]>()
for (const [alias, canonicalID] of Object.entries(MOVEMENT_ALIASES)) {
  const aliases = authoredAliasesByCanonicalID.get(canonicalID) ?? []
  aliases.push(alias)
  authoredAliasesByCanonicalID.set(canonicalID, aliases)
}
for (const [alias, pair] of Object.entries(CARDIO_ALIASES)) {
  const aliases = authoredAliasesByCanonicalID.get(pair.modality) ?? []
  aliases.push(alias)
  authoredAliasesByCanonicalID.set(pair.modality, aliases)
}

const HYROX_ORDER = HYROX_STATIONS.map((station) =>
  station.movementId ?? station.cardio!.modality
)

/* Category shelves normally follow search relevance. A competition whose
 * stations have a fixed sequence is different: the list itself should teach
 * the race from the first station to the finish. This map is also exported
 * into the generated native catalogue, so web and iPhone cannot drift. */
export const EXERCISE_CATEGORY_ORDERS: Partial<Record<ExerciseCategory, string[]>> = {
  hyrox: HYROX_ORDER,
}

const HYROX_IDS = new Set(HYROX_ORDER)
const OLYMPIC_WEIGHTLIFTING_IDS = new Set(['power_clean', 'power_snatch', 'clean_and_jerk'])
const POWERLIFTING_IDS = new Set(['barbell_back_squat', 'barbell_bench_press', 'conventional_deadlift'])
const STREET_WORKOUT_IDS = new Set(
  [...legacyByCanonicalID]
    .filter(([, matches]) => matches.some((match) => match.category === 'street'))
    .map(([canonicalID]) => canonicalID),
)
const FREE_WEIGHT_EQUIPMENT = new Set([
  'barbell', 'plates', 'dumbbells', 'kettlebell', 'trap_bar', 'ez_bar',
  'landmine', 'medicine_ball', 'sandbag', 'weight_plate', 'backpack',
  'steel_mace', 'atlas_stone',
])

function movementCategories(movement: Movement): ExerciseCategory[] {
  const categories = new Set<ExerciseCategory>()
  const disciplines = new Set(movement.disciplines)
  const equipment = [...movement.equipment, ...movement.equipmentAnyOf.flat()]

  if (HYROX_IDS.has(movement.id)) categories.add('hyrox')
  if (OLYMPIC_WEIGHTLIFTING_IDS.has(movement.id)) categories.add('olympic_weightlifting')
  if (POWERLIFTING_IDS.has(movement.id)) categories.add('powerlifting')
  if (STREET_WORKOUT_IDS.has(movement.id)) categories.add('street')
  if (disciplines.has('olympic_weightlifting')) categories.add('olympic_weightlifting')
  if (disciplines.has('powerlifting')) categories.add('powerlifting')
  if (disciplines.has('street_workout')) categories.add('street')
  for (const discipline of ['crossfit', 'kettlebell_sport', 'strongman', 'strength', 'calisthenics', 'yoga', 'pilates', 'balance'] as const) {
    if (disciplines.has(discipline)) categories.add(discipline)
  }
  if (
    disciplines.has('hiit') || disciplines.has('conditioning') || disciplines.has('crossfit')
    || ['conditioning_complex', 'plyometric', 'power_throw'].includes(movement.entityType)
  ) categories.add('hiit')
  if (disciplines.has('mobility') || movement.entityType === 'mobility_drill') categories.add('mobility')
  if (equipment.some((item) => item.includes('machine') || item === 'cable_stack' || item === 'reformer')) categories.add('machine')
  if (equipment.some((item) => FREE_WEIGHT_EQUIPMENT.has(item))) categories.add('weights')

  return [...categories]
}

function primaryCategory(categories: ExerciseCategory[]): ExerciseCategory {
  for (const candidate of ['machine', 'weights', 'calisthenics', 'hiit', 'mobility', 'yoga', 'pilates', 'balance', 'strength'] as const) {
    if (categories.includes(candidate)) return candidate
  }
  return categories[0] ?? 'strength'
}

const MUSCLE_GROUPS: Record<string, HoloMuscleGroup[]> = {
  chest: ['chest'], upper_chest: ['chest'], front_delts: ['frontDelts'], side_delts: ['sideDelts'],
  rear_delts: ['rearDelts'], biceps: ['biceps'], triceps: ['triceps'], forearms: ['forearms'],
  upper_back: ['upperBack'], lats: ['lats'], erectors: ['lowerBack'], lower_back: ['lowerBack'],
  core: ['abs', 'obliques'], abs: ['abs'], obliques: ['obliques'], glutes: ['glutes'],
  glute_medius: ['glutes'], quadriceps: ['quads'], hamstrings: ['hamstrings'], adductors: ['adductors'],
  calves: ['calves'], traps: ['neckTraps'], full_body: ['chest', 'upperBack', 'abs', 'glutes', 'quads'],
}

function holoMuscles(movement: Movement): HoloMuscleGroup[] {
  return [...new Set(
    [...movement.primaryMuscles, ...movement.secondaryMuscles]
      .flatMap((muscle) => MUSCLE_GROUPS[muscle] ?? []),
  )]
}

function dayTypeFor(movement: Movement): DayType {
  if (movement.disciplines.some((discipline) => ['mobility', 'yoga', 'pilates', 'balance'].includes(discipline))) return 'mobility'
  if (movement.disciplines.some((discipline) => ['hiit', 'conditioning', 'crossfit'].includes(discipline))) return 't25'
  if (['squat', 'lunge', 'calf'].includes(movement.pattern)) return 'legs_b'
  if (movement.pattern === 'hip_hinge' || movement.pattern === 'isolation_lower') return 'legs_a'
  if (movement.pattern.includes('push')) return 'push'
  if (movement.pattern.includes('pull')) return 'pull'
  return 'upper'
}

function defaultSets(movement: Movement): number {
  if (['movement_sequence', 'breathing_recovery'].includes(movement.entityType)) return 1
  if (['mobility_drill', 'yoga_pose', 'balance_drill'].includes(movement.entityType)) return 2
  if (['conditioning_complex', 'plyometric', 'power_throw'].includes(movement.entityType)) return 4
  return movement.role === 'primary' ? 4 : 3
}

function defaultRest(movement: Movement): number {
  if (['mobility_drill', 'yoga_pose', 'movement_sequence', 'breathing_recovery'].includes(movement.entityType)) return 15
  if (movement.entityType === 'balance_drill') return 30
  if (['conditioning_complex', 'plyometric', 'power_throw'].includes(movement.entityType)) return 60
  if (movement.fatigueCost >= 5) return 150
  if (movement.fatigueCost >= 4) return 120
  if (movement.fatigueCost >= 3) return 90
  return 60
}

function humaniseEquipment(equipment: string[]): string {
  if (equipment.length === 0) return 'Bodyweight'
  return equipment
    .map((item) => item.replaceAll('_', ' ').replace(/\b\w/g, (letter) => letter.toUpperCase()))
    .join(' · ')
}

function localisations(canonicalID: string, name: string): Pick<ExerciseCatalogItem, 'names' | 'aliases'> {
  const legacy = legacyByCanonicalID.get(canonicalID) ?? []
  const preferred = legacy.find((item) => normalise(item.name) === normalise(name)) ?? legacy[0]
  const aliasesFor = (language: IntroLanguage): string[] => [...new Set([
    ...(language === 'en' ? authoredAliasesByCanonicalID.get(canonicalID) ?? [] : []),
    ...legacy.flatMap((item) => [item.names[language], ...item.aliases[language]]),
  ].filter((alias) => normalise(alias) !== normalise(preferred?.names[language] ?? name)))]

  return {
    names: {
      en: name,
      ro: preferred?.names.ro ?? name,
      th: preferred?.names.th ?? name,
    },
    aliases: {
      en: aliasesFor('en'),
      ro: aliasesFor('ro'),
      th: aliasesFor('th'),
    },
  }
}

function exerciseFromMovement(movement: Movement): ExerciseCatalogItem {
  const categories = movementCategories(movement)
  const legacyMuscles = (legacyByCanonicalID.get(movement.id) ?? []).flatMap((item) => item.muscles)
  return {
    id: movement.id,
    movementID: movement.id,
    name: movement.name,
    category: primaryCategory(categories),
    categories,
    equipment: humaniseEquipment(movement.equipment),
    muscles: [...new Set([...holoMuscles(movement), ...legacyMuscles])],
    dayType: dayTypeFor(movement),
    sets: defaultSets(movement),
    reps: Math.round(((movement.repLow ?? 10) + (movement.repHigh ?? movement.repLow ?? 10)) / 2),
    rest: defaultRest(movement),
    unit: movement.repUnit as RepUnit,
    perSide: movement.unilateral,
    loadable: movement.loadable,
    incrementKG: movement.minIncrementKg ?? 0,
    ...localisations(movement.id, movement.name),
  }
}

function exerciseFromCardio(modality: CardioModality): ExerciseCatalogItem {
  const categories: ExerciseCategory[] = HYROX_IDS.has(modality.id) ? ['hyrox', 'cardio'] : ['cardio']
  return {
    id: modality.id,
    movementID: modality.id,
    name: modality.name,
    category: 'cardio',
    categories,
    equipment: humaniseEquipment(modality.equipment),
    muscles: modality.upperShare > 0.5
      ? ['frontDelts', 'upperBack', 'abs']
      : ['quads', 'hamstrings', 'glutes', ...(modality.upperShare > 0.2 ? ['upperBack' as const] : [])],
    dayType: 't25',
    sets: 1,
    reps: 25,
    rest: 0,
    unit: 'minutes',
    perSide: false,
    loadable: false,
    incrementKG: 0,
    ...localisations(modality.id, modality.name),
  }
}

export const EXERCISE_CATALOG: ExerciseCatalogItem[] = [
  ...MOVEMENTS.map(exerciseFromMovement),
  ...CARDIO_MODALITIES.map(exerciseFromCardio),
]

export function displayExerciseName(item: ExerciseCatalogItem, language: IntroLanguage): string {
  return item.names[language]
}

export function isTreadmillExercise(item: ExerciseCatalogItem | null | undefined): boolean {
  return item?.movementID === 'treadmill'
}

function searchable(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLocaleLowerCase('en')
    .replace(/[^\p{Letter}\p{Number}]+/gu, ' ')
    .trim()
}

const MUSCLE_SEARCH_TERMS: Record<IntroLanguage, Partial<Record<HoloMuscleGroup, string[]>>> = {
  en: {
    chest: ['chest', 'pecs'], frontDelts: ['shoulders', 'front delts'], sideDelts: ['shoulders', 'side delts'], rearDelts: ['shoulders', 'rear delts'],
    biceps: ['biceps'], triceps: ['triceps'], forearms: ['forearms'], upperBack: ['upper back'], lats: ['back', 'lats'], lowerBack: ['lower back'],
    abs: ['abs', 'abdominals', 'core'], obliques: ['obliques', 'core'], glutes: ['glutes'], quads: ['quads'], hamstrings: ['hamstrings'],
    adductors: ['adductors', 'inner thigh'], calves: ['calves', 'calf'], neckTraps: ['traps', 'trapezius'],
  },
  ro: {
    chest: ['piept', 'pectorali'], frontDelts: ['umeri', 'deltoid anterior'], sideDelts: ['umeri', 'deltoid lateral'], rearDelts: ['umeri', 'deltoid posterior'],
    biceps: ['biceps'], triceps: ['triceps'], forearms: ['antebrate'], upperBack: ['spate superior'], lats: ['spate', 'dorsali'], lowerBack: ['lombari', 'spate inferior'],
    abs: ['abdomene', 'abdomen', 'abdominali'], obliques: ['oblici', 'abdomen'], glutes: ['fesieri'], quads: ['cvadricepsi', 'coapse'], hamstrings: ['femurali', 'coapse'],
    adductors: ['aductori', 'adductori', 'interior coapse'], calves: ['gambe', 'gamba'], neckTraps: ['trapez'],
  },
  th: {
    chest: ['อก', 'หน้าอก'], frontDelts: ['ไหล่'], sideDelts: ['ไหล่'], rearDelts: ['หัวไหล่หลัง'], biceps: ['ไบเซปส์'], triceps: ['ไตรเซปส์'],
    forearms: ['ปลายแขน'], upperBack: ['หลังส่วนบน'], lats: ['หลัง', 'ปีก'], lowerBack: ['หลังส่วนล่าง'], abs: ['หน้าท้อง', 'กล้ามท้อง'], obliques: ['หน้าท้องด้านข้าง'],
    glutes: ['ก้น', 'สะโพก'], quads: ['ต้นขาหน้า'], hamstrings: ['ต้นขาหลัง'], adductors: ['ต้นขาด้านใน', 'กล้ามเนื้อหุบขา'], calves: ['น่อง'], neckTraps: ['บ่า', 'ทราพีเซียส'],
  },
}

function editDistance(left: string, right: string): number {
  if (left === right) return 0
  let beforePrevious: number[] | null = null
  let previous = Array.from({ length: right.length + 1 }, (_, index) => index)
  for (let leftIndex = 1; leftIndex <= left.length; leftIndex++) {
    const current = [leftIndex]
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex++) {
      current[rightIndex] = Math.min(
        current[rightIndex - 1] + 1,
        previous[rightIndex] + 1,
        previous[rightIndex - 1] + Number(left[leftIndex - 1] !== right[rightIndex - 1]),
      )
      if (
        beforePrevious &&
        leftIndex > 1 &&
        rightIndex > 1 &&
        left[leftIndex - 1] === right[rightIndex - 2] &&
        left[leftIndex - 2] === right[rightIndex - 1]
      ) {
        current[rightIndex] = Math.min(current[rightIndex], beforePrevious[rightIndex - 2] + 1)
      }
    }
    beforePrevious = previous
    previous = current
  }
  return previous[right.length]
}

function termScore(term: string, tokens: string[], joined: string): number | null {
  let best: number | null = null
  for (const token of tokens) {
    if (token === term) return 90
    if (token.startsWith(term)) best = Math.max(best ?? 0, 70)
    else if (token.includes(term)) best = Math.max(best ?? 0, 55)
    if (term.length < 4) continue
    const allowed = term.length >= 7 ? 2 : 1
    if (Math.abs(token.length - term.length) > allowed) continue
    const distance = editDistance(term, token)
    if (distance <= allowed) best = Math.max(best ?? 0, 38 - distance * 8)
  }
  return best ?? (joined.includes(term) ? 45 : null)
}

export function catalogExerciseByName(name: string): ExerciseCatalogItem | null {
  const normalized = searchable(name.split(' · ')[0])
  return EXERCISE_CATALOG.find((item) =>
    searchable(item.id) === normalized || searchable(item.movementID) === normalized ||
    Object.values(item.names).some((value) => searchable(value) === normalized) ||
    Object.values(item.aliases).flat().some((value) => searchable(value) === normalized),
  ) ?? null
}

export function searchExerciseCatalog(
  query: string,
  category: 'all' | ExerciseCategory,
  language: IntroLanguage = 'en',
): ExerciseCatalogItem[] {
  const terms = searchable(query).split(/\s+/).filter(Boolean)
  const categoryOrder = category === 'all' ? [] : EXERCISE_CATEGORY_ORDERS[category] ?? []
  const categoryRank = new Map(categoryOrder.map((id, index) => [id, index]))
  return EXERCISE_CATALOG
    .filter((item) => category === 'all' || item.categories.includes(category))
    .map((item) => {
      const nativeName = searchable(item.names[language])
      const nativeAliases = item.aliases[language].map(searchable)
      const allNames = Object.values(item.names).map(searchable)
      const allAliases = Object.values(item.aliases).flat().map(searchable)
      const muscleTerms = item.muscles.flatMap((muscle) => MUSCLE_SEARCH_TERMS[language][muscle] ?? []).map(searchable)
      const haystack = searchable(`${allNames.join(' ')} ${allAliases.join(' ')} ${muscleTerms.join(' ')} ${item.equipment} ${item.muscles.join(' ')}`)
      const tokens = haystack.split(/\s+/).filter(Boolean)
      const scores = terms.map((term) => termScore(term, tokens, haystack))
      if (scores.some((score) => score == null)) return null
      const directHaystack = searchable(`${nativeName} ${nativeAliases.join(' ')}`)
      const directTokens = directHaystack.split(/\s+/).filter(Boolean)
      const directScores = terms.map((term) => termScore(term, directTokens, directHaystack))
      const directMatchBonus = directScores.every((score) => score != null)
        ? 120 + directScores.reduce<number>((sum, score) => sum + (score ?? 0), 0)
        : 0
      const joined = terms.join(' ')
      const nativeStart = terms.length > 0 && nativeName.startsWith(joined)
      const aliasStart = nativeAliases.some((alias) => alias.startsWith(joined))
      const nativeHits = terms.filter((term) => nativeName.includes(term)).length
      const fuzzyScore = scores.reduce<number>((sum, score) => sum + (score ?? 0), 0)
      return { item, score: directMatchBonus + (nativeStart ? 200 : 0) + (aliasStart ? 150 : 0) + nativeHits * 20 + fuzzyScore - nativeName.length / 100 }
    })
    .filter((value): value is { item: ExerciseCatalogItem; score: number } => value != null)
    .sort((a, b) => {
      const order = (categoryRank.get(a.item.id) ?? Number.MAX_SAFE_INTEGER)
        - (categoryRank.get(b.item.id) ?? Number.MAX_SAFE_INTEGER)
      return order || b.score - a.score
        || a.item.names[language].localeCompare(b.item.names[language], language)
    })
    .map(({ item }) => item)
}
