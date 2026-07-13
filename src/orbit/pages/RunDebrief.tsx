import { lazy, Suspense, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { GlassCard, GhostButton, GradientButton } from '../../components/ui.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { dailyLogId } from '../../lib/ids.ts'
import type { DailyLog } from '../../lib/types.ts'
import { useStore } from '../../store/AppStore.tsx'
import { useFoodStore } from '../../store/FoodStore.tsx'
import { calculatePortion, isFoodNutritionComplete, type FoodRecord } from '../../lib/food.ts'
import { adaptAfterRun } from '../domain/campaign.ts'
import { analyzeRun, buildRouteDna, missionLabel } from '../domain/analysis.ts'
import { avatarContributionForRun, nutritionAdjustmentForRun, trainingAdjustmentForRun } from '../domain/integrations.ts'
import { orbitUuid } from '../domain/ids.ts'
import { posterMetadata, posterSvg } from '../domain/poster.ts'
import type { OrbitRun, PosterStyle, RunCheckIn } from '../domain/types.ts'
import { OrbitFrame, OrbitPill } from '../components/OrbitFrame.tsx'
import { useOrbitStore } from '../store/OrbitStore.tsx'
import { formatDistance, formatDuration, formatPace, titleCase } from '../ui/format.ts'
import { useOrbitText } from '../ui/i18n.ts'

const OrbitMap = lazy(() => import('../components/OrbitMap.tsx').then((module) => ({ default: module.OrbitMap })))

function downloadText(filename: string, body: string, type: string): void {
  const url = URL.createObjectURL(new Blob([body], { type }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = filename
  anchor.click()
  URL.revokeObjectURL(url)
}

async function downloadPng(filename: string, svg: string): Promise<void> {
  const svgUrl = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }))
  try {
    const image = new Image()
    await new Promise<void>((resolve, reject) => {
      image.onload = () => resolve()
      image.onerror = () => reject(new Error('Route poster could not be rendered.'))
      image.src = svgUrl
    })
    const canvas = document.createElement('canvas')
    canvas.width = 1080
    canvas.height = 1350
    canvas.getContext('2d')?.drawImage(image, 0, 0)
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png', 0.94))
    if (!blob) throw new Error('Route poster could not be rendered.')
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = filename
    anchor.click()
    URL.revokeObjectURL(url)
  } finally { URL.revokeObjectURL(svgUrl) }
}

function Metric({ label, value, detail }: { label: string; value: string; detail?: string }) {
  const t = useOrbitText()
  return <div className="rounded-2xl border border-white/80 bg-white/55 p-3"><p className="text-[10px] font-bold tracking-wide text-ink-faint uppercase">{t(label)}</p><p className="mt-1 font-mono text-lg font-bold text-ink">{t(value)}</p>{detail && <p className="mt-1 text-[10px] text-ink-soft">{t(detail)}</p>}</div>
}

function ElevationProfile({ run }: { run: OrbitRun }) {
  const t = useOrbitText()
  const values = run.samples.map((sample) => sample.elevation_m).filter((value): value is number => value != null && Number.isFinite(value))
  if (values.length < 2) return null
  const low = Math.min(...values)
  const high = Math.max(...values)
  const range = Math.max(1, high - low)
  const points = values.map((value, index) => `${(index / (values.length - 1) * 100).toFixed(2)},${(38 - (value - low) / range * 34).toFixed(2)}`).join(' ')
  return <div className="mt-4 rounded-2xl border border-white/10 bg-white/5 p-3"><div className="flex justify-between text-[9px] font-bold text-slate-500"><span>{t('ELEVATION PROFILE')}</span><span>{Math.round(low)} {t('TO')} {Math.round(high)} {t('M')}</span></div><svg viewBox="0 0 100 40" role="img" aria-label={t('Recorded elevation profile')} className="mt-2 h-20 w-full overflow-visible"><defs><linearGradient id="orbit-elevation-fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#7dd3fc" stopOpacity=".34" /><stop offset="1" stopColor="#7dd3fc" stopOpacity="0" /></linearGradient></defs><polygon points={`0,40 ${points} 100,40`} fill="url(#orbit-elevation-fill)" /><polyline points={points} fill="none" stroke="#7dd3fc" strokeWidth="1.4" vectorEffect="non-scaling-stroke" /></svg></div>
}

