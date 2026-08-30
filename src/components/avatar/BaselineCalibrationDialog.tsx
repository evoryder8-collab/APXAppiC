import { useEffect, useMemo, useRef, useState } from 'react'
import { motion, useReducedMotion } from 'framer-motion'

import {
  buildManualCalibrationEvidence,
  clearBaselineCalibrationDraft,
  emptyBaselineCalibrationAnswers,
  evaluateBaselineCalibration,
  loadBaselineCalibrationDraft,
  normalizedCalibrationEvidence,
  saveBaselineCalibrationDraft,
  type BaselineCalibrationAnswer,
  type BaselineCalibrationAnswers,
  type BaselineCalibrationDomain,
  type BaselineCalibrationDraft,
} from '../../lib/baselineCalibration.ts'
import type { FitnessEvidenceMetric } from '../../lib/fitnessEvidence.ts'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import type { Profile } from '../../lib/types.ts'
import { useStore } from '../../store/AppStore.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { EASE } from '../ui.tsx'

type Route = 'home' | 'questions' | 'recent_result' | 'health'
type SaveState = 'idle' | 'saving' | 'saved' | 'failed'

interface DomainContent {
  domain: BaselineCalibrationDomain
  title: string
  questions: string[]
}

const domains: DomainContent[] = [
  {
    domain: 'cardiorespiratory',
    title: 'Stamina',
    questions: [
      'Sustained effort: a few minutes · brisk 20 minutes · steady cardio 20 minutes · trained intervals',
      'Stairs: frequent pause · one flight comfortable · several flights controlled · repeated climbs trained',
      'Conditioning week: none · one easy session · two steady sessions · three or more purposeful sessions',
    ],
  },
  {
    domain: 'upper_strength',
    title: 'Upper body',
    questions: [
      'Pressing: body weight difficult · raised push-ups · floor push-ups · challenging presses',
      'Pulling: little recent work · light supported rows · controlled rows · pull-ups or challenging pulls',
      'Upper-body training: none · occasional · weekly progressive work · multiple challenging sessions',
    ],
  },
  {
    domain: 'lower_strength',
    title: 'Lower body',
    questions: [
      'Chair and stairs: tiring · comfortable · repeated with control · high work capacity',
      'Squat and lunge: restricted · chair-depth control · deep controlled reps · challenging full-range work',
      'Lower-body training: none · occasional · weekly progressive work · multiple challenging sessions',
    ],
  },
  {
    domain: 'mobility',
    title: 'Mobility',
    questions: [
      'Hips and posterior chain: daily restriction · functional reach · deep hinge or squat · advanced range practice',
      'Ankles: heels lift early · daily range comfortable · knee-over-toe range controlled · deep loaded range trained',
      'Shoulders: overhead reach restricted · daily reach comfortable · full overhead control · advanced range trained',
    ],
  },
]

const answerOptions: Array<{ value: BaselineCalibrationAnswer; label: string }> = [
  { value: 'not_tested', label: 'Not tested' },
  { value: 'foundation', label: 'Foundation' },
  { value: 'developing', label: 'Developing' },
  { value: 'capable', label: 'Capable' },
  { value: 'strong', label: 'Strong signal' },
]

const manualMetrics: Array<{
  metric: FitnessEvidenceMetric
  title: string
  unit: string
  unitLabel: string
  placeholder: string
}> = [
  { metric: 'body_fat_percentage', title: 'Body fat', unit: 'percent', unitLabel: '%', placeholder: '18' },
  { metric: 'resting_metabolic_rate', title: 'Resting energy (BMR/RMR)', unit: 'kcal_per_day', unitLabel: 'kcal/day', placeholder: '1683' },
  { metric: 'vo2_max', title: 'VO₂ max', unit: 'ml_per_kg_min', unitLabel: 'ml/kg/min', placeholder: '42.5' },
  { metric: 'resting_heart_rate', title: 'Resting heart rate', unit: 'bpm', unitLabel: 'bpm', placeholder: '58' },
  { metric: 'waist_circumference', title: 'Waist circumference', unit: 'cm', unitLabel: 'cm', placeholder: '82' },
]

