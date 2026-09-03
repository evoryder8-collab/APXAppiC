import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { motion, useReducedMotion } from 'framer-motion'

import {
  baselineCalibrationQuestions,
  buildDxaCalibrationEvidence,
  buildManualCalibrationEvidence,
  calibrationResultMeasuredAt,
  clearBaselineCalibrationDraft,
  emptyBaselineCalibrationAnswers,
  evaluateBaselineCalibration,
  isBaselineCalibrationQuestionAnswered,
  loadBaselineCalibrationDraft,
  normalizedCalibrationEvidence,
  saveBaselineCalibrationDraft,
  type BaselineCalibrationAnswer,
  type BaselineCalibrationDraft,
  type BaselineCalibrationQuestion,
} from '../../lib/baselineCalibration.ts'
import type { FitnessEvidenceMetric } from '../../lib/fitnessEvidence.ts'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import type { Profile } from '../../lib/types.ts'
import { useStore } from '../../store/AppStore.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { EASE } from '../ui.tsx'

type Route = 'home' | 'questions' | 'recent_result' | 'health'
type ResultRoute = 'chooser' | 'dexa' | 'other'
type SaveState = 'idle' | 'saving' | 'saved' | 'failed'

const manualMetrics: Array<{
  metric: FitnessEvidenceMetric
  title: string
  unit: string
  unitLabel: string
  placeholder: string
}> = [
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
    answered_question_ids: [],
  }
}

