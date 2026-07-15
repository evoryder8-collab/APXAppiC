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

const exactTranslations: Record<string, { ro: string; th: string }> = { ...UI_TRANSLATIONS, ...activityMap }
const foldedTranslations = new Map(Object.entries(exactTranslations).map(([key, value]) => [key.toLocaleLowerCase('en'), value]))

export function registerInterfaceTranslations(values: Record<string, { ro: string; th: string }>): void {
  Object.assign(exactTranslations, values)
  for (const [key, value] of Object.entries(values)) foldedTranslations.set(key.toLocaleLowerCase('en'), value)
}

const segments: Array<[string, string, string]> = [
  ['% to level', '% până la nivelul', '% ถึงระดับ'],
  [' exercises', ' exerciții', ' ท่า'],
  [' exercise', ' exercițiu', ' ท่า'],
  [' DAYS', ' ZILE', ' วัน'],
  [' DAY', ' ZI', ' วัน'],
  [' or ', ' sau ', ' หรือ '],
  ['completed workouts between', 'antrenamente finalizate între date', 'การฝึกที่เสร็จในช่วงนี้'],
  [' selected · matching poses work best', ' selectate · pozițiile identice sunt cele mai utile', ' ภาพที่เลือก · ใช้ท่าเดียวกันจะดีที่สุด'],
  [' checked today', ' bifate azi', ' รายการที่เช็กวันนี้'],
  [' days apart', ' zile diferență', ' วันห่างกัน'],
  ['Instead of ', 'În loc de ', 'แทน '],
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

  const mealAction = value.match(/^(Replace meal|Log meal) · ([\d,.]+) kcal$/)
  if (mealAction) {
    const action = translateInterfaceText(mealAction[1], language)
    return language === 'ro' ? `${action} · ${mealAction[2]} kcal` : `${action} · ${mealAction[2]} แคลอรี`
  }
  const adaptiveSuggestion = value.match(/^APEX suggests you (increase|reduce) this adjustable item\. (.+)$/)
  if (adaptiveSuggestion) {
    const direction = adaptiveSuggestion[1]
    const rationale = adaptiveSuggestion[2]
    const action = language === 'ro'
      ? (direction === 'increase' ? 'să mărești acest aliment adaptiv' : 'să reduci acest aliment adaptiv')
      : (direction === 'increase' ? 'เพิ่มปริมาณรายการที่ปรับได้' : 'ลดปริมาณรายการที่ปรับได้')
    if (rationale === 'Protein is meaningfully below today’s protected target.') {
      return language === 'ro'
        ? `APEX îți sugerează ${action}. Proteinele sunt semnificativ sub obiectivul protejat de azi.`
        : `APEX แนะนำให้${action} โปรตีนยังต่ำกว่าเป้าหมายที่ระบบปกป้องไว้สำหรับวันนี้อย่างชัดเจน`
    }
    const flexibleEnergy = rationale.match(/^(.+?)( training)? leaves (more|less) flexible energy for this meal\.$/)
    if (flexibleEnergy) {
      const activity = translateInterfaceText(flexibleEnergy[1], language)
      const training = Boolean(flexibleEnergy[2])
      const more = flexibleEnergy[3] === 'more'
      if (language === 'ro') {
        return `APEX îți sugerează ${action}. Nivelul ${activity}${training ? ' și antrenamentul' : ''} lasă ${more ? 'mai multă' : 'mai puțină'} energie flexibilă pentru această masă.`
      }
      return `APEX แนะนำให้${action} ระดับ${activity}${training ? 'และการฝึก' : ''}ทำให้มื้อนี้มีพลังงานที่ปรับได้${more ? 'มากขึ้น' : 'น้อยลง'}`
    }
  }
  const foodAmount = value.match(/^Amount for (.+)$/)
  if (foodAmount) return language === 'ro' ? `Cantitate pentru ${foodAmount[1]}` : `ปริมาณสำหรับ ${foodAmount[1]}`
  const plannedPrescription = value.match(/^(.+) · planned prescription$/)
  if (plannedPrescription) return `${translateInterfaceText(plannedPrescription[1], language)} · ${translateInterfaceText('planned prescription', language)}`
  const recordSummary = value.match(/^(\d+)\/(\d+) meals · (\d+)\/(\d+) supplements$/)
  if (recordSummary) return language === 'ro'
    ? `${recordSummary[1]}/${recordSummary[2]} mese · ${recordSummary[3]}/${recordSummary[4]} suplimente`
    : `มื้อ ${recordSummary[1]}/${recordSummary[2]} · อาหารเสริม ${recordSummary[3]}/${recordSummary[4]}`
  const checkedToday = value.match(/^(\d+)\/(\d+) checked today$/)
  if (checkedToday) return language === 'ro'
    ? `${checkedToday[1]}/${checkedToday[2]} bifate azi`
    : `เช็กวันนี้ ${checkedToday[1]}/${checkedToday[2]}`
  const calendarRecord = value.match(/^(.+): (\d+) meals, (\d+) supplements, ([\d.]+) litres water$/)
  if (calendarRecord) {
    const date = translateDates(calendarRecord[1], language)
    return language === 'ro'
      ? `${date}: ${calendarRecord[2]} mese, ${calendarRecord[3]} suplimente, ${calendarRecord[4]} litri de apă`
      : `${date}: ${calendarRecord[2]} มื้อ, ${calendarRecord[3]} รายการอาหารเสริม, น้ำ ${calendarRecord[4]} ลิตร`
  }
  const measuredBmr = value.match(/^Measured BMR active(?: · TDEE now uses)? ·?\s*(\d+)?\s*kcal$/)
  if (measuredBmr) {
    const amount = measuredBmr[1] ? ` · ${measuredBmr[1]} ${language === 'ro' ? 'kcal' : 'แคลอรี'}` : ''
    return `${translateInterfaceText('Measured BMR active', language)}${amount}`
  }

  const durationMission = value.match(/^(\d+) (minutes|min) · (.+)$/)
  if (durationMission) {
    const durationUnit = language === 'ro' ? 'min' : 'นาที'
    return `${durationMission[1]} ${durationUnit} · ${translateInterfaceText(durationMission[3], language)}`
  }
  const daysRemaining = value.match(/^(\d+) days remaining$/)
  if (daysRemaining) return language === 'ro' ? `${daysRemaining[1]} zile rămase` : `เหลือ ${daysRemaining[1]} วัน`
  const namedDaysRemaining = value.match(/^(.+) · (\d+) days remaining$/)
  if (namedDaysRemaining) return language === 'ro' ? `${namedDaysRemaining[1]} · ${namedDaysRemaining[2]} zile rămase` : `${namedDaysRemaining[1]} · เหลือ ${namedDaysRemaining[2]} วัน`
  const questionProgress = value.match(/^QUESTION (\d+) OF (\d+)$/)
  if (questionProgress) return language === 'ro' ? `ÎNTREBAREA ${questionProgress[1]} DIN ${questionProgress[2]}` : `คำถาม ${questionProgress[1]} จาก ${questionProgress[2]}`
  const knownProfile = value.match(/^APEX already knows: (age unavailable|age \d+) · (weight unavailable|[\d.]+ kg) · (\d+) strength days in the Main Phase\.$/)
  if (knownProfile) {
    const age = knownProfile[1] === 'age unavailable'
      ? (language === 'ro' ? 'vârstă indisponibilă' : 'ไม่พบข้อมูลอายุ')
      : (language === 'ro' ? `vârsta ${knownProfile[1].slice(4)}` : `อายุ ${knownProfile[1].slice(4)} ปี`)
    const weight = knownProfile[2] === 'weight unavailable'
      ? (language === 'ro' ? 'greutate indisponibilă' : 'ไม่พบข้อมูลน้ำหนัก')
      : (language === 'ro' ? knownProfile[2] : knownProfile[2].replace(' kg', ' กก.'))
    return language === 'ro'
      ? `APEX știe deja: ${age} · ${weight} · ${knownProfile[3]} zile de antrenament de forță în Faza principală.`
      : `APEX รู้แล้ว: ${age} · ${weight} · ฝึกแรง ${knownProfile[3]} วันในโปรแกรมหลัก`
  }
  const shortVersion = value.match(/^Short on time\? (\d+) min$/)
  if (shortVersion) return language === 'ro' ? `Ai puțin timp? Fă versiunea de ${shortVersion[1]} min` : `เวลาน้อยใช่ไหม? ทำเวอร์ชัน ${shortVersion[1]} นาที`
  const closeRace = value.match(/^There are (\d+) days until the race, which is shorter than Orbit’s 12-week marathon-specific block\. Choose a later event or change the objective rather than compressing the progression\.$/)
  if (closeRace) return language === 'ro'
    ? `Mai sunt ${closeRace[1]} zile până la cursă, mai puțin decât blocul Orbit de 12 săptămâni specific maratonului. Alege un eveniment ulterior sau schimbă obiectivul în loc să comprimi progresia.`
    : `เหลือ ${closeRace[1]} วันก่อนแข่ง ซึ่งสั้นกว่าช่วงฝึกเฉพาะมาราธอน 12 สัปดาห์ของ Orbit ควรเลือกรายการที่ช้ากว่านี้หรือเปลี่ยนเป้าหมาย แทนการเร่งแผน`
  const foundationGate = value.match(/^Foundation to First Marathon was selected because the recent base is below the marathon-specific gate: (\d+) run days per week, approximately (\d+) km per week and a longest recent run near (\d+) km\.$/)
  if (foundationGate) return language === 'ro'
    ? `A fost selectată Fundația spre primul maraton deoarece baza recentă este sub pragul specific maratonului: ${foundationGate[1]} zile de alergare pe săptămână, aproximativ ${foundationGate[2]} km pe săptămână și o alergare recentă maximă de circa ${foundationGate[3]} km.`
    : `เลือกแผนพื้นฐานสู่มาราธอนแรก เพราะพื้นฐานช่วงหลังยังต่ำกว่าเกณฑ์ฝึกเฉพาะมาราธอน: วิ่ง ${foundationGate[1]} วันต่อสัปดาห์ ประมาณ ${foundationGate[2]} กม. ต่อสัปดาห์ และวิ่งยาวล่าสุดราว ${foundationGate[3]} กม.`
  const foundationTimeline = value.match(/^The race is (\d+) days away, but a credible Foundation plus marathon-specific journey needs approximately (\d+) days\. A later race is recommended\.$/)
  if (foundationTimeline) return language === 'ro'
    ? `Cursa este peste ${foundationTimeline[1]} zile, dar o Fundație realistă urmată de pregătirea specifică necesită aproximativ ${foundationTimeline[2]} zile. Este recomandată o cursă ulterioară.`
    : `การแข่งขันเหลือ ${foundationTimeline[1]} วัน แต่เส้นทางพื้นฐานรวมช่วงฝึกเฉพาะมาราธอนที่สมเหตุผลต้องใช้ประมาณ ${foundationTimeline[2]} วัน จึงแนะนำให้เลือกรายการที่ช้ากว่านี้`
  const sessionMinutes = value.match(/^(\d+) minutes at (controlled marathon effort inside the session|comfortably hard, controlled effort)\.$/)
  if (sessionMinutes) {
    if (language === 'ro') return sessionMinutes[2].startsWith('controlled marathon')
      ? `${sessionMinutes[1]} minute la efort de maraton controlat în cadrul sesiunii.`
      : `${sessionMinutes[1]} minute la un efort susținut, dar confortabil și controlat.`
    return sessionMinutes[2].startsWith('controlled marathon')
      ? `${sessionMinutes[1]} นาทีที่ระดับแรงมาราธอนแบบควบคุมภายในเซสชัน`
      : `${sessionMinutes[1]} นาทีที่ระดับหนักพอสบายแบบควบคุม`
  }
  const thresholdBlocks = value.match(/^3 controlled blocks of (\d+) minutes with easy recovery\.$/)
  if (thresholdBlocks) return language === 'ro' ? `3 blocuri controlate a câte ${thresholdBlocks[1]} minute, cu recuperare ușoară.` : `3 ช่วงแบบควบคุม ช่วงละ ${thresholdBlocks[1]} นาที พร้อมพักเบา`
  const campaignWhy = value.match(/^(.+) phase · (.+) campaign · placed to preserve recovery around demanding work\.$/)
  if (campaignWhy) {
    const phase = translateInterfaceText(campaignWhy[1].replace(/\b\w/g, (letter) => letter.toUpperCase()), language)
    const familyKey: Record<string, string> = {
      'foundation first': 'Foundation to First Marathon',
      'first finish': 'First Marathon: Finish Strong',
      'first performance': 'First Marathon: Performance',
      'personal best': 'Marathon Personal Best',
      hybrid: 'Hybrid Athlete Marathon',
    }
    const family = translateInterfaceText(familyKey[campaignWhy[2]] ?? campaignWhy[2], language)
    if (language === 'ro') return `Faza ${phase} · campania ${family} · poziționată pentru a proteja recuperarea în jurul efortului solicitant.`
    return `ช่วง${phase} · แผน ${family} · จัดไว้เพื่อรักษาการฟื้นตัวรอบงานหนัก`
  }
  const completedCampaign = value.match(/^(\d+) campaign sessions are recorded as completed\.$/)
  if (completedCampaign) return language === 'ro' ? `${completedCampaign[1]} sesiuni din campanie sunt înregistrate ca finalizate.` : `บันทึกการฝึกตามแผนที่เสร็จแล้ว ${completedCampaign[1]} ครั้ง`
  const recentLongRuns = value.match(/^(\d+) recent long runs are available for comparison\.$/)
  if (recentLongRuns) return language === 'ro' ? `${recentLongRuns[1]} alergări lungi recente sunt disponibile pentru comparație.` : `มีวิ่งยาวล่าสุด ${recentLongRuns[1]} ครั้งสำหรับเปรียบเทียบ`
  const controlledRuns = value.match(/^(\d+) recent runs were completed at controlled perceived effort\.$/)
  if (controlledRuns) return language === 'ro' ? `${controlledRuns[1]} alergări recente au fost încheiate la un efort perceput controlat.` : `วิ่งล่าสุด ${controlledRuns[1]} ครั้งเสร็จที่ระดับความเหนื่อยแบบควบคุม`
  const fuelingNotes = value.match(/^(\d+) long-run notes mention fueling practice\.$/)
  if (fuelingNotes) return language === 'ro' ? `${fuelingNotes[1]} notițe de la alergări lungi menționează exersarea alimentării.` : `บันทึกวิ่งยาว ${fuelingNotes[1]} รายการกล่าวถึงการซ้อมเติมพลัง`
  const offRoute = value.match(/^You are (\d+) m from the planned route\. Slow down and use the map to return\.$/)
  if (offRoute) return language === 'ro'
    ? `Ești la ${offRoute[1]} m de traseul planificat. Încetinește și folosește harta pentru a reveni.`
    : `คุณอยู่ห่างจากเส้นทางตามแผน ${offRoute[1]} ม. ชะลอลงและใช้แผนที่เพื่อนำกลับ`
  const navigation = value.match(/^Continue (left|right|straight) on the planned route\.$/)
  if (navigation) {
    const direction = language === 'ro'
      ? ({ left: 'la stânga', right: 'la dreapta', straight: 'drept înainte' } as const)[navigation[1] as 'left' | 'right' | 'straight']
      : ({ left: 'ไปทางซ้าย', right: 'ไปทางขวา', straight: 'ตรงไป' } as const)[navigation[1] as 'left' | 'right' | 'straight']
    return language === 'ro' ? `Continuă ${direction} pe traseul planificat.` : `${direction}ตามเส้นทางที่วางไว้`
  }
  const spokenSplit = value.match(/^Kilometre (\d+)\.(?: (.+)\.)?$/)
  if (spokenSplit) return language === 'ro'
    ? `Kilometrul ${spokenSplit[1]}.${spokenSplit[2] ? ` ${spokenSplit[2]}.` : ''}`
    : `กิโลเมตรที่ ${spokenSplit[1]}${spokenSplit[2] ? ` ${spokenSplit[2]}` : ''}`
  const aerobicDecoupling = value.match(/^Aerobic decoupling was approximately ([\d.]+)%\.$/)
  if (aerobicDecoupling) return language === 'ro' ? `Decuplarea aerobă a fost de aproximativ ${aerobicDecoupling[1]}%.` : `การแยกตัวแอโรบิกอยู่ที่ประมาณ ${aerobicDecoupling[1]}%`
  const rejectedGps = value.match(/^(\d+) impossible or low-quality samples rejected\.$/)
  if (rejectedGps) return language === 'ro' ? `${rejectedGps[1]} mostre imposibile sau de calitate slabă au fost respinse.` : `ตัดตัวอย่างที่เป็นไปไม่ได้หรือคุณภาพต่ำ ${rejectedGps[1]} จุด`
  const optionalCarbs = value.match(/^Optional (\d+) g carbohydrate adjustment around the run\. Review the exact change before applying it\.$/)
  if (optionalCarbs) return language === 'ro'
    ? `Ajustare opțională de ${optionalCarbs[1]} g carbohidrați în jurul alergării. Verifică schimbarea exactă înainte de aplicare.`
    : `ปรับคาร์โบไฮเดรตเพิ่มเติม ${optionalCarbs[1]} กรัมรอบการวิ่ง กรุณาตรวจการเปลี่ยนแปลงที่แน่นอนก่อนใช้`
  const longRunFuel = value.match(/^Long-run rehearsal: (\d+) g carbohydrate across familiar pre-run, during-run and recovery foods, plus (\d+) g recovery protein\. Nothing changes until you apply it\.$/)
  if (longRunFuel) return language === 'ro'
    ? `Repetiție pentru alergarea lungă: ${longRunFuel[1]} g carbohidrați din alimente familiare înainte, în timpul și după alergare, plus ${longRunFuel[2]} g proteine pentru recuperare. Nimic nu se schimbă până nu aplici.`
    : `ซ้อมเติมพลังวิ่งยาว: คาร์โบไฮเดรต ${longRunFuel[1]} กรัมจากอาหารที่คุ้นเคยก่อน ระหว่าง และหลังวิ่ง พร้อมโปรตีนฟื้นตัว ${longRunFuel[2]} กรัม จะไม่มีอะไรเปลี่ยนจนกว่าคุณจะกดใช้`
  const nextLower = value.match(/^The run carried high recovery cost and the next lower-body session is (\d{4}-\d{2}-\d{2})\. Orbit proposes protecting that session rather than silently moving it\.$/)
  if (nextLower) return language === 'ro'
    ? `Alergarea a avut un cost mare de recuperare, iar următoarea sesiune pentru partea inferioară este pe ${nextLower[1]}. Orbit propune să o protejeze, nu să o mute pe ascuns.`
    : `การวิ่งมีภาระฟื้นตัวสูง และการฝึกช่วงล่างครั้งถัดไปคือ ${nextLower[1]} Orbit เสนอให้ปกป้องเซสชันนั้นแทนการย้ายอย่างเงียบ ๆ`
  const avatarMinutes = value.match(/^Orbit contributes (\d+) recorded endurance minutes\. The existing Avatar engine receives one authoritative endurance record, not raw GPS points\.$/)
  if (avatarMinutes) return language === 'ro'
    ? `Orbit contribuie cu ${avatarMinutes[1]} minute de anduranță înregistrate. Motorul Avatar primește o singură înregistrare autoritară de anduranță, nu puncte GPS brute.`
    : `Orbit เพิ่มข้อมูลความทนทานที่บันทึกไว้ ${avatarMinutes[1]} นาที ระบบ Avatar จะรับข้อมูลความทนทานที่เชื่อถือได้เพียงรายการเดียว ไม่ใช่จุด GPS ดิบ`
  const kcalLogged = value.match(/^(\d[\d,.]*) kcal logged so far$/)
  if (kcalLogged) return language === 'ro' ? `${kcalLogged[1]} kcal înregistrate până acum` : `บันทึกแล้ว ${kcalLogged[1]} แคลอรี`
  const pointsCount = value.match(/^(\d+) points$/)
  if (pointsCount) return language === 'ro' ? `${pointsCount[1]} puncte` : `${pointsCount[1]} จุด`
  const completionsCount = value.match(/^(\d+) completions$/)
  if (completionsCount) return language === 'ro' ? `${completionsCount[1]} finalizări` : `ทำครบ ${completionsCount[1]} ครั้ง`

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
  const todayName = value.match(/^Today, (.+)\.$/)
  if (todayName) return language === 'ro' ? `Astăzi, ${todayName[1]}.` : `วันนี้ ${todayName[1]}`
  const essentials = value.match(/^(\d+) of (\d+) essentials complete$/)
  if (essentials) return language === 'ro' ? `${essentials[1]} din ${essentials[2]} lucruri esențiale completate` : `เสร็จแล้ว ${essentials[1]} จาก ${essentials[2]} รายการสำคัญ`
  const itemCount = value.match(/^(\d+) (items|supplements)$/)
  if (itemCount) return language === 'ro'
    ? `${itemCount[1]} ${itemCount[2] === 'items' ? 'elemente' : 'suplimente'}`
    : `${itemCount[1]} ${itemCount[2] === 'items' ? 'รายการ' : 'อาหารเสริม'}`
  const bodyMomentum = value.match(/^([+-]?[\d.]+) over 14 days · tap for the full story$/)
  if (bodyMomentum) return language === 'ro'
    ? `${bodyMomentum[1]} în 14 zile · atinge pentru toate detaliile`
    : `${bodyMomentum[1]} ใน 14 วัน · แตะเพื่อดูรายละเอียดทั้งหมด`
  const strongestSignal = value.match(/^Your strongest signal is (.+) at ([\d.]+)\.$/)
  if (strongestSignal) return language === 'ro'
    ? `Cea mai bună calitate este ${translateInterfaceText(strongestSignal[1], language)}, la ${strongestSignal[2]}.`
    : `จุดแข็งที่สุดคือ ${translateInterfaceText(strongestSignal[1], language)} ที่ ${strongestSignal[2]}`
  const waterProgress = value.match(/^([\d.]+) of ([\d.]+) L$/)
  if (waterProgress) return language === 'ro' ? `${waterProgress[1]} din ${waterProgress[2]} L` : `${waterProgress[1]} จาก ${waterProgress[2]} ลิตร`

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
    if (language === 'ro') {
      const nouns = { meals: 'mese', supplements: 'suplimente', workouts: 'antrenamente', photos: 'fotografii', days: 'zile' }
      return `${count[1]} ${nouns[count[2] as keyof typeof nouns]}`
    }
    const nouns = { meals: 'มื้อ', supplements: 'รายการอาหารเสริม', workouts: 'ครั้ง', photos: 'ภาพ', days: 'วัน' }
    return count[2] === 'workouts' ? `ฝึก ${count[1]} ครั้ง` : `${count[1]} ${nouns[count[2] as keyof typeof nouns]}`
  }
  const dayStreak = value.match(/^🔥?\s*(\d+) DAY STREAK$/i)
  if (dayStreak) return language === 'ro' ? `🔥 SERIE DE ${dayStreak[1]} ZILE` : `🔥 ต่อเนื่อง ${dayStreak[1]} วัน`
  const nextLabel = value.match(/^next:\s*(.+)$/i)
  if (nextLabel) return language === 'ro'
    ? `urmează: ${translateInterfaceText(nextLabel[1], language)}`
    : `ถัดไป: ${translateInterfaceText(nextLabel[1], language)}`
  const checkpoint = value.match(/^Checkpoint (\d+)$/)
  if (checkpoint) return language === 'ro' ? `Reper ${checkpoint[1]}` : `จุดตรวจ ${checkpoint[1]}`
  const exerciseCount = value.match(/^~?(\d+) min · (\d+) exercises$/)
  if (exerciseCount) return language === 'ro'
    ? `~${exerciseCount[1]} min · ${exerciseCount[2]} exerciții`
    : `~${exerciseCount[1]} นาที · ${exerciseCount[2]} ท่า`
  const foundationWeek = value.match(/^Foundation week (\d+) of 12: (restore movement quality|build repeatable volume|progress controlled load)$/i)
  if (foundationWeek) {
    const phase = foundationWeek[2].toLocaleLowerCase('en')
    if (language === 'ro') {
      const detail = phase === 'restore movement quality'
        ? 'refacerea calității mișcării'
        : phase === 'build repeatable volume'
          ? 'construirea unui volum repetabil'
          : 'progresie controlată a greutății'
      return `Săptămâna ${foundationWeek[1]} din 12: ${detail}`
    }
    const detail = phase === 'restore movement quality'
      ? 'ฟื้นคุณภาพการเคลื่อนไหว'
      : phase === 'build repeatable volume'
        ? 'สร้างปริมาณที่ทำซ้ำได้'
        : 'เพิ่มน้ำหนักอย่างควบคุม'
    return `สัปดาห์ ${foundationWeek[1]} จาก 12: ${detail}`
  }
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
  const exact = (exactTranslations[core] ?? foldedTranslations.get(core.toLocaleLowerCase('en')))?.[language]
  if (exact) return `${leading}${exact}${trailing}`
  const dynamic = translateDynamic(core, language)
  if (dynamic) return `${leading}${dynamic}${trailing}`

  /* June is a person's immutable name throughout APEX. Mask it from the
     generic month translator unless it is clearly adjacent to a day number. */
  const juneIsDate = /(?:\bJune\s+\d{1,2}|\d{1,2}\s+June\b)/.test(core)
  const protectedJune = juneIsDate ? core : core.replace(/\bJune\b/g, '\uE000APEX_PERSON_JUNE\uE001')
  let translated = translateDates(protectedJune, language)
  for (const [english, romanian, thai] of segments.sort(([a], [b]) => b.length - a.length)) {
    if (!translated.includes(english)) continue
    translated = translated.split(english).join(language === 'ro' ? romanian : thai)
  }
  translated = translated.replaceAll('\uE000APEX_PERSON_JUNE\uE001', 'June')
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
