import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { ChevronLeftIcon, OrbitIcon } from '../../components/Icons.tsx'
import { useOrbitText } from '../ui/i18n.ts'

export function OrbitFrame({ title, subtitle, backTo = '/', children, action }: {
  title: string
  subtitle?: string
  backTo?: string
  children: ReactNode
  action?: ReactNode
}) {
  const t = useOrbitText()
  return (
    <div className="mx-auto w-full max-w-4xl">
      <header className="orbit-header relative mb-5 overflow-hidden rounded-[30px] border border-sky-100/60 bg-[#07111f] px-5 py-5 text-white shadow-[0_24px_70px_-30px_rgba(14,165,233,.72)] sm:px-7 sm:py-6">
        <div className="orbit-stars pointer-events-none absolute inset-0 opacity-75" aria-hidden />
        <div className="pointer-events-none absolute -top-16 right-[-4rem] h-56 w-56 rounded-full bg-sky-400/15 blur-3xl" aria-hidden />
        <div className="relative">
          <div className="flex items-center justify-between gap-3">
            <Link to={backTo} className="inline-flex min-h-10 items-center gap-1 rounded-full border border-white/10 bg-white/5 px-3 text-xs font-bold text-sky-100 active:scale-95">
              <ChevronLeftIcon className="h-4 w-4" /> {t('Back')}
            </Link>
            {action}
          </div>
          <div className="mt-5 flex items-center gap-3">
            <div className="orbit-core flex h-12 w-12 items-center justify-center rounded-2xl border border-sky-200/20 bg-sky-300/10 text-sky-200">
              <OrbitIcon className="h-7 w-7" />
            </div>
            <div>
              <p className="font-mono text-[9px] font-bold tracking-[0.24em] text-sky-300/75">{t('APEX ORBIT')} · {t('RUN INTELLIGENCE')}</p>
              <h1 className="mt-0.5 font-display text-2xl leading-tight font-bold tracking-tight sm:text-3xl">{t(title)}</h1>
              {subtitle && <p className="mt-1 max-w-xl text-sm font-medium text-slate-300">{t(subtitle)}</p>}
            </div>
          </div>
        </div>
      </header>
      {children}
    </div>
  )
}

export function OrbitPill({ children, tone = 'ice' }: { children: ReactNode; tone?: 'ice' | 'amber' | 'emerald' | 'violet' }) {
  const tones = {
    ice: 'border-sky-200/25 bg-sky-300/10 text-sky-100',
    amber: 'border-amber-200/25 bg-amber-300/10 text-amber-100',
    emerald: 'border-emerald-200/25 bg-emerald-300/10 text-emerald-100',
    violet: 'border-violet-200/25 bg-violet-300/10 text-violet-100',
  }
  return <span className={`inline-flex rounded-full border px-3 py-1 font-mono text-[10px] font-bold tracking-wide ${tones[tone]}`}>{children}</span>
}
