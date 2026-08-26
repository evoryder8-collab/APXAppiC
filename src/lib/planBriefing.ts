import type { TrainingGoal, TrainingPlanWeeks, TrainingVenue } from './types.ts'
import { resolveHydrationTarget, type HydrationTargetMode } from './hydration.ts'
import { goalPresetsForPlan, recommendedGoalForTrainingGoal, type NutritionGoalPreset } from './nutrition.ts'
import type { Goal } from './types.ts'

export type PlanBriefingLanguage = 'en' | 'ro' | 'th'
export type PlanBriefingSlideKind = 'overview' | 'safety' | 'hydration' | 'sleep' | 'supplements'
export type PlanBriefingBulletIcon =
  | 'calendar'
  | 'dumbbell.fill'
  | 'chart.line.uptrend.xyaxis'
  | 'hand.raised.fill'
  | 'phone.fill'
  | 'stethoscope'
  | 'drop.fill'
  | 'bolt.heart.fill'
  | 'wave.3.right'
  | 'bed.double.fill'
  | 'alarm.fill'
  | 'gauge.with.dots.needle.67percent'
  | 'fork.knife'
  | 'figure.strengthtraining.traditional'
  | 'fish.fill'

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

export interface PlanBriefingBullet {
  text: string
  icon: PlanBriefingBulletIcon
}

export interface PlanBriefingSlide {
  kind: PlanBriefingSlideKind
  eyebrow: string
  title: string
  body: string
  bullets: PlanBriefingBullet[]
  assetName: `plan-briefing-${PlanBriefingSlideKind}`
  evidenceLabel: string
  evidenceURL?: string
  energyPresets?: NutritionGoalPreset[]
  recommendedGoal?: Goal
}

export interface PlanBriefing {
  hydrationTargetML: number
  slides: PlanBriefingSlide[]
}

