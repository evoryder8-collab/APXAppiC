import { useState } from 'react'
import { avatarStatKeys, avatarStatLabels, equalStartingPoints, validStartingPoints } from '../../lib/avatarStartingPoints'
import { clientPolicyForAccount } from '../../lib/coachAccess'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { bespokeProtocolFor } from '../../lib/profilePolicy'
import { useStore } from '../../store/AppStore'

export function AvatarStartingPoints({ required = false }: { required?: boolean }) {
  const { appAccess, coachContext, data, saveAvatarStartingPoints, toast } = useStore()
  const { language } = useLanguage()
  const [draft, setDraft] = useState({ ...equalStartingPoints })
  const [saving, setSaving] = useState(false)
  const [failed, setFailed] = useState(false)
  const profile = data.profile
  if (!profile || bespokeProtocolFor(profile) || validStartingPoints(profile.avatar_starting_points)
    || (!required && !clientPolicyForAccount(appAccess, coachContext).can_use_avatar)) return null
  const t = (text: string) => translateInterfaceText(text, language)
  const total = avatarStatKeys.reduce((sum, key) => sum + (draft[key] || 0), 0)
  const form = <form className="mt-3" onSubmit={async event => {
      event.preventDefault()
      if (saving || !validStartingPoints(draft)) return
      setSaving(true)
      setFailed(false)
      try {
        const status = await saveAvatarStartingPoints(profile.user_id, draft)
        toast(t(status === 'saved' ? 'Self-selected starting points' : 'Starting points were already saved on another device.'), 'ok')
      } catch {
        setFailed(true)
      } finally {
        setSaving(false)
      }
    }}>
      <p className="mb-3 text-sm text-ink-soft">{t('Distribute 300 points across six Avatar stats. These are game scores you choose. Logged activity changes them over time.')}</p>
      <p className="mb-3 text-sm text-ink-soft">{t('You can save your starting points once.')}</p>
      <fieldset disabled={saving} className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        {avatarStatKeys.map(key => <label key={key} className="flex flex-col gap-1 text-sm font-semibold">
          {t(avatarStatLabels[key])}
          <input type="number" min="0" max="100" step="1" required inputMode="numeric"
            className="min-h-11 w-full rounded-lg border border-ink/25 bg-white px-3 text-base"
            value={Number.isFinite(draft[key]) ? draft[key] : ''}
            onChange={e => setDraft({ ...draft, [key]: e.currentTarget.valueAsNumber })} />
        </label>)}
      </fieldset>
      {failed && <p role="alert" className="mt-3 text-sm font-bold">{t('Could not save starting points. Check your connection and try again.')}</p>}
      <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
        <output aria-live="polite" className="text-sm font-bold">{t('Points remaining')} · {300 - total}</output>
        <button type="submit" disabled={saving || !validStartingPoints(draft)} className="min-h-11 rounded-full bg-emerald-800 px-4 font-bold text-white disabled:opacity-50">{t('Save starting points')}</button>
      </div>
    </form>
  const card = 'mx-auto mb-4 w-full max-w-3xl rounded-2xl border border-emerald-200 bg-white p-4 text-ink'
  return required
    ? <section className={card}><h1 className="font-display text-2xl font-bold">{t('Choose starting points')}</h1>{form}</section>
    : <details className={card}><summary className="cursor-pointer font-display font-bold">{t('Choose starting points')}</summary>{form}</details>
}
