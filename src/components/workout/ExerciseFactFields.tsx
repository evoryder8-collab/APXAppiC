import { useEffect, useId, useState } from 'react'
import type { ExerciseLoggingDescriptor, ExerciseLoggingField } from '../../lib/exerciseLogging'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import type { SetEntry } from '../../lib/workoutSession'

const FACTS: Record<ExerciseLoggingField, {
  label: string
  key: keyof SetEntry
  integer: boolean
}> = {
  reps: { label: 'Reps', key: 'reps', integer: true },
  signedLoad: { label: 'Load kg (+/−)', key: 'weight', integer: false },
  rir: { label: 'RIR', key: 'rir', integer: true },
  duration: { label: 'Time sec', key: 'durationSeconds', integer: true },
  distance: { label: 'Distance m', key: 'distanceMeters', integer: false },
  contacts: { label: 'Contacts', key: 'contacts', integer: true },
  completion: { label: 'Completed', key: 'reps', integer: true },
  rounds: { label: 'Rounds', key: 'rounds', integer: true },
  work: { label: 'Work sec', key: 'workSeconds', integer: true },
  recovery: { label: 'Recovery sec', key: 'recoverySeconds', integer: true },
}

function FactNumberInput({
  label,
  value,
  integer,
  allowNegative,
  max,
  disabled,
  onChange,
  onCommit,
}: {
  label: string
  value: number | null | undefined
  integer: boolean
  allowNegative: boolean
  max?: number
  disabled: boolean
  onChange: (value: number | null) => void
  onCommit?: () => void
}) {
  const inputId = useId()
  const [text, setText] = useState(value == null ? '' : String(value))
  const [focused, setFocused] = useState(false)

  useEffect(() => {
    if (!focused) setText(value == null ? '' : String(value))
  }, [focused, value])

  const update = (raw: string) => {
    setText(raw)
    if (raw === '') {
      onChange(null)
      return
    }
    if (raw === '-' || raw === '.' || raw === '-.') return
    const parsed = Number(raw)
    if (!Number.isFinite(parsed) || (!allowNegative && parsed < 0)) return
    const normalized = integer ? Math.round(parsed) : parsed
    onChange(max == null ? normalized : Math.min(max, normalized))
  }

  return (
    <div className="min-w-0">
      <label htmlFor={inputId} className="mb-1 block truncate text-center font-mono text-[8px] font-black uppercase text-ink-faint">{label}</label>
      <span className="relative block">
        <input
          id={inputId}
          aria-label={label}
          type="text"
          inputMode="decimal"
          pattern={allowNegative ? '-?[0-9]*[.,]?[0-9]*' : '[0-9]*[.,]?[0-9]*'}
          disabled={disabled}
          value={text}
          onFocus={() => setFocused(true)}
          onBlur={() => {
            setFocused(false)
            if (text === '-' || text === '.' || text === '-.') setText(value == null ? '' : String(value))
            onCommit?.()
          }}
          onKeyDown={(event) => { if (event.key === 'Enter') event.currentTarget.blur() }}
          onChange={(event) => update(event.target.value.replace(',', '.'))}
          className={`w-full rounded-xl bg-slate-50 px-2 py-2.5 text-center font-mono text-sm font-black text-ink outline-none focus:ring-2 focus:ring-cyan-200 disabled:opacity-40 ${allowNegative ? 'pr-9' : ''}`}
        />
        {allowNegative && (
          <button
            type="button"
            aria-label={`${label} (+/−)`}
            disabled={disabled}
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => update(String(-(Number(text) || 0)))}
            className="absolute inset-y-1 right-1 grid w-7 place-items-center rounded-lg bg-cyan-100 font-mono text-xs font-black text-cyan-900"
          >±</button>
        )}
      </span>
    </div>
  )
}

export function ExerciseFactFields({
  descriptor,
  value,
  onChange,
  disabled = false,
  onCommit,
}: {
  descriptor: ExerciseLoggingDescriptor
  value: SetEntry
  onChange: (patch: Partial<SetEntry>) => void
  disabled?: boolean
  onCommit?: () => void
}) {
  const { language } = useLanguage()
  const t = (text: string): string => translateInterfaceText(text, language)

  if (!descriptor.supported) {
    return (
      <p className="rounded-xl bg-amber-50 px-3 py-2 text-xs font-semibold text-amber-900">
        {t('Grouped rounds will arrive with supersets. This sequence cannot be logged as an ordinary set.')}
      </p>
    )
  }

  const carryDose = value.durationSeconds != null && value.distanceMeters == null ? 'duration' : 'distance'
  const editable = descriptor.fields.filter((field) => {
    if (field === 'completion') return false
    if (descriptor.kind !== 'carry') return true
    if (field === 'duration') return carryDose === 'duration'
    if (field === 'distance') return carryDose === 'distance'
    return true
  })
  return (
    <div>
      {descriptor.kind === 'carry' && (
        <div className="mb-2 grid grid-cols-2 rounded-xl bg-slate-100 p-1" aria-label={t('Carry target')}>
          {(['distance', 'duration'] as const).map((dose) => (
            <button
              key={dose}
              type="button"
              disabled={disabled}
              aria-pressed={carryDose === dose}
              onClick={() => onChange(dose === 'distance'
                ? { durationSeconds: null }
                : { distanceMeters: null })}
              className={`rounded-lg px-2 py-1.5 text-[10px] font-black ${carryDose === dose ? 'bg-white text-cyan-900 shadow-sm' : 'text-ink-faint'}`}
            >
              {t(dose === 'distance' ? 'Distance' : 'Time')}
            </button>
          ))}
        </div>
      )}
      {editable.length > 0 && (
        <div className={`grid gap-2 ${editable.length >= 3 ? 'grid-cols-3' : 'grid-cols-2'}`}>
          {editable.map((field) => {
            const fact = FACTS[field]
            return <FactNumberInput
              key={field}
              label={t(fact.label)}
              value={value[fact.key] as number | null | undefined}
              integer={fact.integer}
              allowNegative={field === 'signedLoad'}
              max={field === 'rir' ? 5 : undefined}
              disabled={disabled}
              onChange={(next) => onChange({ [fact.key]: next })}
              onCommit={onCommit}
            />
          })}
        </div>
      )}
      {descriptor.fields.includes('signedLoad') && (
        <p className="mt-1 text-[9px] font-semibold text-ink-faint">
          {t('Negative load means supported; zero means bodyweight; positive means added load.')}
        </p>
      )}
      {descriptor.fields.includes('completion') && (
        <p className="rounded-xl bg-emerald-50 px-3 py-2 text-xs font-semibold text-emerald-800">
          {t('Saving records this movement as completed. Time is optional.')}
        </p>
      )}
    </div>
  )
}
