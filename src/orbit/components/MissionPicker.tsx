import type { RunMission } from '../domain/types.ts'
import { RUN_MISSIONS } from '../domain/types.ts'
import { missionLabel } from '../domain/analysis.ts'
import { useOrbitText } from '../ui/i18n.ts'

const visible: RunMission[] = RUN_MISSIONS.filter((mission) => mission !== 'free_run')

export function MissionPicker({ value, onChange, compact = false }: { value: RunMission; onChange: (mission: RunMission) => void; compact?: boolean }) {
  const t = useOrbitText()
  return (
    <div className={`flex gap-2 overflow-x-auto pb-1 ${compact ? '' : 'sm:flex-wrap'}`} role="listbox" aria-label={t('Run mission')}>
      {visible.map((mission) => (
        <button
          key={mission}
          type="button"
          role="option"
          aria-selected={value === mission}
          onClick={() => onChange(mission)}
          className={`shrink-0 rounded-full border px-3 py-2 text-xs font-bold transition-all ${value === mission
            ? 'border-sky-300/60 bg-[#0b2940] text-white shadow-[0_8px_24px_-10px_rgba(56,189,248,.8)]'
            : 'border-white/75 bg-white/60 text-ink-soft'}`}
        >
          {t(missionLabel(mission))}
        </button>
      ))}
    </div>
  )
}
