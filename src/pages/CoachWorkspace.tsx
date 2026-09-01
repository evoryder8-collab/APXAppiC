import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { EXERCISE_CATALOG, searchExerciseCatalog, type ExerciseCatalogItem } from '../data/exerciseCatalog'
import { CoachScopePicker } from '../components/coach/CoachScopePicker'
import { coachAPI } from '../lib/coachApi'
import { coachText } from '../lib/coachCopy'
import {
  validateCoachPlan,
  type CoachClientOverview,
  type CoachConsentScope,
  type CoachExerciseTemplate,
  type CoachPlanDraft,
  type CoachRosterEntry,
  type CoachSessionTemplate,
} from '../lib/coachPlatform'
import { useLanguage } from '../lib/i18n'
import { useStore } from '../store/AppStore'

const DEFAULT_SCOPES: CoachConsentScope[] = [
  'nutrition', 'workouts', 'activity', 'hydration', 'supplements', 'avatar', 'measurements', 'recovery',
]

function id(prefix: string): string {
  return `${prefix}-${crypto.randomUUID()}`
}

function dateInFourWeeks(): string {
  const date = new Date()
  date.setDate(date.getDate() + 28)
  return date.toISOString().slice(0, 10)
}

function emptyPlan(): CoachPlanDraft {
  return {
    title: '',
    objective: '',
    coach_note: '',
    review_date: dateInFourWeeks(),
    checklist: {
      nutrition: false,
      workouts: false,
      supplements: false,
      hydration: false,
      schedule: false,
      review_date: false,
    },
    sessions: [],
  }
}

function emptySession(index: number): CoachSessionTemplate {
  return {
    id: id('session'),
    weekday: Math.min(7, index + 1),
    name: '',
    session_mode: 'guided',
    estimated_minutes: 45,
    warmup_note: '',
    exercises: [],
  }
}

function exerciseFromCatalog(item: ExerciseCatalogItem): CoachExerciseTemplate {
  const unit = ['reps', 'seconds', 'minutes', 'metres', 'steps', 'rounds'].includes(item.unit)
    ? item.unit as CoachExerciseTemplate['unit']
    : 'reps'
  return {
    id: id('exercise'),
    movement_id: item.movementID,
    name: item.name,
    sets: Math.max(1, Math.min(20, item.sets)),
    target_min: Math.max(1, item.reps),
    target_max: Math.max(1, item.reps),
    unit,
    per_side: item.perSide,
    rest_seconds: Math.max(0, item.rest),
    tempo_up_seconds: 1,
    tempo_down_seconds: 2,
    tempo_pause_seconds: 0,
    notes: '',
    optional: false,
    group_id: null,
    group_position: null,
  }
}

function FieldLabel({ children }: { children: ReactNode }) {
  return <span className="mb-1.5 block font-mono text-[9px] font-black tracking-[0.14em] text-ink-faint uppercase">{children}</span>
}

function Surface({ children, className = '' }: { children?: ReactNode; className?: string }) {
  return <section className={`rounded-[1.75rem] border border-white/85 bg-white/72 p-4 shadow-[0_24px_60px_-34px_rgba(72,49,128,.42)] backdrop-blur-xl sm:p-5 ${className}`}>{children}</section>
}

