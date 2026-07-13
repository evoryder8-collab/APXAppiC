import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { GlassCard, GhostButton, GradientButton } from '../../components/ui.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { useStore } from '../../store/AppStore.tsx'
import { assessInduction, coordinateCampaignWithEvents, createCampaign, EMPTY_INDUCTION_ANSWERS, generateCampaignSessions } from '../domain/campaign.ts'
import { orbitUuid } from '../domain/ids.ts'
import type { MarathonInduction, MarathonInductionAnswers } from '../domain/types.ts'
import { OrbitFrame, OrbitPill } from '../components/OrbitFrame.tsx'
import { useOrbitStore } from '../store/OrbitStore.tsx'
import { useOrbitText } from '../ui/i18n.ts'

type AnswerKey = keyof MarathonInductionAnswers
type Choice = { value: string; label: string }
type Question = {
  key: AnswerKey | 'constraints' | 'unavailable_days' | 'current_status'
  title: string
  helper?: string
  type: 'text' | 'date' | 'choice' | 'multi'
  choices?: Choice[]
  optional?: boolean
  visible?: (answers: MarathonInductionAnswers) => boolean
}

const QUESTIONS: Question[] = [
  { key: 'race_name', title: 'Which marathon are you preparing for?', helper: 'Use the event name. Orbit keeps this private.', type: 'text' },
  { key: 'race_date', title: 'What is the race date?', type: 'date' },
  { key: 'race_goal', title: 'What matters most at this marathon?', type: 'choice', choices: [
    { value: 'finish', label: 'Finish' }, { value: 'finish_comfortably', label: 'Finish comfortably' }, { value: 'target_time', label: 'Reach a target time' }, { value: 'best_realistic', label: 'Pursue the best realistic performance' },
  ] },
  { key: 'target_time', title: 'What target time do you have in mind?', helper: 'This is a planning input, not a promised result.', type: 'text', optional: true, visible: (answers) => answers.race_goal === 'target_time' },
  { key: 'course_profile', title: 'What is the course profile?', type: 'choice', choices: [{ value: 'flat', label: 'Mostly flat' }, { value: 'rolling', label: 'Rolling' }, { value: 'hilly', label: 'Hilly' }] },
  { key: 'course_surface', title: 'What surface does the race use?', type: 'choice', choices: [{ value: 'road', label: 'Road' }, { value: 'trail', label: 'Trail' }, { value: 'mixed', label: 'Mixed' }, { value: 'path', label: 'Mostly path' }] },
  { key: 'climate_familiar', title: 'Is the expected climate familiar to you?', type: 'choice', choices: [{ value: 'yes', label: 'Yes' }, { value: 'no', label: 'No' }, { value: 'unsure', label: 'I am not sure' }] },
  { key: 'running_frequency', title: 'How often are you currently running?', type: 'choice', choices: [{ value: 'none', label: 'I am not currently running' }, { value: 'one', label: 'Once per week' }, { value: 'two', label: 'Twice per week' }, { value: 'three', label: 'Three times per week' }, { value: 'four', label: 'Four times per week' }, { value: 'five_plus', label: 'Five or more times per week' }] },
  { key: 'weekly_distance', title: 'What is your recent weekly distance?', type: 'choice', choices: [{ value: 'under_10', label: 'Under 10 km' }, { value: '10_20', label: '10 to 20 km' }, { value: '20_35', label: '20 to 35 km' }, { value: '35_50', label: '35 to 50 km' }, { value: 'over_50', label: 'More than 50 km' }, { value: 'unsure', label: 'I am not sure' }] },
  { key: 'longest_run', title: 'What is your longest recent run?', type: 'choice', choices: [{ value: 'under_5', label: 'Under 5 km' }, { value: '5_10', label: '5 to 10 km' }, { value: '10_15', label: '10 to 15 km' }, { value: '15_21', label: '15 to 21 km' }, { value: 'over_21', label: 'More than 21 km' }, { value: 'unsure', label: 'I am not sure' }] },
  { key: 'consistency', title: 'How long have you trained consistently?', type: 'choice', choices: [{ value: 'none', label: 'I have not trained consistently' }, { value: 'under_month', label: 'Less than one month' }, { value: 'one_three_months', label: 'One to three months' }, { value: 'three_six_months', label: 'Three to six months' }, { value: 'over_six_months', label: 'More than six months' }] },
  { key: 'race_experience', title: 'What organised race experience do you have?', type: 'choice', choices: [{ value: 'none', label: 'No organised races' }, { value: '5k', label: '5K' }, { value: '10k', label: '10K' }, { value: 'half', label: 'Half marathon' }, { value: 'marathon', label: 'Marathon' }, { value: 'multiple_marathons', label: 'Multiple marathons' }] },
  { key: 'marathon_experience', title: 'How many marathons have you completed?', type: 'choice', choices: [{ value: 'never', label: 'Never' }, { value: 'one', label: 'One marathon' }, { value: 'two_four', label: 'Two to four marathons' }, { value: 'five_plus', label: 'Five or more marathons' }] },
  { key: 'structured_plan', title: 'What is your structured-plan experience?', type: 'choice', choices: [{ value: 'never', label: 'Never followed one' }, { value: 'inconsistent', label: 'Followed one inconsistently' }, { value: 'completed_one', label: 'Completed one' }, { value: 'completed_several', label: 'Completed several' }] },
  { key: 'running_style', title: 'Which running style suits you now?', type: 'choice', choices: [{ value: 'continuous', label: 'Mostly continuous running' }, { value: 'run_walk', label: 'Mostly run and walk' }, { value: 'either', label: 'Comfortable with either' }, { value: 'unsure', label: 'Not sure yet' }] },
  { key: 'available_days', title: 'How many running days are realistically available?', type: 'choice', choices: [{ value: 'three', label: 'Three days' }, { value: 'four', label: 'Four days' }, { value: 'five', label: 'Five days' }, { value: 'six', label: 'Six days' }, { value: 'variable', label: 'Variable schedule' }] },
  { key: 'long_run_day', title: 'Which long-run day works best?', type: 'choice', choices: [{ value: 'saturday', label: 'Saturday' }, { value: 'sunday', label: 'Sunday' }, { value: 'other', label: 'Another fixed day' }, { value: 'variable', label: 'Variable' }] },
  { key: 'unavailable_days', title: 'Which days are regularly unavailable?', helper: 'Choose any that apply. Leave all clear if the schedule varies.', type: 'multi', optional: true, choices: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'].map((label, index) => ({ value: String(index), label })) },
  { key: 'constraints', title: 'Which lifestyle constraints should Orbit protect?', helper: 'APEX already coordinates these with strength and calendar context.', type: 'multi', optional: true, choices: [{ value: 'physical_work', label: 'Physically demanding work' }, { value: 'travel', label: 'Travel' }, { value: 'shift_work', label: 'Shift work' }, { value: 'childcare', label: 'Childcare' }, { value: 'events', label: 'Events' }] },
  { key: 'previous_issue', title: 'Have you had a previous issue affecting running?', helper: 'An old resolved issue does not automatically block a campaign.', type: 'choice', choices: [{ value: 'none', label: 'No significant previous issue' }, { value: 'knee', label: 'Knee' }, { value: 'hip', label: 'Hip' }, { value: 'ankle', label: 'Ankle' }, { value: 'foot', label: 'Foot' }, { value: 'lower_back', label: 'Lower back' }, { value: 'other', label: 'Another area' }] },
  { key: 'previous_surgery', title: 'Have you had surgery affecting running?', type: 'choice', choices: [{ value: 'no', label: 'No' }, { value: 'over_three_years', label: 'Yes, more than three years ago' }, { value: 'one_three_years', label: 'Yes, one to three years ago' }, { value: 'six_twelve_months', label: 'Yes, six to twelve months ago' }, { value: 'under_six_months', label: 'Yes, within the last six months' }, { value: 'prefer_not', label: 'Prefer not to answer' }] },
  { key: 'issue_status', title: 'What is the current status of the previous issue?', type: 'choice', choices: [{ value: 'resolved', label: 'Fully returned with no current symptoms' }, { value: 'noticeable', label: 'Occasionally noticeable but does not change movement' }, { value: 'changes_movement', label: 'Currently causes pain or changes movement' }, { value: 'rehabilitating', label: 'Currently rehabilitating' }, { value: 'restricted', label: 'Currently under a professional restriction' }] },
  { key: 'current_status', title: 'Do any of these currently apply?', helper: 'This is a fitness-readiness check, not medical clearance or diagnosis.', type: 'multi', optional: true, choices: [{ value: 'pain_changes_movement', label: 'Pain that changes walking or running' }, { value: 'chest_discomfort', label: 'Chest discomfort during exertion' }, { value: 'fainting', label: 'Unexplained fainting or near-fainting' }, { value: 'unusual_breathlessness', label: 'Unusual breathlessness' }, { value: 'recent_illness_or_operation', label: 'A recent significant illness or operation' }, { value: 'professional_restriction', label: 'A professional restriction on strenuous exercise' }] },
  { key: 'medication', title: 'Is medication relevant to exercise response?', helper: 'Do not enter medication names or doses. Orbit does not interpret interactions.', type: 'choice', choices: [{ value: 'none', label: 'No medication relevant to exercise' }, { value: 'clinician_knows', label: 'Yes, and my prescribing clinician knows about my training' }, { value: 'not_discussed', label: 'Yes, but I have not discussed marathon training' }, { value: 'changes_response', label: 'I have been told it changes heart-rate or exercise response' }, { value: 'unsure', label: 'Unsure or prefer not to answer' }] },
]

const STATUS_KEYS = ['pain_changes_movement', 'chest_discomfort', 'fainting', 'unusual_breathlessness', 'recent_illness_or_operation', 'professional_restriction'] as const

function ageFromBirthdate(value: string): number | null {
  if (!value) return null
  const born = new Date(`${value}T12:00:00`)
  const now = new Date()
  let age = now.getFullYear() - born.getFullYear()
  if (now.getMonth() < born.getMonth() || (now.getMonth() === born.getMonth() && now.getDate() < born.getDate())) age -= 1
  return age
}

export function MarathonInductionPage() {
  const navigate = useNavigate()
  const t = useOrbitText()
  const app = useStore()
  const orbit = useOrbitStore()
  const userId = app.data.profile?.user_id ?? ''
  const existing = [...orbit.state.inductions].sort((a, b) => b.updated_at.localeCompare(a.updated_at)).find((item) => !item.completed)
  const mainProgram = app.data.programs.find((program) => program.slug === 'main')
  const strengthDays = new Set(app.data.program_days.filter((day) => day.program_id === mainProgram?.id).map((day) => day.weekday)).size
  const [inductionId] = useState(() => existing?.id ?? orbitUuid(userId || 'pending', `induction:${Date.now()}`))
  const [answers, setAnswers] = useState<MarathonInductionAnswers>(() => existing?.answers ?? { ...EMPTY_INDUCTION_ANSWERS, strength_days_per_week: strengthDays })
  const [step, setStep] = useState(existing?.current_step ?? 0)
  const hydrated = useRef(Boolean(existing))

  useEffect(() => {
    if (hydrated.current || !existing) return
    hydrated.current = true
    setAnswers(existing.answers)
    setStep(existing.current_step)
  }, [existing])

  const visible = useMemo(() => QUESTIONS.filter((question) => !question.visible || question.visible(answers)), [answers])
  const question = visible[Math.min(step, visible.length - 1)]
  const progress = Math.round(((step + 1) / visible.length) * 100)
  const age = ageFromBirthdate(app.data.profile?.birthdate ?? '')

  const selectedValues = (item: Question): string[] => {
    if (item.key === 'constraints') return answers.constraints
    if (item.key === 'unavailable_days') return answers.unavailable_days.map(String)
    if (item.key === 'current_status') return STATUS_KEYS.filter((key) => answers[key])
    return []
  }

  const setValue = (item: Question, value: string): void => {
    setAnswers((current) => ({ ...current, [item.key]: value }))
  }

  const toggleMulti = (item: Question, value: string): void => {
    setAnswers((current) => {
      if (item.key === 'constraints') {
        const choice = value as MarathonInductionAnswers['constraints'][number]
        return { ...current, constraints: current.constraints.includes(choice) ? current.constraints.filter((itemValue) => itemValue !== choice) : [...current.constraints, choice] }
      }
      if (item.key === 'unavailable_days') {
        const day = Number(value)
        return { ...current, unavailable_days: current.unavailable_days.includes(day) ? current.unavailable_days.filter((itemValue) => itemValue !== day) : [...current.unavailable_days, day] }
      }
      if (item.key === 'current_status') {
        const key = value as typeof STATUS_KEYS[number]
        return { ...current, [key]: !current[key] }
      }
      return current
    })
  }

  const hasAnswer = (): boolean => {
    if (question.optional || question.type === 'multi') return true
    return Boolean(answers[question.key as AnswerKey])
  }

  const persist = async (nextStep: number, complete = false): Promise<MarathonInduction> => {
    const now = new Date().toISOString()
    const assessment = complete ? assessInduction(answers) : null
    const row: MarathonInduction = {
      id: inductionId, user_id: userId, answers: { ...answers, strength_days_per_week: strengthDays || answers.strength_days_per_week },
      current_step: nextStep, completed: complete, outcome: assessment?.outcome ?? null, outcome_reason: assessment?.reason ?? '',
      created_at: existing?.created_at ?? now, updated_at: now, sync_state: 'local',
    }
    await orbit.saveInduction(row)
    return row
  }

  const next = async (): Promise<void> => {
    if (!hasAnswer()) return
    if (step < visible.length - 1) {
      const nextStep = step + 1
      setStep(nextStep)
      await persist(nextStep)
      return
    }
    const completed = await persist(step, true)
    const campaign = createCampaign(completed)
    const lowerWeekdays = app.data.program_days.filter((day) => day.program_id === mainProgram?.id && ['legs_a', 'legs_b'].includes(day.day_type)).map((day) => day.weekday === 7 ? 0 : day.weekday)
    const sessions = generateCampaignSessions(campaign, completed.answers, lowerWeekdays)
    const coordinated = coordinateCampaignWithEvents(campaign, sessions, app.data.events, lowerWeekdays)
    await orbit.saveCampaign(coordinated.campaign, coordinated.sessions)
    navigate('/orbit/campaign', { replace: true, state: { justCompleted: true } })
  }

  const currentValue = question.key === 'current_status' || question.key === 'constraints' || question.key === 'unavailable_days' ? '' : String(answers[question.key as AnswerKey] ?? '')
  const knownProfile = `APEX already knows: ${age == null ? 'age unavailable' : `age ${age}`} · ${app.data.profile?.weight_kg == null ? 'weight unavailable' : `${app.data.profile.weight_kg} kg`} · ${strengthDays} strength days in the Main Phase.`
  return (
    <OrbitFrame title="Fitness-readiness check" subtitle="One clear question at a time. APEX reuses what it already knows." backTo="/orbit/campaign" action={<OrbitPill tone="ice">{progress}%</OrbitPill>}>
      <div className="mx-auto max-w-2xl space-y-4">
        <div className="h-1.5 overflow-hidden rounded-full bg-slate-200"><div className="h-full rounded-full bg-gradient-to-r from-sky-500 to-violet-500 transition-all duration-500" style={{ width: `${progress}%` }} /></div>
        <GlassCard accent={ACCENTS.ice} className="p-6 sm:p-8">
          <p className="font-mono text-[10px] font-bold tracking-widest text-sky-700">{t(`QUESTION ${step + 1} OF ${visible.length}`)}</p>
          <h2 className="mt-3 font-display text-2xl font-bold leading-tight text-ink">{t(question.title)}</h2>
          {question.helper && <p className="mt-2 text-sm leading-relaxed text-ink-soft">{t(question.helper)}</p>}
          {question.type === 'text' && <input autoFocus value={currentValue} onChange={(event) => setValue(question, event.target.value)} placeholder={t(question.key === 'target_time' ? 'Example: 4:15:00' : 'Type your answer')} className="mt-6 min-h-14 w-full rounded-2xl border border-white/80 bg-white/75 px-4 text-base font-semibold text-ink outline-none focus:ring-2 focus:ring-sky-300" />}
          {question.type === 'date' && <input autoFocus type="date" min={new Date().toISOString().slice(0, 10)} value={currentValue} onChange={(event) => setValue(question, event.target.value)} className="mt-6 min-h-14 w-full rounded-2xl border border-white/80 bg-white/75 px-4 text-base font-semibold text-ink outline-none" />}
          {question.type === 'choice' && <div className="mt-6 grid gap-2">{question.choices?.map((choice) => <button key={choice.value} type="button" onClick={() => setValue(question, choice.value)} className={`min-h-13 rounded-2xl border px-4 py-3 text-left text-sm font-bold transition ${currentValue === choice.value ? 'border-sky-400 bg-[#071b2d] text-white shadow-lg' : 'border-white/80 bg-white/65 text-ink'}`}>{t(choice.label)}</button>)}</div>}
          {question.type === 'multi' && <div className="mt-6 grid gap-2">{question.choices?.map((choice) => { const selected = selectedValues(question).includes(choice.value); return <button key={choice.value} type="button" onClick={() => toggleMulti(question, choice.value)} className={`flex min-h-13 items-center gap-3 rounded-2xl border px-4 py-3 text-left text-sm font-bold ${selected ? 'border-sky-400 bg-sky-950 text-white' : 'border-white/80 bg-white/65 text-ink'}`}><span className={`grid h-5 w-5 place-items-center rounded-md border ${selected ? 'border-sky-300 bg-sky-500' : 'border-slate-300'}`}>{selected ? '✓' : ''}</span>{t(choice.label)}</button> })}</div>}
        </GlassCard>

        <GlassCard className="p-4"><p className="text-xs font-bold text-ink">{t(knownProfile)}</p><p className="mt-1 text-[11px] leading-relaxed text-ink-soft">{t('Age informs recovery spacing, but recent consistency and actual performance matter more than stereotypes.')}</p></GlassCard>
        <div className="flex justify-between gap-3"><GhostButton onClick={() => { if (step > 0) setStep((value) => value - 1); else navigate('/orbit/campaign') }}>{t('Back')}</GhostButton><GradientButton accent={ACCENTS.ice} onClick={() => void next()} disabled={!hasAnswer()} className="min-w-36">{step === visible.length - 1 ? t('Complete induction') : t('Next')}</GradientButton></div>
        <p className="px-2 text-center text-[10px] leading-relaxed text-ink-faint">{t('APEX Orbit Marathon Campaign provides personalized fitness training, educational guidance and performance tracking for adults preparing for endurance events. It does not diagnose, treat, monitor, predict or prevent disease or injury and does not determine medical fitness for exercise.')}</p>
      </div>
    </OrbitFrame>
  )
}
