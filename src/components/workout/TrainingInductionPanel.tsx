import { useMemo, useState } from 'react'
import type { ProgramSlug, TrainingGoal, TrainingInactivity, TrainingPainArea, TrainingVenue } from '../../lib/types'
import { useLanguage } from '../../lib/i18n'
import { todayIso } from '../../lib/plan'
import {
  EQUIPMENT_CATALOG,
  assessTrainingInput,
  generateTrainingPlan,
  searchEquipment,
  type TrainingInductionInput,
} from '../../lib/trainingInduction'
import { ACCENTS } from '../../lib/theme'
import { useStore } from '../../store/AppStore'
import { AccentChip, GhostButton, GlassCard, GradientButton, Sheet } from '../ui'

type Language = 'en' | 'ro' | 'th'

const COPY = {
  en: {
    eyebrow: 'PERSONAL STARTING PATH', transitionTitle: 'Your first 12 weeks, made simple', mainTitle: 'Your next phase is already mapped',
    emptyBody: 'Answer four short questions. APEX will build a minimal plan around your training gap, body, location and equipment.',
    activeBody: 'Your plan is installed in the calendar. Every block has one job, so progress stays obvious.',
    build: 'Build my first 12 weeks', review: 'Review plan', mainButton: 'Set up my main phase',
    starts: 'Starts', mainStarts: 'Main phase', sessions: 'sessions / week', home: 'Home', gym: 'Gym',
    wizard: 'Training induction', step: 'Step', back: 'Back', next: 'Continue', install: 'Install my plan',
    gapTitle: 'How long has regular strength training been absent?', gapBody: 'This changes the starting volume, not your potential.',
    frequency: 'How many weekly sessions can you repeat in a normal week?',
    bodyTitle: 'Anything the plan must protect?', bodyBody: 'Choose current joint pain or fatigue. Do not count normal muscle soreness.',
    operation: 'Recent operation', lowerBack: 'Chronic lower-back pain', none: 'Nothing to flag',
    venueTitle: 'Where will you train?', venueBody: 'Every exercise will stay inside the setup you actually have.',
    homeLabel: 'At home', homeBody: 'Bodyweight and only the tools you select', gymLabel: 'In a gym', gymBody: 'Machines, cables and free weights',
    equipmentTitle: 'What equipment is available?', equipmentBody: 'Type a few letters. “dum” immediately finds both dumbbell types.',
    equipmentPlaceholder: 'Search equipment', noEquipment: 'No equipment is completely fine. A bodyweight version will be built.',
    goalTitle: 'What should the next phase prioritize?', rebuild: 'Rebuild consistency', muscle: 'Build muscle', strength: 'Build strength',
    reviewTitle: 'Your plan logic', standard: 'Standard foundation', cautious: 'Conservative foundation', clearance: 'Clearance-first path',
    standardBody: 'A repeatable schedule with gradual volume and logged-load progression.',
    cautiousBody: 'Volume is reduced and every movement begins with 3 to 4 reps in reserve.',
    clearanceBody: 'Recent surgery needs clinician clearance. APEX installs only gentle preparation until loaded training is cleared.',
    phases: 'Weeks 1-4 restore · 5-8 build · 9-12 progress', installed: 'Your personalized 12-week path is installed.',
  },
  ro: {
    eyebrow: 'TRASEU PERSONAL DE ÎNCEPUT', transitionTitle: 'Primele 12 săptămâni, fără complicații', mainTitle: 'Următoarea etapă este deja pregătită',
    emptyBody: 'Răspunde la patru întrebări scurte. APEX construiește un plan minimal pe baza pauzei, corpului, locului și echipamentului tău.',
    activeBody: 'Planul este instalat în calendar. Fiecare etapă are un singur scop, iar progresul rămâne clar.',
    build: 'Construiește primele 12 săptămâni', review: 'Revizuiește planul', mainButton: 'Configurează faza principală',
    starts: 'Începe', mainStarts: 'Faza principală', sessions: 'sesiuni / săptămână', home: 'Acasă', gym: 'Sală',
    wizard: 'Inducție pentru antrenament', step: 'Pasul', back: 'Înapoi', next: 'Continuă', install: 'Instalează planul',
    gapTitle: 'De cât timp lipsește antrenamentul regulat de forță?', gapBody: 'Răspunsul schimbă volumul de început, nu potențialul tău.',
    frequency: 'Câte sesiuni poți repeta într-o săptămână normală?',
    bodyTitle: 'Ce trebuie să protejeze planul?', bodyBody: 'Alege durerea sau oboseala articulară actuală. Nu include febra musculară normală.',
    operation: 'Operație recentă', lowerBack: 'Durere lombară cronică', none: 'Nimic de semnalat',
    venueTitle: 'Unde te vei antrena?', venueBody: 'Fiecare exercițiu va folosi doar spațiul și resursele pe care le ai.',
    homeLabel: 'Acasă', homeBody: 'Greutatea corpului și doar echipamentul selectat', gymLabel: 'La sală', gymBody: 'Aparate, cabluri și greutăți libere',
    equipmentTitle: 'Ce echipament ai disponibil?', equipmentBody: 'Scrie câteva litere. „gan” găsește imediat ambele tipuri de gantere.',
    equipmentPlaceholder: 'Caută echipament', noEquipment: 'Este în regulă și fără echipament. Va fi creată o variantă cu greutatea corpului.',
    goalTitle: 'Care este prioritatea fazei următoare?', rebuild: 'Refacerea consecvenței', muscle: 'Masă musculară', strength: 'Forță',
    reviewTitle: 'Logica planului tău', standard: 'Fundație standard', cautious: 'Fundație conservatoare', clearance: 'Traseu cu aviz medical',
    standardBody: 'Un program repetabil, cu volum gradual și progresie bazată pe greutățile înregistrate.',
    cautiousBody: 'Volumul este redus, iar fiecare mișcare începe cu 3 sau 4 repetări în rezervă.',
    clearanceBody: 'O operație recentă necesită aviz medical. APEX instalează doar pregătire ușoară până când efortul cu greutăți este permis.',
    phases: 'Săpt. 1-4 refacere · 5-8 construcție · 9-12 progres', installed: 'Traseul personalizat de 12 săptămâni a fost instalat.',
  },
  th: {
    eyebrow: 'เส้นทางเริ่มต้นส่วนตัว', transitionTitle: '12 สัปดาห์แรกที่ทำตามได้ง่าย', mainTitle: 'ช่วงถัดไปของคุณพร้อมแล้ว',
    emptyBody: 'ตอบคำถามสั้น ๆ 4 ข้อ APEX จะสร้างแผนที่เรียบง่ายจากช่วงที่หยุดฝึก สภาพร่างกาย สถานที่ และอุปกรณ์ของคุณ',
    activeBody: 'ติดตั้งแผนลงในปฏิทินแล้ว แต่ละช่วงมีเป้าหมายเดียว จึงเห็นความก้าวหน้าได้ชัดเจน',
    build: 'สร้างแผน 12 สัปดาห์แรก', review: 'ทบทวนแผน', mainButton: 'ตั้งค่าช่วงหลัก',
    starts: 'เริ่ม', mainStarts: 'ช่วงหลัก', sessions: 'ครั้ง / สัปดาห์', home: 'ที่บ้าน', gym: 'ยิม',
    wizard: 'แบบประเมินก่อนเริ่มฝึก', step: 'ขั้นตอน', back: 'ย้อนกลับ', next: 'ต่อไป', install: 'ติดตั้งแผนของฉัน',
    gapTitle: 'หยุดฝึกเวทอย่างสม่ำเสมอมานานเท่าไร?', gapBody: 'คำตอบนี้เปลี่ยนปริมาณเริ่มต้น ไม่ได้จำกัดศักยภาพของคุณ',
    frequency: 'ในสัปดาห์ปกติ คุณทำได้กี่ครั้งอย่างสม่ำเสมอ?',
    bodyTitle: 'มีส่วนใดที่แผนต้องระวัง?', bodyBody: 'เลือกอาการปวดหรือความล้าของข้อต่อในตอนนี้ ไม่นับอาการปวดกล้ามเนื้อตามปกติ',
    operation: 'เพิ่งผ่าตัด', lowerBack: 'ปวดหลังส่วนล่างเรื้อรัง', none: 'ไม่มีสิ่งที่ต้องแจ้ง',
    venueTitle: 'คุณจะฝึกที่ไหน?', venueBody: 'ทุกท่าจะใช้เฉพาะสถานที่และอุปกรณ์ที่คุณมีจริง',
    homeLabel: 'ที่บ้าน', homeBody: 'น้ำหนักตัวและอุปกรณ์ที่คุณเลือกเท่านั้น', gymLabel: 'ในยิม', gymBody: 'เครื่อง เคเบิล และฟรีเวท',
    equipmentTitle: 'คุณมีอุปกรณ์อะไรบ้าง?', equipmentBody: 'พิมพ์เพียงไม่กี่ตัว ระบบจะแสดงตัวเลือกที่ใกล้เคียงทันที',
    equipmentPlaceholder: 'ค้นหาอุปกรณ์', noEquipment: 'ไม่มีอุปกรณ์ก็ได้ ระบบจะสร้างเวอร์ชันน้ำหนักตัวให้',
    goalTitle: 'ช่วงถัดไปควรเน้นอะไร?', rebuild: 'กลับมาสม่ำเสมอ', muscle: 'สร้างกล้ามเนื้อ', strength: 'เพิ่มความแข็งแรง',
    reviewTitle: 'เหตุผลของแผน', standard: 'พื้นฐานมาตรฐาน', cautious: 'พื้นฐานแบบระมัดระวัง', clearance: 'เริ่มหลังได้รับอนุญาต',
    standardBody: 'ตารางที่ทำซ้ำได้ เพิ่มปริมาณทีละน้อย และใช้ค่าน้ำหนักที่บันทึกเพื่อพัฒนา',
    cautiousBody: 'ลดปริมาณฝึก และเริ่มทุกท่าโดยเหลือแรงอีก 3 ถึง 4 ครั้ง',
    clearanceBody: 'การผ่าตัดล่าสุดต้องได้รับอนุญาตจากแพทย์ APEX จะติดตั้งเฉพาะการเตรียมตัวเบา ๆ จนกว่าจะได้รับอนุญาตให้ฝึกแรงต้าน',
    phases: 'สัปดาห์ 1-4 ฟื้นพื้นฐาน · 5-8 สร้าง · 9-12 พัฒนา', installed: 'ติดตั้งเส้นทางส่วนตัว 12 สัปดาห์แล้ว',
  },
} satisfies Record<Language, Record<string, string>>

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

