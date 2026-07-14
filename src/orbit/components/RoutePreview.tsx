import type { GeoPoint } from '../domain/types.ts'
import { routePreviewGeometry } from '../domain/routePresentation.ts'
import { useOrbitText } from '../ui/i18n.ts'

export function RoutePreview({ points, name }: { points: GeoPoint[]; name: string }) {
  const t = useOrbitText()
  const geometry = routePreviewGeometry(points)
  return (
    <div className="orbit-route-preview relative overflow-hidden rounded-[22px] bg-[#06101e]" role="img" aria-label={`${t('Route preview')}: ${name}`}>
      <div className="orbit-stars pointer-events-none absolute inset-0 opacity-35" aria-hidden />
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_72%_18%,rgba(56,189,248,.16),transparent_42%)]" aria-hidden />
      {geometry ? (
        <svg viewBox="0 0 320 150" className="relative h-[150px] w-full" aria-hidden>
          <defs>
            <linearGradient id={`route-${name.replaceAll(/[^a-zA-Z0-9]/g, '')}`} x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stopColor="#67e8f9" />
              <stop offset="1" stopColor="#818cf8" />
            </linearGradient>
          </defs>
          <path d={geometry.path} fill="none" stroke="#020617" strokeWidth="11" strokeLinecap="round" strokeLinejoin="round" opacity=".88" />
          <path d={geometry.path} fill="none" stroke="#38bdf8" strokeWidth="8" strokeLinecap="round" strokeLinejoin="round" opacity=".2" />
          <path d={geometry.path} fill="none" stroke={`url(#route-${name.replaceAll(/[^a-zA-Z0-9]/g, '')})`} strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" />
          {geometry.closed ? (
            <g transform={`translate(${geometry.start.x} ${geometry.start.y})`}>
              <circle r="8" fill="#f8fafc" stroke="#0f172a" strokeWidth="2" />
              <circle r="3.5" fill="#22d3ee" />
            </g>
          ) : (
            <>
              <circle cx={geometry.start.x} cy={geometry.start.y} r="7" fill="#34d399" stroke="#fff" strokeWidth="2.5" />
              <circle cx={geometry.finish.x} cy={geometry.finish.y} r="7" fill="#fbbf24" stroke="#fff" strokeWidth="2.5" />
            </>
          )}
        </svg>
      ) : (
        <div className="relative grid h-[150px] place-items-center px-6 text-center text-xs font-semibold text-slate-400">{t('Route preview unavailable')}</div>
      )}
      <div className="pointer-events-none absolute top-3 left-3 rounded-full border border-white/10 bg-slate-950/80 px-2.5 py-1.5 font-mono text-[8px] font-bold tracking-[.15em] text-sky-200">{t('PRIVATE ROUTE')}</div>
      {geometry && <div className="pointer-events-none absolute right-3 bottom-3 rounded-full bg-slate-950/75 px-2.5 py-1.5 font-mono text-[8px] font-bold text-slate-300">{geometry.pointCount} {t('POINTS')}</div>}
    </div>
  )
}
