import { useState } from 'react'
import { GlassCard, GradientButton, SectionHeader, Stepper, Toggle } from '../components/ui'
import { ACCENTS } from '../lib/theme'
import { useStore } from '../store/AppStore'
import { isLocalMode } from '../lib/supabase'
import { ageFrom } from '../lib/nutrition'
import { ensurePermission } from '../lib/notify'

const violet = ACCENTS.violet
const emerald = ACCENTS.emerald

export function Settings() {
  const { data, setProfile, setSettings, signOut, toast } = useStore()
  const profile = data.profile
  const settings = data.settings
  const [birth, setBirth] = useState(profile?.birthdate ?? '1992-07-25')
  if (!profile || !settings) return null

  const row = 'flex items-center justify-between gap-3 py-3'
  const label = 'text-sm font-bold text-ink'
  const sub = 'text-xs font-medium text-ink-soft'

  return (
    <div className="mx-auto w-full max-w-3xl">
      <SectionHeader accent={violet} title="Settings" subtitle="Profile, targets and preferences" />

      <div className="space-y-5">
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

        <GlassCard accent={emerald} className="p-5">
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
        </GlassCard>

        <GlassCard accent={violet} className="p-5">
          <h2 className="font-display text-lg font-bold text-ink">Account</h2>
          {isLocalMode ? (
            <p className="mt-2 text-sm font-medium text-ink-soft">
              Running in local mode: everything lives in this browser. Add the two Supabase env
              vars and redeploy to sync across devices (see README).
            </p>
          ) : (
            <div className="mt-3">
              <GradientButton accent={violet} onClick={() => void signOut()}>
                Sign out
              </GradientButton>
            </div>
          )}
        </GlassCard>
      </div>
    </div>
  )
}