function todayKey(): string {
  const now = new Date()
  const year = now.getFullYear()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const day = String(now.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

function initialDraft(profile: Profile): BaselineCalibrationDraft {
  return loadBaselineCalibrationDraft(window.localStorage, profile.user_id) ?? {
    step: 0,
    answers: emptyBaselineCalibrationAnswers(),
  }
}

export function BaselineCalibrationDialog({ profile, onClose }: { profile: Profile; onClose: () => void }) {
  const store = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const reduceMotion = useReducedMotion()
  const closeRef = useRef<HTMLButtonElement>(null)
  const onCloseRef = useRef(onClose)
  const saveStateRef = useRef<SaveState>('idle')
  const [route, setRoute] = useState<Route>('home')
  const [draft, setDraft] = useState<BaselineCalibrationDraft>(() => initialDraft(profile))
  const [saveState, setSaveState] = useState<SaveState>('idle')
  const [metricIndex, setMetricIndex] = useState(0)
  const [resultValue, setResultValue] = useState('')
  const [resultSource, setResultSource] = useState('')
  const [resultDate, setResultDate] = useState(todayKey())

  useEffect(() => {
    onCloseRef.current = onClose
  }, [onClose])

  useEffect(() => {
    saveStateRef.current = saveState
  }, [saveState])

  useEffect(() => {
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null
    const oldOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    closeRef.current?.focus()
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && saveStateRef.current !== 'saving') onCloseRef.current()
    }
    window.addEventListener('keydown', onKeyDown)
    return () => {
      window.removeEventListener('keydown', onKeyDown)
      document.body.style.overflow = oldOverflow
      previous?.focus()
    }
  }, [])

  useEffect(() => {
    if (draft.step > 0) saveBaselineCalibrationDraft(window.localStorage, profile.user_id, draft)
  }, [draft, profile.user_id])

  const evaluation = useMemo(() => evaluateBaselineCalibration({
    user_id: profile.user_id,
    measured_at: new Date().toISOString(),
    imported_at: new Date().toISOString(),
    answers: draft.answers,
  }), [draft.answers, profile.user_id])

  const goToQuestions = () => {
    setSaveState('idle')
    setDraft((current) => ({ ...current, step: current.step === 0 ? 1 : current.step }))
    setRoute('questions')
  }

  const setAnswer = (domain: BaselineCalibrationDomain, index: number, value: BaselineCalibrationAnswer) => {
    setSaveState('idle')
    setDraft((current) => {
      const answers: BaselineCalibrationAnswers = {
        ...current.answers,
        [domain]: [...current.answers[domain]],
      }
      answers[domain][index] = value
      return { ...current, answers }
    })
  }

  const saveQuestions = () => {
    if (evaluation.status !== 'accepted') return
    setSaveState('saving')
    try {
      const now = new Date().toISOString()
      const final = evaluateBaselineCalibration({
        user_id: profile.user_id,
        measured_at: now,
        imported_at: now,
        answers: draft.answers,
      })
      if (final.status !== 'accepted' || final.evidence.length === 0) throw new Error('empty_calibration')
      const evidence = normalizedCalibrationEvidence(final.evidence, now)
      if (evidence.length !== final.evidence.length) throw new Error('invalid_calibration_evidence')
      evidence.forEach(store.recordFitnessEvidence)
      clearBaselineCalibrationDraft(window.localStorage, profile.user_id)
      setSaveState('saved')
      store.toast(t('Saved to your evidence'), 'ok')
    } catch {
      setSaveState('failed')
    }
  }

  const saveRecentResult = () => {
    const metric = manualMetrics[metricIndex]
    const value = Number(resultValue.replace(',', '.'))
    if (!Number.isFinite(value)) return
    setSaveState('saving')
    const measuredAt = new Date(`${resultDate}T12:00:00.000Z`).toISOString()
    const importedAt = new Date().toISOString()
    const result = buildManualCalibrationEvidence({
      user_id: profile.user_id,
      metric: metric.metric,
      value,
      unit: metric.unit,
      declared_source: resultSource,
      measured_at: measuredAt,
      imported_at: importedAt,
    })
    if (result.status === 'rejected') {
      setSaveState('failed')
      return
    }
    try {
      store.recordFitnessEvidence(result.evidence)
      setResultValue('')
      setSaveState('saved')
      store.toast(t('Result saved'), 'ok')
    } catch {
      setSaveState('failed')
    }
  }

  const currentDomain = domains[Math.max(0, Math.min(3, draft.step - 1))]
  const metric = manualMetrics[metricIndex]
  const resultIsReady = Number.isFinite(Number(resultValue.replace(',', '.'))) && resultSource.trim().length > 0

  return (
    <div
      className="fixed inset-0 z-[100] grid place-items-end bg-slate-950/38 px-3 pt-[max(1rem,env(safe-area-inset-top))] pb-[max(.75rem,env(safe-area-inset-bottom))] backdrop-blur-md sm:place-items-center sm:p-5"
      role="presentation"
      onPointerDown={(event) => { if (event.target === event.currentTarget && saveState !== 'saving') onClose() }}
    >
      <motion.section
        initial={reduceMotion ? false : { opacity: 0, y: 28, scale: 0.98 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: reduceMotion ? 0 : 0.28, ease: EASE }}
        role="dialog"
        aria-modal="true"
        aria-labelledby="baseline-calibration-title"
        className="flex max-h-[min(88dvh,760px)] w-full max-w-xl flex-col overflow-hidden rounded-[30px] border border-white/90 bg-[linear-gradient(145deg,rgba(255,255,255,.98),rgba(240,253,250,.97),rgba(245,243,255,.97))] shadow-2xl"
      >
        <header className="flex items-center justify-between gap-3 border-b border-ink/8 px-5 py-4">
          <div className="min-w-0">
            <p className="font-mono text-[9px] font-bold tracking-[.2em] text-emerald uppercase">APEX AVATAR</p>
            <h2 id="baseline-calibration-title" className="font-display text-xl leading-tight font-bold text-ink">{t('Calibrate my baseline')}</h2>
          </div>
          <button ref={closeRef} type="button" onClick={onClose} disabled={saveState === 'saving'} className="grid min-h-11 min-w-11 place-items-center rounded-full bg-white/80 text-xl font-bold text-ink shadow-sm" aria-label={t('Close')}>×</button>
        </header>

        <div className="overflow-y-auto px-4 py-5 sm:px-6">
          {route === 'home' && (
            <div className="space-y-4">
              <div><h3 className="font-display text-3xl font-bold text-ink">{t('Sharpen your map')}</h3><p className="mt-1 text-sm leading-relaxed font-medium text-ink-soft">{t('Add better evidence without turning fitness into a test you can fail.')}</p></div>
              <div className="flex gap-2.5 rounded-2xl bg-emerald-500/8 p-3.5 text-xs leading-relaxed font-semibold text-ink-soft"><span aria-hidden>🛡️</span><p>{t(profile.profile_kind === 'bespoke' ? 'Your bespoke plan stays protected. Calibration only refines your evidence.' : 'Calibration refines your evidence. It never rewrites your training or nutrition plan.')}</p></div>
              <RouteButton title="Sharpen with questions" detail="Twelve observable prompts in four short sections." icon="⌁" tint={ACCENTS.emerald.bright} onClick={goToQuestions} t={t} />
              <RouteButton title="Connect what you track" detail="Import the Apple Health categories you choose." icon="♥" tint={ACCENTS.ice.bright} onClick={() => setRoute('health')} t={t} />
              <RouteButton title="Add a recent result" detail="Keep a DEXA, metabolic, VO₂, heart-rate or waist result with its source." icon="＋" tint={ACCENTS.violet.bright} onClick={() => { setSaveState('idle'); setRoute('recent_result') }} t={t} />
              {draft.step > 1 && <p className="text-xs font-bold text-emerald">✓ {t('Your question progress is saved privately on this device.')}</p>}
            </div>
          )}

          {route === 'questions' && draft.step < 5 && (
            <div className="space-y-4">
              <div className="h-1.5 overflow-hidden rounded-full bg-ink/8" aria-label={t('Calibration progress')} aria-valuenow={draft.step} aria-valuemin={1} aria-valuemax={4} role="progressbar"><div className="h-full rounded-full bg-emerald" style={{ width: `${draft.step * 25}%` }} /></div>
              <div><h3 className="font-display text-3xl font-bold text-ink">{t(currentDomain.title)}</h3><p className="mt-1 text-xs leading-relaxed font-medium text-ink-soft">{t('Answer from recent, pain-free experience. Do not test a movement now. Choose Not tested if pain or uncertainty is involved.')}</p><p className="mt-2 text-[11px] leading-relaxed font-bold text-emerald">{t('Read each line left to right: Foundation, Developing, Capable, Strong signal.')}</p></div>
              {currentDomain.questions.map((question, index) => (
                <label key={question} className="block rounded-2xl border border-white bg-white/75 p-4 shadow-sm">
                  <span className="block text-[13px] leading-relaxed font-bold text-ink">{t(question)}</span>
                  <select value={draft.answers[currentDomain.domain][index]} onChange={(event) => setAnswer(currentDomain.domain, index, event.target.value as BaselineCalibrationAnswer)} className="mt-3 min-h-11 w-full rounded-xl border border-emerald-200/60 bg-emerald-50/70 px-3 text-sm font-bold text-ink">
                    {answerOptions.map((option) => <option key={option.value} value={option.value}>{t(option.label)}</option>)}
                  </select>
                </label>
              ))}
              <div className="flex gap-3 pt-1"><button type="button" onClick={() => draft.step === 1 ? setRoute('home') : setDraft((current) => ({ ...current, step: current.step - 1 }))} className="min-h-11 rounded-full border border-ink/12 bg-white px-5 text-sm font-bold text-ink">{t('Back')}</button><button type="button" onClick={() => setDraft((current) => ({ ...current, step: current.step + 1 }))} className="min-h-11 flex-1 rounded-full bg-emerald px-5 text-sm font-bold text-white">{t(draft.step === 4 ? 'Review my baseline' : 'Continue')}</button></div>
            </div>
          )}

          {route === 'questions' && draft.step >= 5 && evaluation.status === 'accepted' && (
            <div className="space-y-4">
              <div><h3 className="font-display text-3xl font-bold text-ink">{t('Your sharper starting map')}</h3><p className="mt-1 text-xs leading-relaxed font-medium text-ink-soft">{t('These remain broad bands, not laboratory measurements. Overall Fitness stays Building your baseline until enough independent evidence exists.')}</p></div>
              <div className="space-y-2">{([
                ['Stamina', evaluation.bands.cardiorespiratory], ['Upper body', evaluation.bands.upper_strength], ['Lower body', evaluation.bands.lower_strength], ['Mobility', evaluation.bands.mobility],
              ] as const).map(([title, band]) => <div key={title} className="flex items-center justify-between gap-3 rounded-2xl bg-white/80 p-3.5"><span className="text-sm font-bold text-ink">{t(title)}</span><span className="rounded-full bg-emerald-500/8 px-3 py-2 font-mono text-[10px] font-bold text-emerald">{t(band === 'building_baseline' ? 'Building your baseline' : band === 'strong' ? 'Strong signal' : band[0].toUpperCase() + band.slice(1))}</span></div>)}</div>
              {evaluation.evidence.length === 0 && <p className="text-xs font-bold text-amber-700">{t('Answer at least two prompts in a section to sharpen that band.')}</p>}
              {saveState === 'saved' ? <div className="space-y-3"><p className="text-sm font-bold text-emerald">✓ {t('Saved to your evidence')}</p><button type="button" onClick={onClose} className="min-h-12 w-full rounded-full bg-emerald px-5 text-sm font-bold text-white">{t('Done')}</button></div> : <button type="button" disabled={evaluation.evidence.length === 0 || saveState === 'saving'} onClick={saveQuestions} className="min-h-12 w-full rounded-full bg-emerald px-5 text-sm font-bold text-white disabled:opacity-40">{t(saveState === 'saving' ? 'Saving…' : 'Save baseline')}</button>}
              {saveState === 'failed' && <p className="text-xs font-bold text-crimson">{t('Your baseline could not be saved yet. Your answers remain on this device.')}</p>}
              <button type="button" onClick={() => { setSaveState('idle'); setDraft((current) => ({ ...current, step: 4 })) }} className="min-h-11 rounded-full border border-ink/12 bg-white px-5 text-sm font-bold text-ink">{t('Back to questions')}</button>
            </div>
          )}

          {route === 'recent_result' && (
            <div className="space-y-4">
              <div><h3 className="font-display text-3xl font-bold text-ink">{t('Add a recent result')}</h3><p className="mt-1 text-xs leading-relaxed font-medium text-ink-soft">{t('APEX keeps a value you enter as unverified until a supported source confirms it.')}</p></div>
              <label className="block text-xs font-bold text-ink">{t('Result type')}<select value={metricIndex} onChange={(event) => { setMetricIndex(Number(event.target.value)); setSaveState('idle') }} className="mt-2 min-h-12 w-full rounded-2xl border border-ink/10 bg-white px-4 text-sm font-bold">{manualMetrics.map((item, index) => <option key={item.metric} value={index}>{t(item.title)}</option>)}</select></label>
              <label className="block text-xs font-bold text-ink">{t('Value')}<span className="mt-2 flex min-h-12 items-center rounded-2xl border border-ink/10 bg-white px-4"><input inputMode="decimal" value={resultValue} onChange={(event) => { setResultValue(event.target.value); setSaveState('idle') }} placeholder={metric.placeholder} className="min-w-0 flex-1 bg-transparent text-base font-bold outline-none" /><span className="font-mono text-[10px] font-bold text-ink-soft">{metric.unitLabel}</span></span></label>
              <label className="block text-xs font-bold text-ink">{t('Where did this result come from?')}<input value={resultSource} onChange={(event) => { setResultSource(event.target.value); setSaveState('idle') }} placeholder={t('For example, DEXA report or laboratory test')} className="mt-2 min-h-12 w-full rounded-2xl border border-ink/10 bg-white px-4 text-sm font-semibold outline-none" /></label>
              <label className="block text-xs font-bold text-ink">{t('Measured on')}<input type="date" max={todayKey()} value={resultDate} onChange={(event) => setResultDate(event.target.value)} className="mt-2 min-h-12 w-full rounded-2xl border border-ink/10 bg-white px-4 text-sm font-bold" /></label>
              {saveState === 'saved' && <p className="text-sm font-bold text-emerald">✓ {t('Result saved')}</p>}
              <button type="button" disabled={!resultIsReady || saveState === 'saving'} onClick={saveRecentResult} className="min-h-12 w-full rounded-full bg-violet px-5 text-sm font-bold text-white disabled:opacity-40">{t(saveState === 'saving' ? 'Saving…' : 'Save result')}</button>
              {saveState === 'failed' && <p className="text-xs font-bold text-crimson">{t('Check the value and source, then try again.')}</p>}
              <button type="button" onClick={() => setRoute('home')} className="min-h-11 rounded-full border border-ink/12 bg-white px-5 text-sm font-bold text-ink">{t('Back')}</button>
            </div>
          )}

          {route === 'health' && (
            <div className="space-y-4">
              <h3 className="font-display text-3xl font-bold text-ink">{t('Apple Health')}</h3>
              <p className="text-sm leading-relaxed font-medium text-ink-soft">{t('Apple Health connects through the APEX iPhone app, where iOS lets you choose each category. Denial or missing data never lowers your baseline.')}</p>
              <p className="rounded-2xl bg-cyan-500/8 p-4 text-xs leading-relaxed font-semibold text-ink-soft">{t('Open Avatar on your iPhone and choose Edit, then Connect what you track. Your manual routes remain available here.')}</p>
              <button type="button" onClick={() => setRoute('home')} className="min-h-11 rounded-full border border-ink/12 bg-white px-5 text-sm font-bold text-ink">{t('Back')}</button>
            </div>
          )}
        </div>
      </motion.section>
    </div>
  )
}

function RouteButton({ title, detail, icon, tint, onClick, t }: { title: string; detail: string; icon: string; tint: string; onClick: () => void; t: (value: string) => string }) {
  return <button type="button" onClick={onClick} className="flex min-h-[74px] w-full items-center gap-3 rounded-[22px] border border-white bg-white/75 p-3.5 text-left shadow-sm"><span className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl text-xl font-bold text-white" style={{ backgroundColor: tint }}>{icon}</span><span className="min-w-0 flex-1"><span className="block text-sm font-bold text-ink">{t(title)}</span><span className="mt-0.5 block text-xs leading-relaxed font-medium text-ink-soft">{t(detail)}</span></span><span className="text-xl text-ink-soft" aria-hidden>›</span></button>
}