export function RunDebrief() {
  const { runId } = useParams()
  const navigate = useNavigate()
  const t = useOrbitText()
  const app = useStore()
  const foodStore = useFoodStore()
  const orbit = useOrbitStore()
  const run = orbit.state.runs.find((item) => item.id === runId)
  const [checkIn, setCheckIn] = useState<RunCheckIn>(run?.check_in ?? { perceived_effort: null, legs: null, discomfort: null, note: '' })
  const [posterStyle, setPosterStyle] = useState<PosterStyle>('constellation')
  const [privacyTrim, setPrivacyTrim] = useState(200)
  const [includeHr, setIncludeHr] = useState(false)
  const [posterNote, setPosterNote] = useState('')
  const checkInHydrated = useRef(Boolean(run))

  useEffect(() => {
    if (!run || checkInHydrated.current) return
    checkInHydrated.current = true
    setCheckIn(run.check_in)
  }, [run])

  const analysis = useMemo(() => run ? analyzeRun({ ...run, check_in: checkIn }) : null, [checkIn, run])
  const route = run ? orbit.state.routes.find((item) => item.id === run.route_id) ?? null : null
  const dna = useMemo(() => route ? buildRouteDna(route, orbit.state.runs) : null, [orbit.state.runs, route])
  const nutrition = run ? nutritionAdjustmentForRun(run, app.data.profile?.weight_kg ?? 70) : null
  const foodMemory = useMemo(() => {
    if (!nutrition || nutrition.carbs_g <= 0) return null
    const preference = new Map(foodStore.preferences.map((item) => [item.food_id, item]))
    const candidates = foodStore.foods.filter((food) => isFoodNutritionComplete(food) && (food.carbs_100 ?? 0) >= 20 && !preference.get(food.id)?.hidden)
    candidates.sort((a, b) => {
      const pa = preference.get(a.id)
      const pb = preference.get(b.id)
      return Number(pb?.favourite ?? false) - Number(pa?.favourite ?? false) || (pb?.usage_count ?? 0) - (pa?.usage_count ?? 0)
    })
    const food: FoodRecord | undefined = candidates[0]
    if (!food || !food.carbs_100) return null
    const amount = Math.max(5, Math.round((nutrition.carbs_g / food.carbs_100 * 100) / 5) * 5)
    const unit = food.nutrition_basis === 'per_100ml' ? 'ml' as const : 'g' as const
    const macros = calculatePortion(food, amount, unit)
    return macros ? { food, amount, unit, macros } : null
  }, [foodStore.foods, foodStore.preferences, nutrition?.carbs_g])

  if (!run || !analysis || !nutrition) return <OrbitFrame title="Performance Debrief" subtitle="This private run is not available on this profile." backTo="/orbit"><GlassCard className="p-6 text-center"><p className="font-bold text-ink">{t('Run not found.')}</p><GradientButton accent={ACCENTS.ice} onClick={() => navigate('/orbit')} className="mt-4">{t('Return to Orbit')}</GradientButton></GlassCard></OrbitFrame>
  const training = trainingAdjustmentForRun({ ...run, check_in: checkIn }, app.data.workout_sessions, app.data.program_days)
  const avatar = avatarContributionForRun({ ...run, check_in: checkIn })
  const previousRuns = orbit.state.runs.filter((item) => item.id !== run.id && item.started_at < run.started_at)
  const comparable = previousRuns.filter((item) => item.metrics.distance_m > run.metrics.distance_m * 0.9 && item.metrics.distance_m < run.metrics.distance_m * 1.1 && item.metrics.avg_pace_sec_km != null)
  const routeAttempts = previousRuns.filter((item) => run.route_id != null && item.route_id === run.route_id && item.metrics.avg_pace_sec_km != null)
  const isLongestRunRecord = run.metrics.distance_m >= 1000 && previousRuns.every((item) => item.metrics.distance_m < run.metrics.distance_m)
  const isComparablePaceRecord = run.metrics.avg_pace_sec_km != null && comparable.length > 0 && comparable.every((item) => item.metrics.avg_pace_sec_km! > run.metrics.avg_pace_sec_km!)
  const isRouteRecord = run.metrics.avg_pace_sec_km != null && routeAttempts.length > 0 && routeAttempts.every((item) => item.metrics.avg_pace_sec_km! > run.metrics.avg_pace_sec_km!)

  const saveCheckIn = async (): Promise<void> => {
    const updated: OrbitRun = { ...run, check_in: checkIn, updated_at: new Date().toISOString(), sync_state: 'local' }
    await orbit.saveRun(updated)
    const campaign = orbit.state.campaigns.find((item) => item.id === orbit.state.sessions.find((session) => session.id === run.campaign_session_id)?.campaign_id)
    if (campaign) {
      const adapted = adaptAfterRun(campaign, orbit.state.sessions.filter((session) => session.campaign_id === campaign.id), updated)
      await orbit.saveCampaign(adapted.campaign, adapted.sessions)
    }
    app.toast(t('Run reflection saved and the next decision reconsidered.'), 'ok')
  }

  const applyNutrition = (): void => {
    const profile = app.data.profile
    if (!profile || nutrition.kcal === 0 || run.nutrition_adjustment_applied_at) return
    const exact = foodMemory?.macros ?? nutrition
    const existing = app.data.daily_logs.find((log) => log.date === run.local_date)
    const next: DailyLog = {
      id: existing?.id ?? dailyLogId(run.local_date, profile.user_id), user_id: profile.user_id, date: run.local_date,
      kcal: (existing?.kcal ?? 0) + exact.kcal, protein_g: (existing?.protein_g ?? 0) + exact.protein_g,
      fat_g: (existing?.fat_g ?? 0) + exact.fat_g, carbs_g: (existing?.carbs_g ?? 0) + exact.carbs_g,
      water_l: existing?.water_l ?? 0, estimated_tdee: existing?.estimated_tdee ?? null, computed_pal: existing?.computed_pal ?? null,
      activity_mode: existing?.activity_mode ?? 'precise', weight_kg: existing?.weight_kg ?? profile.weight_kg,
      nutrition_source: 'manual', manual_kcal: (existing?.manual_kcal ?? existing?.kcal ?? 0) + exact.kcal,
      manual_protein_g: (existing?.manual_protein_g ?? existing?.protein_g ?? 0) + exact.protein_g,
      manual_fat_g: (existing?.manual_fat_g ?? existing?.fat_g ?? 0) + exact.fat_g,
      manual_carbs_g: (existing?.manual_carbs_g ?? existing?.carbs_g ?? 0) + exact.carbs_g,
    }
    app.upsert('daily_logs', next)
    void orbit.saveRun({ ...run, nutrition_adjustment_applied_at: new Date().toISOString(), updated_at: new Date().toISOString(), sync_state: 'local' })
    app.toast(t('The reviewed nutrition adjustment was added to that day.'), 'ok')
  }

  const savePoster = async (kind: 'svg' | 'png'): Promise<void> => {
    const profileName = app.data.profile?.display_name ?? 'APEX athlete'
    const metadata = posterMetadata(run, posterStyle, profileName, privacyTrim, includeHr)
    if (metadata.visible_points.length < 2) return app.toast(t('Privacy trim leaves too little route to create a poster.'))
    const svg = posterSvg(metadata, posterNote)
    const created = new Date().toISOString()
    await orbit.savePoster({ id: orbitUuid(run.user_id, `poster:${run.id}:${posterStyle}:${created}`), user_id: run.user_id, run_id: run.id, style: posterStyle, privacy_trim_m: privacyTrim, include_heart_rate: includeHr, note: posterNote, created_at: created, sync_state: 'local' })
    try {
      if (kind === 'svg') downloadText(`apex-orbit-${run.local_date}.svg`, svg, 'image/svg+xml')
      else await downloadPng(`apex-orbit-${run.local_date}.png`, svg)
    } catch (error) {
      app.toast(t(error instanceof Error ? error.message : 'Route poster failed.'))
    }
  }

  return (
    <OrbitFrame title="Performance Debrief" subtitle={`${t(missionLabel(run.mission))} · ${run.local_date}`} backTo="/orbit">
      <div className="space-y-4">
        <div className="relative overflow-hidden rounded-[30px] border border-sky-100/20 bg-[#050b16] p-4 text-white shadow-2xl sm:p-5">
          <div className="orbit-stars pointer-events-none absolute inset-0 opacity-45" aria-hidden />
          <div className="relative">
            {run.samples.length > 1 ? <Suspense fallback={<div className="h-72 animate-pulse rounded-[22px] bg-slate-900" />}><OrbitMap planned={route?.points ?? []} completed={run.samples} /></Suspense> : <div className="grid h-44 place-items-center rounded-[22px] bg-white/5 text-sm text-slate-400">{t('No usable GPS track was recorded.')}</div>}
            <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
              <div><p className="text-[10px] text-slate-500">{t('DISTANCE')}</p><p className="font-mono text-xl font-bold">{formatDistance(run.metrics.distance_m)}</p></div>
              <div><p className="text-[10px] text-slate-500">{t('ELAPSED')}</p><p className="font-mono text-xl font-bold">{formatDuration(run.metrics.elapsed_s)}</p></div>
              <div><p className="text-[10px] text-slate-500">{t('MOVING')}</p><p className="font-mono text-xl font-bold">{formatDuration(run.metrics.moving_s)}</p></div>
              <div><p className="text-[10px] text-slate-500">{t('AVG PACE')}</p><p className="font-mono text-xl font-bold">{formatPace(run.metrics.avg_pace_sec_km)}</p></div>
              <div><p className="text-[10px] text-slate-500">{t('BEST PACE')}</p><p className="font-mono text-xl font-bold">{formatPace(run.metrics.best_pace_sec_km)}</p></div>
              <div><p className="text-[10px] text-slate-500">{t('ELEVATION')}</p><p className="font-mono text-xl font-bold">{run.metrics.elevation_gain_m == null ? t('Not recorded') : `${run.metrics.elevation_gain_m} m`}</p></div>
              {run.metrics.calories_kcal != null && <div><p className="text-[10px] text-slate-500">{t('EST. ENERGY')}</p><p className="font-mono text-xl font-bold">{run.metrics.calories_kcal} kcal</p></div>}
              {run.metrics.heart_rate_avg != null && <div><p className="text-[10px] text-slate-500">{t('HEART RATE')}</p><p className="font-mono text-xl font-bold">{run.metrics.heart_rate_avg} bpm</p></div>}
              {run.metrics.cadence_avg != null && <div><p className="text-[10px] text-slate-500">{t('CADENCE')}</p><p className="font-mono text-xl font-bold">{run.metrics.cadence_avg} spm</p></div>}
            </div>
            <ElevationProfile run={run} />
            {(isLongestRunRecord || isComparablePaceRecord || isRouteRecord) && <div className="mt-4 flex flex-wrap gap-2">{isLongestRunRecord && <OrbitPill tone="amber">{t('PRIVATE DISTANCE RECORD')}</OrbitPill>}{isComparablePaceRecord && <OrbitPill tone="amber">{t('PRIVATE PACE RECORD')}</OrbitPill>}{isRouteRecord && <OrbitPill tone="amber">{t('ROUTE RECORD')}</OrbitPill>}</div>}
          </div>
        </div>

        <GlassCard accent={analysis.mission.state === 'harder_than_planned' ? ACCENTS.amber : ACCENTS.ice} className="p-5">
          <p className="text-[10px] font-bold tracking-widest text-ink-faint uppercase">{t('Mission execution')}</p>
          <h2 className="mt-2 font-display text-xl font-bold text-ink">{t(analysis.mission.headline)}</h2>
          {analysis.mission.details.map((detail) => <p key={detail} className="mt-2 text-sm leading-relaxed text-ink-soft">{t(detail)}</p>)}
          {analysis.facts.length > 0 && <ul className="mt-3 space-y-1 text-sm text-ink-soft">{analysis.facts.map((fact) => <li key={fact}>• {t(fact)}</li>)}</ul>}
        </GlassCard>

        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {analysis.pace_stability_pct != null && <Metric label={t('Pace stability')} value={`${analysis.pace_stability_pct.toFixed(1)}% CV`} detail="Lower variation means steadier pacing." />}
          <Metric label="Split pattern" value={titleCase(analysis.split_classification)} />
          {analysis.cardiac_drift_pct != null && <Metric label={t('Cardiac drift')} value={`${analysis.cardiac_drift_pct.toFixed(1)}%`} detail="Shown only with enough heart-rate data." />}
          {analysis.training_load != null && <Metric label={t('Training load')} value={`${analysis.training_load} AU`} detail="Minutes × reported effort." />}
          {analysis.recovery_cost != null && <Metric label="Recovery cost" value={titleCase(analysis.recovery_cost)} />}
          <Metric label="GPS confidence" value={titleCase(run.metrics.gps_confidence)} detail={`${run.metrics.rejected_samples} impossible or low-quality samples rejected.`} />
        </div>

        {run.metrics.splits.length > 0 && <GlassCard className="p-5"><h3 className="font-display text-lg font-bold text-ink">{t('Kilometre splits')}</h3><div className="mt-3 divide-y divide-slate-200/60">{run.metrics.splits.map((split) => <div key={split.index} className="grid grid-cols-4 items-center py-2 text-sm"><span className="font-mono font-bold text-sky-700">{split.index}</span><span className="font-mono font-bold text-ink">{formatPace(split.pace_sec_km)}</span><span className="text-xs text-ink-soft">{split.elevation_delta_m == null ? t('No elevation') : `${split.elevation_delta_m >= 0 ? '+' : ''}${split.elevation_delta_m} m`}</span><span className="text-right text-xs text-ink-soft">{split.heart_rate_avg == null ? t('No HR') : `${split.heart_rate_avg} bpm`}</span></div>)}</div></GlassCard>}

        <GlassCard accent={ACCENTS.violet} className="p-5">
          <h3 className="font-display text-lg font-bold text-ink">{t('How did it feel?')}</h3>
          <p className="mt-3 text-xs font-bold text-ink-faint">{t('Perceived effort')}</p>
          <div className="mt-2 flex gap-1 overflow-x-auto pb-1">{Array.from({ length: 10 }, (_, index) => index + 1).map((value) => <button key={value} onClick={() => setCheckIn((current) => ({ ...current, perceived_effort: value }))} className={`h-10 w-10 shrink-0 rounded-xl text-sm font-bold ${checkIn.perceived_effort === value ? 'bg-violet-600 text-white' : 'bg-white/70 text-ink'}`}>{value}</button>)}</div>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            <label className="text-xs font-bold text-ink-faint">{t('Legs')}<select value={checkIn.legs ?? ''} onChange={(event) => setCheckIn((current) => ({ ...current, legs: (event.target.value || null) as RunCheckIn['legs'] }))} className="mt-1 min-h-12 w-full rounded-2xl border border-white/80 bg-white/70 px-3 text-sm text-ink"><option value="">{t('Choose')}</option><option value="fresh">{t('Fresh')}</option><option value="normal">{t('Normal')}</option><option value="heavy">{t('Heavy')}</option><option value="very_heavy">{t('Very heavy')}</option></select></label>
            <label className="text-xs font-bold text-ink-faint">{t('Discomfort')}<select value={checkIn.discomfort ?? ''} onChange={(event) => setCheckIn((current) => ({ ...current, discomfort: (event.target.value || null) as RunCheckIn['discomfort'] }))} className="mt-1 min-h-12 w-full rounded-2xl border border-white/80 bg-white/70 px-3 text-sm text-ink"><option value="">{t('Choose')}</option><option value="none">{t('None')}</option><option value="noticeable">{t('Noticeable')}</option><option value="changed_movement">{t('Changed movement')}</option></select></label>
          </div>
          <textarea value={checkIn.note} onChange={(event) => setCheckIn((current) => ({ ...current, note: event.target.value }))} placeholder={t('Optional private note, including fueling tolerance')} className="mt-3 min-h-24 w-full rounded-2xl border border-white/80 bg-white/70 p-3 text-sm text-ink outline-none" />
          {checkIn.discomfort === 'changed_movement' && <p className="mt-3 rounded-2xl bg-amber-50 px-3 py-2 text-xs leading-relaxed text-amber-900">{t('Orbit will reduce training load. It cannot diagnose an injury. Consider professional review if symptoms persist or concern you.')}</p>}
          <GradientButton accent={ACCENTS.violet} onClick={() => void saveCheckIn()} className="mt-4">{t('Save check-in')}</GradientButton>
        </GlassCard>

        <div className="grid gap-4 sm:grid-cols-2">
          <GlassCard accent={ACCENTS.amber} className="p-5"><p className="text-[10px] font-bold tracking-widest text-ink-faint uppercase">{t('NUTRITION · FOOD MEMORY')}</p><p className="mt-2 font-display text-lg font-bold text-ink">{foodMemory ? `${foodMemory.amount} ${foodMemory.unit} ${foodMemory.food.name}` : nutrition.kcal > 0 ? `+${nutrition.kcal} kcal · ${nutrition.carbs_g} g ${t('carbs')} · ${nutrition.protein_g} g ${t('protein')}` : t('Normal meals cover this run')}</p>{foodMemory && <p className="mt-1 font-mono text-[10px] text-amber-800">+{foodMemory.macros.kcal} KCAL · P {foodMemory.macros.protein_g} · C {foodMemory.macros.carbs_g} · F {foodMemory.macros.fat_g}</p>}<p className="mt-2 text-xs leading-relaxed text-ink-soft">{t(nutrition.explanation)}{foodMemory ? ` ${t('Orbit selected a familiar high-carbohydrate food from your private Food Memory. Review before applying.')}` : ''}</p>{nutrition.kcal > 0 && <GradientButton accent={ACCENTS.amber} onClick={applyNutrition} disabled={Boolean(run.nutrition_adjustment_applied_at)} className="mt-4 w-full">{run.nutrition_adjustment_applied_at ? t('Adjustment applied') : t('Apply nutrition adjustment')}</GradientButton>}</GlassCard>
          <GlassCard accent={ACCENTS.emerald} className="p-5"><p className="text-[10px] font-bold tracking-widest text-ink-faint uppercase">{t('APEX RESPONSE')}</p><p className="mt-2 text-sm font-bold text-ink">{t(training.explanation)}</p><p className="mt-3 text-xs leading-relaxed text-ink-soft">{t('Avatar')}: {avatar.endurance_minutes} {t('endurance minutes')} · {t('pacing discipline')} {Math.round(avatar.pacing_discipline_signal * 100)}%. {t(avatar.explanation)}</p><p className="mt-3 text-[10px] font-bold text-emerald-800">{t('PROPOSED AND REVERSIBLE · NEVER SILENT')}</p></GlassCard>
        </div>

        {dna && <GlassCard accent={ACCENTS.ice} className="p-5"><div className="flex items-center justify-between"><h3 className="font-display text-lg font-bold text-ink">{t('Route DNA')}</h3><OrbitPill tone="ice">{dna.completions} {t('Completions').toUpperCase()}</OrbitPill></div><div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3"><Metric label="Typical distance" value={formatDistance(dna.typical_distance_m)} /><Metric label="Typical time" value={formatDuration(dna.typical_duration_s)} /><Metric label="Typical pace" value={formatPace(dna.typical_pace_sec_km)} />{dna.typical_elevation_gain_m != null && <Metric label="Typical elevation" value={`${dna.typical_elevation_gain_m} m`} />}{dna.typical_heart_rate != null && <Metric label="Typical heart rate" value={`${dna.typical_heart_rate} bpm`} />}{dna.pace_consistency_pct != null && <Metric label="Pace variation" value={`${dna.pace_consistency_pct.toFixed(1)}%`} />}</div><p className="mt-3 text-sm font-bold text-ink">{t(dna.interpretation)}</p><p className="mt-1 text-xs text-ink-soft">{t(dna.recent_trend)}</p></GlassCard>}

        <GlassCard accent={ACCENTS.ice} className="p-5">
          <h3 className="font-display text-lg font-bold text-ink">{t('Create route poster')}</h3>
          <div className="mt-3 flex gap-2 overflow-x-auto">{(['map', 'constellation', 'elevation', 'minimal'] as PosterStyle[]).map((style) => <button key={style} onClick={() => setPosterStyle(style)} className={`shrink-0 rounded-full px-3 py-2 text-xs font-bold ${posterStyle === style ? 'bg-sky-700 text-white' : 'bg-white/70 text-ink'}`}>{t(titleCase(style))}</button>)}</div>
          <label className="mt-4 block text-xs font-bold text-ink-faint">{t('Privacy trim')} · {privacyTrim} {t('m from both ends')}<input type="range" min="0" max="1000" step="50" value={privacyTrim} onChange={(event) => setPrivacyTrim(Number(event.target.value))} className="mt-2 w-full accent-sky-500" /></label>
          <p className="mt-1 text-xs text-ink-soft">{t('No precise start or finish is shared by default.')}</p>
          <label className="mt-3 flex items-center gap-2 text-xs font-bold text-ink"><input type="checkbox" checked={includeHr} disabled={run.metrics.heart_rate_avg == null} onChange={(event) => setIncludeHr(event.target.checked)} className="h-5 w-5 accent-sky-500" /> {t('Include recorded heart rate')}</label>
          <input value={posterNote} onChange={(event) => setPosterNote(event.target.value)} maxLength={90} placeholder={t('Optional poster note')} className="mt-3 min-h-12 w-full rounded-2xl border border-white/80 bg-white/70 px-3 text-sm" />
          <div className="mt-4 flex gap-2"><GradientButton accent={ACCENTS.ice} onClick={() => void savePoster('png')}>{t('Save PNG')}</GradientButton><GhostButton onClick={() => void savePoster('svg')}>{t('Save SVG')}</GhostButton></div>
        </GlassCard>
      </div>
    </OrbitFrame>
  )
}
