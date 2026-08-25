import { useMemo, useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'
import type { ProgramSlug, TrainingGoal, TrainingInactivity, TrainingPainArea, TrainingPlanWeeks, TrainingVenue } from '../../lib/types'
import { useLanguage } from '../../lib/i18n'
import { todayIso } from '../../lib/plan'
import {
  EQUIPMENT_CATALOG,
  activeTrainingProgramDays,
  assessTrainingInput,
  commitTrainingPlanAddons,
  generateTrainingPlan,
  invalidateTrainingPlanAddons,
  markPendingTrainingPlanAddons,
  searchEquipment,
  TRAINING_PLAN_WEEK_OPTIONS,
  trainingInputFromProfile,
  trainingGenerationRevision,
  type TrainingInductionInput,
} from '../../lib/trainingInduction'
import { ACCENTS } from '../../lib/theme'
import { buildPlanBriefing, type PlanBriefing } from '../../lib/planBriefing'
import { useStore } from '../../store/AppStore'
import { AccentChip, GhostButton, GlassCard, GradientButton, Sheet } from '../ui'

type Language = 'en' | 'ro' | 'th'

const COPY = {
  en: {
    eyebrow: 'PERSONAL STARTING PATH', transitionTitle: 'Your plan, built around your timeline', mainTitle: 'Your next phase is already mapped',
    emptyBody: 'Answer six focused sections. APEX will build a minimal plan around your timeline, training gap, body, location and equipment.',
    activeBody: 'Your plan is installed in the calendar. Every block has one job, so progress stays obvious.',
    build: 'Build my plan', review: 'Review plan', guide: 'Plan guide', mainButton: 'Set up my main phase',
    starts: 'Starts', mainStarts: 'Main phase', ends: 'Ends', sessions: 'sessions / week', home: 'Home', gym: 'Gym', outdoors: 'Outdoors',
    wizard: 'Training induction', step: 'Step', back: 'Back', next: 'Continue', install: 'Install my plan',
    gapTitle: 'How long has regular strength training been absent?', gapBody: 'This changes the starting volume, not your potential.',
    frequency: 'How many weekly sessions can you repeat in a normal week?',
    bodyTitle: 'Anything the plan must protect?', bodyBody: 'Choose current joint pain or fatigue. Do not count normal muscle soreness.',
    operation: 'Recent operation', lowerBack: 'Chronic lower-back pain', none: 'Nothing to flag',
    venueTitle: 'Where will you train?', venueBody: 'Every exercise will stay inside the setup you actually have.',
    homeLabel: 'At home', homeBody: 'Bodyweight and only the tools you select', gymLabel: 'In a gym', gymBody: 'Machines, cables and free weights', outdoorLabel: 'Outdoors', outdoorBody: 'Open-air training with only the tools you select',
    equipmentTitle: 'What equipment is available?', equipmentBody: 'Type a few letters. “dum” immediately finds both dumbbell types.',
    equipmentPlaceholder: 'Search equipment', noEquipment: 'No equipment is completely fine. A bodyweight version will be built.',
    goalTitle: 'What should the next phase prioritize?', rebuild: 'Rebuild consistency', muscle: 'Build muscle', fatLoss: 'Lose fat', strength: 'Build strength', endurance: 'Build endurance',
    durationTitle: 'How long should your plan be?', durationBody: 'Choose the horizon you can commit to. APEX stores a real end date and will never repeat this plan forever.', weeks: 'weeks', sixMonths: '6 months',
    reviewTitle: 'Your plan logic', standard: 'Standard foundation', cautious: 'Conservative foundation', clearance: 'Clearance-first path',
    standardBody: 'A repeatable schedule with gradual volume and logged-load progression.',
    cautiousBody: 'Volume is reduced and every movement begins with 3 to 4 reps in reserve.',
    clearanceBody: 'Recent surgery needs clinician clearance. APEX installs only gentle preparation until loaded training is cleared.',
    phases4: 'Weeks 1-4 restore consistency', phases8: 'Weeks 1-4 restore · 5-8 build', phases12: 'Weeks 1-4 restore · 5-8 build · 9-12 progress', phases26: 'Weeks 1-12 foundation · 13-26 main phase', installed: 'Your personalized plan is installed.',
  },
  ro: {
    eyebrow: 'TRASEU PERSONAL DE ÎNCEPUT', transitionTitle: 'Planul tău, construit pentru perioada aleasă', mainTitle: 'Următoarea etapă este deja pregătită',
    emptyBody: 'Răspunde la șase secțiuni scurte. APEX construiește un plan minimal pe baza perioadei, pauzei, corpului, locului și echipamentului tău.',
    activeBody: 'Planul este instalat în calendar. Fiecare etapă are un singur scop, iar progresul rămâne clar.',
    build: 'Construiește planul', review: 'Revizuiește planul', guide: 'Ghidul planului', mainButton: 'Configurează faza principală',
    starts: 'Începe', mainStarts: 'Faza principală', ends: 'Se încheie', sessions: 'sesiuni / săptămână', home: 'Acasă', gym: 'Sală', outdoors: 'În aer liber',
    wizard: 'Inducție pentru antrenament', step: 'Pasul', back: 'Înapoi', next: 'Continuă', install: 'Instalează planul',
    gapTitle: 'De cât timp lipsește antrenamentul regulat de forță?', gapBody: 'Răspunsul schimbă volumul de început, nu potențialul tău.',
    frequency: 'Câte sesiuni poți repeta într-o săptămână normală?',
    bodyTitle: 'Ce trebuie să protejeze planul?', bodyBody: 'Alege durerea sau oboseala articulară actuală. Nu include febra musculară normală.',
    operation: 'Operație recentă', lowerBack: 'Durere lombară cronică', none: 'Nimic de semnalat',
    venueTitle: 'Unde te vei antrena?', venueBody: 'Fiecare exercițiu va folosi doar spațiul și resursele pe care le ai.',
    homeLabel: 'Acasă', homeBody: 'Greutatea corpului și doar echipamentul selectat', gymLabel: 'La sală', gymBody: 'Aparate, cabluri și greutăți libere', outdoorLabel: 'În aer liber', outdoorBody: 'Antrenament afară cu doar echipamentul selectat',
    equipmentTitle: 'Ce echipament ai disponibil?', equipmentBody: 'Scrie câteva litere. „gan” găsește imediat ambele tipuri de gantere.',
    equipmentPlaceholder: 'Caută echipament', noEquipment: 'Este în regulă și fără echipament. Va fi creată o variantă cu greutatea corpului.',
    goalTitle: 'Care este prioritatea fazei următoare?', rebuild: 'Refacerea consecvenței', muscle: 'Masă musculară', fatLoss: 'Pierdere de grăsime', strength: 'Forță', endurance: 'Rezistență',
    durationTitle: 'Cât de lung să fie planul tău?', durationBody: 'Alege perioada pe care o poți urma. APEX salvează o dată reală de final și nu va repeta planul la nesfârșit.', weeks: 'săptămâni', sixMonths: '6 luni',
    reviewTitle: 'Logica planului tău', standard: 'Fundație standard', cautious: 'Fundație conservatoare', clearance: 'Traseu cu aviz medical',
    standardBody: 'Un program repetabil, cu volum gradual și progresie bazată pe greutățile înregistrate.',
    cautiousBody: 'Volumul este redus, iar fiecare mișcare începe cu 3 sau 4 repetări în rezervă.',
    clearanceBody: 'O operație recentă necesită aviz medical. APEX instalează doar pregătire ușoară până când efortul cu greutăți este permis.',
    phases4: 'Săpt. 1-4 refacerea consecvenței', phases8: 'Săpt. 1-4 refacere · 5-8 construcție', phases12: 'Săpt. 1-4 refacere · 5-8 construcție · 9-12 progres', phases26: 'Săpt. 1-12 fundație · 13-26 faza principală', installed: 'Planul personalizat a fost instalat.',
  },
  th: {
    eyebrow: 'เส้นทางเริ่มต้นส่วนตัว', transitionTitle: 'แผนที่สร้างตามช่วงเวลาของคุณ', mainTitle: 'ช่วงถัดไปของคุณพร้อมแล้ว',
    emptyBody: 'ตอบคำถามสั้น ๆ 6 ส่วน APEX จะสร้างแผนจากช่วงเวลา ช่วงที่หยุดฝึก สภาพร่างกาย สถานที่ และอุปกรณ์ของคุณ',
    activeBody: 'ติดตั้งแผนลงในปฏิทินแล้ว แต่ละช่วงมีเป้าหมายเดียว จึงเห็นความก้าวหน้าได้ชัดเจน',
    build: 'สร้างแผนของฉัน', review: 'ทบทวนแผน', guide: 'คำแนะนำแผน', mainButton: 'ตั้งค่าช่วงหลัก',
    starts: 'เริ่ม', mainStarts: 'ช่วงหลัก', ends: 'สิ้นสุด', sessions: 'ครั้ง / สัปดาห์', home: 'ที่บ้าน', gym: 'ยิม', outdoors: 'กลางแจ้ง',
    wizard: 'แบบประเมินก่อนเริ่มฝึก', step: 'ขั้นตอน', back: 'ย้อนกลับ', next: 'ต่อไป', install: 'ติดตั้งแผนของฉัน',
    gapTitle: 'หยุดฝึกเวทอย่างสม่ำเสมอมานานเท่าไร?', gapBody: 'คำตอบนี้เปลี่ยนปริมาณเริ่มต้น ไม่ได้จำกัดศักยภาพของคุณ',
    frequency: 'ในสัปดาห์ปกติ คุณทำได้กี่ครั้งอย่างสม่ำเสมอ?',
    bodyTitle: 'มีส่วนใดที่แผนต้องระวัง?', bodyBody: 'เลือกอาการปวดหรือความล้าของข้อต่อในตอนนี้ ไม่นับอาการปวดกล้ามเนื้อตามปกติ',
    operation: 'เพิ่งผ่าตัด', lowerBack: 'ปวดหลังส่วนล่างเรื้อรัง', none: 'ไม่มีสิ่งที่ต้องแจ้ง',
    venueTitle: 'คุณจะฝึกที่ไหน?', venueBody: 'ทุกท่าจะใช้เฉพาะสถานที่และอุปกรณ์ที่คุณมีจริง',
    homeLabel: 'ที่บ้าน', homeBody: 'น้ำหนักตัวและอุปกรณ์ที่คุณเลือกเท่านั้น', gymLabel: 'ในยิม', gymBody: 'เครื่อง เคเบิล และฟรีเวท', outdoorLabel: 'กลางแจ้ง', outdoorBody: 'ฝึกกลางแจ้งด้วยอุปกรณ์ที่คุณเลือกเท่านั้น',
    equipmentTitle: 'คุณมีอุปกรณ์อะไรบ้าง?', equipmentBody: 'พิมพ์เพียงไม่กี่ตัว ระบบจะแสดงตัวเลือกที่ใกล้เคียงทันที',
    equipmentPlaceholder: 'ค้นหาอุปกรณ์', noEquipment: 'ไม่มีอุปกรณ์ก็ได้ ระบบจะสร้างเวอร์ชันน้ำหนักตัวให้',
    goalTitle: 'ช่วงถัดไปควรเน้นอะไร?', rebuild: 'กลับมาสม่ำเสมอ', muscle: 'สร้างกล้ามเนื้อ', fatLoss: 'ลดไขมัน', strength: 'เพิ่มความแข็งแรง', endurance: 'เพิ่มความทนทาน',
    durationTitle: 'คุณต้องการให้แผนนานเท่าไร?', durationBody: 'เลือกช่วงเวลาที่ทำได้จริง APEX จะบันทึกวันสิ้นสุดและไม่ทำให้แผนวนซ้ำตลอดไป', weeks: 'สัปดาห์', sixMonths: '6 เดือน',
    reviewTitle: 'เหตุผลของแผน', standard: 'พื้นฐานมาตรฐาน', cautious: 'พื้นฐานแบบระมัดระวัง', clearance: 'เริ่มหลังได้รับอนุญาต',
    standardBody: 'ตารางที่ทำซ้ำได้ เพิ่มปริมาณทีละน้อย และใช้ค่าน้ำหนักที่บันทึกเพื่อพัฒนา',
    cautiousBody: 'ลดปริมาณฝึก และเริ่มทุกท่าโดยเหลือแรงอีก 3 ถึง 4 ครั้ง',
    clearanceBody: 'การผ่าตัดล่าสุดต้องได้รับอนุญาตจากแพทย์ APEX จะติดตั้งเฉพาะการเตรียมตัวเบา ๆ จนกว่าจะได้รับอนุญาตให้ฝึกแรงต้าน',
    phases4: 'สัปดาห์ 1-4 กลับมาสม่ำเสมอ', phases8: 'สัปดาห์ 1-4 ฟื้นพื้นฐาน · 5-8 สร้าง', phases12: 'สัปดาห์ 1-4 ฟื้นพื้นฐาน · 5-8 สร้าง · 9-12 พัฒนา', phases26: 'สัปดาห์ 1-12 พื้นฐาน · 13-26 ช่วงหลัก', installed: 'ติดตั้งแผนส่วนตัวแล้ว',
  },
} satisfies Record<Language, Record<string, string>>

const FREQUENCY_COPY = {
  en: {
    days: 'days / week', recovery: 'RECOVERY PLAN',
    sixTitle: 'Six days needs distributed load', sevenTitle: 'Seven days needs one low-load day',
    summary: 'APEX keeps every selected training day while changing how stress is placed across the week.',
    adapts: 'HOW APEX ADAPTS', recoveryTitle: 'RECOVERY ANCHORS',
    alternate: 'Upper and lower loading alternate so the same muscle group is not trained hard on consecutive days.',
    sets: 'Loaded movements are capped at two hard sets per exercise.',
    sixStructure: 'A low-load mobility session separates repeated muscle-group work.',
    sevenStructure: 'Mobility and conversational-pace capacity replace a seventh hard session.',
    sleep: 'Protect a consistent sleep window and aim for at least seven hours.',
    protein: 'Meet your APEX protein target across the day.',
    water: 'Use your personal hydration target. More water is not always better.',
    signals: 'Reduce load if performance, soreness, sleep or motivation worsen.',
    disclaimer: 'This lowers avoidable load stacking, but it cannot guarantee recovery or prevent overtraining.',
    accept: 'Use these training days', fewer: 'Choose fewer days',
  },
  ro: {
    days: 'zile / săptămână', recovery: 'PLAN CU RECUPERARE',
    sixTitle: 'Șase zile cer distribuirea efortului', sevenTitle: 'Șapte zile cer o zi cu efort redus',
    summary: 'APEX păstrează toate zilele alese, dar schimbă modul în care efortul este distribuit în săptămână.',
    adapts: 'CUM ADAPTEAZĂ APEX', recoveryTitle: 'REPERE PENTRU RECUPERARE',
    alternate: 'Efortul pentru partea superioară și inferioară alternează, astfel încât aceeași grupă musculară să nu fie solicitată intens în zile consecutive.',
    sets: 'Mișcările cu încărcare sunt limitate la două seturi grele per exercițiu.',
    sixStructure: 'O sesiune ușoară de mobilitate separă repetarea grupelor musculare.',
    sevenStructure: 'Mobilitatea și efortul conversațional înlocuiesc o a șaptea sesiune grea.',
    sleep: 'Protejează un program constant de somn și urmărește cel puțin șapte ore.',
    protein: 'Atinge ținta APEX de proteine pe parcursul zilei.',
    water: 'Folosește ținta personală de hidratare. Mai multă apă nu este întotdeauna mai bine.',
    signals: 'Redu încărcarea dacă performanța, febra musculară, somnul sau motivația se înrăutățesc.',
    disclaimer: 'Aceasta reduce suprapunerea evitabilă a efortului, dar nu poate garanta recuperarea sau preveni supraantrenamentul.',
    accept: 'Folosește aceste zile', fewer: 'Alege mai puține zile',
  },
  th: {
    days: 'วัน / สัปดาห์', recovery: 'แผนเน้นการฟื้นตัว',
    sixTitle: 'หกวันต้องกระจายภาระการฝึก', sevenTitle: 'เจ็ดวันต้องมีหนึ่งวันที่เบาลง',
    summary: 'APEX จะคงทุกวันที่คุณเลือก แต่ปรับการกระจายความหนักตลอดสัปดาห์',
    adapts: 'APEX ปรับอย่างไร', recoveryTitle: 'หลักการฟื้นตัว',
    alternate: 'สลับการฝึกส่วนบนและส่วนล่าง เพื่อไม่ให้กล้ามเนื้อกลุ่มเดิมฝึกหนักในวันติดกัน',
    sets: 'ท่าที่มีน้ำหนักจำกัดไม่เกินสองเซ็ตหนักต่อท่า',
    sixStructure: 'แทรกเซสชันเคลื่อนไหวเบา ๆ ระหว่างวันที่ใช้กล้ามเนื้อกลุ่มเดิม',
    sevenStructure: 'ใช้การเคลื่อนไหวและคาร์ดิโอเบาที่พูดคุยได้ แทนการฝึกหนักวันที่เจ็ด',
    sleep: 'รักษาเวลานอนให้สม่ำเสมอและตั้งเป้าอย่างน้อยเจ็ดชั่วโมง',
    protein: 'ทำเป้าหมายโปรตีนของ APEX ให้ครบตลอดวัน',
    water: 'ใช้เป้าหมายการดื่มน้ำส่วนบุคคล การดื่มมากเกินไปไม่ได้ดีกว่าเสมอ',
    signals: 'ลดความหนักหากผลงาน อาการล้า การนอน หรือแรงจูงใจแย่ลง',
    disclaimer: 'แนวทางนี้ช่วยลดการซ้อนภาระที่เลี่ยงได้ แต่ไม่รับประกันการฟื้นตัวหรือป้องกันการฝึกเกินได้',
    accept: 'ใช้จำนวนวันนี้', fewer: 'เลือกวันให้น้อยลง',
  },
} satisfies Record<Language, Record<string, string>>

const GOAL_PRESENTATION: Record<TrainingGoal, { symbol: string; detail: Record<Language, string> }> = {
  rebuild: { symbol: '↻', detail: { en: 'Build a balanced, repeatable training rhythm', ro: 'Construiește un ritm echilibrat și repetabil', th: 'สร้างจังหวะการฝึกที่สมดุลและทำซ้ำได้' } },
  muscle: { symbol: 'M', detail: { en: 'Prioritize progressive resistance work', ro: 'Prioritizează rezistența progresivă', th: 'เน้นแรงต้านที่พัฒนาอย่างต่อเนื่อง' } },
  fat_loss: { symbol: '◇', detail: { en: 'Pair resistance work with sustainable activity', ro: 'Combină rezistența cu activitate sustenabilă', th: 'ผสานแรงต้านกับกิจกรรมที่ทำต่อเนื่องได้' } },
  strength: { symbol: '↑', detail: { en: 'Keep load progression prominent and measurable', ro: 'Păstrează progresia greutății clară și măsurabilă', th: 'ทำให้การเพิ่มน้ำหนักชัดเจนและวัดผลได้' } },
  endurance: { symbol: '∞', detail: { en: 'Give aerobic capacity a clear place in the week', ro: 'Oferă capacității aerobe un loc clar în săptămână', th: 'จัดพื้นที่ชัดเจนให้ความทนทานในแต่ละสัปดาห์' } },
}

const INACTIVITY: Array<{ value: TrainingInactivity; en: string; ro: string; th: string }> = [
  { value: 'currently_training', en: 'I currently train', ro: 'Mă antrenez acum', th: 'กำลังฝึกอยู่' },
  { value: 'under_1_month', en: 'Under 1 month', ro: 'Sub o lună', th: 'น้อยกว่า 1 เดือน' },
  { value: 'one_to_three_months', en: '1-3 months', ro: '1-3 luni', th: '1-3 เดือน' },
  { value: 'three_to_six_months', en: '3-6 months', ro: '3-6 luni', th: '3-6 เดือน' },
  { value: 'six_to_twelve_months', en: '6-12 months', ro: '6-12 luni', th: '6-12 เดือน' },
  { value: 'over_one_year', en: 'Over 1 year', ro: 'Peste un an', th: 'มากกว่า 1 ปี' },
]

const PAIN: Array<{ value: TrainingPainArea; en: string; ro: string; th: string }> = [
  { value: 'shoulders', en: 'Shoulders', ro: 'Umeri', th: 'ไหล่' },
  { value: 'elbows', en: 'Elbows', ro: 'Coate', th: 'ข้อศอก' },
  { value: 'wrists', en: 'Wrists', ro: 'Încheieturi', th: 'ข้อมือ' },
  { value: 'hips', en: 'Hips', ro: 'Șolduri', th: 'สะโพก' },
  { value: 'knees', en: 'Knees', ro: 'Genunchi', th: 'เข่า' },
  { value: 'ankles', en: 'Ankles', ro: 'Glezne', th: 'ข้อเท้า' },
]

function Choice({ active, children, onClick, className = '' }: { active: boolean; children: React.ReactNode; onClick: () => void; className?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-2xl border px-3 py-3 text-left text-sm font-bold transition ${className}`}
      style={active
        ? { borderColor: 'rgba(124,58,237,.48)', background: 'linear-gradient(135deg,rgba(124,58,237,.14),rgba(34,211,238,.12))', color: '#4c1d95', boxShadow: '0 12px 30px -24px rgba(109,40,217,.9)' }
        : { borderColor: 'rgba(26,26,34,.08)', background: 'rgba(255,255,255,.58)', color: '#55555f' }}
    >
      {children}
    </button>
  )
}

function PlanBriefingDeck({ briefing, language, onClose }: { briefing: PlanBriefing; language: Language; onClose: () => void }) {
  const [activeSlide, setActiveSlide] = useState(0)
  const reduceMotion = useReducedMotion()
  const controls = {
    en: { title: 'Your plan briefing', hint: 'Swipe for the full guide', done: 'Open my plan', close: 'Close plan briefing' },
    ro: { title: 'Ghidul planului tău', hint: 'Glisează pentru ghidul complet', done: 'Deschide planul', close: 'Închide ghidul planului' },
    th: { title: 'คำแนะนำสำหรับแผนของคุณ', hint: 'ปัดเพื่ออ่านคำแนะนำทั้งหมด', done: 'เปิดแผนของฉัน', close: 'ปิดคำแนะนำแผน' },
  }[language]

  return (
    <div
      data-no-translate
      className="-m-5 min-h-[90dvh] overflow-hidden p-5 sm:min-h-0 sm:rounded-3xl"
      style={{ background: 'radial-gradient(circle at 8% 0%, rgba(124,58,237,.14), transparent 34%), radial-gradient(circle at 96% 4%, rgba(34,211,238,.13), transparent 32%), #f8f9fc' }}
    >
      <header className="flex items-start justify-between gap-4">
        <div>
          <p className="font-mono text-[9px] font-black tracking-[.2em] text-violet-700 uppercase">APEX PLAN INTELLIGENCE</p>
          <h2 className="mt-1 font-display text-2xl font-bold text-ink">{controls.title}</h2>
          <p className="mt-1 text-xs font-semibold text-ink-soft">{controls.hint}</p>
        </div>
        <button type="button" onClick={onClose} aria-label={controls.close} className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-white/70 text-lg font-black text-ink-soft shadow-sm">×</button>
      </header>

      <div
        className="mt-5 flex snap-x snap-mandatory gap-4 overflow-x-auto overscroll-x-contain pb-3 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        onScroll={(event) => {
          const track = event.currentTarget
          const stride = track.clientWidth + 16
          setActiveSlide(Math.max(0, Math.min(briefing.slides.length - 1, Math.round(track.scrollLeft / stride))))
        }}
        aria-label={controls.title}
      >
        {briefing.slides.map((slide, index) => (
          <motion.article
            key={slide.kind}
            className="min-w-[calc(100%-1rem)] snap-center overflow-hidden rounded-[2rem] border border-white/80 bg-white/75 p-5 shadow-[0_24px_80px_rgba(76,29,149,.12)] backdrop-blur-xl sm:min-w-full sm:p-7"
            initial={{ x: 0 }}
            animate={index === 0 && !reduceMotion ? { x: [0, -14, 0] } : { x: 0 }}
            transition={index === 0 ? { delay: 0.65, duration: 0.75, ease: 'easeInOut' } : undefined}
          >
            <div className="grid gap-4 sm:grid-cols-[minmax(0,1fr)_220px] sm:items-center">
              <div className="order-2 sm:order-1">
                <p className="font-mono text-[9px] font-black tracking-[.2em] text-violet-700 uppercase">{slide.eyebrow}</p>
                <h3 className="mt-2 font-display text-[1.65rem] leading-tight font-bold text-ink">{slide.title}</h3>
                <p className="mt-3 text-sm leading-relaxed font-medium text-ink-soft">{slide.body}</p>
              </div>
              <img
                src={`${import.meta.env.BASE_URL}plan-briefing/${slide.assetName}.png`}
                alt=""
                className="order-1 mx-auto h-44 w-44 object-contain drop-shadow-[0_18px_24px_rgba(76,29,149,.15)] sm:order-2 sm:h-52 sm:w-52"
                draggable={false}
              />
            </div>
            <ul className="mt-5 space-y-2.5">
              {slide.bullets.map((bullet) => (
                <li key={bullet} className="flex gap-3 rounded-2xl bg-violet-50/65 px-3.5 py-3 text-xs leading-relaxed font-semibold text-ink-soft">
                  <span className="mt-0.5 text-violet-600">✦</span><span>{bullet}</span>
                </li>
              ))}
            </ul>
            <p className="mt-4 font-mono text-[8px] font-bold tracking-[.08em] text-ink-faint uppercase">Evidence · {slide.evidence}</p>
          </motion.article>
        ))}
      </div>

      <div className="mt-2 flex justify-center gap-2" aria-label={`${activeSlide + 1} / ${briefing.slides.length}`}>
        {briefing.slides.map((slide, index) => <span key={slide.kind} className={`h-1.5 rounded-full transition-all ${index === activeSlide ? 'w-8 bg-violet-600' : 'w-1.5 bg-violet-200'}`} />)}
      </div>
      <GradientButton accent={ACCENTS.violet} onClick={onClose} className="mt-5 w-full">{controls.done}</GradientButton>
    </div>
  )
}

export function TrainingInductionPanel({ slug }: { slug: ProgramSlug }) {
  const { data, bulkUpsert, setSettings, toast } = useStore()
  const { language } = useLanguage()
  const lang = language as Language
  const copy = COPY[lang]
  const current = data.settings?.addons.training_induction
  const draftFromCurrent = (): TrainingInductionInput => current
    ? trainingInputFromProfile(current, todayIso())
    : {
        start_date: todayIso(),
        inactivity: 'one_to_three_months',
        venue: 'gym',
        equipment: [],
        pain_areas: [],
        recent_operation: false,
        chronic_lower_back_pain: false,
        sessions_per_week: 3,
        plan_weeks: 12,
        goal: 'rebuild',
      }
  const [open, setOpen] = useState(false)
  const [briefingOpen, setBriefingOpen] = useState(false)
  const [briefing, setBriefing] = useState<PlanBriefing | null>(null)
  const [step, setStep] = useState(0)
  const [search, setSearch] = useState('')
  const [pendingFrequency, setPendingFrequency] = useState<6 | 7 | null>(null)
  const [draft, setDraft] = useState<TrainingInductionInput>(draftFromCurrent)
  const assessment = useMemo(() => assessTrainingInput(draft), [draft])
  const equipmentResults = useMemo(() => searchEquipment(search, lang).filter((item) => !draft.equipment.includes(item.id)).slice(0, 6), [draft.equipment, lang, search])
  const labelForEquipment = (id: string): string => {
    const item = EQUIPMENT_CATALOG.find((candidate) => candidate.id === id)
    return item?.[lang] ?? id
  }
  const togglePain = (area: TrainingPainArea): void => setDraft((value) => ({
    ...value,
    pain_areas: value.pain_areas.includes(area) ? value.pain_areas.filter((item) => item !== area) : [...value.pain_areas, area],
  }))
  const openBuilder = (): void => {
    setDraft(draftFromCurrent())
    setSearch('')
    setPendingFrequency(null)
    setStep(0)
    setOpen(true)
  }
  const briefingFor = (input: TrainingInductionInput, plannedMinutes: number[]): PlanBriefing => {
    const profile = data.profile
    const hydration = data.hydration_preferences
    const usableMinutes = plannedMinutes.filter((minutes) => Number.isFinite(minutes) && minutes > 0)
    const plannedExerciseMinutes = usableMinutes.length > 0
      ? Math.round(usableMinutes.reduce((total, minutes) => total + minutes, 0) / usableMinutes.length)
      : 45
    return buildPlanBriefing({
      language: lang,
      planWeeks: input.plan_weeks,
      sessionsPerWeek: input.sessions_per_week,
      goal: input.goal,
      venue: input.venue,
      caution: assessTrainingInput(input).caution,
      sex: profile?.sex ?? 'male',
      weightKg: profile?.weight_kg ?? 87,
      plannedExerciseMinutes,
      hydrationMode: hydration?.target_mode === 'custom' ? 'custom' : 'automatic',
      customHydrationTargetML: hydration?.target_ml ?? null,
      displayUnit: hydration?.display_unit ?? 'liters',
    })
  }
  const openCurrentBriefing = (): void => {
    if (!current) return
    const input = trainingInputFromProfile(current, todayIso())
    const claimedDayIds = new Set([...current.transition_day_ids, ...current.main_day_ids])
    setBriefing(briefingFor(input, data.program_days.filter((day) => claimedDayIds.has(day.id)).map((day) => day.est_minutes)))
    setBriefingOpen(true)
  }
  const install = (): void => {
    const userId = data.profile?.user_id ?? data.settings?.user_id
    const settings = data.settings
    if (!userId || !settings) return
    /*
     * Installing a starter plan narrows every calendar to the generated days.
     * The established programme is not deleted, but it disappears from view,
     * which is indistinguishable from data loss for the person looking at it.
     * Confirm before that happens, and say plainly that it is reversible.
     */
    const replacingExistingPlan = activeTrainingProgramDays(data).length > 0 && !settings.addons.training_induction
    if (replacingExistingPlan && !window.confirm(
      'This installs a generated beginner plan and shows it instead of your current programme. Your existing programme is kept and returns from Settings, Restore my original programme. Continue?',
    )) return
    let addons = settings.addons
    if (settings.addons.training_induction) {
      addons = invalidateTrainingPlanAddons(addons)
    }
    const generated = generateTrainingPlan(
      userId,
      draft,
      data.programs,
      new Date().toISOString(),
      trainingGenerationRevision(addons),
    )
    const syncGroup = `training-induction:${userId}:${generated.induction.generation_revision ?? 0}:${generated.induction.completed_at}`
    addons = markPendingTrainingPlanAddons(addons, generated)
    /* One durable pre-row write carries both invalidation and pending IDs.
       Separate settings writes can coalesce in the offline queue and drop the
       pending barrier before the generated rows reach the server. */
    setSettings({ addons }, { syncGroup })
    bulkUpsert('programs', generated.programs, { syncGroup })
    bulkUpsert('program_days', generated.program_days, { syncGroup })
    bulkUpsert('exercises', generated.exercises, { syncGroup })
    setSettings({ addons: commitTrainingPlanAddons(addons, generated) }, { syncGroup })
    setBriefing(briefingFor(draft, generated.program_days.map((day) => day.est_minutes)))
    toast(copy.installed, 'ok')
    setOpen(false)
    setStep(0)
    setBriefingOpen(true)
  }
  const cautionTitle = assessment.caution === 'clearance' ? copy.clearance : assessment.caution === 'cautious' ? copy.cautious : copy.standard
  const cautionBody = assessment.caution === 'clearance' ? copy.clearanceBody : assessment.caution === 'cautious' ? copy.cautiousBody : copy.standardBody
  const goalLabel: Record<TrainingGoal, string> = {
    rebuild: copy.rebuild,
    muscle: copy.muscle,
    fat_loss: copy.fatLoss,
    strength: copy.strength,
    endurance: copy.endurance,
  }
  const frequencyCopy = FREQUENCY_COPY[lang]
  const goalChoices = (Object.keys(goalLabel) as TrainingGoal[]).map((goal) => ({
    goal,
    label: goalLabel[goal],
    ...GOAL_PRESENTATION[goal],
  }))
  const durationLabel = (weeks: TrainingPlanWeeks): string => weeks === 26 ? copy.sixMonths : `${weeks} ${copy.weeks}`
  const phases = draft.plan_weeks === 4 ? copy.phases4 : draft.plan_weeks === 8 ? copy.phases8 : draft.plan_weeks === 26 ? copy.phases26 : copy.phases12

  return (
    <div data-no-translate>
      <GlassCard accent={ACCENTS.violet} breathe className="p-5 sm:p-6">
        <div className="grid gap-5 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center">
          <div>
            <p className="font-mono text-[9px] font-black tracking-[.2em] text-violet-700 uppercase">{copy.eyebrow}</p>
            <h2 className="mt-2 font-display text-2xl font-bold text-ink">{slug === 'main' ? copy.mainTitle : copy.transitionTitle}</h2>
            <p className="mt-2 max-w-xl text-sm leading-relaxed font-medium text-ink-soft">{current ? copy.activeBody : copy.emptyBody}</p>
            {current && (
              <div className="mt-3 flex flex-wrap gap-2">
                <AccentChip accent={ACCENTS.violet}>{current.venue === 'gym' ? copy.gym : current.venue === 'outdoors' ? copy.outdoors : copy.home}</AccentChip>
                <AccentChip accent={ACCENTS.teal}>{current.sessions_per_week} {copy.sessions}</AccentChip>
                <AccentChip accent={ACCENTS.violet}>{durationLabel(current.plan_weeks ?? 12)}</AccentChip>
                <AccentChip accent={current.caution === 'standard' ? ACCENTS.emerald : ACCENTS.amber}>{current.caution === 'clearance' ? copy.clearance : current.caution === 'cautious' ? copy.cautious : copy.standard}</AccentChip>
              </div>
            )}
            {current && <p className="mt-3 font-mono text-[10px] font-bold text-ink-faint">{copy.starts}: {current.start_date} · {(current.plan_weeks ?? 12) > 12 ? copy.mainStarts : copy.ends}: {(current.plan_weeks ?? 12) > 12 ? current.main_start_date : (current.end_date ?? current.main_start_date)}</p>}
          </div>
          <div className="grid w-full gap-2 sm:w-auto">
            <GradientButton accent={ACCENTS.violet} onClick={openBuilder} className="w-full sm:w-auto">
              {current ? copy.review : slug === 'main' ? copy.mainButton : copy.build}
            </GradientButton>
            {current && <GhostButton onClick={openCurrentBriefing} className="w-full sm:w-auto">{copy.guide}</GhostButton>}
          </div>
        </div>
      </GlassCard>

      <Sheet open={open} onClose={() => setOpen(false)} wide>
        <div
          data-no-translate
          className="-m-5 min-h-[88dvh] p-5 sm:min-h-0 sm:rounded-3xl"
          style={{ background: 'radial-gradient(circle at 12% 0%, rgba(124,58,237,.10), transparent 34%), radial-gradient(circle at 92% 8%, rgba(34,211,238,.10), transparent 30%), #f8f9fc' }}
        >
          <div className="flex items-start justify-between gap-3">
            <div>
              <p className="font-mono text-[9px] font-black tracking-[.2em] text-violet-700 uppercase">{copy.step} {step + 1} / 6</p>
              <h2 className="mt-1 font-display text-2xl font-bold text-ink">{copy.wizard}</h2>
            </div>
            <button type="button" onClick={() => setOpen(false)} className="grid h-10 w-10 place-items-center rounded-full bg-ink/5 text-lg font-bold text-ink-soft" aria-label="Close">×</button>
          </div>
          <div className="mt-4 grid grid-cols-6 gap-1.5" aria-hidden>
            {[0, 1, 2, 3, 4, 5].map((item) => <div key={item} className="h-1.5 rounded-full transition" style={{ background: item <= step ? ACCENTS.violet.gradient : 'rgba(26,26,34,.08)' }} />)}
          </div>

          <div className="mt-6 min-h-[360px]">
            {step === 0 && (
              <div>
                <h3 className="font-display text-xl font-bold text-ink">{copy.gapTitle}</h3>
                <p className="mt-1 text-sm font-medium text-ink-soft">{copy.gapBody}</p>
                <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3">
                  {INACTIVITY.map((option) => <Choice key={option.value} active={draft.inactivity === option.value} onClick={() => setDraft((value) => ({ ...value, inactivity: option.value }))}>{option[lang]}</Choice>)}
                </div>
                <h3 className="mt-7 font-display text-lg font-bold text-ink">{copy.frequency}</h3>
                <p className="mt-1 text-xs font-bold tracking-wide text-violet-700 uppercase">{frequencyCopy.days}</p>
                <div className="mt-3 grid grid-cols-3 gap-2 sm:grid-cols-6">
                  {([2, 3, 4, 5, 6, 7] as const).map((count) => (
                    <Choice
                      key={count}
                      active={draft.sessions_per_week === count}
                      onClick={() => {
                        if (count === 6 || count === 7) setPendingFrequency(count)
                        else setDraft((value) => ({ ...value, sessions_per_week: count }))
                      }}
                      className="text-center"
                    >
                      <span className="block font-mono text-xl text-ink">{count}</span>
                      <span className="mt-1 block text-[9px] font-black tracking-wide text-ink-faint uppercase">{frequencyCopy.days}</span>
                      {count >= 6 && <span className="mt-1 block text-[8px] font-black text-amber-700 uppercase">{frequencyCopy.recovery}</span>}
                    </Choice>
                  ))}
                </div>
              </div>
            )}
            {step === 1 && (
              <div>
                <h3 className="font-display text-xl font-bold text-ink">{copy.bodyTitle}</h3>
                <p className="mt-1 text-sm font-medium text-ink-soft">{copy.bodyBody}</p>
                <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-3">
                  {PAIN.map((option) => <Choice key={option.value} active={draft.pain_areas.includes(option.value)} onClick={() => togglePain(option.value)}>{option[lang]}</Choice>)}
                </div>
                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  <Choice active={draft.recent_operation} onClick={() => setDraft((value) => ({ ...value, recent_operation: !value.recent_operation }))}>{copy.operation}</Choice>
                  <Choice active={draft.chronic_lower_back_pain} onClick={() => setDraft((value) => ({ ...value, chronic_lower_back_pain: !value.chronic_lower_back_pain }))}>{copy.lowerBack}</Choice>
                </div>
                {!draft.recent_operation && !draft.chronic_lower_back_pain && draft.pain_areas.length === 0 && <p className="mt-4 text-center text-xs font-bold text-emerald-700">✓ {copy.none}</p>}
              </div>
            )}
            {step === 2 && (
              <div>
                <h3 className="font-display text-xl font-bold text-ink">{copy.venueTitle}</h3>
                <p className="mt-1 text-sm font-medium text-ink-soft">{copy.venueBody}</p>
                <div className="mt-5 grid gap-3 sm:grid-cols-3">
                  {([['home', copy.homeLabel, copy.homeBody], ['gym', copy.gymLabel, copy.gymBody], ['outdoors', copy.outdoorLabel, copy.outdoorBody]] as Array<[TrainingVenue, string, string]>).map(([venue, title, body]) => (
                    <Choice key={venue} active={draft.venue === venue} onClick={() => setDraft((value) => ({ ...value, venue }))} className="min-h-28">
                      <span className="block font-display text-lg text-ink">{title}</span><span className="mt-1 block text-xs leading-relaxed font-medium text-ink-soft">{body}</span>
                    </Choice>
                  ))}
                </div>
              </div>
            )}
            {step === 3 && (
              <div>
                {draft.venue !== 'gym' && (
                  <>
                    <h3 className="font-display text-xl font-bold text-ink">{copy.equipmentTitle}</h3>
                    <p className="mt-1 text-sm font-medium text-ink-soft">{copy.equipmentBody}</p>
                    <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder={copy.equipmentPlaceholder} className="glass mt-4 w-full rounded-2xl px-4 py-3 text-sm font-bold text-ink outline-none" />
                    <div className="mt-2 grid gap-2 sm:grid-cols-2">
                      {equipmentResults.map((item) => <Choice key={item.id} active={false} onClick={() => { setDraft((value) => ({ ...value, equipment: [...value.equipment, item.id] })); setSearch('') }}>+ {item[lang]}</Choice>)}
                    </div>
                    {draft.equipment.length > 0 ? <div className="mt-3 flex flex-wrap gap-2">{draft.equipment.map((id) => <button key={id} type="button" onClick={() => setDraft((value) => ({ ...value, equipment: value.equipment.filter((item) => item !== id) }))} className="rounded-full bg-violet-100 px-3 py-1.5 text-xs font-bold text-violet-800">{labelForEquipment(id)} ×</button>)}</div> : <p className="mt-3 text-xs font-medium text-ink-faint">{copy.noEquipment}</p>}
                  </>
                )}
                <h3 className={`${draft.venue !== 'gym' ? 'mt-7' : ''} font-display text-xl font-bold text-ink`}>{copy.goalTitle}</h3>
                <div className="mt-3 grid gap-2 sm:grid-cols-2">
                  {goalChoices.map(({ goal, label, symbol, detail }) => (
                    <Choice key={goal} active={draft.goal === goal} onClick={() => setDraft((value) => ({ ...value, goal }))} className="min-h-24">
                      <span className="flex items-start gap-3">
                        <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-violet-100 font-display text-lg text-violet-800">{symbol}</span>
                        <span>
                          <span className="block font-display text-base text-ink">{label}</span>
                          <span className="mt-1 block text-xs leading-relaxed font-medium text-ink-soft">{detail[lang]}</span>
                        </span>
                      </span>
                    </Choice>
                  ))}
                </div>
              </div>
            )}
            {step === 4 && (
              <div>
                <h3 className="font-display text-xl font-bold text-ink">{copy.durationTitle}</h3>
                <p className="mt-1 text-sm font-medium text-ink-soft">{copy.durationBody}</p>
                <div className="mt-5 grid grid-cols-2 gap-3">
                  {TRAINING_PLAN_WEEK_OPTIONS.map((weeks) => (
                    <Choice key={weeks} active={draft.plan_weeks === weeks} onClick={() => setDraft((value) => ({ ...value, plan_weeks: weeks }))} className="min-h-28 text-center">
                      <span className="block font-display text-3xl text-ink">{weeks === 26 ? '6' : weeks}</span>
                      <span className="mt-1 block text-xs font-black tracking-wide text-violet-700 uppercase">{weeks === 26 ? copy.sixMonths.replace(/^6\s*/, '') : copy.weeks}</span>
                    </Choice>
                  ))}
                </div>
              </div>
            )}
            {step === 5 && (
              <div>
                <h3 className="font-display text-xl font-bold text-ink">{copy.reviewTitle}</h3>
                <div className="mt-4 rounded-3xl border border-violet-200/60 bg-gradient-to-br from-violet-50/90 to-cyan-50/80 p-5">
                  <div className="flex flex-wrap items-center justify-between gap-3"><h4 className="font-display text-xl font-bold text-ink">{cautionTitle}</h4><AccentChip accent={assessment.caution === 'standard' ? ACCENTS.emerald : ACCENTS.amber}>{assessment.sessions_per_week} {copy.sessions}</AccentChip></div>
                  <p className="mt-3 text-sm leading-relaxed font-medium text-ink-soft">{cautionBody}</p>
                  <p className="mt-4 font-mono text-[10px] font-black tracking-[.08em] text-violet-800 uppercase">{phases}</p>
                </div>
                <div className="mt-4 grid grid-cols-2 gap-2 text-center sm:grid-cols-4">
                  {[draft.venue === 'gym' ? copy.gym : draft.venue === 'outdoors' ? copy.outdoors : copy.home, `${assessment.sessions_per_week} ${copy.sessions}`, durationLabel(draft.plan_weeks), goalLabel[draft.goal]].map((value) => <div key={value} className="rounded-2xl bg-white/65 px-2 py-3 text-xs font-bold text-ink-soft">{value}</div>)}
                </div>
              </div>
            )}
          </div>

          <div className="mt-6 flex gap-2 border-t border-ink/8 pt-4">
            {step > 0 && <GhostButton onClick={() => setStep((value) => value - 1)} className="flex-1">{copy.back}</GhostButton>}
            {step < 5 ? <GradientButton accent={ACCENTS.violet} onClick={() => setStep((value) => value + 1)} className="flex-1">{copy.next}</GradientButton> : <GradientButton accent={ACCENTS.violet} onClick={install} className="flex-1">{copy.install}</GradientButton>}
          </div>

          {pendingFrequency && (
            <div className="fixed inset-0 z-[90] grid place-items-center overflow-y-auto bg-ink/45 p-4 backdrop-blur-sm" role="dialog" aria-modal="true" aria-labelledby="high-frequency-title">
              <div className="my-6 w-full max-w-xl rounded-[2rem] border border-white/70 bg-white/95 p-6 shadow-2xl sm:p-7">
                <div className="grid h-12 w-12 place-items-center rounded-full bg-gradient-to-br from-amber-400 to-orange-500 text-xl text-white shadow-lg">⌁</div>
                <h3 id="high-frequency-title" className="mt-4 font-display text-2xl font-bold text-ink">
                  {pendingFrequency === 7 ? frequencyCopy.sevenTitle : frequencyCopy.sixTitle}
                </h3>
                <p className="mt-2 text-sm leading-relaxed font-medium text-ink-soft">{frequencyCopy.summary}</p>

                <div className="mt-5 rounded-2xl bg-violet-50/90 p-4">
                  <p className="font-mono text-[9px] font-black tracking-[.16em] text-violet-800 uppercase">{frequencyCopy.adapts}</p>
                  <ul className="mt-3 space-y-2 text-sm leading-relaxed font-semibold text-ink-soft">
                    {[frequencyCopy.alternate, frequencyCopy.sets, pendingFrequency === 7 ? frequencyCopy.sevenStructure : frequencyCopy.sixStructure].map((item) => <li key={item} className="flex gap-2"><span className="text-violet-600">✓</span><span>{item}</span></li>)}
                  </ul>
                </div>

                <div className="mt-4 rounded-2xl bg-cyan-50/90 p-4">
                  <p className="font-mono text-[9px] font-black tracking-[.16em] text-cyan-800 uppercase">{frequencyCopy.recoveryTitle}</p>
                  <ul className="mt-3 space-y-2 text-sm leading-relaxed font-semibold text-ink-soft">
                    {[frequencyCopy.sleep, frequencyCopy.protein, frequencyCopy.water, frequencyCopy.signals].map((item) => <li key={item} className="flex gap-2"><span className="text-cyan-600">•</span><span>{item}</span></li>)}
                  </ul>
                </div>

                <p className="mt-4 rounded-xl bg-amber-50 px-3 py-2.5 text-xs leading-relaxed font-semibold text-amber-900">{frequencyCopy.disclaimer}</p>
                <div className="mt-5 grid gap-2 sm:grid-cols-2">
                  <GhostButton onClick={() => setPendingFrequency(null)}>{frequencyCopy.fewer}</GhostButton>
                  <GradientButton accent={ACCENTS.violet} onClick={() => {
                    setDraft((value) => ({ ...value, sessions_per_week: pendingFrequency }))
                    setPendingFrequency(null)
                  }}>{frequencyCopy.accept}</GradientButton>
                </div>
              </div>
            </div>
          )}
        </div>
      </Sheet>
      <Sheet open={briefingOpen && briefing != null} onClose={() => setBriefingOpen(false)} wide>
        {briefing && <PlanBriefingDeck briefing={briefing} language={lang} onClose={() => setBriefingOpen(false)} />}
      </Sheet>
    </div>
  )
}