export function CoachWorkspace() {
  const { coachContext, toast } = useStore()
  const { language } = useLanguage()
  const t = (value: string) => coachText(value, language)
  const [roster, setRoster] = useState<CoachRosterEntry[]>([])
  const [query, setQuery] = useState('')
  const [loadingRoster, setLoadingRoster] = useState(false)
  const [selectedID, setSelectedID] = useState<string | null>(null)
  const [overview, setOverview] = useState<CoachClientOverview | null>(null)
  const [loadingClient, setLoadingClient] = useState(false)
  const [plan, setPlan] = useState<CoachPlanDraft>(emptyPlan)
  const [expectedVersion, setExpectedVersion] = useState(0)
  const [saving, setSaving] = useState(false)
  const [inviteEmail, setInviteEmail] = useState('')
  const [inviteScopes, setInviteScopes] = useState<CoachConsentScope[]>(DEFAULT_SCOPES)
  const [requestVisualProgress, setRequestVisualProgress] = useState(false)
  const [inviteLink, setInviteLink] = useState('')
  const [inviting, setInviting] = useState(false)

  const knownMovementIDs = useMemo(() => new Set(EXERCISE_CATALOG.map((item) => item.movementID)), [])
  const publication = useMemo(
    () => validateCoachPlan(plan, { publishing: true, known_movement_ids: knownMovementIDs }),
    [knownMovementIDs, plan],
  )

  const loadRoster = useCallback(async (search = '') => {
    if (!coachContext.capabilities.coach_workspace) return
    setLoadingRoster(true)
    try {
      setRoster(await coachAPI.roster(search))
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not load clients.', 'error')
    } finally {
      setLoadingRoster(false)
    }
  }, [coachContext.capabilities.coach_workspace, toast])

  useEffect(() => { void loadRoster() }, [loadRoster])

  const openClient = async (relationshipID: string) => {
    setSelectedID(relationshipID)
    setLoadingClient(true)
    try {
      const result = await coachAPI.clientOverview(relationshipID)
      setOverview(result)
      setPlan(result.current_plan?.plan ? structuredClone(result.current_plan.plan) : emptyPlan())
      setExpectedVersion(result.current_plan?.version ?? 0)
    } catch (error) {
      setOverview(null)
      toast(error instanceof Error ? error.message : 'Could not open this client.', 'error')
    } finally {
      setLoadingClient(false)
    }
  }

  const createInvite = async () => {
    setInviting(true)
    try {
      const scopes = requestVisualProgress ? [...new Set([...inviteScopes, 'visual_progress' as const])] : inviteScopes
      const receipt = await coachAPI.createInvitation(inviteEmail.trim(), scopes, requestVisualProgress)
      const base = `${window.location.origin}${window.location.pathname}`
      setInviteLink(`${base}#/coach/invite/${receipt.token}`)
      setInviteEmail('')
      toast(t('Invite copied'), 'ok')
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not create invitation.', 'error')
    } finally {
      setInviting(false)
    }
  }

  const copyInvite = async () => {
    await navigator.clipboard.writeText(inviteLink)
    toast(t('Invite copied'), 'ok')
  }

  const updateSession = (sessionID: string, patch: Partial<CoachSessionTemplate>) => {
    setPlan((current) => ({
      ...current,
      sessions: current.sessions.map((session) => session.id === sessionID ? { ...session, ...patch } : session),
    }))
  }

  const updateExercise = (sessionID: string, exerciseID: string, patch: Partial<CoachExerciseTemplate>) => {
    setPlan((current) => ({
      ...current,
      sessions: current.sessions.map((session) => session.id === sessionID ? {
        ...session,
        exercises: session.exercises.map((exercise) => exercise.id === exerciseID ? { ...exercise, ...patch } : exercise),
      } : session),
    }))
  }

  const writePlan = async (publish: boolean) => {
    if (!selectedID) return toast(t('Choose a client first.'), 'error')
    if (publish && !publication.publishable) return toast(`${t('Publishing check')}: ${publication.issues.length}`, 'error')
    setSaving(true)
    try {
      const receipt = publish
        ? await coachAPI.publishPlan(selectedID, plan, expectedVersion)
        : await coachAPI.saveDraft(selectedID, plan, expectedVersion)
      setExpectedVersion(receipt.version)
      toast(t(publish ? 'Plan published' : 'Draft saved'), 'ok')
      await loadRoster(query)
      await openClient(selectedID)
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not save this plan.', 'error')
    } finally {
      setSaving(false)
    }
  }

  if (!coachContext.capabilities.coach_workspace || !coachContext.coach) {
    return (
      <div className="mx-auto max-w-xl pt-12 text-center">
        <h1 className="font-display text-3xl font-black text-ink">{t('Coach workspace')}</h1>
        <p className="mt-3 text-sm font-semibold text-ink-soft">{t('Coach tools are not enabled for this account.')}</p>
        <Link to="/" className="mt-6 inline-flex rounded-full bg-emerald-600 px-5 py-3 text-sm font-black text-white">{t('Return home')}</Link>
      </div>
    )
  }

  const coach = coachContext.coach
  const selectedRoster = roster.find((entry) => entry.id === selectedID)

  return (
    <div className="mx-auto w-full max-w-6xl space-y-5">
      <header className="rounded-[2rem] bg-gradient-to-br from-violet-600 via-fuchsia-500 to-amber-300 p-6 text-white shadow-[0_28px_70px_-28px_rgba(126,34,206,.7)] sm:p-8">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="font-mono text-[10px] font-black tracking-[0.22em] uppercase opacity-80">APEX · {t('Development access')}</p>
            <h1 className="mt-2 font-display text-4xl font-black tracking-tight sm:text-5xl">{t('Coach workspace')}</h1>
            <p className="mt-2 max-w-xl text-sm font-semibold text-white/85">{t('Your clients, plans and reviews in one private place.')}</p>
          </div>
          <div className="rounded-2xl border border-white/30 bg-white/16 px-4 py-3 text-right backdrop-blur">
            <p className="font-mono text-[9px] font-black tracking-[0.15em] uppercase opacity-75">{t('Sponsored seats')}</p>
            <p className="mt-1 font-display text-3xl font-black">{coach.active_seats}<span className="text-lg opacity-70">/{coach.seat_limit}</span></p>
          </div>
        </div>
      </header>

      <div className="grid gap-5 lg:grid-cols-[20rem_minmax(0,1fr)]">
        <aside className="space-y-5">
          <Surface>
            <h2 className="font-display text-xl font-black text-ink">{t('Invite a client')}</h2>
            <label className="mt-4 block">
              <FieldLabel>{t('Client email')}</FieldLabel>
              <input type="email" value={inviteEmail} onChange={(event) => setInviteEmail(event.target.value)} className="w-full rounded-2xl border border-violet-100 bg-white/85 px-4 py-3 text-sm font-bold text-ink outline-none focus:ring-2 focus:ring-violet-400" />
            </label>
            <div className="mt-4">
              <CoachScopePicker
                language={language}
                scopes={inviteScopes}
                onChange={setInviteScopes}
                visualProgressConsent={requestVisualProgress}
                onVisualProgressConsent={setRequestVisualProgress}
              />
            </div>
            <button type="button" disabled={inviting || !inviteEmail.includes('@')} onClick={() => void createInvite()} className="mt-4 w-full rounded-2xl bg-violet-600 px-4 py-3 text-sm font-black text-white shadow-lg disabled:opacity-45">{t('Create private invite')}</button>
            {inviteLink && (
              <button type="button" onClick={() => void copyInvite()} className="mt-2 w-full break-words rounded-2xl border border-violet-200 bg-violet-50 px-3 py-3 text-xs font-black text-violet-800">{t('Copy invite link')}</button>
            )}
          </Surface>

          <Surface>
            <label>
              <FieldLabel>{t('Search clients')}</FieldLabel>
              <input value={query} onChange={(event) => { setQuery(event.target.value); void loadRoster(event.target.value) }} className="w-full rounded-2xl border border-emerald-100 bg-white/85 px-4 py-3 text-sm font-bold text-ink outline-none focus:ring-2 focus:ring-emerald-400" />
            </label>
            <div className="mt-3 space-y-2" aria-busy={loadingRoster}>
              {!loadingRoster && roster.length === 0 && <p className="py-5 text-center text-sm font-semibold text-ink-soft">{t('No clients yet')}</p>}
              {roster.map((client) => (
                <button key={client.id} type="button" onClick={() => void openClient(client.id)} className={`w-full rounded-2xl border p-3 text-left transition ${selectedID === client.id ? 'border-violet-400 bg-violet-50 shadow-md' : 'border-white bg-white/70 hover:border-violet-200'}`}>
                  <div className="flex items-center justify-between gap-2"><span className="truncate text-sm font-black text-ink">{client.display_name}</span><span className={`h-2.5 w-2.5 shrink-0 rounded-full ${client.attention.length ? 'bg-amber-400' : 'bg-emerald-400'}`} /></div>
                  <p className="mt-1 truncate text-[10px] font-bold text-ink-soft">{client.plan_title ?? t('Nothing has been published yet.')}</p>
                  <p className="mt-1 font-mono text-[8px] font-black tracking-wide text-ink-faint uppercase">{client.attention.length ? t('Needs attention') : t('Up to date')}</p>
                </button>
              ))}
            </div>
          </Surface>
        </aside>

        <main className="min-w-0 space-y-5">
          {!selectedID ? (
            <Surface className="grid min-h-72 place-items-center text-center"><div><p className="text-4xl">✦</p><p className="mt-3 text-sm font-bold text-ink-soft">{t('Choose a client first.')}</p></div></Surface>
          ) : loadingClient ? (
            <Surface className="h-72 animate-pulse" />
          ) : overview ? (
            <>
              <Surface>
                <div className="flex flex-wrap items-end justify-between gap-3">
                  <div><p className="font-mono text-[9px] font-black tracking-[0.16em] text-emerald-700 uppercase">{t('Shared overview')}</p><h2 className="mt-1 font-display text-3xl font-black text-ink">{overview.display_name}</h2><p className="mt-1 text-xs font-semibold text-ink-soft">{t('Only categories this client consented to are visible.')}</p></div>
                  <span className="rounded-full bg-emerald-100 px-3 py-1.5 font-mono text-[9px] font-black tracking-wide text-emerald-800 uppercase">{overview.consented_scopes.length} scopes</span>
                </div>
                <div className="mt-4 grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
                  {overview.workouts && <OverviewStat label={t('Workouts in 30 days')} value={String(overview.workouts.completed_30d)} />}
                  {overview.nutrition && <OverviewStat label={t('Average daily energy')} value={overview.nutrition.average_kcal == null ? '–' : `${overview.nutrition.average_kcal} kcal`} />}
                  {overview.hydration && <OverviewStat label={t('Average daily water')} value={overview.hydration.average_litres == null ? '–' : `${overview.hydration.average_litres} L`} />}
                  {overview.measurements && <OverviewStat label={t('Current weight')} value={`${overview.measurements.weight_kg} kg`} />}
                </div>
              </Surface>

              <Surface>
                <div className="flex flex-wrap items-start justify-between gap-3"><div><p className="font-mono text-[9px] font-black tracking-[0.16em] text-violet-700 uppercase">{t('Plan studio')} · v{expectedVersion + 1}</p><h2 className="mt-1 font-display text-3xl font-black text-ink">{selectedRoster?.display_name}</h2></div><button type="button" onClick={() => setPlan(emptyPlan())} className="rounded-full border border-violet-200 px-3 py-2 text-[10px] font-black text-violet-700">New version</button></div>
                <div className="mt-5 grid gap-4 sm:grid-cols-2">
                  <label><FieldLabel>{t('Plan title')}</FieldLabel><input value={plan.title} maxLength={80} onChange={(event) => setPlan({ ...plan, title: event.target.value })} className="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm font-bold outline-none focus:ring-2 focus:ring-violet-400" /></label>
                  <label><FieldLabel>{t('Review date')}</FieldLabel><input type="date" value={plan.review_date ?? ''} onChange={(event) => setPlan({ ...plan, review_date: event.target.value || null })} className="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm font-bold outline-none focus:ring-2 focus:ring-violet-400" /></label>
                  <label className="sm:col-span-2"><FieldLabel>{t('Objective')}</FieldLabel><input value={plan.objective} maxLength={240} onChange={(event) => setPlan({ ...plan, objective: event.target.value })} className="w-full rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm font-bold outline-none focus:ring-2 focus:ring-violet-400" /></label>
                  <label className="sm:col-span-2"><FieldLabel>{t('Coach note')}</FieldLabel><textarea value={plan.coach_note} maxLength={4000} rows={3} onChange={(event) => setPlan({ ...plan, coach_note: event.target.value })} className="w-full resize-y rounded-2xl border border-slate-200 bg-white px-4 py-3 text-sm font-semibold outline-none focus:ring-2 focus:ring-violet-400" /></label>
                </div>

                <div className="mt-5 space-y-4">
                  {plan.sessions.map((session, sessionIndex) => (
                    <SessionEditor key={session.id} language={language} session={session} index={sessionIndex} onChange={(patch) => updateSession(session.id, patch)} onRemove={() => setPlan((current) => ({ ...current, sessions: current.sessions.filter((item) => item.id !== session.id) }))} onExerciseChange={(exerciseID, patch) => updateExercise(session.id, exerciseID, patch)} />
                  ))}
                  <button type="button" onClick={() => setPlan((current) => ({ ...current, sessions: [...current.sessions, emptySession(current.sessions.length)] }))} className="w-full rounded-2xl border-2 border-dashed border-violet-200 px-4 py-4 text-sm font-black text-violet-700">+ {t('Add session')}</button>
                </div>

                <div className="mt-5 rounded-2xl bg-slate-50 p-4">
                  <p className="font-mono text-[9px] font-black tracking-[0.16em] text-ink-faint uppercase">{t('Publishing check')}</p>
                  <div className="mt-3 grid gap-2 sm:grid-cols-2">
                    {Object.entries(plan.checklist).map(([key, checked]) => (
                      <label key={key} className="flex items-center gap-2 rounded-xl bg-white px-3 py-2 text-xs font-bold text-ink"><input type="checkbox" checked={Boolean(checked)} onChange={(event) => setPlan((current) => ({ ...current, checklist: { ...current.checklist, [key]: event.target.checked } }))} className="h-4 w-4 accent-emerald-600" />{key.replace('_', ' ')}</label>
                    ))}
                  </div>
                  {!publication.publishable && <p className="mt-3 text-[11px] font-bold text-amber-700">{publication.issues.length} checks remain. The draft is safe to save; publication stays locked.</p>}
                </div>

                <div className="mt-5 grid gap-3 sm:grid-cols-2">
                  <button type="button" disabled={saving} onClick={() => void writePlan(false)} className="rounded-2xl border border-violet-200 bg-white px-4 py-3 text-sm font-black text-violet-800 disabled:opacity-45">{t('Save draft')}</button>
                  <button type="button" disabled={saving || !publication.publishable} onClick={() => void writePlan(true)} className="rounded-2xl bg-gradient-to-r from-violet-600 to-fuchsia-500 px-4 py-3 text-sm font-black text-white shadow-lg disabled:opacity-40">{t('Publish to client')}</button>
                </div>
              </Surface>
            </>
          ) : null}
        </main>
      </div>
    </div>
  )
}

