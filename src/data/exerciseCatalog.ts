import type { DayType, RepUnit } from '../lib/types'
import type { HoloMuscleGroup } from '../components/hologram/muscleMap'
import type { IntroLanguage } from '../lib/introLanguage'

export type ExerciseCategory = 'machine' | 'weights' | 'calisthenics' | 'street' | 'hiit' | 'cardio' | 'mobility'

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
  names: Record<IntroLanguage, string>
  aliases: Record<IntroLanguage, string[]>
}

export const EXERCISE_CATEGORIES: Array<{ id: 'all' | ExerciseCategory; label: string }> = [
  { id: 'all', label: 'All styles' },
  { id: 'machine', label: 'Gym machines' },
  { id: 'weights', label: 'Free weights' },
  { id: 'calisthenics', label: 'Calisthenics' },
  { id: 'street', label: 'Street workout' },
  { id: 'hiit', label: 'HIIT & conditioning' },
  { id: 'cardio', label: 'Cardio machines' },
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
  ['chest-supported-machine-row', 'Chest-Supported Machine Row', 'machine', 'Plate-loaded or selectorized row', ['lats', 'upperBack', 'rearDelts', 'biceps'], 'pull', 4, 10, 90],
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
  'standing-calf-machine': { ro: 'Ridicări pe vârfuri la aparat', th: 'เครื่องยืนเขย่งน่อง' },
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

export const EXERCISE_CATALOG: ExerciseCatalogItem[] = rows.map(([
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

export function displayExerciseName(item: ExerciseCatalogItem, language: IntroLanguage): string {
  return item.names[language]
}

export function isTreadmillExercise(item: ExerciseCatalogItem | null | undefined): boolean {
  return item?.id === 'treadmill-walk' || item?.id === 'treadmill-run'
}

function searchable(value: string): string {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLocaleLowerCase('en')
    .replace(/[^\p{Letter}\p{Number}]+/gu, ' ')
    .trim()
}

export function catalogExerciseByName(name: string): ExerciseCatalogItem | null {
  const normalized = searchable(name.split(' · ')[0])
  return EXERCISE_CATALOG.find((item) =>
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
  return EXERCISE_CATALOG
    .filter((item) => category === 'all' || item.category === category)
    .map((item) => {
      const nativeName = searchable(item.names[language])
      const nativeAliases = item.aliases[language].map(searchable)
      const allNames = Object.values(item.names).map(searchable)
      const allAliases = Object.values(item.aliases).flat().map(searchable)
      const haystack = searchable(`${allNames.join(' ')} ${allAliases.join(' ')} ${item.equipment} ${item.muscles.join(' ')}`)
      if (!terms.every((term) => haystack.includes(term))) return null
      const joined = terms.join(' ')
      const nativeStart = terms.length > 0 && nativeName.startsWith(joined)
      const aliasStart = nativeAliases.some((alias) => alias.startsWith(joined))
      const nativeHits = terms.filter((term) => nativeName.includes(term)).length
      return { item, score: (nativeStart ? 200 : 0) + (aliasStart ? 150 : 0) + nativeHits * 20 - nativeName.length / 100 }
    })
    .filter((value): value is { item: ExerciseCatalogItem; score: number } => value != null)
    .sort((a, b) => b.score - a.score || a.item.names[language].localeCompare(b.item.names[language], language))
    .map(({ item }) => item)
}
