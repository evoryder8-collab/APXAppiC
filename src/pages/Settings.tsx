import { useRef, useState } from 'react'
import { AccentChip, GlassCard, GradientButton, SectionHeader, Stepper, Toggle } from '../components/ui'
import { ACCENTS } from '../lib/theme'
import { useStore } from '../store/AppStore'
import { isLocalMode } from '../lib/supabase'
import { ageFrom, computeTargets } from '../lib/nutrition'
import { ensurePermission } from '../lib/notify'
import { buildImportRows, parseHealthFile, type ImportResult } from '../lib/healthImport'
import { clearEntryGrant, clearSelectedPersona } from '../lib/persona'

const violet = ACCENTS.violet
const emerald = ACCENTS.emerald
const amber = ACCENTS.amber

type ImportState =
  | { phase: 'idle' }
  | { phase: 'parsing'; progress: number }
  | { phase: 'done'; result: ImportResult }

export function Settings() {
  const { data, setProfile, setSettings, signOut, toast, bulkUpsert } = useStore()
  const fileRef = useRef<HTMLInputElement>(null)
  const [importState, setImportState] = useState<ImportState>({ phase: 'idle' })

  const switchPerson = async (): Promise<void> => {
    clearEntryGrant()
    clearSelectedPersona()
    await signOut()
    window.location.hash = '#/'
    window.location.reload()
  }

  const runImport = async (file: File): Promise<void> => {
    try {
      setImportState({ phase: 'parsing', progress: 0 })
      const parsed = await parseHealthFile(file, (p) =>
        setImportState({ phase: 'parsing', progress: p }),
      )
      const { dailyLogs, metrics, activities, result } = buildImportRows(data, parsed)
      bulkUpsert('daily_logs', dailyLogs)
      bulkUpsert('health_metrics', metrics)
      bulkUpsert('imported_activities', activities)
      if (
        result.latestWeight != null &&
        data.profile &&
        Math.abs(result.latestWeight - data.profile.weight_kg) > 0.2
      ) {
        setProfile({ weight_kg: Math.round(result.latestWeight * 10) / 10 })
      }
      setImportState({ phase: 'done', result })
      toast('Apple Health data imported', 'ok')
    } catch {
      setImportState({ phase: 'idle' })
      toast('Could not read that file. Export from the Health app and pick export.xml')
    }
  }
  const profile = data.profile
  const settings = data.settings
  const [birth, setBirth] = useState(profile?.birthdate ?? '1992-07-25')
  if (!profile || !settings) return null
  const targets = computeTargets(profile)

  const row = 'flex items-center justify-between gap-3 py-3'
  const label = 'text-sm font-bold text-ink'
  const sub = 'text-xs font-medium text-ink-soft'

  return (
    <div className="mx-auto w-full max-w-3xl">
      <SectionHeader accent={violet} title="Settings" subtitle="Profile, targets and preferences" />

      <div className="space-y-5">
        <GlassCard accent={violet} breathe className="p-5">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="font-mono text-[10px] font-bold tracking-[0.18em] text-ink-faint uppercase">Active identity</p>
              <h2 className="mt-1 font-display text-2xl font-bold tracking-tight text-ink">{profile.display_name}</h2>
            </div>
            <AccentChip accent={violet}>{profile.persona.toUpperCase()}</AccentChip>
          </div>
          <p className="mt-3 text-[13px] leading-relaxed font-medium text-ink-soft">{profile.profile_note}</p>
          {profile.target_kcal != null && (
            <div className="mt-4 grid grid-cols-4 gap-2 rounded-2xl bg-white/45 p-3 text-center">
              {[
                ['KCAL', targets.kcal],
                ['PROTEIN', `${targets.protein_g}g`],
                ['FAT', `${targets.fat_g}g`],
                ['CARBS', `${targets.carbs_g}g`],
              ].map(([labelText, value]) => (
                <div key={labelText}>
                  <p className="font-mono text-[8px] font-bold tracking-wide text-ink-faint">{labelText}</p>
                  <p className="mt-1 font-mono text-sm font-bold text-ink">{value}</p>
                </div>
              ))}
            </div>
          )}
        </GlassCard>

        <GlassCard accent={violet} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Body profile</h2>
          <p className={sub}>
            Age {ageFrom(profile.birthdate)}, computed from your birthdate. Never hardcoded.
          </p>
          <div className="mt-3 divide-y divide-ink/8">
            <div className={row}>
              <span className={label}>Weight</span>
              <Stepper accent={violet} value={profile.weight_kg} step={0.5} unit="kg" onChange={(v) => setProfile({ weight_kg: v })} />
            </div>
            <div className={row}>
              <span className={label}>Body fat</span>
              <Stepper accent={violet} value={profile.body_fat_pct} step={0.5} unit="%" onChange={(v) => setProfile({ body_fat_pct: v })} />
            </div>
            <div className={row}>
              <span className={label}>Height</span>
              <Stepper accent={violet} value={profile.height_cm} step={1} unit="cm" onChange={(v) => setProfile({ height_cm: v })} />
            </div>
            <div className={row}>
              <span className={label}>Birthdate</span>
              <input
                type="date"
                value={birth}
                onChange={(e) => {
                  setBirth(e.target.value)
                  if (e.target.value) setProfile({ birthdate: e.target.value })
                }}
                className="glass rounded-xl px-3 py-2 font-mono text-sm font-bold text-ink"
              />
            </div>
            <div className={row}>
              <span className={label}>Default training time</span>
              <input
                type="time"
                value={profile.training_time}
                onChange={(e) => setProfile({ training_time: e.target.value })}
                className="glass rounded-xl px-3 py-2 font-mono text-sm font-bold text-ink"
              />
            </div>
          </div>
        </GlassCard>

        <GlassCard accent={violet} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Player</h2>
          <div className="mt-2 divide-y divide-ink/8">
            <div className={row}>
              <div>
                <p className={label}>Voice announcements</p>
                <p className={sub}>Rep numbers and cues, Web Speech</p>
              </div>
              <Toggle accent={violet} on={settings.voice_on} onChange={(v) => setSettings({ voice_on: v })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Cadence ticks</p>
                <p className={sub}>Subtle audio ticks pacing each rep</p>
              </div>
              <Toggle accent={violet} on={settings.ticks_on} onChange={(v) => setSettings({ ticks_on: v })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Overload Guardian sensitivity</p>
                <p className={sub}>Warn when a jump exceeds this multiple of your typical increment</p>
              </div>
              <Stepper accent={violet} value={settings.guardian_factor} step={0.1} min={1} max={3} onChange={(v) => setSettings({ guardian_factor: v })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Meal + stack reminders</p>
                <p className={sub}>Browser notifications while APEX is open</p>
              </div>
              <Toggle
                accent={violet}
                on={settings.notifications_on}
                onChange={(v) => {
                  if (v)
                    void ensurePermission().then((ok) => {
                      if (ok) setSettings({ notifications_on: true })
                      else toast('Notifications blocked by the browser')
                    })
                  else setSettings({ notifications_on: false })
                }}
              />
            </div>
          </div>
        </GlassCard>

        {profile.persona === 'constantine' && <GlassCard accent={emerald} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Main Phase add-on protocols</h2>
          <p className={sub}>Off by default. They appear inside Main Phase sessions when on.</p>
          <div className="mt-2 divide-y divide-ink/8">
            <div className={row}>
              <div>
                <p className={label}>Endurance Phase 1</p>
                <p className={sub}>Biweekly Thursday: 1x max BW pushups + 1x max BW pull-ups</p>
              </div>
              <Toggle accent={emerald} on={settings.addons.endurance1} onChange={(v) => setSettings({ addons: { ...settings.addons, endurance1: v } })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Endurance Phase 2</p>
                <p className={sub}>Unlocks at 40+ BW pushups. Tuesdays: 1 set BW pushups to failure</p>
              </div>
              <Toggle accent={emerald} on={settings.addons.endurance2} onChange={(v) => setSettings({ addons: { ...settings.addons, endurance2: v } })} />
            </div>
            <div className={row}>
              <div>
                <p className={label}>Endurance Phase 3</p>
                <p className={sub}>Unlocks at 15+ BW pull-ups. Sundays: ladder 1-2-3-4-5-4-3-2-1</p>
              </div>
              <Toggle accent={emerald} on={settings.addons.endurance3} onChange={(v) => setSettings({ addons: { ...settings.addons, endurance3: v } })} />
            </div>
          </div>
        </GlassCard>}

        <GlassCard accent={amber} className="p-5">
          <div className="flex items-center justify-between gap-3">
            <div>
              <h2 className="font-display text-lg font-bold text-ink">Apple Health import</h2>
              <p className={sub}>
                Nutrition, water, weight, VO2max, resting heart rate and workouts feed the engine.
              </p>
            </div>
            {importState.phase !== 'parsing' && (
              <GradientButton accent={amber} onClick={() => fileRef.current?.click()} className="shrink-0">
                Import
              </GradientButton>
            )}
          </div>
          <input
            ref={fileRef}
            type="file"
            accept=".xml,text/xml"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) void runImport(f)
              e.target.value = ''
            }}
          />

          {importState.phase === 'parsing' && (
            <div className="mt-4">
              <div className="h-2.5 overflow-hidden rounded-full bg-ink/8">
                <div
                  className="h-full rounded-full transition-[width] duration-200"
                  style={{ width: `${importState.progress * 100}%`, background: amber.gradient }}
                />
              </div>
              <p className="mt-2 font-mono text-xs font-semibold text-ink-soft">
                Streaming your export, {(importState.progress * 100).toFixed(0)}%. Big files are fine.
              </p>
            </div>
          )}

          {importState.phase === 'done' && (
            <div className="mt-4 flex flex-wrap gap-1.5">
              <AccentChip accent={amber}>{importState.result.dailyLogsTouched} NUTRITION/WATER DAYS</AccentChip>
              <AccentChip accent={amber}>{importState.result.workoutsAdded} WORKOUTS</AccentChip>
              <AccentChip accent={amber}>{importState.result.metricsTouched} BODY METRIC DAYS</AccentChip>
              {importState.result.latestWeight != null && (
                <AccentChip accent={amber}>LATEST WEIGHT {importState.result.latestWeight.toFixed(1)} KG</AccentChip>
              )}
              {importState.result.latestVo2max != null && (
                <AccentChip accent={amber}>VO2MAX {importState.result.latestVo2max.toFixed(1)}</AccentChip>
              )}
            </div>
          )}

          <p className="mt-3 text-xs leading-relaxed font-medium text-ink-faint">
            Days without the watch or phone never count against you: imports only add signal,
            they never create decay. Anything you logged manually in APEX always wins over
            imported values. Export from iPhone: Health app, profile picture, Export All Health
            Data, then pick the export.xml inside the zip. Re-importing later is safe.
          </p>
        </GlassCard>

        <GlassCard accent={violet} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Account</h2>
          {isLocalMode ? (
            <p className="mt-2 text-sm font-medium text-ink-soft">
              Running in local mode: everything lives in this browser. Add the two Supabase env
              vars and redeploy to sync across devices (see README).
            </p>
          ) : null}
          <div className="mt-3 flex flex-wrap gap-2">
            <GradientButton accent={violet} onClick={() => void switchPerson()}>
              Switch person
            </GradientButton>
            {!isLocalMode && (
              <GradientButton accent={violet} onClick={() => void signOut()}>
                Sign out
              </GradientButton>
            )}
          </div>
        </GlassCard>
      </div>
    </div>
  )
}
