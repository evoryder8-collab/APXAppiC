import { createContext, useCallback, useContext, useLayoutEffect, useState, type ReactNode } from 'react'
import {
  getIntroLanguage,
  isSelectableIntroLanguage,
  LANGUAGE_CHANGE_EVENT,
  setIntroLanguage,
  type IntroLanguage,
} from './introLanguage'
import { ACTIVITY_TRANSLATIONS, DATE_WORDS, UI_TRANSLATIONS } from './translations'
import { translateAvatarAssessmentSummary } from './avatarLocalization'

interface LanguageContextValue {
  language: IntroLanguage
  setLanguage: (language: IntroLanguage) => void
}

const LanguageContext = createContext<LanguageContextValue | null>(null)

const activityMap = Object.fromEntries(
  ACTIVITY_TRANSLATIONS.map(([english, romanian, thai]) => [english, { ro: romanian, th: thai }]),
)

const exactTranslations = { ...UI_TRANSLATIONS, ...activityMap }

const segments: Array<[string, string, string]> = [
  ['% to level', '% până la nivelul', '% ถึงระดับ'],
  [' exercises', ' exerciții', ' ท่า'],
  [' exercise', ' exercițiu', ' ท่า'],
  [' DAYS', ' ZILE', ' วัน'],
  [' DAY', ' ZI', ' วัน'],
  [' or ', ' sau ', ' หรือ '],
  ['completed workouts between', 'antrenamente finalizate între date', 'การฝึกที่เสร็จในช่วงนี้'],
  ['newest first', 'cele mai noi primele', 'ล่าสุดก่อน'],
  ['planned sessions completed in the last 14 days', 'sesiuni planificate finalizate în ultimele 14 zile', 'การฝึกตามแผนที่ทำเสร็จใน 14 วันล่าสุด'],
  ['days since mobility work', 'zile de la ultima sesiune de mobilitate', 'วันนับจากการฝึกความคล่องตัวครั้งล่าสุด'],
  ['days since a push or pull day', 'zile de la ultima zi de împins sau tras', 'วันนับจากวันฝึกดันหรือดึงครั้งล่าสุด'],
  ['on target on', 'la obiectiv în', 'ถึงเป้าใน'],
  ['of logged days', 'din zilele înregistrate', 'ของวันที่บันทึก'],
  ['instead of cutting lower', 'în loc să scadă mai mult', 'แทนที่จะลดลงอีก'],
  ['than the textbook estimate', 'față de estimarea standard', 'กว่าค่ามาตรฐาน'],
  ['Calibrated from your recent logged intake and morning weight.', 'Calibrat din aportul recent și greutatea de dimineață.', 'ปรับเทียบจากอาหารที่บันทึกล่าสุดและน้ำหนักตอนเช้า'],
  ['Your engine runs about', 'Motorul tău funcționează cu aproximativ', 'ระบบของคุณทำงานประมาณ'],
  ['hotter', 'mai intens', 'สูงกว่า'],
  ['cooler', 'mai lent', 'ต่ำกว่า'],
  ['estimated TDEE', 'TDEE estimat', 'TDEE โดยประมาณ'],
  ['activity', 'activitate', 'กิจกรรม'],
  ['final', 'final', 'สรุปแล้ว'],
  ['planned', 'planificat', 'ตามแผน'],
  ['net kcal', 'kcal nete', 'แคลอรีสุทธิ'],
  ['kcal day', 'kcal pe zi', 'แคลอรีต่อวัน'],
  ['Training at', 'Antrenament la', 'ฝึกเวลา'],
  ['Morning', 'Dimineață', 'ตอนเช้า'],
  ['Breakfast', 'Mic dejun', 'อาหารเช้า'],
  ['Lunch', 'Prânz', 'อาหารกลางวัน'],
  ['Dinner', 'Cină', 'อาหารเย็น'],
  ['Snack', 'Gustare', 'ของว่าง'],
  ['Wake', 'Trezire', 'ตื่นนอน'],
  ['Pre-workout', 'Înainte de antrenament', 'ก่อนฝึก'],
  ['Post-workout', 'După antrenament', 'หลังฝึก'],
  ['Before sleep', 'Înainte de somn', 'ก่อนนอน'],
  ['Upper Body Strength', 'Forță partea superioară', 'ความแข็งแรงช่วงบน'],
  ['Lower Body Strength', 'Forță partea inferioară', 'ความแข็งแรงช่วงล่าง'],
  ['Overall Fitness Level', 'Nivel general de fitness', 'ระดับความฟิตโดยรวม'],
  ['Health', 'Sănătate', 'สุขภาพ'],
  ['Joint Health Balance', 'Echilibrul articulațiilor', 'สมดุลสุขภาพข้อต่อ'],
  ['Body Flexibility', 'Flexibilitate', 'ความยืดหยุ่น'],
  ['Endurance & VO2max', 'Anduranță și VO2max', 'ความอดทนและ VO2max'],
  ['Strength', 'Forță', 'ความแข็งแรง'],
  ['Endurance', 'Anduranță', 'ความอดทน'],
  ['Flexibility', 'Flexibilitate', 'ความยืดหยุ่น'],
  ['Joint Health', 'Sănătatea articulațiilor', 'สุขภาพข้อต่อ'],
  ['Upper', 'Superior', 'ช่วงบน'],
  ['Lower', 'Inferior', 'ช่วงล่าง'],
  ['Push-ups', 'Flotări', 'วิดพื้น'],
  ['Pushups', 'Flotări', 'วิดพื้น'],
  ['Pull-ups', 'Tracțiuni', 'ดึงข้อ'],
  ['Squats', 'Genuflexiuni', 'สควอท'],
  ['Lunges', 'Fandări', 'ลันจ์'],
  ['Hip Thrusts', 'Ridicări de bazin', 'ฮิปทรัสต์'],
  ['Romanian Deadlift', 'Îndreptări românești', 'โรมาเนียนเดดลิฟต์'],
  ['Calf Raises', 'Ridicări pe vârfuri', 'เขย่งน่อง'],
  ['Lateral Raises', 'Ridicări laterale', 'ยกแขนด้านข้าง'],
  ['Rows', 'Ramat', 'โรว์'],
  ['Curls', 'Flexii pentru biceps', 'ไบเซปเคิร์ล'],
  ['Plank', 'Planșă', 'แพลงก์'],
  ['Mobility', 'Mobilitate', 'ความคล่องตัว'],
  ['eggs', 'ouă', 'ฟอง'],
  ['egg', 'ou', 'ฟอง'],
  ['nut mix', 'mix de nuci', 'ถั่วรวม'],
  ['oats', 'ovăz', 'ข้าวโอ๊ต'],
  ['milk', 'lapte', 'นม'],
  ['berries', 'fructe de pădure', 'เบอร์รี'],
  ['banana', 'banană', 'กล้วย'],
  ['kiwi', 'kiwi', 'กีวี'],
  ['seed mix', 'mix de semințe', 'เมล็ดพืชรวม'],
  ['chicken hearts', 'inimi de pui', 'หัวใจไก่'],
  ['chicken', 'pui', 'ไก่'],
  ['sweet potato', 'cartof dulce', 'มันหวาน'],
  ['cottage cheese', 'brânză cottage', 'คอตเทจชีส'],
  ['avocado', 'avocado', 'อะโวคาโด'],
  ['Zero-starch, protein-first morning.', 'Dimineață fără amidon, cu proteina prima.', 'มื้อเช้าไม่มีแป้ง เริ่มด้วยโปรตีน'],
  ['Target-aligned portion', 'Porție aliniată obiectivului', 'ปริมาณตามเป้า'],
  ['change activity above to recalculate', 'schimbă activitatea pentru recalculare', 'เปลี่ยนกิจกรรมด้านบนเพื่อคำนวณใหม่'],
  ['gimbal', 'gimbal', 'กิมบอล'],
  ['rig carry', 'transport echipament', 'ขนอุปกรณ์'],
  ['run', 'alergare', 'วิ่ง'],
  ['steps', 'pași', 'ก้าว'],
]

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function translateDates(value: string, language: Exclude<IntroLanguage, 'en'>): string {
  let output = value
  const words = Object.entries(DATE_WORDS[language]).sort(([a], [b]) => b.length - a.length)
  for (const [english, translated] of words) {
    output = output.replace(new RegExp(`\\b${escapeRegExp(english)}\\b`, 'g'), translated)
  }
  return output
}

