import { Link } from 'react-router-dom'
import { ApexMark, SlidersIcon } from './Icons'
import { useStore } from '../store/AppStore'

const DOT_COLORS = {
  synced: { color: '#10b981', label: 'Synced' },
  queued: { color: '#f59e0b', label: 'Changes queued, waiting for connection' },
  local: { color: '#38bdf8', label: 'Local mode, add Supabase keys to sync' },
} as const

export function TopBar() {
  const { syncStatus } = useStore()
  const dot = DOT_COLORS[syncStatus]
  return (
    <header className="fixed inset-x-0 top-0 z-40 px-4 pt-[max(0.75rem,env(safe-area-inset-top))]">
      <div className="glass mx-auto flex h-13 max-w-3xl items-center justify-between rounded-full px-4">
        <Link to="/" className="flex items-center gap-2" aria-label="APEX home">
          <ApexMark className="h-6 w-6" />
          <span className="font-display text-[15px] font-bold tracking-[0.22em] text-ink">
            APEX
          </span>
        </Link>

        <div className="flex items-center gap-4">
          <div
            className="relative flex h-2.5 w-2.5 items-center justify-center"
            role="status"
            aria-label={dot.label}
            title={dot.label}
          >
            <span className="ping-soft absolute inset-0 rounded-full" style={{ background: dot.color }} />
            <span
              className="relative h-2.5 w-2.5 rounded-full"
              style={{ background: dot.color, boxShadow: `0 0 10px ${dot.color}aa` }}
            />
          </div>

          <Link
            to="/settings"
            className="flex h-9 w-9 items-center justify-center rounded-full text-ink-soft transition-colors hover:bg-white/70 hover:text-ink active:scale-95"
            aria-label="Settings"
          >
            <SlidersIcon className="h-[18px] w-[18px]" />
          </Link>
        </div>
      </div>
    </header>
  )
}