const COPY = {
  en: {
    goals: { rebuild: 'general fitness', muscle: 'muscle-building', fat_loss: 'fat-loss', strength: 'strength', endurance: 'endurance' },
    venues: { home: 'at home', gym: 'in the gym', outdoors: 'outdoors' },
    ready: 'WHY THIS PLAN FITS', overviewBody: (_sessions: number, venue: string) => `Your goal and answers set the training load, recovery spacing and energy choices. Built ${venue}.`,
    overviewBullets: ['The calendar has real start and finish dates.', 'Every session matches the equipment you selected.', 'Log the work you complete; APEX adapts from it.'],
    safetyEyebrow: 'TRAIN SMART', safetyTitle: 'Know when to stop', safetyBody: 'Training effort is normal. Stop for sharp pain, chest pressure, fainting, or sudden breathlessness.',
    safetyBullets: ['Stop any movement that causes sharp or worsening pain.', 'For chest pressure, fainting, or sudden breathlessness, call emergency services.', 'For milder symptoms that persist or return, pause training and seek clinical advice.'],
    clearance: 'Your answers require clearance first. Begin loaded training only after the clinician managing your recovery clears it.',
    hydrationEyebrow: 'HYDRATION', hydrationTitle: (target: string) => `Your starting target: ${target}`, hydrationBody: 'This includes drinks and water in food. Recorded activity can adjust it later.',
    hydrationBullets: ['Water and regular meals cover most shorter sessions.', 'Long, hot, or very sweaty sessions may benefit from a formulated electrolyte drink.', 'If you are sodium-restricted, follow your clinician’s guidance.'],
    sleepEyebrow: 'RECOVERY', sleepTitle: 'Make sleep repeatable', sleepBody: 'A consistent sleep window is one of your most useful training tools.',
    sleepBullets: ['Aim for at least seven hours.', 'Keep wake time steady and seek daylight early.', 'If sleep and performance slide, reduce training load.'],
    supplementsEyebrow: 'OPTIONAL SUPPORT', supplementsTitle: 'Start with what works', supplementsBody: 'Food is the base. Use supplements to fill a specific nutrition or training gap.',
    supplementsBullets: ['Protein powder is a practical way to reach your protein target.', 'Creatine monohydrate is the well-studied form for repeated high-intensity and strength work.', 'Fatty fish provides EPA and DHA; algae-derived EPA/DHA is the plant-based option.'],
  },
  ro: {
    goals: { rebuild: 'fitness general', muscle: 'masă musculară', fat_loss: 'pierdere de grăsime', strength: 'forță', endurance: 'rezistență' },
    venues: { home: 'acasă', gym: 'la sală', outdoors: 'în aer liber' },
    ready: 'DE CE ȚI SE POTRIVEȘTE', overviewBody: (_sessions: number, venue: string) => `Obiectivul și răspunsurile tale stabilesc efortul, recuperarea și energia. Creat ${venue}.`,
    overviewBullets: ['Calendarul are date reale de început și final.', 'Fiecare sesiune folosește echipamentul selectat.', 'Înregistrează ce faci; APEX se adaptează din date reale.'],
    safetyEyebrow: 'ANTRENEAZĂ-TE INTELIGENT', safetyTitle: 'Știi când să te oprești', safetyBody: 'Efortul este normal. Durerea ascuțită, presiunea toracică, leșinul sau lipsa bruscă de aer nu sunt.',
    safetyBullets: ['Oprește orice mișcare ce provoacă durere ascuțită sau crescândă.', 'Pentru presiune toracică, leșin sau lipsă bruscă de aer, sună la urgențe (144 în Elveția).', 'Dacă simptomele ușoare persistă sau revin, oprește antrenamentul și cere sfat medical.'],
    clearance: 'Răspunsurile tale cer aviz înainte. Începe antrenamentul cu greutăți doar după acordul clinicianului care îți gestionează recuperarea.',
    hydrationEyebrow: 'HIDRATARE', hydrationTitle: (target: string) => `Ținta ta inițială: ${target}`, hydrationBody: 'Include băuturile și apa din alimente. Activitatea înregistrată o poate ajusta ulterior.',
    hydrationBullets: ['Apa și mesele obișnuite sunt suficiente pentru majoritatea sesiunilor scurte.', 'Sesiunile lungi, fierbinți sau cu transpirație abundentă pot beneficia de electroliți formulați.', 'Dacă ai restricție de sodiu, urmează indicația clinicianului.'],
    sleepEyebrow: 'RECUPERARE', sleepTitle: 'Fă somnul repetabil', sleepBody: 'Un interval constant de somn este unul dintre cele mai utile instrumente de antrenament.',
    sleepBullets: ['Țintește cel puțin șapte ore.', 'Păstrează ora trezirii constantă și caută lumină naturală dimineața.', 'Dacă somnul și performanța scad, redu efortul.'],
    supplementsEyebrow: 'SUPORT OPȚIONAL', supplementsTitle: 'Începe cu ce funcționează', supplementsBody: 'Mâncarea este baza. Folosește suplimente pentru un deficit clar de nutriție sau antrenament.',
    supplementsBullets: ['Pudra proteică te poate ajuta practic să atingi ținta de proteină.', 'Creatina monohidrat este forma bine studiată pentru efort intens repetat și forță.', 'Peștele gras oferă EPA și DHA; EPA/DHA din alge este alternativa vegetală.'],
  },
  th: {
    goals: { rebuild: 'สมรรถภาพทั่วไป', muscle: 'สร้างกล้ามเนื้อ', fat_loss: 'ลดไขมัน', strength: 'เพิ่มความแข็งแรง', endurance: 'ความทนทาน' },
    venues: { home: 'ที่บ้าน', gym: 'ในยิม', outdoors: 'กลางแจ้ง' },
    ready: 'ทำไมแผนนี้เหมาะกับคุณ', overviewBody: (_sessions: number, venue: string) => `เป้าหมายและคำตอบของคุณกำหนดภาระ การฟื้นตัว และพลังงาน สร้างสำหรับ${venue}`,
    overviewBullets: ['ปฏิทินมีวันเริ่มและวันสิ้นสุดจริง', 'ทุกเซสชันใช้อุปกรณ์ที่คุณเลือก', 'บันทึกสิ่งที่ทำจริง แล้ว APEX จะปรับตามข้อมูลนั้น'],
    safetyEyebrow: 'ฝึกอย่างฉลาด', safetyTitle: 'รู้ว่าเมื่อไรควรหยุด', safetyBody: 'ความเหนื่อยเป็นเรื่องปกติ แต่ความเจ็บแปลบ แน่นหน้าอก หน้ามืด หรือหายใจลำบากฉับพลันไม่ใช่',
    safetyBullets: ['หยุดท่าที่ทำให้เจ็บแปลบหรือเจ็บมากขึ้น', 'หากแน่นหน้าอก หมดสติ หรือหายใจลำบากฉับพลัน ให้โทรฉุกเฉิน (144 ในสวิตเซอร์แลนด์)', 'หากอาการเล็กน้อยไม่หายหรือกลับมา ให้พักการฝึกและปรึกษาแพทย์'],
    clearance: 'คำตอบของคุณต้องได้รับอนุญาตก่อน เริ่มฝึกด้วยแรงต้านเมื่อแพทย์ผู้ดูแลการฟื้นตัวอนุญาตแล้วเท่านั้น',
    hydrationEyebrow: 'การดื่มน้ำ', hydrationTitle: (target: string) => `เป้าหมายเริ่มต้น: ${target}`, hydrationBody: 'รวมเครื่องดื่มและน้ำในอาหาร กิจกรรมที่บันทึกอาจปรับเป้าหมายภายหลัง',
    hydrationBullets: ['น้ำและอาหารตามปกติเพียงพอสำหรับเซสชันสั้นส่วนใหญ่', 'เซสชันที่ยาว ร้อน หรือเสียเหงื่อมากอาจเหมาะกับเครื่องดื่มเกลือแร่ที่มีสูตรชัดเจน', 'หากต้องจำกัดโซเดียม ให้ทำตามคำแนะนำของแพทย์'],
    sleepEyebrow: 'การฟื้นตัว', sleepTitle: 'ทำเวลานอนให้สม่ำเสมอ', sleepBody: 'ช่วงเวลานอนที่สม่ำเสมอคือหนึ่งในเครื่องมือฝึกที่มีประโยชน์ที่สุด',
    sleepBullets: ['ตั้งเป้าอย่างน้อยเจ็ดชั่วโมง', 'รักษาเวลาตื่นให้คงที่และรับแสงธรรมชาติช่วงเช้า', 'หากการนอนและผลงานลดลง ให้ลดภาระการฝึก'],
    supplementsEyebrow: 'ตัวช่วยเพิ่มเติม', supplementsTitle: 'เริ่มจากสิ่งที่ได้ผล', supplementsBody: 'อาหารคือพื้นฐาน ใช้อาหารเสริมเพื่อเติมช่องว่างที่ชัดเจนด้านโภชนาการหรือการฝึก',
    supplementsBullets: ['โปรตีนผงช่วยให้ถึงเป้าหมายโปรตีนได้สะดวก', 'ครีเอทีนโมโนไฮเดรตคือรูปแบบที่มีการศึกษาดีสำหรับแรงสูงซ้ำและความแข็งแรง', 'ปลามันให้ EPA และ DHA ส่วน EPA/DHA จากสาหร่ายคือทางเลือกจากพืช'],
  },
} as const