function parseOptionalNumber(value: string): number | null | undefined {
  if (!value.trim()) return null
  const parsed = Number(value.replace(',', '.'))
  return Number.isFinite(parsed) ? parsed : undefined
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
  const [resultRoute, setResultRoute] = useState<ResultRoute>('chooser')
  const [draft, setDraft] = useState<BaselineCalibrationDraft>(() => initialDraft(profile))
  const [saveState, setSaveState] = useState<SaveState>('idle')
  const [metricIndex, setMetricIndex] = useState(0)
  const [resultValue, setResultValue] = useState('')
  const [dxaBodyFat, setDxaBodyFat] = useState('')
  const [dxaRestingEnergy, setDxaRestingEnergy] = useState('')
  const [resultSource, setResultSource] = useState('')
  const [resultDate, setResultDate] = useState(todayKey())
  const [savedResults, setSavedResults] = useState<string[]>([])

  useEffect(() => { onCloseRef.current = onClose }, [onClose])
  useEffect(() => { saveStateRef.current = saveState }, [saveState])

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

  const questionIndex = Math.max(0, Math.min(baselineCalibrationQuestions.length - 1, draft.step - 1))
  const currentQuestion = baselineCalibrationQuestions[questionIndex]
  const questionIsAnswered = isBaselineCalibrationQuestionAnswered(draft, currentQuestion.id)
  const selectedAnswer = draft.answers[currentQuestion.domain][currentQuestion.answer_index]
  const metric = manualMetrics[metricIndex]

  const goToQuestions = () => {
    setSaveState('idle')
    setDraft((current) => ({ ...current, step: current.step === 0 ? 1 : current.step }))
    setRoute('questions')
  }

  const setAnswer = (question: BaselineCalibrationQuestion, value: BaselineCalibrationAnswer) => {
    setSaveState('idle')
    setDraft((current) => {
      const answers = {
        ...current.answers,
        [question.domain]: [...current.answers[question.domain]],
      }
      answers[question.domain][question.answer_index] = value
      return {
        ...current,
        answers,
        answered_question_ids: [...new Set([...current.answered_question_ids, question.id])],
      }
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

  const saveDxaResult = () => {
    const bodyFat = parseOptionalNumber(dxaBodyFat)
    const restingEnergy = parseOptionalNumber(dxaRestingEnergy)
    const measuredAt = calibrationResultMeasuredAt(resultDate)
    if (bodyFat === undefined || restingEnergy === undefined || measuredAt == null) {
      setSaveState('failed')
      return
    }
    setSaveState('saving')
    try {
      const result = buildDxaCalibrationEvidence({
        user_id: profile.user_id,
        body_fat_percentage: bodyFat,
        resting_metabolic_rate: restingEnergy,
        declared_source: resultSource,
        measured_at: measuredAt,
        imported_at: new Date().toISOString(),
        existing_custom_bmr: profile.custom_bmr ?? null,
        existing_custom_bmr_source: profile.custom_bmr_source ?? null,
      })
      if (result.status === 'rejected') throw new Error(result.reason)
      const activeProfile = store.data.profile
      const activeSettings = store.data.settings
      if (
        !activeProfile
        || activeProfile.user_id !== result.persistence.owner_id
        || (result.persistence.settings_addons_patch != null
          && (!activeSettings || activeSettings.user_id !== result.persistence.owner_id))
      ) {
        throw new Error('dexa_calibration_account_mismatch')
      }
      result.evidence.forEach(store.recordFitnessEvidence)
      if (result.persistence.profile_patch) {
        store.setProfile(result.persistence.profile_patch)
      }
      if (result.persistence.settings_addons_patch && activeSettings) {
        store.setSettings({
          addons: {
            ...activeSettings.addons,
            ...result.persistence.settings_addons_patch,
          },
        })
      }
      setSavedResults([
        ...(bodyFat == null ? [] : [`${t('Body fat')} · ${bodyFat}%`]),
        ...(restingEnergy == null ? [] : [`${t('Resting energy (BMR/RMR)')} · ${restingEnergy} ${t('kcal/day')}`]),
      ])
      setSaveState('saved')
      store.toast(t('DEXA results saved'), 'ok')
    } catch {
      setSaveState('failed')
    }
  }

  const saveOtherResult = () => {
    const value = Number(resultValue.replace(',', '.'))
    const measuredAt = calibrationResultMeasuredAt(resultDate)
    if (!Number.isFinite(value) || measuredAt == null) {
      setSaveState('failed')
      return
    }
    setSaveState('saving')
    try {
      const result = buildManualCalibrationEvidence({
        user_id: profile.user_id,
        metric: metric.metric,
        value,
        unit: metric.unit,
        declared_source: resultSource,
        measured_at: measuredAt,
        imported_at: new Date().toISOString(),
      })
      if (result.status === 'rejected') throw new Error(result.reason)
      store.recordFitnessEvidence(result.evidence)
      setSavedResults([`${t(metric.title)} · ${value} ${t(metric.unitLabel)}`])
      setSaveState('saved')
      store.toast(t('Result saved'), 'ok')
    } catch {
      setSaveState('failed')
    }
  }

  const resetResult = () => {
    setSaveState('idle')
    setSavedResults([])
    setResultValue('')
    setDxaBodyFat('')
    setDxaRestingEnergy('')
    setResultSource('')
    setResultRoute('chooser')
  }

  const resultDateIsValid = calibrationResultMeasuredAt(resultDate) != null
  const dxaReady = resultDateIsValid
    && resultSource.trim().length > 0
    && parseOptionalNumber(dxaBodyFat) !== undefined
    && parseOptionalNumber(dxaRestingEnergy) !== undefined
    && (dxaBodyFat.trim().length > 0 || dxaRestingEnergy.trim().length > 0)
  const otherReady = resultDateIsValid
    && Number.isFinite(Number(resultValue.replace(',', '.')))
    && resultSource.trim().length > 0

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
        className="flex max-h-[min(92dvh,820px)] w-full max-w-xl flex-col overflow-hidden rounded-[32px] border border-white/90 bg-[linear-gradient(145deg,rgba(255,255,255,.99),rgba(236,253,245,.98),rgba(245,243,255,.98))] shadow-2xl"
      >
        <header className="flex items-center justify-between gap-3 border-b border-ink/8 px-5 py-4">
          <div className="min-w-0">
            <p className="font-mono text-[9px] font-bold tracking-[.2em] text-emerald uppercase">APEX AVATAR</p>
            <h2 id="baseline-calibration-title" className="font-display text-xl leading-tight font-bold text-ink">{t('Calibrate my baseline')}</h2>
          </div>
          <button ref={closeRef} type="button" onClick={onClose} disabled={saveState === 'saving'} className="grid min-h-11 min-w-11 place-items-center rounded-full bg-white/90 text-xl font-bold text-ink shadow-sm" aria-label={t('Close')}>×</button>
        </header>

        <div className="overflow-y-auto px-4 py-5 sm:px-6">
          {route === 'home' && (
            <div className="space-y-4">
              <div className="rounded-[26px] bg-[radial-gradient(circle_at_top_right,rgba(167,139,250,.25),transparent_48%),linear-gradient(135deg,rgba(16,185,129,.12),rgba(255,255,255,.7))] p-5">
                <p className="font-mono text-[10px] font-bold tracking-[.18em] text-violet uppercase">{t('A clearer starting point')}</p>
                <h3 className="mt-2 font-display text-3xl font-bold text-ink">{t('Sharpen your map')}</h3>
                <p className="mt-2 text-sm leading-relaxed font-medium text-ink-soft">{t('Add better evidence without turning fitness into a test you can fail.')}</p>
              </div>
              <div className="flex gap-2.5 rounded-2xl bg-emerald-500/8 p-3.5 text-xs leading-relaxed font-semibold text-ink-soft"><span aria-hidden>🛡️</span><p>{t(profile.profile_kind === 'bespoke' ? 'Your bespoke plan stays protected. Calibration only refines your evidence.' : 'Calibration refines your evidence. It never rewrites your training or nutrition plan.')}</p></div>
              <RouteButton title="Sharpen with questions" detail="12 clear questions · about 3 minutes" icon="⌁" tint={ACCENTS.emerald.bright} onClick={goToQuestions} t={t} />
              <RouteButton title="Connect what you track" detail="Import the Apple Health categories you choose." icon="♥" tint={ACCENTS.ice.bright} onClick={() => setRoute('health')} t={t} />
              <RouteButton title="Add a recent result" detail="Lab & DEXA results · about 1 minute" icon="＋" tint={ACCENTS.violet.bright} onClick={() => { resetResult(); setRoute('recent_result') }} t={t} />
              {draft.answered_question_ids.length > 0 && <p className="text-xs font-bold text-emerald">✓ {t('Your question progress is saved privately on this device.')}</p>}
            </div>
          )}

          {route === 'questions' && draft.step <= baselineCalibrationQuestions.length && (
            <div className="space-y-5">
              <div>
                <div className="flex items-center justify-between gap-3 font-mono text-[10px] font-bold tracking-[.12em] text-ink-soft uppercase"><span>{t(currentQuestion.section_title)}</span><span>{t('Question')} {draft.step} / {baselineCalibrationQuestions.length}</span></div>
                <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-ink/8" aria-label={t('Calibration progress')} aria-valuenow={draft.step} aria-valuemin={1} aria-valuemax={baselineCalibrationQuestions.length} role="progressbar"><div className="h-full rounded-full bg-gradient-to-r from-emerald to-violet" style={{ width: `${draft.step / baselineCalibrationQuestions.length * 100}%` }} /></div>
              </div>
              <div>
                <h3 className="font-display text-[2rem] leading-tight font-bold text-ink">{t(currentQuestion.prompt)}</h3>
                <p className="mt-2 text-sm leading-relaxed font-medium text-ink-soft">{t('Choose what has felt true recently. Never test through pain.')}</p>
              </div>
              <fieldset className="space-y-2.5">
                <legend className="sr-only">{t('Choose one answer')}</legend>
                {currentQuestion.options.map((option) => (
                  <AnswerButton key={option.value} selected={questionIsAnswered && selectedAnswer === option.value} label={t(option.label)} onClick={() => setAnswer(currentQuestion, option.value)} />
                ))}
                <AnswerButton selected={questionIsAnswered && selectedAnswer === 'not_tested'} label={t("I'm not sure or haven't done this recently")} muted onClick={() => setAnswer(currentQuestion, 'not_tested')} />
              </fieldset>
              <div className="sticky bottom-0 -mx-1 flex gap-3 bg-gradient-to-t from-white via-white/95 to-transparent px-1 pt-5 pb-1">
                <button type="button" onClick={() => draft.step === 1 ? setRoute('home') : setDraft((current) => ({ ...current, step: current.step - 1 }))} className="min-h-12 rounded-full border border-ink/12 bg-white px-5 text-sm font-bold text-ink">{t('Back')}</button>
                <button type="button" disabled={!questionIsAnswered} onClick={() => setDraft((current) => ({ ...current, step: Math.min(13, current.step + 1) }))} className="min-h-12 flex-1 rounded-full bg-emerald px-5 text-sm font-bold text-white shadow-lg shadow-emerald-500/20 disabled:cursor-not-allowed disabled:opacity-35">{t(draft.step === baselineCalibrationQuestions.length ? 'Review my baseline' : 'Continue')}</button>
              </div>
            </div>
          )}

          {route === 'questions' && draft.step > baselineCalibrationQuestions.length && evaluation.status === 'accepted' && (
            <div className="space-y-4">
              <div><p className="font-mono text-[10px] font-bold tracking-[.16em] text-emerald uppercase">{t('Calibration complete')}</p><h3 className="mt-2 font-display text-3xl font-bold text-ink">{t('Your sharper starting map')}</h3><p className="mt-2 text-xs leading-relaxed font-medium text-ink-soft">{t('These remain broad bands, not laboratory measurements. Overall Fitness stays Building your baseline until enough independent evidence exists.')}</p></div>
              <div className="grid grid-cols-2 gap-2">{([
                ['Stamina', evaluation.bands.cardiorespiratory], ['Upper body', evaluation.bands.upper_strength], ['Lower body', evaluation.bands.lower_strength], ['Mobility', evaluation.bands.mobility],
              ] as const).map(([title, band]) => <div key={title} className="rounded-2xl bg-white/85 p-4 shadow-sm"><span className="block text-xs font-bold text-ink-soft">{t(title)}</span><span className="mt-1 block text-sm font-bold text-emerald">{t(band === 'building_baseline' ? 'Building your baseline' : band === 'strong' ? 'Strong signal' : band[0].toUpperCase() + band.slice(1))}</span></div>)}</div>
              {evaluation.evidence.length === 0 && <p className="text-xs font-bold text-amber-700">{t('Not enough recent answers to change a band yet. Your existing baseline stays safe.')}</p>}
              {saveState === 'saved' ? <div className="rounded-[24px] bg-emerald-500/10 p-5" role="status"><p className="text-base font-bold text-emerald">✓ {t('Saved to your evidence')}</p><button type="button" onClick={onClose} className="mt-4 min-h-12 w-full rounded-full bg-emerald px-5 text-sm font-bold text-white">{t('Done')}</button></div> : <button type="button" disabled={evaluation.evidence.length === 0 || saveState === 'saving'} onClick={saveQuestions} className="min-h-12 w-full rounded-full bg-emerald px-5 text-sm font-bold text-white disabled:opacity-40">{t(saveState === 'saving' ? 'Saving…' : 'Save baseline')}</button>}
              {saveState === 'failed' && <p className="text-xs font-bold text-crimson">{t('Your baseline could not be saved yet. Your answers remain on this device.')}</p>}
              <button type="button" onClick={() => { setSaveState('idle'); setDraft((current) => ({ ...current, step: 12 })) }} className="min-h-11 rounded-full border border-ink/12 bg-white px-5 text-sm font-bold text-ink">{t('Back to questions')}</button>
            </div>
          )}

          {route === 'recent_result' && resultRoute === 'chooser' && (
            <div className="space-y-4">
              <div><p className="font-mono text-[10px] font-bold tracking-[.16em] text-violet uppercase">{t('Evidence, not guesswork')}</p><h3 className="mt-2 font-display text-3xl font-bold text-ink">{t('What are you adding?')}</h3><p className="mt-2 text-sm leading-relaxed font-medium text-ink-soft">{t('Choose the report you have. APEX will only ask for values that belong to it.')}</p></div>
              <RouteButton title="DEXA body composition report" detail="Save body fat and any resting-energy estimate printed on the same report." icon="◫" tint={ACCENTS.violet.bright} onClick={() => setResultRoute('dexa')} t={t} />
              <RouteButton title="Other health or fitness result" detail="Add VO₂ max, resting heart rate, waist or a metabolic test." icon="＋" tint={ACCENTS.ice.bright} onClick={() => setResultRoute('other')} t={t} />
            </div>
          )}

          {route === 'recent_result' && resultRoute === 'dexa' && (
            <ResultShell eyebrow="DEXA REPORT" title="Add your DEXA results" detail="Enter either value or both. Leave a field blank when it is not printed on your report." t={t}>
              {saveState === 'saved' ? <SavedResultPanel results={savedResults} onDone={onClose} onAnother={resetResult} t={t} /> : <>
                <div className="rounded-2xl bg-violet-500/8 p-4 text-xs leading-relaxed font-semibold text-ink-soft">{t('DEXA measures body composition. Some reports also print an estimated BMR or RMR; APEX stores that number as report-supplied, not as a direct metabolic measurement.')}</div>
                <ResultField label={t('Body fat (optional)')} value={dxaBodyFat} onChange={(value) => { setDxaBodyFat(value); setSaveState('idle') }} placeholder="18.4" unit="%" identifier="calibration.result.dexa-body-fat" />
                <ResultField label={t('Resting metabolism printed on the report (optional)')} value={dxaRestingEnergy} onChange={(value) => { setDxaRestingEnergy(value); setSaveState('idle') }} placeholder="1683" unit={t('kcal/day')} identifier="calibration.result.dexa-resting-energy" />
                <SourceAndDate source={resultSource} setSource={(value) => { setResultSource(value); setSaveState('idle') }} date={resultDate} setDate={setResultDate} t={t} />
                <button type="button" disabled={!dxaReady || saveState === 'saving'} onClick={saveDxaResult} className="min-h-12 w-full rounded-full bg-violet px-5 text-sm font-bold text-white shadow-lg shadow-violet-500/20 disabled:opacity-35">{t(saveState === 'saving' ? 'Saving…' : 'Save DEXA results')}</button>
                {saveState === 'failed' && <p className="text-xs font-bold text-crimson" role="alert">{t('Enter at least one valid value and name the report or clinic.')}</p>}
              </>}
            </ResultShell>
          )}

          {route === 'recent_result' && resultRoute === 'other' && (
            <ResultShell eyebrow="RECENT RESULT" title="Add another result" detail="Manual entries stay low-confidence until a supported source confirms them." t={t}>
              {saveState === 'saved' ? <SavedResultPanel results={savedResults} onDone={onClose} onAnother={resetResult} t={t} /> : <>
                <label className="block text-xs font-bold text-ink">{t('Result type')}<select value={metricIndex} onChange={(event) => { setMetricIndex(Number(event.target.value)); setSaveState('idle') }} className="mt-2 min-h-12 w-full rounded-2xl border border-ink/10 bg-white px-4 text-sm font-bold">{manualMetrics.map((item, index) => <option key={item.metric} value={index}>{t(item.title)}</option>)}</select></label>
                <ResultField label={t('Value')} value={resultValue} onChange={(value) => { setResultValue(value); setSaveState('idle') }} placeholder={metric.placeholder} unit={t(metric.unitLabel)} identifier="calibration.result.value" />
                <SourceAndDate source={resultSource} setSource={(value) => { setResultSource(value); setSaveState('idle') }} date={resultDate} setDate={setResultDate} t={t} />
                <button type="button" disabled={!otherReady || saveState === 'saving'} onClick={saveOtherResult} className="min-h-12 w-full rounded-full bg-violet px-5 text-sm font-bold text-white disabled:opacity-35">{t(saveState === 'saving' ? 'Saving…' : 'Save result')}</button>
                {saveState === 'failed' && <p className="text-xs font-bold text-crimson" role="alert">{t('Check the value and source, then try again.')}</p>}
              </>}
            </ResultShell>
          )}

          {route === 'health' && (
            <div className="space-y-4">
              <h3 className="font-display text-3xl font-bold text-ink">{t('Apple Health')}</h3>
              <p className="text-sm leading-relaxed font-medium text-ink-soft">{t('Apple Health connects through the APEX iPhone app, where iOS lets you choose each category. Denial or missing data never lowers your baseline.')}</p>
              <p className="rounded-2xl bg-cyan-500/8 p-4 text-xs leading-relaxed font-semibold text-ink-soft">{t('Open Avatar on your iPhone and choose Edit, then Connect what you track. Your manual routes remain available here.')}</p>
            </div>
          )}

          {route !== 'home' && route !== 'questions' && saveState !== 'saved' && <button type="button" onClick={() => resultRoute === 'chooser' ? setRoute('home') : setResultRoute('chooser')} className="mt-5 min-h-11 rounded-full border border-ink/12 bg-white px-5 text-sm font-bold text-ink">{t('Back')}</button>}
        </div>
      </motion.section>
    </div>
  )
}

function AnswerButton({ selected, label, muted = false, onClick }: { selected: boolean; label: string; muted?: boolean; onClick: () => void }) {
  return <button type="button" role="radio" aria-checked={selected} onClick={onClick} className={`flex min-h-14 w-full items-center gap-3 rounded-[20px] border px-4 py-3 text-left transition ${selected ? 'border-emerald bg-emerald text-white shadow-lg shadow-emerald-500/18' : muted ? 'border-dashed border-ink/14 bg-white/55 text-ink-soft' : 'border-white bg-white/85 text-ink shadow-sm hover:border-emerald/30'}`}><span className={`grid h-6 w-6 shrink-0 place-items-center rounded-full border text-xs font-black ${selected ? 'border-white/70 bg-white/18' : 'border-ink/15'}`}>{selected ? '✓' : ''}</span><span className="text-sm leading-snug font-bold">{label}</span></button>
}

function ResultField({ label, value, onChange, placeholder, unit, identifier }: { label: string; value: string; onChange: (value: string) => void; placeholder: string; unit: string; identifier: string }) {
  return <label className="block text-xs font-bold text-ink">{label}<span className="mt-2 flex min-h-[52px] items-center rounded-2xl border border-ink/10 bg-white px-4 shadow-sm"><input data-testid={identifier} inputMode="decimal" value={value} onChange={(event) => onChange(event.target.value)} placeholder={placeholder} className="min-w-0 flex-1 bg-transparent text-base font-bold outline-none" /><span className="ml-2 shrink-0 font-mono text-[10px] font-bold text-ink-soft">{unit}</span></span></label>
}

function SourceAndDate({ source, setSource, date, setDate, t }: { source: string; setSource: (value: string) => void; date: string; setDate: (value: string) => void; t: (value: string) => string }) {
  return <div className="grid gap-3 sm:grid-cols-2"><label className="block text-xs font-bold text-ink">{t('Report or clinic')}<input value={source} onChange={(event) => setSource(event.target.value)} placeholder={t('For example, DEXA report or laboratory test')} className="mt-2 min-h-12 w-full rounded-2xl border border-ink/10 bg-white px-4 text-sm font-semibold outline-none shadow-sm" /></label><label className="block text-xs font-bold text-ink">{t('Measured on')}<input type="date" max={todayKey()} value={date} onChange={(event) => setDate(event.target.value)} className="mt-2 min-h-12 w-full rounded-2xl border border-ink/10 bg-white px-4 text-sm font-bold shadow-sm" /></label></div>
}

function ResultShell({ eyebrow, title, detail, t, children }: { eyebrow: string; title: string; detail: string; t: (value: string) => string; children: ReactNode }) {
  return <div className="space-y-4"><div><p className="font-mono text-[10px] font-bold tracking-[.16em] text-violet uppercase">{t(eyebrow)}</p><h3 className="mt-2 font-display text-3xl font-bold text-ink">{t(title)}</h3><p className="mt-2 text-sm leading-relaxed font-medium text-ink-soft">{t(detail)}</p></div>{children}</div>
}

function SavedResultPanel({ results, onDone, onAnother, t }: { results: string[]; onDone: () => void; onAnother: () => void; t: (value: string) => string }) {
  return <div className="rounded-[26px] border border-emerald/15 bg-emerald-500/10 p-5" role="status" aria-live="polite"><div className="grid h-12 w-12 place-items-center rounded-full bg-emerald text-2xl font-black text-white">✓</div><h4 className="mt-4 font-display text-2xl font-bold text-ink">{t('Saved to your evidence')}</h4><div className="mt-3 space-y-2">{results.map((result) => <p key={result} className="rounded-xl bg-white/75 px-3 py-2 text-sm font-bold text-ink">{result}</p>)}</div><p className="mt-3 text-xs leading-relaxed font-medium text-ink-soft">{t('You can close this screen. These values are now part of your private evidence history.')}</p><div className="mt-4 flex gap-2"><button type="button" onClick={onAnother} className="min-h-11 flex-1 rounded-full border border-ink/12 bg-white px-4 text-sm font-bold text-ink">{t('Add another')}</button><button type="button" onClick={onDone} className="min-h-11 flex-1 rounded-full bg-emerald px-4 text-sm font-bold text-white">{t('Done')}</button></div></div>
}

function RouteButton({ title, detail, icon, tint, onClick, t }: { title: string; detail: string; icon: string; tint: string; onClick: () => void; t: (value: string) => string }) {
  return <button type="button" onClick={onClick} className="flex min-h-[78px] w-full items-center gap-3 rounded-[22px] border border-white bg-white/80 p-3.5 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"><span className="grid h-12 w-12 shrink-0 place-items-center rounded-2xl text-xl font-bold text-white" style={{ backgroundColor: tint }}>{icon}</span><span className="min-w-0 flex-1"><span className="block text-sm font-bold text-ink">{t(title)}</span><span className="mt-0.5 block text-xs leading-relaxed font-medium text-ink-soft">{t(detail)}</span></span><span className="text-xl text-ink-soft" aria-hidden>›</span></button>
}