function translateDynamic(value: string, language: Exclude<IntroLanguage, 'en'>): string | null {
  const assessmentSummary = translateAvatarAssessmentSummary(value, language)
  if (assessmentSummary) return assessmentSummary

  const nameGreeting = value.match(/^Good (morning|afternoon|evening), (.+)\.$/)
  if (nameGreeting) {
    const [, period, name] = nameGreeting
    if (language === 'ro') {
      const greeting = period === 'morning' ? 'Bună dimineața' : period === 'afternoon' ? 'Bună ziua' : 'Bună seara'
      return `${greeting}, ${name}.`
    }
    const greeting = period === 'morning' ? 'อรุณสวัสดิ์' : period === 'afternoon' ? 'สวัสดีตอนบ่าย' : 'สวัสดีตอนเย็น'
    return `${greeting} ${name}`
  }
  const late = value.match(/^Up late, (.+)\.$/)
  if (late) return language === 'ro' ? `E târziu, ${late[1]}.` : `ยังไม่นอนอีกเหรอ ${late[1]}`

  const remaining = value.match(/^(\d[\d,.]*) kcal remain today\. Protein remaining: (\d[\d,.]*) g\.$/)
  if (remaining) return language === 'ro'
    ? `Mai ai ${remaining[1]} kcal și ${remaining[2]} g de proteine pentru azi.`
    : `วันนี้เหลือ ${remaining[1]} แคลอรี และโปรตีน ${remaining[2]} กรัม`

  const photos = value.match(/^(\d+) photos? · newest first$/)
  if (photos) return language === 'ro' ? `${photos[1]} fotografii · cele mai noi primele` : `${photos[1]} ภาพ · ล่าสุดก่อน`
  const days = value.match(/^(\d+) days? · (\d+) completed workouts between$/)
  if (days) return language === 'ro' ? `${days[1]} zile · ${days[2]} antrenamente finalizate` : `${days[1]} วัน · ฝึกเสร็จ ${days[2]} ครั้ง`
  const age = value.match(/^Age (\d+)$/)
  if (age) return language === 'ro' ? `Vârstă ${age[1]}` : `อายุ ${age[1]} ปี`
  const count = value.match(/^(\d+) (meals|supplements|workouts|photos|days)$/)
  if (count) {
    const nouns = language === 'ro'
      ? { meals: 'mese', supplements: 'suplimente', workouts: 'antrenamente', photos: 'fotografii', days: 'zile' }
      : { meals: 'มื้อ', supplements: 'รายการอาหารเสริม', workouts: 'การฝึก', photos: 'ภาพ', days: 'วัน' }
    return language === 'ro' ? `${count[1]} ${nouns[count[2] as keyof typeof nouns]}` : `${nouns[count[2] as keyof typeof nouns]} ${count[1]}`
  }
  const exerciseCount = value.match(/^~?(\d+) min · (\d+) exercises$/)
  if (exerciseCount) return language === 'ro'
    ? `~${exerciseCount[1]} min · ${exerciseCount[2]} exerciții`
    : `~${exerciseCount[1]} นาที · ${exerciseCount[2]} ท่า`
  const levelProgress = value.match(/^(\d+)% to level (\d+)$/)
  if (levelProgress) return language === 'ro' ? `${levelProgress[1]}% până la nivelul ${levelProgress[2]}` : `อีก ${levelProgress[1]}% ถึงระดับ ${levelProgress[2]}`
  const calibrated = value.match(/^Calibrated for (.+): age (\d+), ([\d.]+) kg, ([\d.]+)% body fat and ([\d.]+) cm\. (.+)$/)
  if (calibrated) return language === 'ro'
    ? `Calibrat pentru ${calibrated[1]}: ${calibrated[2]} ani, ${calibrated[3]} kg, ${calibrated[4]}% grăsime corporală și ${calibrated[5]} cm. ${translateInterfaceText(calibrated[6], language)}`
    : `ปรับเทียบสำหรับ ${calibrated[1]}: อายุ ${calibrated[2]} ปี น้ำหนัก ${calibrated[3]} กก. ไขมัน ${calibrated[4]}% และส่วนสูง ${calibrated[5]} ซม. ${translateInterfaceText(calibrated[6], language)}`
  const baselineLabel = value.match(/^(Strength-Upper|Strength-Lower|Endurance|Flexibility|Joint Health|Health) ([\d.]+)$/)
  if (baselineLabel) return `${translateInterfaceText(baselineLabel[1], language)} ${baselineLabel[2]}`
  const overallWeights = value.match(/^Overall computes from the weights \(Strength 25%, Endurance 20%, Joint 20%, Health 20%,\s*Flexibility 15%\), starting at ([\d.]+)\.$/)
  if (overallWeights) return language === 'ro'
    ? `Scorul general folosește ponderile: Forță 25%, Anduranță 20%, Articulații 20%, Sănătate 20% și Flexibilitate 15%. Valoarea inițială este ${overallWeights[1]}.`
    : `คะแนนรวมคำนวณจากน้ำหนัก: ความแข็งแรง 25% ความอดทน 20% ข้อต่อ 20% สุขภาพ 20% และความยืดหยุ่น 15% โดยเริ่มที่ ${overallWeights[1]}`
  const rising = value.match(/^Your Overall score has risen ([\d.]+) points over the comparison window, so the current direction is productive\.$/)
  if (rising) return language === 'ro'
    ? `Scorul general a crescut cu ${rising[1]} puncte în perioada comparată, deci direcția actuală este bună.`
    : `คะแนนรวมเพิ่มขึ้น ${rising[1]} จุดในช่วงที่เปรียบเทียบ แสดงว่าทิศทางปัจจุบันกำลังได้ผล`
  const falling = value.match(/^Your Overall score has fallen ([\d.]+) points over the comparison window, which points to an underfed training or recovery input\.$/)
  if (falling) return language === 'ro'
    ? `Scorul general a scăzut cu ${falling[1]} puncte în perioada comparată, ceea ce indică alimentație sau recuperare insuficientă.`
    : `คะแนนรวมลดลง ${falling[1]} จุดในช่วงที่เปรียบเทียบ ซึ่งชี้ว่าอาหารหรือการฟื้นตัวยังไม่พอ`
  const restingHeartRate = value.match(/^Resting heart rate up ([\d.]+) bpm this week$/)
  if (restingHeartRate) return language === 'ro'
    ? `Pulsul de repaus a crescut cu ${restingHeartRate[1]} bpm săptămâna aceasta`
    : `ชีพจรขณะพักเพิ่มขึ้น ${restingHeartRate[1]} ครั้งต่อนาทีในสัปดาห์นี้`
  const enduranceDown = value.match(/^Endurance down ([\d.]+) points in 2 weeks$/)
  if (enduranceDown) return language === 'ro' ? `Anduranța a scăzut cu ${enduranceDown[1]} puncte în 2 săptămâni` : `ความอดทนลดลง ${enduranceDown[1]} จุดใน 2 สัปดาห์`
  const noCardio = value.match(/^No cardio in (\d+) days$/)
  if (noCardio) return language === 'ro' ? `Fără cardio de ${noCardio[1]} zile` : `ไม่ได้ทำคาร์ดิโอมา ${noCardio[1]} วัน`
  const flexibilityDown = value.match(/^Flexibility down ([\d.]+) points over 2 weeks$/)
  if (flexibilityDown) return language === 'ro' ? `Flexibilitatea a scăzut cu ${flexibilityDown[1]} puncte în 2 săptămâni` : `ความยืดหยุ่นลดลง ${flexibilityDown[1]} จุดใน 2 สัปดาห์`
  const mobilityDays = value.match(/^(\d+) days since mobility work$/)
  if (mobilityDays) return language === 'ro' ? `${mobilityDays[1]} zile de la ultima sesiune de mobilitate` : `ไม่ได้ฝึกความคล่องตัวมา ${mobilityDays[1]} วัน`
  const jointDown = value.match(/^Joint Health down ([\d.]+) points$/)
  if (jointDown) return language === 'ro' ? `Sănătatea articulațiilor a scăzut cu ${jointDown[1]} puncte` : `สุขภาพข้อต่อลดลง ${jointDown[1]} จุด`
  const healthDown = value.match(/^Health slipping, ([\d.]+) points in 2 weeks$/)
  if (healthDown) return language === 'ro' ? `Sănătatea a scăzut cu ${healthDown[1]} puncte în 2 săptămâni` : `สุขภาพลดลง ${healthDown[1]} จุดใน 2 สัปดาห์`
  const pushPullDays = value.match(/^(\d+) days since a push or pull day$/)
  if (pushPullDays) return language === 'ro' ? `${pushPullDays[1]} zile de la ultima zi de împins sau tras` : `ไม่ได้ฝึกดันหรือดึงมา ${pushPullDays[1]} วัน`
  const lagging = value.match(/^Strength-Lower is your lagging stat \(([\d.]+) vs ([\d.]+) upper\)$/)
  if (lagging) return language === 'ro'
    ? `Forța părții inferioare este în urmă (${lagging[1]} față de ${lagging[2]} sus)`
    : `ความแข็งแรงช่วงล่างยังตามหลัง (${lagging[1]} เทียบกับช่วงบน ${lagging[2]})`
  const strongest = value.match(/^(.+) is your strongest current signal at ([\d.]+)\.$/)
  if (strongest) return language === 'ro'
    ? `${translateInterfaceText(strongest[1], language)} este cea mai bună valoare acum, la ${strongest[2]}.`
    : `${translateInterfaceText(strongest[1], language)} เป็นค่าที่ดีที่สุดตอนนี้ที่ ${strongest[2]}`
  const runnerUp = value.match(/^(.+) is the next strongest quality at ([\d.]+), giving you a useful base to build from\.$/)
  if (runnerUp) return language === 'ro'
    ? `${translateInterfaceText(runnerUp[1], language)} este următoarea calitate, la ${runnerUp[2]}, și oferă o bază bună.`
    : `${translateInterfaceText(runnerUp[1], language)} เป็นค่ารองที่ดีที่สุดที่ ${runnerUp[2]} เป็นฐานที่ดีให้พัฒนาต่อ`
  const summary = value.match(/^(.+) is the clearest limiter at ([\d.]+), while (.+) currently leads at ([\d.]+)\. Your Overall score is broadly stable, so the next improvement will come from consistently feeding the weakest quality\.$/)
  if (summary) return language === 'ro'
    ? `${translateInterfaceText(summary[1], language)} este limita principală la ${summary[2]}, iar ${translateInterfaceText(summary[3], language)} conduce la ${summary[4]}. Scorul general este stabil; progresul următor vine din lucrul constant la punctul cel mai slab.`
    : `${translateInterfaceText(summary[1], language)} เป็นข้อจำกัดหลักที่ ${summary[2]} ส่วน ${translateInterfaceText(summary[3], language)} นำที่ ${summary[4]} คะแนนรวมค่อนข้างคงที่ ควรพัฒนาจุดที่อ่อนที่สุดอย่างต่อเนื่อง`
  const gap = value.match(/^Close the upper\/lower strength gap \(([\d.]+) vs ([\d.]+)\) by protecting both weekly lower-body exposures\.$/)
  if (gap) return language === 'ro'
    ? `Redu diferența dintre partea superioară și inferioară (${gap[1]} față de ${gap[2]}) păstrând ambele antrenamente de picioare.`
    : `ลดช่องว่างระหว่างช่วงบนและช่วงล่าง (${gap[1]} เทียบกับ ${gap[2]}) โดยรักษาการฝึกช่วงล่างทั้ง 2 ครั้งต่อสัปดาห์`
  const retained = value.match(/^Upper-body strength has retained a solid base at ([\d.]+) while the lower body catches up\.$/)
  if (retained) return language === 'ro'
    ? `Forța părții superioare are o bază bună la ${retained[1]}, iar partea inferioară recuperează.`
    : `ความแข็งแรงช่วงบนยังมีฐานที่ดีที่ ${retained[1]} ขณะที่ช่วงล่างกำลังไล่ตาม`
  const momentum = value.match(/^Momentum is positive: Overall \+([\d.]+)\.$/)
  if (momentum) return language === 'ro' ? `Direcția este pozitivă: scor general +${momentum[1]}.` : `แนวโน้มเป็นบวก: คะแนนรวม +${momentum[1]}`
  const sessions = value.match(/^(\d+) planned sessions? completed in the last 14 days\.$/)
  if (sessions) return language === 'ro'
    ? `${sessions[1]} sesiuni planificate finalizate în ultimele 14 zile.`
    : `ทำการฝึกตามแผนเสร็จ ${sessions[1]} ครั้งใน 14 วันล่าสุด`
  const proteinTarget = value.match(/^Protein was on target on (\d+)% of logged days\.$/)
  if (proteinTarget) return language === 'ro' ? `Proteina a fost la obiectiv în ${proteinTarget[1]}% din zilele înregistrate.` : `โปรตีนถึงเป้าใน ${proteinTarget[1]}% ของวันที่บันทึก`
  const hydrationTarget = value.match(/^Hydration was on target on (\d+)% of logged days\.$/)
  if (hydrationTarget) return language === 'ro' ? `Hidratarea a fost la obiectiv în ${hydrationTarget[1]}% din zilele înregistrate.` : `น้ำถึงเป้าใน ${hydrationTarget[1]}% ของวันที่บันทึก`
  const hydrationLow = value.match(/^Hydration reached target on only (\d+)% of logged days\. Build a repeatable 2\.5–3 L rhythm\.$/)
  if (hydrationLow) return language === 'ro'
    ? `Hidratarea a atins obiectivul în doar ${hydrationLow[1]}% din zilele înregistrate. Creează un ritm constant de 2,5-3 L.`
    : `น้ำถึงเป้าเพียง ${hydrationLow[1]}% ของวันที่บันทึก สร้างนิสัยดื่ม 2.5-3 ลิตรให้สม่ำเสมอ`
  const proteinLow = value.match(/^Protein reached target on only (\d+)% of logged days\. Distribute it across the target-aligned meals\.$/)
  if (proteinLow) return language === 'ro'
    ? `Proteina a atins obiectivul în doar ${proteinLow[1]}% din zilele înregistrate. Distribuie proteina între mesele stabilite.`
    : `โปรตีนถึงเป้าเพียง ${proteinLow[1]}% ของวันที่บันทึก แบ่งโปรตีนให้ครบในแต่ละมื้อตามเป้า`
  const appleCardio = value.match(/^Apple Watch cardio \(([\d.]+) min\) fed Endurance$/)
  if (appleCardio) return language === 'ro' ? `Cardio Apple Watch (${appleCardio[1]} min) a susținut anduranța` : `คาร์ดิโอจาก Apple Watch (${appleCardio[1]} นาที) เพิ่มค่าความอดทน`
  const appleStrength = value.match(/^Apple Watch strength work \(([\d.]+) min\) fed Strength$/)
  if (appleStrength) return language === 'ro' ? `Antrenamentul de forță Apple Watch (${appleStrength[1]} min) a susținut forța` : `การฝึกแรงจาก Apple Watch (${appleStrength[1]} นาที) เพิ่มค่าความแข็งแรง`
  const importedMobility = value.match(/^Imported mobility session \(([\d.]+) min\) fed Flexibility$/)
  if (importedMobility) return language === 'ro' ? `Sesiunea de mobilitate importată (${importedMobility[1]} min) a susținut flexibilitatea` : `การฝึกความคล่องตัวที่นำเข้า (${importedMobility[1]} นาที) เพิ่มค่าความยืดหยุ่น`
  const vo2Anchor = value.match(/^VO2max measured at ([\d.]+)\. Endurance anchored toward ([\d.]+)$/)
  if (vo2Anchor) return language === 'ro' ? `VO2max măsurat la ${vo2Anchor[1]}. Anduranța a fost calibrată spre ${vo2Anchor[2]}` : `วัด VO2max ได้ ${vo2Anchor[1]} ปรับค่าความอดทนไปทาง ${vo2Anchor[2]}`
  return null
}

