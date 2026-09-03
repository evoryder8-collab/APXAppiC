import { useState } from 'react'

import {
  accountAccessRecoveryReason,
  type AccountAccessRecoveryReason,
} from '../lib/coachAccess.ts'
import { translateInterfaceText, useLanguage } from '../lib/i18n.tsx'
import { useStore } from '../store/AppStore.tsx'

const RECOVERY_COPY: Record<AccountAccessRecoveryReason, {
  title: string
  body: string
  guidance: string
}> = {
  update_required: {
    title: 'APEX needs an update',
    body: 'This APEX web version is older than the minimum version required for your account.',
    guidance: 'Reload the page to check for the required web version. If this message remains, that version is not available here yet.',
  },
  revoked: {
    title: 'Access was revoked',
    body: 'Access for this account has been revoked.',
    guidance: 'Check access again if this changed recently, or sign out safely.',
  },
  expired: {
    title: 'Access has expired',
    body: 'Access for this account has expired.',
    guidance: 'Check access again if access was renewed, or sign out safely.',
  },
  locked: {
    title: 'Access is not active',
    body: 'This account does not currently have access to APEX.',
    guidance: 'Check access again if your account was just updated, or sign out safely.',
  },
  uncertain: {
    title: 'Access needs attention',
    body: 'APEX could not confirm access for this account. Your account data has not been changed.',
    guidance: 'Access is still unavailable. Try again when online, or sign out safely.',
  },
}

/**
 * Recovery for the exceptional case where the server cannot confirm access.
 *
 * This web build cannot sell or restore an App Store product, so it never
 * draws a purchase control or a price. Refresh and sign-out are operations the
 * web client can genuinely complete, including when the network stays down.
 */
export function AccessRecovery() {
  const { appAccess, refreshAppAccess, refreshCoachContext, signOut } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [checking, setChecking] = useState(false)
  const reason = accountAccessRecoveryReason(appAccess)
  const copy = RECOVERY_COPY[reason]

  const checkAccess = async (): Promise<void> => {
    if (checking) return
    setChecking(true)
    try {
      await Promise.allSettled([
        refreshAppAccess(),
        refreshCoachContext(),
      ])
    } finally {
      setChecking(false)
    }
  }

  return (
    <main className="relative z-10 flex min-h-dvh items-center justify-center px-5 py-[max(1.5rem,env(safe-area-inset-top))]">
      <section aria-labelledby="access-recovery-title" className="glass w-full max-w-md rounded-[2rem] border border-white/85 p-6 shadow-2xl sm:p-8">
        <span aria-hidden className="grid h-12 w-12 place-items-center rounded-2xl bg-amber-100 text-xl text-amber-800">◇</span>
        <p className="mt-5 font-mono text-[9px] font-black tracking-[.2em] text-amber-700 uppercase">{t('Account access')}</p>
        <h1 id="access-recovery-title" className="mt-2 font-display text-3xl leading-tight font-black text-ink">{t(copy.title)}</h1>
        <p className="mt-3 text-sm leading-relaxed text-ink-soft">{t(copy.body)}</p>
        <p role="status" aria-live="polite" className="mt-3 text-xs leading-relaxed font-bold text-amber-800">{t(copy.guidance)}</p>
        <p className="mt-3 rounded-2xl bg-white/55 px-4 py-3 text-xs leading-relaxed font-semibold text-ink-soft">{t('Purchases are not available in this web preview.')}</p>

        <div className="mt-6 grid gap-3">
          {reason === 'update_required' && (
            <button type="button" onClick={() => window.location.reload()} className="rounded-2xl bg-emerald-600 px-5 py-3.5 text-sm font-black text-white shadow-sm">
              {t('Reload APEX')}
            </button>
          )}
          <button type="button" disabled={checking} onClick={() => void checkAccess()} className="rounded-2xl bg-emerald-600 px-5 py-3.5 text-sm font-black text-white shadow-sm disabled:opacity-55">
            {checking ? t('Checking access…') : t('Check access again')}
          </button>
          <button type="button" onClick={() => void signOut()} className="rounded-2xl border border-slate-300/80 bg-white/65 px-5 py-3.5 text-sm font-black text-ink">
            {t('Sign out')}
          </button>
        </div>
      </section>
    </main>
  )
}
