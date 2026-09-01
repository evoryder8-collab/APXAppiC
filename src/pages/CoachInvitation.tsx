import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { CoachScopePicker } from '../components/coach/CoachScopePicker'
import { coachAPI } from '../lib/coachApi'
import { coachText } from '../lib/coachCopy'
import type { CoachConsentScope, CoachInvitationPreview } from '../lib/coachPlatform'
import { useLanguage } from '../lib/i18n'
import { useStore } from '../store/AppStore'

export function CoachInvitation() {
  const { token = '' } = useParams()
  const navigate = useNavigate()
  const { language } = useLanguage()
  const { refreshCoachContext, toast } = useStore()
  const t = (value: string) => coachText(value, language)
  const [preview, setPreview] = useState<CoachInvitationPreview | null>(null)
  const [scopes, setScopes] = useState<CoachConsentScope[]>([])
  const [visualProgress, setVisualProgress] = useState(false)
  const [loading, setLoading] = useState(true)
  const [accepting, setAccepting] = useState(false)

  useEffect(() => {
    let current = true
    void coachAPI.previewInvitation(token).then((result) => {
      if (!current) return
      setPreview(result)
      setScopes(result.requested_scopes.filter((scope) => scope !== 'visual_progress'))
    }).catch((error) => {
      if (current) toast(error instanceof Error ? error.message : 'Invitation unavailable.', 'error')
    }).finally(() => { if (current) setLoading(false) })
    return () => { current = false }
  }, [toast, token])

  const accept = async () => {
    if (!preview) return
    setAccepting(true)
    try {
      await coachAPI.acceptInvitation(token, scopes, visualProgress)
      await refreshCoachContext()
      toast(t('Invitation accepted'), 'ok')
      navigate('/coach-plan', { replace: true })
    } catch (error) {
      toast(error instanceof Error ? error.message : 'Could not accept this invitation.', 'error')
    } finally {
      setAccepting(false)
    }
  }

  return (
    <div className="mx-auto w-full max-w-2xl">
      <div className="rounded-[2rem] border border-white/85 bg-white/76 p-5 shadow-[0_30px_80px_-38px_rgba(109,40,217,.55)] backdrop-blur-xl sm:p-8">
        <p className="font-mono text-[10px] font-black tracking-[0.2em] text-violet-700 uppercase">APEX · {t('Private by default')}</p>
        <h1 className="mt-3 font-display text-4xl font-black tracking-tight text-ink">{t('Accept coach invitation')}</h1>
        {loading ? <div className="mt-8 h-56 animate-pulse rounded-3xl bg-violet-50" /> : preview ? (
          <>
            <p className="mt-3 text-sm font-semibold leading-relaxed text-ink-soft"><strong className="text-ink">{preview.coach_display_name}</strong><br />{t('Review every category before sharing. You can change these choices later.')}</p>
            <div className="mt-6">
              <CoachScopePicker
                language={language}
                scopes={scopes}
                onChange={setScopes}
                allowedScopes={preview.requested_scopes}
                visualProgressOffered={preview.visual_progress_requested}
                visualProgressConsent={visualProgress}
                onVisualProgressConsent={setVisualProgress}
              />
            </div>
            <button type="button" disabled={accepting || scopes.length === 0} onClick={() => void accept()} className="mt-6 w-full rounded-2xl bg-gradient-to-r from-violet-600 to-fuchsia-500 px-5 py-4 text-sm font-black text-white shadow-xl disabled:opacity-45">{t('Accept and continue')}</button>
          </>
        ) : <div className="mt-8 text-center"><p className="text-sm font-bold text-ink-soft">Invitation unavailable.</p><Link to="/" className="mt-4 inline-flex rounded-full bg-ink px-5 py-3 text-sm font-black text-white">{t('Return home')}</Link></div>}
      </div>
    </div>
  )
}