function OverviewStat({ label, value }: { label: string; value: string }) {
  return <div className="rounded-2xl border border-white bg-gradient-to-br from-white to-violet-50 p-3"><p className="text-[10px] font-bold text-ink-soft">{label}</p><p className="mt-1 font-display text-xl font-black text-ink">{value}</p></div>
}

function SessionEditor({ language, session, index, onChange, onRemove, onExerciseChange }: {
  language: 'en' | 'ro' | 'th'
  session: CoachSessionTemplate
  index: number
  onChange: (patch: Partial<CoachSessionTemplate>) => void
  onRemove: () => void
  onExerciseChange: (id: string, patch: Partial<CoachExerciseTemplate>) => void
}) {
  const t = (value: string) => coachText(value, language)
  const [movementQuery, setMovementQuery] = useState('')
  const results = useMemo(() => movementQuery.trim() ? searchExerciseCatalog(movementQuery, 'all', language).slice(0, 8) : [], [language, movementQuery])

  return (
    <article className="rounded-[1.5rem] border border-violet-100 bg-violet-50/45 p-4">
      <div className="flex items-center justify-between gap-3"><p className="font-mono text-[9px] font-black tracking-[0.14em] text-violet-700 uppercase">Session {index + 1}</p><button type="button" onClick={onRemove} className="text-[10px] font-black text-rose-600">{t('Remove')}</button></div>
      <div className="mt-3 grid gap-3 sm:grid-cols-[5rem_minmax(0,1fr)_8rem_6rem]">
        <label><FieldLabel>Day</FieldLabel><input type="number" min={1} max={7} value={session.weekday} onChange={(event) => onChange({ weekday: Number(event.target.value) })} className="w-full rounded-xl border border-violet-100 bg-white px-3 py-2.5 text-sm font-bold" /></label>
        <label><FieldLabel>{t('Session name')}</FieldLabel><input value={session.name} maxLength={80} onChange={(event) => onChange({ name: event.target.value })} className="w-full rounded-xl border border-violet-100 bg-white px-3 py-2.5 text-sm font-bold" /></label>
        <label><FieldLabel>Mode</FieldLabel><select value={session.session_mode} onChange={(event) => onChange({ session_mode: event.target.value as CoachSessionTemplate['session_mode'] })} className="w-full rounded-xl border border-violet-100 bg-white px-3 py-2.5 text-sm font-bold"><option value="guided">{t('Guided')}</option><option value="tracked">{t('Tracked')}</option></select></label>
        <label><FieldLabel>{t('minutes')}</FieldLabel><input type="number" min={5} max={360} value={session.estimated_minutes} onChange={(event) => onChange({ estimated_minutes: Number(event.target.value) })} className="w-full rounded-xl border border-violet-100 bg-white px-3 py-2.5 text-sm font-bold" /></label>
      </div>
      <label className="mt-3 block"><FieldLabel>{t('Warm-up note')}</FieldLabel><input value={session.warmup_note} maxLength={1000} onChange={(event) => onChange({ warmup_note: event.target.value })} className="w-full rounded-xl border border-violet-100 bg-white px-3 py-2.5 text-sm font-semibold" /></label>
      <div className="mt-3 space-y-2">
        {session.exercises.map((exercise) => (
          <div key={exercise.id} className="rounded-2xl border border-white bg-white/85 p-3">
            <div className="flex items-start justify-between gap-3"><p className="min-w-0 break-words text-sm font-black text-ink">{exercise.name}</p><button type="button" onClick={() => onChange({ exercises: session.exercises.filter((item) => item.id !== exercise.id) })} className="shrink-0 text-[10px] font-black text-rose-600">{t('Remove')}</button></div>
            <div className="mt-2 grid grid-cols-3 gap-2 sm:grid-cols-6">
              <MiniNumber label={t('sets')} value={exercise.sets} min={1} max={20} onChange={(sets) => onExerciseChange(exercise.id, { sets })} />
              <MiniNumber label="min" value={exercise.target_min} min={1} max={9999} onChange={(target_min) => onExerciseChange(exercise.id, { target_min })} />
              <MiniNumber label="max" value={exercise.target_max} min={1} max={9999} onChange={(target_max) => onExerciseChange(exercise.id, { target_max })} />
              <MiniNumber label={`${t('rest')} s`} value={exercise.rest_seconds} min={0} max={900} onChange={(rest_seconds) => onExerciseChange(exercise.id, { rest_seconds })} />
              <label className="flex items-end gap-1 pb-2 text-[9px] font-bold text-ink-soft"><input type="checkbox" checked={exercise.per_side} onChange={(event) => onExerciseChange(exercise.id, { per_side: event.target.checked })} className="h-4 w-4 accent-violet-600" />{t('per side')}</label>
              <label className="flex items-end gap-1 pb-2 text-[9px] font-bold text-ink-soft"><input type="checkbox" checked={exercise.optional} onChange={(event) => onExerciseChange(exercise.id, { optional: event.target.checked })} className="h-4 w-4 accent-violet-600" />{t('Optional')}</label>
            </div>
          </div>
        ))}
      </div>
      <div className="relative mt-3">
        <input value={movementQuery} onChange={(event) => setMovementQuery(event.target.value)} placeholder={t('Find a reviewed movement')} className="w-full rounded-2xl border border-violet-200 bg-white px-4 py-3 text-sm font-bold outline-none focus:ring-2 focus:ring-violet-400" />
        {results.length > 0 && <div className="absolute inset-x-0 top-full z-10 mt-1 max-h-64 overflow-y-auto rounded-2xl border border-violet-100 bg-white p-1 shadow-xl">{results.map((item) => <button key={item.id} type="button" onClick={() => { onChange({ exercises: [...session.exercises, exerciseFromCatalog(item)] }); setMovementQuery('') }} className="flex w-full items-center justify-between gap-3 rounded-xl px-3 py-2 text-left hover:bg-violet-50"><span className="text-xs font-black text-ink">{item.names[language]}</span><span className="text-[9px] font-bold text-ink-faint">{item.equipment}</span></button>)}</div>}
      </div>
    </article>
  )
}

function MiniNumber({ label, value, min, max, onChange }: { label: string; value: number; min: number; max: number; onChange: (value: number) => void }) {
  return <label><span className="mb-1 block text-[8px] font-black text-ink-faint uppercase">{label}</span><input type="number" value={value} min={min} max={max} onChange={(event) => onChange(Number(event.target.value))} className="w-full rounded-lg border border-slate-100 bg-slate-50 px-2 py-2 font-mono text-xs font-black text-ink" /></label>
}
