import { useState, type FormEvent } from 'react'
import { motion } from 'framer-motion'
import { ApexMark } from '../components/Icons'
import { EASE } from '../components/ui'
import { personaBySlug, type PersonaSlug } from '../lib/persona'
import { getIntroLanguage, localizedLoginError, LOGIN_COPY } from '../lib/introLanguage'
import { useStore } from '../store/AppStore'

export function Login({
  persona: personaSlug,
  onBack,
  onSuccess,
}: {
  persona: PersonaSlug
  onBack: () => void
  onSuccess: () => void
}) {
  const { signIn } = useStore()
  const persona = personaBySlug(personaSlug)
  const language = getIntroLanguage()
  const copy = LOGIN_COPY[language]
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const submit = async (event: FormEvent): Promise<void> => {
    event.preventDefault()
    setBusy(true)
    setError(null)
    const signInError = await signIn(email.trim(), password)
    if (signInError) setError(localizedLoginError(signInError, language))
    else onSuccess()
    setBusy(false)
  }

  const input =
    'w-full rounded-2xl border border-white/10 bg-white/[0.055] px-4 py-3.5 text-[15px] font-medium text-white outline-none transition placeholder:text-white/25 focus:border-white/30 focus:bg-white/[0.075]'

  return (
    <div className="fixed inset-0 z-[70] min-h-dvh overflow-hidden bg-[#05070b] text-white">
      <div className="intro-aurora absolute inset-0" aria-hidden />
      <div className="intro-grid absolute inset-0" aria-hidden />
      <div className="intro-vignette absolute inset-0" aria-hidden />
      <div
        className="absolute top-[12%] left-1/2 h-[42vh] w-[42vh] -translate-x-1/2 rounded-full opacity-35 blur-[90px]"
        style={{ background: persona.halo }}
        aria-hidden
      />

      <motion.header
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        className="absolute inset-x-0 top-0 z-30 flex items-center justify-between px-5 pt-[max(1.25rem,env(safe-area-inset-top))] sm:px-10"
      >
        <div className="flex items-center gap-3">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl border border-white/12 bg-white/7 backdrop-blur-xl">
            <ApexMark className="h-5 w-5" />
          </span>
          <p className="text-[13px] font-bold tracking-[0.3em]">APEX</p>
        </div>
        <p className="font-mono text-[8px] tracking-[0.2em] text-white/34 uppercase">{copy.encrypted}</p>
      </motion.header>

      <div className="relative z-10 flex min-h-dvh items-center justify-center overflow-y-auto px-5 pt-24 pb-[max(1.5rem,env(safe-area-inset-bottom))]">
        <motion.div
          initial={{ opacity: 0, y: 24, scale: 0.97 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          transition={{ duration: 0.62, ease: EASE }}
          className="w-full max-w-[420px]"
        >
          <div className="relative overflow-hidden rounded-[2.1rem] border border-white/12 bg-[#0b0e14]/78 p-6 shadow-2xl backdrop-blur-2xl sm:p-8" style={{ boxShadow: `0 38px 100px -38px ${persona.halo}` }}>
            <div className="pointer-events-none absolute inset-x-0 top-0 h-px" style={{ background: `linear-gradient(90deg, transparent, ${persona.colorSoft}, transparent)` }} />
            <div className="flex items-center gap-4">
              <div className="relative h-[76px] w-[76px] shrink-0 overflow-hidden rounded-[1.35rem] border border-white/12 bg-white/5">
                <div className="absolute inset-0 opacity-50 blur-xl" style={{ background: persona.halo }} />
                <img src={persona.portrait} alt={`${persona.name} portrait`} className="relative h-full w-full scale-125 object-contain object-bottom" />
              </div>
              <div className="min-w-0">
                <p className="font-mono text-[8px] font-bold tracking-[0.24em] uppercase" style={{ color: persona.colorSoft }}>
                  {persona.title}
                </p>
                <h1 className="mt-1 truncate text-2xl font-semibold tracking-[-0.04em]">{copy.welcome(persona.firstName)}</h1>
                <p className="mt-1 text-xs text-white/42">{copy.authenticate}</p>
              </div>
            </div>

            <form onSubmit={(event) => void submit(event)} className="mt-7 space-y-3.5">
              <label className="block">
                <span className="mb-2 block font-mono text-[8px] font-semibold tracking-[0.2em] text-white/38 uppercase">{copy.email}</span>
                <input
                  className={input}
                  type="email"
                  inputMode="email"
                  autoCapitalize="none"
                  autoComplete="username"
                  placeholder="you@example.com"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  required
                  autoFocus
                />
              </label>
              <label className="block">
                <span className="mb-2 block font-mono text-[8px] font-semibold tracking-[0.2em] text-white/38 uppercase">{copy.password}</span>
                <span className="relative block">
                  <input
                    className={`${input} pr-16`}
                    type={showPassword ? 'text' : 'password'}
                    autoComplete="current-password"
                    placeholder={copy.passwordPlaceholder}
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                    required
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword((current) => !current)}
                    className="absolute inset-y-0 right-0 px-4 text-[10px] font-bold text-white/40 transition hover:text-white/75"
                    aria-label={showPassword ? copy.hide : copy.show}
                  >
                    {showPassword ? copy.hide.toUpperCase() : copy.show.toUpperCase()}
                  </button>
                </span>
              </label>

              {error && (
                <motion.p initial={{ opacity: 0, y: -4 }} animate={{ opacity: 1, y: 0 }} role="alert" className="rounded-xl border border-red-400/15 bg-red-400/8 px-3 py-2.5 text-xs leading-relaxed font-semibold text-red-200">
                  {error}
                </motion.p>
              )}

              <motion.button
                type="submit"
                disabled={busy}
                whileTap={{ scale: 0.98 }}
                className="mt-1 flex w-full items-center justify-center rounded-2xl px-5 py-3.5 text-sm font-bold text-[#06080b] disabled:opacity-55"
                style={{ background: persona.gradient, boxShadow: `0 15px 42px -15px ${persona.halo}` }}
              >
                {busy ? copy.verifying : copy.unlock(persona.firstName)}
              </motion.button>
            </form>

            <div className="mt-5 flex items-center justify-between border-t border-white/8 pt-4">
              <button type="button" onClick={onBack} className="text-xs font-semibold text-white/40 transition hover:text-white/75">
                {copy.back}
              </button>
              <span className="flex items-center gap-1.5 font-mono text-[8px] tracking-[0.16em] text-emerald-200/55 uppercase">
                <span className="h-1.5 w-1.5 rounded-full bg-emerald-300" /> {copy.private}
              </span>
            </div>
          </div>

          <p className="mx-auto mt-4 max-w-xs text-center text-[10px] leading-relaxed text-white/25">
            {copy.credentials}
          </p>
        </motion.div>
      </div>
    </div>
  )
}
