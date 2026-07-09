import { Link } from 'react-router-dom'
import { ApexMark, SlidersIcon } from './Icons'

type SyncState = 'synced' | 'queued'

/* Phase 2 wires this to the real offline queue. */
const syncState: SyncState = 'synced'

export function TopBar() {
  const synced = syncState === 'synced'
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
            aria-label={synced ? 'Synced' : 'Changes queued, offline'}
            title={synced ? 'Synced' : 'Changes queued, offline'}
          >
            <span
              className="ping-soft absolute inset-0 rounded-full"
              style={{ background: synced ? '#10b981' : '#f59e0b' }}
            />
            <span
              className="relative h-2.5 w-2.5 rounded-full"
              style={{
                background: synced ? '#10b981' : '#f59e0b',
                boxShadow: synced
                  ? '0 0 10px rgba(16, 185, 129, 0.65)'
                  : '0 0 10px rgba(245, 158, 11, 0.65)',
              }}
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
