import type { TrainingGoal, TrainingPlanWeeks, TrainingVenue } from './types.ts'
import { resolveHydrationTarget, type HydrationTargetMode } from './hydration.ts'

export type PlanBriefingLanguage = 'en' | 'ro' | 'th'
export type PlanBriefingSlideKind = 'overview' | 'safety' | 'hydration' | 'sleep' | 'supplements'

export interface PlanBriefingInput {
  language: PlanBriefingLanguage
  planWeeks: TrainingPlanWeeks
  sessionsPerWeek: number
  goal: TrainingGoal
  venue: TrainingVenue
  caution: 'standard' | 'cautious' | 'clearance'
  sex: 'male' | 'female'
  weightKg: number
  plannedExerciseMinutes: number
  hydrationMode: HydrationTargetMode
  customHydrationTargetML: number | null
  displayUnit: 'liters' | 'gallons'
}

export interface PlanBriefingSlide {
  kind: PlanBriefingSlideKind
  eyebrow: string
  title: string
  body: string
  bullets: string[]
  assetName: `plan-briefing-${PlanBriefingSlideKind}`
  evidence: string
}

export interface PlanBriefing {
  hydrationTargetML: number
  slides: PlanBriefingSlide[]
}

const COPY = {
  en: {
    goals: { rebuild: 'consistency', muscle: 'muscle-building', fat_loss: 'fat-loss', strength: 'strength', endurance: 'endurance' },
    venues: { home: 'at home', gym: 'in the gym', outdoors: 'outdoors' },
    ready: 'IMPORTANT INFO AND TIPS ABOUT YOUR PLAN', overviewBody: (sessions: number, venue: string) => `${sessions} sessions per week ${venue}, arranged to make progression and recovery easy to follow.`,
    overviewBullets: ['The calendar now carries the real start and end dates.', 'Each workout stays inside the equipment and recovery limits you selected.', 'Log what actually happened; APEX adapts from measured work, not guesses.'],
    safetyEyebrow: 'SAFETY FIRST', safetyTitle: 'Use a clear stop rule', safetyBody: 'Normal effort is expected. Sharp pain, faintness, chest pressure, or unusual breathlessness are signals to stop, not tests to push through.',
    safetyBullets: ['Stop the movement immediately if something feels wrong; do not train through sharp or escalating pain.', 'Chest pain or pressure, fainting, or sudden unexplained shortness of breath needs emergency medical help.', 'For milder symptoms, end the exercise, rest, and seek a clinician for persistent, returning, or worsening symptoms.'],
    clearance: 'Your answers selected a clearance-first plan. Do not begin loaded training until the clinician responsible for your recovery clears it.',
    hydrationEyebrow: 'PERSONAL HYDRATION', hydrationTitle: (target: string) => `Start with ${target} total water`, hydrationBody: 'This personalized starting target includes water from drinks and food. APEX can make a small, capped adjustment later when a longer session or wearable activity is actually recorded.',
    hydrationBullets: ['For most shorter sessions, plain water and normal meals are enough.', 'For long, hot, or very sweaty training, a properly formulated electrolyte drink may be useful.', 'Do not add salt routinely. If you are sodium-restricted or have a relevant medical condition, follow your clinician’s guidance.'],
    sleepEyebrow: 'RECOVERY THAT COUNTS', sleepTitle: 'Protect a regular sleep window', sleepBody: 'Most adults need at least seven hours. Consistent bed and wake times, plus daylight earlier in the day, support recovery without pretending everyone must literally follow sunrise.',
    sleepBullets: ['Choose a repeatable sleep window before adding more training volume.', 'Keep wake time reasonably consistent, including after a poor night.', 'If sleep or performance keeps worsening, reduce load rather than trying to outwork fatigue.'],
    supplementsEyebrow: 'EVIDENCE, NOT HYPE', supplementsTitle: 'Food first. Supplements stay optional.', supplementsBody: 'Supplements are optional and do not rescue an inconsistent plan. Use them only to solve a real dietary or training need, with qualified advice when health conditions or medicines are involved.',
    supplementsBullets: ['Protein powder is a convenient food tool when meals do not meet your protein target; it is not mandatory.', 'Creatine monohydrate has strong evidence for repeated high-intensity and strength work, but its value varies by activity and person.', 'Fatty fish supplies EPA and DHA; algae-derived EPA/DHA is a plant-based option. Ask a clinician or sports dietitian before supplementing when relevant.'],
  },
  ro: {
    goals: { rebuild: 'consecvență', muscle: 'masă musculară', fat_loss: 'pierdere de grăsime', strength: 'forță', endurance: 'rezistență' },
    venues: { home: 'acasă', gym: 'la sală', outdoors: 'în aer liber' },
    ready: 'PLANUL TĂU ESTE GATA', overviewBody: (sessions: number, venue: string) => `${sessions} sesiuni pe săptămână ${venue}, aranjate pentru ca progresul și recuperarea să fie ușor de urmărit.`,
    overviewBullets: ['Calendarul are acum date reale de început și sfârșit.', 'Fiecare antrenament respectă echipamentul și limitele de recuperare selectate.', 'Înregistrează ce ai făcut; APEX adaptează din date măsurate, nu din presupuneri.'],
    safetyEyebrow: 'SIGURANȚA ÎNAINTE', safetyTitle: 'Folosește o regulă clară de oprire', safetyBody: 'Efortul normal este de așteptat. Durerea ascuțită, leșinul, presiunea toracică sau lipsa neobișnuită de aer înseamnă oprire, nu forțare.',
    safetyBullets: ['Oprește imediat mișcarea dacă ceva nu este în regulă; nu continua prin durere ascuțită sau crescândă.', 'Durerea sau presiunea toracică, leșinul ori lipsa bruscă și inexplicabilă de aer necesită ajutor medical de urgență.', 'Pentru simptome mai ușoare, oprește exercițiul, odihnește-te și cere sfatul unui clinician dacă persistă, revin sau se agravează.'],
    clearance: 'Răspunsurile tale au selectat un plan care cere aviz medical. Nu începe antrenamentul cu greutăți până nu primești acordul clinicianului responsabil de recuperare.',
    hydrationEyebrow: 'HIDRATARE PERSONALĂ', hydrationTitle: (target: string) => `Începe cu ${target} apă totală`, hydrationBody: 'Ținta personală inițială include apa din băuturi și alimente. APEX poate face ulterior o ajustare mică și limitată când este înregistrată o sesiune mai lungă sau activitate de pe dispozitiv.',
    hydrationBullets: ['Pentru majoritatea sesiunilor scurte, apa simplă și mesele normale sunt suficiente.', 'Pentru efort lung, foarte transpirat sau pe căldură, o băutură cu electroliți formulată corect poate fi utilă.', 'Nu adăuga sare de rutină. Dacă ai restricție de sodiu sau o afecțiune relevantă, urmează indicația clinicianului.'],
    sleepEyebrow: 'RECUPERARE REALĂ', sleepTitle: 'Protejează un program regulat de somn', sleepBody: 'Majoritatea adulților au nevoie de cel puțin șapte ore. Orele consecvente de culcare și trezire, plus lumină naturală mai devreme în zi, susțin recuperarea fără a cere tuturor să urmeze literal răsăritul.',
    sleepBullets: ['Alege un interval de somn repetabil înainte de a adăuga volum de antrenament.', 'Păstrează ora trezirii rezonabil de constantă, inclusiv după o noapte slabă.', 'Dacă somnul sau performanța continuă să scadă, redu efortul în loc să forțezi prin oboseală.'],
    supplementsEyebrow: 'DOVEZI, NU PROMISIUNI', supplementsTitle: 'Mâncarea întâi. Suplimentele rămân opționale.', supplementsBody: 'Suplimentele nu repară un plan inconsecvent. Folosește-le doar pentru o nevoie reală de alimentație sau antrenament și cere sfat calificat dacă există afecțiuni ori medicamente.',
    supplementsBullets: ['Pudra proteică este o opțiune alimentară comodă când mesele nu ating ținta; nu este obligatorie.', 'Creatina monohidrat are dovezi solide pentru efort repetat de intensitate mare și forță, dar utilitatea diferă după activitate și persoană.', 'Peștele gras oferă EPA și DHA; EPA/DHA din alge este o opțiune vegetală. Cere sfatul unui clinician sau dietetician sportiv când este relevant.'],
  },
  th: {
    goals: { rebuild: 'ความสม่ำเสมอ', muscle: 'สร้างกล้ามเนื้อ', fat_loss: 'ลดไขมัน', strength: 'เพิ่มความแข็งแรง', endurance: 'ความทนทาน' },
    venues: { home: 'ที่บ้าน', gym: 'ในยิม', outdoors: 'กลางแจ้ง' },
    ready: 'แผนของคุณพร้อมแล้ว', overviewBody: (sessions: number, venue: string) => `${sessions} เซสชันต่อสัปดาห์${venue} จัดไว้ให้ติดตามความก้าวหน้าและการฟื้นตัวได้ง่าย`,
    overviewBullets: ['ปฏิทินมีวันเริ่มและวันสิ้นสุดจริงแล้ว', 'ทุกเซสชันอยู่ภายในอุปกรณ์และข้อจำกัดการฟื้นตัวที่คุณเลือก', 'บันทึกสิ่งที่ทำจริง APEX จะปรับจากข้อมูลที่วัดได้ ไม่ใช่การเดา'],
    safetyEyebrow: 'ปลอดภัยไว้ก่อน', safetyTitle: 'มีกฎหยุดที่ชัดเจน', safetyBody: 'ความเหนื่อยตามปกติเกิดขึ้นได้ แต่ความเจ็บแปลบ หน้ามืด แน่นหน้าอก หรือหายใจลำบากผิดปกติคือสัญญาณให้หยุด ไม่ใช่สิ่งที่ต้องฝืน',
    safetyBullets: ['หยุดท่านั้นทันทีเมื่อรู้สึกผิดปกติ และอย่าฝืนความเจ็บแปลบหรือเจ็บมากขึ้น', 'เจ็บหรือแน่นหน้าอก หมดสติ หรือหายใจลำบากเฉียบพลันโดยไม่ทราบสาเหตุ ต้องขอความช่วยเหลือฉุกเฉิน', 'อาการที่เบากว่าให้หยุด พัก และพบแพทย์หากอาการไม่หาย กลับมา หรือแย่ลง'],
    clearance: 'คำตอบของคุณเลือกแผนที่ต้องได้รับอนุญาตก่อน อย่าเริ่มฝึกด้วยแรงต้านจนกว่าแพทย์ผู้ดูแลการฟื้นตัวจะอนุญาต',
    hydrationEyebrow: 'น้ำที่เหมาะกับคุณ', hydrationTitle: (target: string) => `เริ่มที่น้ำรวม ${target}`, hydrationBody: 'เป้าหมายเริ่มต้นนี้รวมทั้งน้ำจากเครื่องดื่มและอาหาร APEX อาจปรับเพิ่มเล็กน้อยและมีเพดาน เมื่อมีการบันทึกเซสชันที่ยาวขึ้นหรือกิจกรรมจากอุปกรณ์จริง',
    hydrationBullets: ['สำหรับเซสชันสั้นส่วนใหญ่ น้ำเปล่าและอาหารตามปกติก็เพียงพอ', 'การฝึกที่ยาว ร้อน หรือเสียเหงื่อมาก อาจเหมาะกับเครื่องดื่มเกลือแร่ที่มีสูตรชัดเจน', 'อย่าเติมเกลือเป็นกิจวัตร หากต้องจำกัดโซเดียมหรือมีภาวะที่เกี่ยวข้อง ให้ทำตามคำแนะนำของแพทย์'],
    sleepEyebrow: 'การฟื้นตัวที่มีผล', sleepTitle: 'รักษาเวลานอนให้สม่ำเสมอ', sleepBody: 'ผู้ใหญ่ส่วนใหญ่ต้องการอย่างน้อยเจ็ดชั่วโมง เวลาเข้านอนและตื่นที่สม่ำเสมอ รวมถึงแสงธรรมชาติช่วงต้นวัน ช่วยการฟื้นตัวโดยไม่จำเป็นต้องทำตามพระอาทิตย์ขึ้นแบบตายตัว',
    sleepBullets: ['กำหนดช่วงเวลานอนที่ทำซ้ำได้ก่อนเพิ่มปริมาณการฝึก', 'รักษาเวลาตื่นให้ค่อนข้างคงที่ แม้หลังคืนที่นอนไม่ดี', 'หากการนอนหรือผลงานแย่ลงต่อเนื่อง ให้ลดภาระแทนการฝืนความล้า'],
    supplementsEyebrow: 'หลักฐาน ไม่ใช่กระแส', supplementsTitle: 'อาหารมาก่อน อาหารเสริมเป็นทางเลือก', supplementsBody: 'อาหารเสริมแก้แผนที่ไม่สม่ำเสมอไม่ได้ ใช้เมื่อมีความต้องการจริง และขอคำแนะนำจากผู้เชี่ยวชาญเมื่อมีโรคประจำตัวหรือใช้ยา',
    supplementsBullets: ['โปรตีนผงเป็นอาหารที่สะดวกเมื่อมื้ออาหารยังไม่ถึงเป้าหมาย แต่ไม่จำเป็นสำหรับทุกคน', 'ครีเอทีนโมโนไฮเดรตมีหลักฐานดีสำหรับแรงระเบิดซ้ำและงานเพิ่มความแข็งแรง แต่ประโยชน์ต่างกันตามกิจกรรมและแต่ละคน', 'ปลามันให้ EPA และ DHA ส่วน EPA/DHA จากสาหร่ายเป็นทางเลือกจากพืช ควรถามแพทย์หรือนักกำหนดอาหารกีฬาเมื่อเหมาะสม'],
  },
} as const