export function translateInterfaceText(value: string, language: IntroLanguage): string {
  if (language === 'en' || !value.trim()) return value
  const leading = value.match(/^\s*/)?.[0] ?? ''
  const trailing = value.match(/\s*$/)?.[0] ?? ''
  const core = value.trim()
  const exact = exactTranslations[core]?.[language]
  if (exact) return `${leading}${exact}${trailing}`
  const dynamic = translateDynamic(core, language)
  if (dynamic) return `${leading}${dynamic}${trailing}`

  let translated = translateDates(core, language)
  for (const [english, romanian, thai] of segments.sort(([a], [b]) => b.length - a.length)) {
    if (!translated.includes(english)) continue
    translated = translated.split(english).join(language === 'ro' ? romanian : thai)
  }
  return `${leading}${translated}${trailing}`
}

interface TextState { source: string; last: string }
interface AttributeState { source: string; last: string }

const textStates = new WeakMap<Text, TextState>()
const attributeStates = new WeakMap<Element, Map<string, AttributeState>>()
const translatedAttributes = ['placeholder', 'aria-label', 'title'] as const

function shouldSkip(node: Node): boolean {
  const parent = node instanceof Element ? node : node.parentElement
  if (!parent) return false
  return Boolean(parent.closest('script, style, code, [data-no-translate], [contenteditable="true"]'))
}

