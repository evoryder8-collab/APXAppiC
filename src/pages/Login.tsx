import { AnimatePresence, motion, useReducedMotion } from 'framer-motion'
import { useEffect, useRef, useState, type CSSProperties, type FormEvent } from 'react'
import { ApexMark } from '../components/Icons'
import { EASE } from '../components/ui'
import { entryRevealDelay } from '../lib/entryFlow'
import { getIntroLanguage, localizedLoginError, LOGIN_COPY } from '../lib/introLanguage'
import { personaBySlug, type PersonaSlug } from '../lib/persona'
import { useStore } from '../store/AppStore'

export function Login({ onBack, onSuccess }: { onBack: () => void; onSuccess: (persona: PersonaSlug) => void }) {
  const { signIn } = useStore()
  const reduceMotion = useReducedMotion()
  const language = getIntroLanguage()
  const copy = LOGIN_COPY[language]
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [revealedPersona, setRevealedPersona] = useState<PersonaSlug | null>(null)
  const persona = revealedPersona ? personaBySlug(revealedPersona) : null
  const onSuccessRef = useRef(onSuccess)

  useEffect(() => {
    onSuccessRef.current = onSuccess
  }, [onSuccess])

  useEffect(() => {
    if (!revealedPersona) return
    const timer = window.setTimeout(() => onSuccessRef.current(revealedPersona), entryRevealDelay(Boolean(reduceMotion)))
    return () => window.clearTimeout(timer)
  }, [reduceMotion, revealedPersona])

  const submit = async (event: FormEvent): Promise<void> => {
    event.preventDefault()
    if (busy) return
    setBusy(true)
    setError(null)
    const result = await signIn(email.trim(), password)
    if (result.error || !result.persona) {
      setError(localizedLoginError(result.error ?? 'Sign-in failed', language))
      setBusy(false)
      return
    }
    setRevealedPersona(result.persona)
    setBusy(false)
  }

  const input = 'w-full rounded-2xl border border-white/10 bg-white/[0.055] px-4 py-3.5 text-base font-medium text-white outline-none transition placeholder:text-white/25 focus:border-white/30 focus:bg-white/[0.075]'

  return (
    <div className="fixed inset-0 z-[70] min-h-dvh overflow-hidden bg-[#05070b] text-white">
      <div className="intro-aurora absolute inset-0" aria-hidden />
      <div className="intro-grid absolute inset-0" aria-hidden />
      <div className="intro-vignette absolute inset-0" aria-hidden />

      <motion.header
        initial={reduceMotion ? false : { opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={reduceMotion ? { duration: 0 } : { duration: 0.45 }}
        className="absolute inset-x-0 top-0 z-30 flex items-center justify-between px-5 pt-[max(1.25rem,env(safe-area-inset-top))] sm:px-10"
      >
        <div className="flex items-center gap-3">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/12 bg-white/7 backdrop-blur-xl"><ApexMark className="h-5 w-5" /></span>
          <p className="text-[13px] font-bold tracking-[0.3em]">APEX</p>
        </div>
        <p className="font-mono text-[8px] tracking-[0.2em] text-white/34 uppercase">{copy.encrypted}</p>
      </motion.header>

      <AnimatePresence mode="wait" initial={false}>
        {!persona ? (
          <motion.main
            key="neutral-login"
            data-testid="neutral-login"
            initial={reduceMotion ? false : { opacity: 0, y: 20, scale: 0.98 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={reduceMotion ? { opacity: 0 } : { opacity: 0, y: -12, scale: 0.985 }}
            transition={reduceMotion ? { duration: 0 } : { duration: 0.48, ease: EASE }}
            className="relative z-10 flex min-h-dvh items-center justify-center overflow-y-auto px-5 pt-24 pb-[max(1.5rem,env(safe-area-inset-bottom))]"
          >
            <div className="w-full max-w-[420px]">
              <div className="relative overflow-hidden rounded-[2.1rem] border border-white/12 bg-[#0b0e14]/82 p-6 shadow-2xl backdrop-blur-2xl sm:p-8">
                <div className="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-cyan-100/55 to-transparent" />
                <div className="flex items-center gap-3">
                  <span className="grid h-11 w-11 shrink-0 place-items-center rounded-2xl border border-white/10 bg-white/5"><span className="h-2.5 w-2.5 rounded-full bg-emerald-300 shadow-[0_0_20px_rgba(110,231,183,.7)]" /></span>
                  <div>
                    <p className="font-mono text-[8px] font-bold tracking-[0.24em] text-cyan-100/50 uppercase">{copy.access}</p>
                    <h1 className="mt-1 text-2xl font-semibold tracking-[-0.04em]">{copy.title}</h1>
                  </div>
                </div>
                <p className="mt-4 text-xs leading-relaxed text-white/42">{copy.authenticate}</p>

                <form onSubmit={(event) => void submit(event)} className="mt-6 space-y-3.5">
                  <label className="block">
                    <span className="mb-2 block font-mono text-[8px] font-semibold tracking-[0.2em] text-white/38 uppercase">{copy.email}</span>
                    <input className={input} type="email" inputMode="email" autoCapitalize="none" autoComplete="username" placeholder="you@example.com" value={email} onChange={(event) => setEmail(event.target.value)} required autoFocus />
                  </label>
                  <label className="block">
                    <span className="mb-2 block font-mono text-[8px] font-semibold tracking-[0.2em] text-white/38 uppercase">{copy.password}</span>
                    <span className="relative block">
                      <input className={`${input} pr-16`} type={showPassword ? 'text' : 'password'} autoComplete="current-password" placeholder={copy.passwordPlaceholder} value={password} onChange={(event) => setPassword(event.target.value)} required />
                      <button type="button" onClick={() => setShowPassword((current) => !current)} className="absolute inset-y-0 right-0 px-4 text-[10px] font-bold text-white/40 transition hover:text-white/75" aria-label={showPassword ? copy.hide : copy.show}>{showPassword ? copy.hide.toUpperCase() : copy.show.toUpperCase()}</button>
                    </span>
                  </label>

                  {error && <motion.p initial={reduceMotion ? false : { opacity: 0, y: -4 }} animate={{ opacity: 1, y: 0 }} role="alert" className="rounded-xl border border-red-400/15 bg-red-400/8 px-3 py-2.5 text-xs leading-relaxed font-semibold text-red-200">{error}</motion.p>}

                  <motion.button type="submit" disabled={busy} whileTap={reduceMotion ? undefined : { scale: 0.98 }} className="entry-login-button mt-1 flex w-full items-center justify-center rounded-2xl px-5 py-3.5 text-sm font-black text-[#06080b] disabled:opacity-55">
                    {busy ? copy.verifying : copy.unlock}
                  </motion.button>
                </form>

                <div className="mt-5 flex items-center justify-between border-t border-white/8 pt-4">
                  <button type="button" onClick={onBack} className="text-xs font-semibold text-white/40 transition hover:text-white/75">{copy.back}</button>
                  <span className="flex items-center gap-1.5 font-mono text-[8px] tracking-[0.16em] text-emerald-200/55 uppercase"><span className="h-1.5 w-1.5 rounded-full bg-emerald-300" /> {copy.private}</span>
                </div>
              </div>
              <p className="mx-auto mt-4 max-w-xs text-center text-[10px] leading-relaxed text-white/25">{copy.credentials}</p>
            </div>
          </motion.main>
        ) : (
          <motion.main
            key={`identity-reveal-${persona.slug}`}
            data-testid="authenticated-persona-reveal"
            role="status"
            aria-live="polite"
            initial={reduceMotion ? false : { opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={reduceMotion ? { duration: 0 } : { duration: 0.35 }}
            className="relative z-10 flex min-h-dvh flex-col items-center justify-center overflow-hidden px-5 pt-20 pb-[max(1.5rem,env(safe-area-inset-bottom))] text-center"
          >
            <div className="entry-reveal-stage" style={{ '--entry-halo': persona.halo, '--entry-color': persona.color } as CSSProperties}>
              <span className="entry-reveal-aura" aria-hidden />
              <motion.span className="entry-reveal-ring entry-reveal-ring-one" aria-hidden animate={reduceMotion ? undefined : { rotate: 360 }} transition={{ duration: 18, repeat: Infinity, ease: 'linear' }} />
              <motion.span className="entry-reveal-ring entry-reveal-ring-two" aria-hidden animate={reduceMotion ? undefined : { rotate: -360 }} transition={{ duration: 24, repeat: Infinity, ease: 'linear' }} />
              <motion.img
                src={persona.portrait}
                alt=""
                draggable={false}
                initial={reduceMotion ? false : { opacity: 0, y: 38, scale: 0.86, filter: 'blur(16px) saturate(.7)' }}
                animate={{ opacity: 1, y: 0, scale: 1, filter: 'blur(0px) saturate(1.08)' }}
                transition={reduceMotion ? { duration: 0 } : { duration: 0.9, delay: 0.1, ease: EASE }}
                className="entry-reveal-portrait"
              />
            </div>
            <motion.div initial={reduceMotion ? false : { opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={reduceMotion ? { duration: 0 } : { duration: 0.5, delay: 0.62, ease: EASE }} className="relative z-20 -mt-5">
              <p className="font-mono text-[9px] font-black tracking-[0.28em] uppercase" style={{ color: persona.colorSoft }}>{copy.verified}</p>
              <h1 className="mt-2 text-[clamp(2.2rem,10vw,4.8rem)] leading-none font-semibold tracking-[-0.065em]">{copy.welcome(persona.firstName)}</h1>
              <p className="mt-3 text-sm font-semibold text-white/48">{copy.ready}</p>
            </motion.div>
          </motion.main>
        )}
      </AnimatePresence>
    </div>
  )
}