export function TrainingInductionPanel({ slug }: { slug: ProgramSlug }) {
  const { data, bulkUpsert, setSettings, toast } = useStore()
  const { language } = useLanguage()
  const lang = language as Language
  const copy = COPY[lang]
  const current = data.settings?.addons.training_induction
  const [open, setOpen] = useState(false)
  const [step, setStep] = useState(0)
  const [search, setSearch] = useState('')
  const [draft, setDraft] = useState<TrainingInductionInput>(() => ({
    start_date: current?.start_date ?? todayIso(),
    inactivity: current?.inactivity ?? 'one_to_three_months',
    venue: current?.venue ?? 'gym',
    equipment: current?.equipment ?? [],
    pain_areas: current?.pain_areas ?? [],
    recent_operation: current?.recent_operation ?? false,
    chronic_lower_back_pain: current?.chronic_lower_back_pain ?? false,
    sessions_per_week: current?.sessions_per_week ?? 3,
    goal: current?.goal ?? 'rebuild',
  }))
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
  const install = (): void => {
    const userId = data.profile?.user_id
    const settings = data.settings
    if (!userId || !settings) return
    const generated = generateTrainingPlan(userId, draft, data.programs)
    bulkUpsert('programs', generated.programs)
    bulkUpsert('program_days', generated.program_days)
    bulkUpsert('exercises', generated.exercises)
    setSettings({ addons: { ...settings.addons, newbie_mode: true, training_induction: generated.induction } })
    toast(copy.installed, 'ok')
    setOpen(false)
    setStep(0)
  }
  const cautionTitle = assessment.caution === 'clearance' ? copy.clearance : assessment.caution === 'cautious' ? copy.cautious : copy.standard
  const cautionBody = assessment.caution === 'clearance' ? copy.clearanceBody : assessment.caution === 'cautious' ? copy.cautiousBody : copy.standardBody

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
                <AccentChip accent={ACCENTS.violet}>{current.venue === 'gym' ? copy.gym : copy.home}</AccentChip>
                <AccentChip accent={ACCENTS.teal}>{current.sessions_per_week} {copy.sessions}</AccentChip>
                <AccentChip accent={current.caution === 'standard' ? ACCENTS.emerald : ACCENTS.amber}>{current.caution === 'clearance' ? copy.clearance : current.caution === 'cautious' ? copy.cautious : copy.standard}</AccentChip>
              </div>
            )}
            {current && <p className="mt-3 font-mono text-[10px] font-bold text-ink-faint">{copy.starts}: {current.start_date} · {copy.mainStarts}: {current.main_start_date}</p>}
          </div>
          <GradientButton accent={ACCENTS.violet} onClick={() => setOpen(true)} className="w-full sm:w-auto">
            {current ? copy.review : slug === 'main' ? copy.mainButton : copy.build}
          </GradientButton>
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
              <p className="font-mono text-[9px] font-black tracking-[.2em] text-violet-700 uppercase">{copy.step} {step + 1} / 5</p>
              <h2 className="mt-1 font-display text-2xl font-bold text-ink">{copy.wizard}</h2>
            </div>
            <button type="button" onClick={() => setOpen(false)} className="grid h-10 w-10 place-items-center rounded-full bg-ink/5 text-lg font-bold text-ink-soft" aria-label="Close">×</button>
          </div>
          <div className="mt-4 grid grid-cols-5 gap-1.5" aria-hidden>
            {[0, 1, 2, 3, 4].map((item) => <div key={item} className="h-1.5 rounded-full transition" style={{ background: item <= step ? ACCENTS.violet.gradient : 'rgba(26,26,34,.08)' }} />)}
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
                <div className="mt-3 grid grid-cols-3 gap-2">
                  {([2, 3, 4] as const).map((count) => <Choice key={count} active={draft.sessions_per_week === count} onClick={() => setDraft((value) => ({ ...value, sessions_per_week: count }))} className="text-center"><span className="font-mono text-xl text-ink">{count}</span></Choice>)}
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
                <div className="mt-5 grid gap-3 sm:grid-cols-2">
                  {([['home', copy.homeLabel, copy.homeBody], ['gym', copy.gymLabel, copy.gymBody]] as Array<[TrainingVenue, string, string]>).map(([venue, title, body]) => (
                    <Choice key={venue} active={draft.venue === venue} onClick={() => setDraft((value) => ({ ...value, venue }))} className="min-h-28">
                      <span className="block font-display text-lg text-ink">{title}</span><span className="mt-1 block text-xs leading-relaxed font-medium text-ink-soft">{body}</span>
                    </Choice>
                  ))}
                </div>
              </div>
            )}
            {step === 3 && (
              <div>
                {draft.venue === 'home' && (
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
                <h3 className={`${draft.venue === 'home' ? 'mt-7' : ''} font-display text-xl font-bold text-ink`}>{copy.goalTitle}</h3>
                <div className="mt-3 grid gap-2 sm:grid-cols-3">
                  {([['rebuild', copy.rebuild], ['muscle', copy.muscle], ['strength', copy.strength]] as Array<[TrainingGoal, string]>).map(([goal, label]) => <Choice key={goal} active={draft.goal === goal} onClick={() => setDraft((value) => ({ ...value, goal }))}>{label}</Choice>)}
                </div>
              </div>
            )}
            {step === 4 && (
              <div>
                <h3 className="font-display text-xl font-bold text-ink">{copy.reviewTitle}</h3>
                <div className="mt-4 rounded-3xl border border-violet-200/60 bg-gradient-to-br from-violet-50/90 to-cyan-50/80 p-5">
                  <div className="flex flex-wrap items-center justify-between gap-3"><h4 className="font-display text-xl font-bold text-ink">{cautionTitle}</h4><AccentChip accent={assessment.caution === 'standard' ? ACCENTS.emerald : ACCENTS.amber}>{assessment.sessions_per_week} {copy.sessions}</AccentChip></div>
                  <p className="mt-3 text-sm leading-relaxed font-medium text-ink-soft">{cautionBody}</p>
                  <p className="mt-4 font-mono text-[10px] font-black tracking-[.08em] text-violet-800 uppercase">{copy.phases}</p>
                </div>
                <div className="mt-4 grid grid-cols-2 gap-2 text-center sm:grid-cols-4">
                  {[draft.venue === 'gym' ? copy.gym : copy.home, `${assessment.sessions_per_week} ${copy.sessions}`, draft.start_date, draft.goal === 'rebuild' ? copy.rebuild : draft.goal === 'muscle' ? copy.muscle : copy.strength].map((value) => <div key={value} className="rounded-2xl bg-white/65 px-2 py-3 text-xs font-bold text-ink-soft">{value}</div>)}
                </div>
              </div>
            )}
          </div>

          <div className="mt-6 flex gap-2 border-t border-ink/8 pt-4">
            {step > 0 && <GhostButton onClick={() => setStep((value) => value - 1)} className="flex-1">{copy.back}</GhostButton>}
            {step < 4 ? <GradientButton accent={ACCENTS.violet} onClick={() => setStep((value) => value + 1)} className="flex-1">{copy.next}</GradientButton> : <GradientButton accent={ACCENTS.violet} onClick={install} className="flex-1">{copy.install}</GradientButton>}
          </div>
        </div>
      </Sheet>
    </div>
  )
}