function translateTextNode(node: Text, language: IntroLanguage): void {
  if (shouldSkip(node)) return
  const current = node.nodeValue ?? ''
  let state = textStates.get(node)
  if (!state) {
    state = { source: current, last: current }
    textStates.set(node, state)
  } else if (current !== state.last) {
    state.source = current
  }
  const translated = translateInterfaceText(state.source, language)
  state.last = translated
  if (current !== translated) node.nodeValue = translated
}

function translateElementAttributes(element: Element, language: IntroLanguage): void {
  if (shouldSkip(element)) return
  let states = attributeStates.get(element)
  if (!states) {
    states = new Map()
    attributeStates.set(element, states)
  }
  for (const attribute of translatedAttributes) {
    const current = element.getAttribute(attribute)
    if (current == null) continue
    let state = states.get(attribute)
    if (!state) {
      state = { source: current, last: current }
      states.set(attribute, state)
    } else if (current !== state.last) {
      state.source = current
    }
    const translated = translateInterfaceText(state.source, language)
    state.last = translated
    if (current !== translated) element.setAttribute(attribute, translated)
  }
}

function translateTree(node: Node, language: IntroLanguage): void {
  if (node.nodeType === Node.TEXT_NODE) {
    translateTextNode(node as Text, language)
    return
  }
  if (!(node instanceof Element) || shouldSkip(node)) return
  translateElementAttributes(node, language)
  for (const child of node.childNodes) translateTree(child, language)
}

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [language, setLanguageState] = useState<IntroLanguage>(getIntroLanguage)

  const setLanguage = useCallback((nextLanguage: IntroLanguage) => {
    setIntroLanguage(nextLanguage)
    setLanguageState(nextLanguage)
  }, [])

  useLayoutEffect(() => {
    const onLanguageChange = (event: Event): void => {
      const next = (event as CustomEvent<unknown>).detail
      if (isSelectableIntroLanguage(next)) setLanguageState(next)
    }
    window.addEventListener(LANGUAGE_CHANGE_EVENT, onLanguageChange)
    return () => window.removeEventListener(LANGUAGE_CHANGE_EVENT, onLanguageChange)
  }, [])

  useLayoutEffect(() => {
    document.documentElement.lang = language
    if (document.body) translateTree(document.body, language)
    // English is the authored source language, so it needs no continuous DOM
    // observer. This keeps the default experience at effectively zero runtime
    // localization cost while Romanian and Thai remain live for lazy content.
    if (language === 'en') return
    const observer = new MutationObserver((records) => {
      for (const record of records) {
        if (record.type === 'characterData') translateTextNode(record.target as Text, language)
        else if (record.type === 'attributes') translateElementAttributes(record.target as Element, language)
        else for (const node of record.addedNodes) translateTree(node, language)
      }
    })
    observer.observe(document.body, {
      subtree: true,
      childList: true,
      characterData: true,
      attributes: true,
      attributeFilter: [...translatedAttributes],
    })
    return () => observer.disconnect()
  }, [language])

  return <LanguageContext.Provider value={{ language, setLanguage }}>{children}</LanguageContext.Provider>
}

export function useLanguage(): LanguageContextValue {
  const context = useContext(LanguageContext)
  if (!context) throw new Error('useLanguage must be used inside LanguageProvider')
  return context
}
