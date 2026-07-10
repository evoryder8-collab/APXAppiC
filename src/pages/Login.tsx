import { useState, type FormEvent } from 'react'
import { motion } from 'framer-motion'
import { GlassCard, GradientButton, EASE } from '../components/ui'
import { ACCENTS } from '../lib/theme'
import { ApexMark } from '../components/Icons'
import { useStore } from '../store/AppStore'

export function Login() {
  const { signIn } = useStore()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const submit = async (e: FormEvent): Promise<void> => {
    e.preventDefault()
    setBusy(true)
    setError(null)
    const err = await signIn(email.trim(), password)
    if (err) setError(err)
    setBusy(false)
  }

  const input =
    'w-full rounded-2xl border border-ink/10 bg-white/70 px-4 py-3 font-medium text-ink outline-none backdrop-blur-sm placeholder:text-ink-faint focus:border-violet/50'

  return (
    <div className="flex min-h-dvh items-center justify-center px-5">
      <motion.div
        initial={{ opacity: 0, y: 22 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.55, ease: EASE }}
        className="w-full max-w-sm"
      >
        <GlassCard accent={ACCENTS.violet} breathe className="p-7">
          <div className="mb-6 flex items-center gap-3">
            <ApexMark className="h-9 w-9" />
            <div>
              <p className="font-display text-xl font-bold tracking-[0.18em] text-ink">APEX</p>
              <p className="text-xs font-medium text-ink-soft">Personal performance system</p>
            </div>
          </div>
          <form onSubmit={(e) => void submit(e)} className="space-y-3">
            <input
              className={input}
              type="email"
              autoComplete="email"
              placeholder="Email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
            <input
              className={input}
              type="password"
              autoComplete="current-password"
              placeholder="Password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
            {error && <p className="text-sm font-semibold text-crimson">{error}</p>}
            <GradientButton accent={ACCENTS.violet} type="submit" disabled={busy} className="w-full">
              {busy ? 'Signing in' : 'Enter'}
            </GradientButton>
          </form>
          <p className="mt-4 text-center text-xs font-medium text-ink-faint">
            Single account. Create it once in the Supabase dashboard.
          </p>
        </GlassCard>
      </motion.div>
    </div>
  )
}