function durationLabel(weeks: TrainingPlanWeeks, language: PlanBriefingLanguage): string {
  if (language === 'en') return weeks === 26 ? '6-month' : `${weeks}-week`
  if (language === 'ro') return weeks === 26 ? '6 luni' : `${weeks} săptămâni`
  return weeks === 26 ? '6 เดือน' : `${weeks} สัปดาห์`
}

function targetLabel(targetML: number, unit: PlanBriefingInput['displayUnit']): string {
  if (unit === 'gallons') return `${(targetML / 3_785.411_784).toFixed(2)} US gal`
  return `${(targetML / 1_000).toFixed(2)} L`
}

export function buildPlanBriefing(input: PlanBriefingInput): PlanBriefing {
  const copy = COPY[input.language]
  const hydration = resolveHydrationTarget({
    sex: input.sex,
    weightKg: input.weightKg,
    mode: input.hydrationMode,
    customTargetML: input.customHydrationTargetML,
    plannedExerciseMinutes: input.plannedExerciseMinutes,
  })
  const goal = copy.goals[input.goal]
  const venue = copy.venues[input.venue]
  const duration = durationLabel(input.planWeeks, input.language)
  const planTitle = input.language === 'en'
    ? `Your ${duration} ${goal} plan`
    : input.language === 'ro'
      ? `Planul tău de ${goal} · ${duration}`
      : `แผน${goal}ของคุณ · ${duration}`
  const safetyBullets: string[] = [...copy.safetyBullets]
  if (input.caution === 'clearance') safetyBullets.unshift(copy.clearance)

  return {
    hydrationTargetML: hydration.targetML,
    slides: [
      {
        kind: 'overview', eyebrow: copy.ready, title: planTitle,
        body: copy.overviewBody(input.sessionsPerWeek, venue), bullets: [...copy.overviewBullets],
        assetName: 'plan-briefing-overview', evidence: 'APEX plan facts',
      },
      {
        kind: 'safety', eyebrow: copy.safetyEyebrow, title: copy.safetyTitle,
        body: copy.safetyBody, bullets: safetyBullets,
        assetName: 'plan-briefing-safety', evidence: 'CDC · American Heart Association',
      },
      {
        kind: 'hydration', eyebrow: copy.hydrationEyebrow,
        title: copy.hydrationTitle(targetLabel(hydration.targetML, input.displayUnit)),
        body: copy.hydrationBody, bullets: [...copy.hydrationBullets],
        assetName: 'plan-briefing-hydration', evidence: 'APEX hydration policy · American Heart Association',
      },
      {
        kind: 'sleep', eyebrow: copy.sleepEyebrow, title: copy.sleepTitle,
        body: copy.sleepBody, bullets: [...copy.sleepBullets],
        assetName: 'plan-briefing-sleep', evidence: 'CDC sleep guidance',
      },
      {
        kind: 'supplements', eyebrow: copy.supplementsEyebrow, title: copy.supplementsTitle,
        body: copy.supplementsBody, bullets: [...copy.supplementsBullets],
        assetName: 'plan-briefing-supplements', evidence: 'NIH Office of Dietary Supplements',
      },
    ],
  }
}