const BULLET_ICONS = {
  overview: ['calendar', 'dumbbell.fill', 'chart.line.uptrend.xyaxis'],
  safety: ['hand.raised.fill', 'phone.fill', 'stethoscope'],
  hydration: ['drop.fill', 'bolt.heart.fill', 'wave.3.right'],
  sleep: ['bed.double.fill', 'alarm.fill', 'gauge.with.dots.needle.67percent'],
  supplements: ['fork.knife', 'figure.strengthtraining.traditional', 'fish.fill'],
} as const satisfies Record<PlanBriefingSlideKind, readonly PlanBriefingBulletIcon[]>

function bulletsFor(kind: PlanBriefingSlideKind, texts: readonly string[]): PlanBriefingBullet[] {
  return texts.map((text, index) => ({ text, icon: BULLET_ICONS[kind][index] }))
}

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
    ? `${duration} ${goal} · ${input.sessionsPerWeek} sessions/week`
    : input.language === 'ro'
      ? `${goal} · ${duration} · ${input.sessionsPerWeek} sesiuni/săpt.`
      : `${goal} · ${duration} · ${input.sessionsPerWeek} ครั้ง/สัปดาห์`
  const safetyBody = input.caution === 'clearance' ? copy.clearance : copy.safetyBody
  const energyPresets = goalPresetsForPlan({ trainingGoal: input.goal, planWeeks: input.planWeeks })

  return {
    hydrationTargetML: hydration.targetML,
    slides: [
      {
        kind: 'overview', eyebrow: copy.ready, title: planTitle,
        body: copy.overviewBody(input.sessionsPerWeek, venue), bullets: bulletsFor('overview', copy.overviewBullets),
        assetName: 'plan-briefing-overview', evidenceLabel: 'Your answers · APEX plan engine',
        energyPresets, recommendedGoal: recommendedGoalForTrainingGoal(input.goal),
      },
      {
        kind: 'safety', eyebrow: copy.safetyEyebrow, title: copy.safetyTitle,
        body: safetyBody, bullets: bulletsFor('safety', copy.safetyBullets),
        assetName: 'plan-briefing-safety', evidenceLabel: 'Swiss Heart Foundation',
        evidenceURL: 'https://swissheart.ch/erkrankungen-und-notfall/notfall/verhalten-im-notfall',
      },
      {
        kind: 'hydration', eyebrow: copy.hydrationEyebrow,
        title: copy.hydrationTitle(targetLabel(hydration.targetML, input.displayUnit)),
        body: copy.hydrationBody, bullets: bulletsFor('hydration', copy.hydrationBullets),
        assetName: 'plan-briefing-hydration', evidenceLabel: 'Swiss FSVO · APEX hydration policy',
        evidenceURL: 'https://www.blv.admin.ch/dam/blv/en/dokumente/lebensmittel-und-ernaehrung/ernaehrung/Ernaehrungsempfehlungen/Schweizer%20Ern%C3%A4hrungsempfehlungen_Langversion_EN.pdf.download.pdf/Schweizer%20Ern%C3%A4hrungsempfehlungen_Langversion_EN.pdf',
      },
      {
        kind: 'sleep', eyebrow: copy.sleepEyebrow, title: copy.sleepTitle,
        body: copy.sleepBody, bullets: bulletsFor('sleep', copy.sleepBullets),
        assetName: 'plan-briefing-sleep', evidenceLabel: 'Swiss Society for Sleep Research (SSSSC)',
        evidenceURL: 'https://swiss-sleep.ch/',
      },
      {
        kind: 'supplements', eyebrow: copy.supplementsEyebrow, title: copy.supplementsTitle,
        body: copy.supplementsBody, bullets: bulletsFor('supplements', copy.supplementsBullets),
        assetName: 'plan-briefing-supplements', evidenceLabel: 'Swiss Sports Nutrition Society (SSNS)',
        evidenceURL: 'https://www.ssns.ch/sportsnutrition/supplemente/supplementguide/',
      },
    ],
  }
}
