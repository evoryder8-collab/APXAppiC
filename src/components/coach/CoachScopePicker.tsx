import { COACH_CONSENT_SCOPES, type CoachConsentScope } from '../../lib/coachPlatform'
import { COACH_SCOPE_LABELS, coachText } from '../../lib/coachCopy'
import type { IntroLanguage } from '../../lib/introLanguage'

interface CoachScopePickerProps {
  language: IntroLanguage
  scopes: CoachConsentScope[]
  onChange: (scopes: CoachConsentScope[]) => void
  allowedScopes?: readonly CoachConsentScope[]
  visualProgressOffered?: boolean
  visualProgressConsent: boolean
  onVisualProgressConsent: (value: boolean) => void
  disabled?: boolean
}

export function CoachScopePicker({
  language,
  scopes,
  onChange,
  allowedScopes = COACH_CONSENT_SCOPES,
  visualProgressOffered = true,
  visualProgressConsent,
  onVisualProgressConsent,
  disabled = false,
}: CoachScopePickerProps) {
  const allowed = new Set(allowedScopes)
  const ordinary = COACH_CONSENT_SCOPES.filter((scope) => scope !== 'visual_progress' && allowed.has(scope))
  const selected = new Set(scopes)

  const toggle = (scope: CoachConsentScope, enabled: boolean) => {
    const next = new Set(selected)
    if (enabled) next.add(scope)
    else next.delete(scope)
    next.delete('visual_progress')
    onChange([...next])
  }

  return (
    <fieldset disabled={disabled} className="space-y-3">
      <legend className="mb-3 font-mono text-[10px] font-black tracking-[0.16em] text-ink-faint uppercase">
        {coachText('What they may share', language)}
      </legend>
      <div className="grid gap-2 sm:grid-cols-2">
        {ordinary.map((scope) => (
          <label key={scope} className="flex min-h-12 items-center gap-3 rounded-2xl border border-white/80 bg-white/70 px-3 py-2.5 shadow-sm">
            <input
              type="checkbox"
              checked={selected.has(scope)}
              onChange={(event) => toggle(scope, event.target.checked)}
              className="h-5 w-5 accent-emerald-600"
            />
            <span className="text-sm font-bold text-ink">{COACH_SCOPE_LABELS[scope][language]}</span>
          </label>
        ))}
      </div>
      {visualProgressOffered && allowed.has('visual_progress') && (
        <div className="rounded-2xl border border-violet-200/70 bg-violet-50/75 p-3">
          <label className="flex items-start gap-3">
            <input
              type="checkbox"
              checked={visualProgressConsent}
              onChange={(event) => onVisualProgressConsent(event.target.checked)}
              className="mt-0.5 h-5 w-5 accent-violet-600"
            />
            <span>
              <span className="block text-sm font-black text-violet-950">{COACH_SCOPE_LABELS.visual_progress[language]}</span>
              <span className="mt-0.5 block text-[11px] font-semibold leading-relaxed text-violet-800">
                {coachText('Visual progress is always a separate opt-in.', language)}
              </span>
            </span>
          </label>
        </div>
      )}
    </fieldset>
  )
}
