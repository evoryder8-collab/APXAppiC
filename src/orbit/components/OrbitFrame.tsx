import type { ReactNode } from 'react'
import { Link, useLocation } from 'react-router-dom'
import { ChevronLeftIcon, OrbitIcon } from '../../components/Icons.tsx'
import { useOrbitText } from '../ui/i18n.ts'

type NavIcon = 'today' | 'plan' | 'progress' | 'campaign'

function NavigationIcon({ icon }: { icon: NavIcon }) {
  if (icon === 'today') return <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden><circle cx="12" cy="12" r="7" fill="none" stroke="currentColor" strokeWidth="1.8"/><circle cx="12" cy="12" r="2.3" fill="currentColor"/><path d="M12 2v2M12 20v2M2 12h2M20 12h2" stroke="currentColor" strokeLinecap="round" strokeWidth="1.8"/></svg>
  if (icon === 'plan') return <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden><path d="M5 18c3-9 6 1 9-7 1.5-4 3.5-4 5-3" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="1.9"/><circle cx="5" cy="18" r="2" fill="none" stroke="currentColor" strokeWidth="1.7"/><circle cx="19" cy="8" r="2" fill="none" stroke="currentColor" strokeWidth="1.7"/></svg>
  if (icon === 'progress') return <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden><path d="M4 18V9M10 18V5M16 18v-7M22 18V3" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="2"/></svg>
  return <svg viewBox="0 0 24 24" className="h-5 w-5" aria-hidden><path d="M4 17c3-8 6-11 9-9s3 7 7 4" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="1.8"/><circle cx="4" cy="17" r="2" fill="currentColor"/><circle cx="13" cy="8" r="2" fill="currentColor"/><circle cx="20" cy="12" r="2" fill="currentColor"/></svg>
}

export function OrbitFrame({ title, subtitle, backTo = '/', children, action, hideNavigation = false }: {
  title: string
  subtitle?: string
  backTo?: string
  children: ReactNode
  action?: ReactNode
  hideNavigation?: boolean
}) {
  const t = useOrbitText()
  const location = useLocation()
  const distractionFree = hideNavigation || location.pathname === '/orbit/run' || location.pathname === '/orbit/induction'
  const items: Array<{ to: string; label: string; icon: NavIcon; active: boolean }> = [
    { to: '/orbit', label: 'Today', icon: 'today', active: location.pathname === '/orbit' || location.pathname === '/orbit/run' },
    { to: '/orbit/plan', label: 'Plan', icon: 'plan', active: location.pathname === '/orbit/plan' },
    { to: '/orbit/library', label: 'Progress', icon: 'progress', active: location.pathname.startsWith('/orbit/library') || location.pathname.startsWith('/orbit/debrief') },
    { to: '/orbit/campaign', label: 'Campaign', icon: 'campaign', active: location.pathname === '/orbit/campaign' || location.pathname === '/orbit/science' },
  ]
  return (
    <div className="mx-auto w-full max-w-5xl">
      <header className="orbit-header relative mb-3 overflow-hidden rounded-[28px] border border-sky-100/20 bg-[#07111f] px-4 py-4 text-white shadow-[0_22px_65px_-34px_rgba(14,165,233,.74)] sm:px-6 sm:py-5">
        <div className="orbit-stars pointer-events-none absolute inset-0 opacity-60" aria-hidden />
        <div className="pointer-events-none absolute -top-20 right-[-5rem] h-56 w-56 rounded-full bg-sky-400/14 blur-3xl" aria-hidden />
        <div className="relative">
          <div className="flex items-center justify-between gap-3">
            <Link to={backTo} className="inline-flex min-h-10 items-center gap-1 rounded-full border border-white/10 bg-white/6 px-3 text-[11px] font-bold text-sky-100 active:scale-95">
              <ChevronLeftIcon className="h-4 w-4" /> {t('Back')}
            </Link>
            <div className="flex min-w-0 items-center gap-2 text-sky-200">
              <OrbitIcon className="h-5 w-5 shrink-0" />
              <p className="truncate font-mono text-[9px] font-bold tracking-[0.2em]">{t('APEX ORBIT')}</p>
            </div>
            <div className="flex min-w-12 justify-end">{action}</div>
          </div>
          <div className="mt-3">
            <h1 className="font-display text-[25px] leading-tight font-bold tracking-tight sm:text-3xl">{t(title)}</h1>
            {subtitle && <p className="mt-1 max-w-2xl text-xs font-medium leading-relaxed text-slate-300 sm:text-sm">{t(subtitle)}</p>}
          </div>
        </div>
      </header>
      {!distractionFree && (
        <nav aria-label={t('Orbit navigation')} className="glass mb-5 grid grid-cols-4 gap-1 rounded-[22px] border border-white/80 p-1.5 shadow-[0_14px_38px_-28px_rgba(15,23,42,.45)]">
          {items.map((item) => (
            <Link key={item.to} to={item.to} aria-current={item.active ? 'page' : undefined} className={`flex min-h-14 flex-col items-center justify-center gap-0.5 rounded-[17px] px-1 text-[10px] font-bold transition active:scale-[.97] ${item.active ? 'bg-[#07111f] text-sky-100 shadow-[0_10px_24px_-14px_rgba(2,6,23,.75)]' : 'text-ink-soft'}`}>
              <NavigationIcon icon={item.icon} />
              <span>{t(item.label)}</span>
            </Link>
          ))}
        </nav>
      )}
      {children}
    </div>
  )
}

export function OrbitPill({ children, tone = 'ice', contrast = false }: { children: ReactNode; tone?: 'ice' | 'amber' | 'emerald' | 'violet'; contrast?: boolean }) {
  const tones = {
    ice: 'border-sky-200/25 bg-sky-300/10 text-sky-100',
    amber: 'border-amber-200/25 bg-amber-300/10 text-amber-100',
    emerald: 'border-emerald-200/25 bg-emerald-300/10 text-emerald-100',
    violet: 'border-violet-200/25 bg-violet-300/10 text-violet-100',
  }
  const contrastTones = {
    ice: 'border-sky-300/80 bg-sky-100 text-sky-950 shadow-[0_8px_22px_-14px_rgba(2,132,199,.85)]',
    amber: 'border-amber-300/80 bg-amber-100 text-amber-950 shadow-[0_8px_22px_-14px_rgba(217,119,6,.8)]',
    emerald: 'border-emerald-300/80 bg-emerald-100 text-emerald-950 shadow-[0_8px_22px_-14px_rgba(5,150,105,.8)]',
    violet: 'border-violet-300/80 bg-violet-100 text-violet-950 shadow-[0_8px_22px_-14px_rgba(124,58,237,.8)]',
  }
  return <span className={`inline-flex rounded-full border px-3 py-1 font-mono text-[10px] font-black tracking-wide ${contrast ? contrastTones[tone] : tones[tone]}`}>{children}</span>
}
