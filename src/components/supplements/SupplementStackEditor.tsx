import { useMemo, useState } from 'react'
import { formatSupplementDose, searchSupplementCatalogue, type SupplementEntry } from '../../data/supplementCatalogue'
import type { Supplement } from '../../lib/types'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { useStore } from '../../store/AppStore'

interface SupplementStackEditorProps {
  date: string
  compact?: boolean
}

function ageFromBirthdate(value: string | null | undefined): number {
  if (!value) return 0
  const birthdate = new Date(`${value.slice(0, 10)}T12:00:00`)
  if (Number.isNaN(birthdate.getTime())) return 0
  const now = new Date()
  let age = now.getFullYear() - birthdate.getFullYear()
  const beforeBirthday = now.getMonth() < birthdate.getMonth()
    || (now.getMonth() === birthdate.getMonth() && now.getDate() < birthdate.getDate())
  if (beforeBirthday) age -= 1
  return Math.max(0, age)
}

function evidenceLabel(entry: SupplementEntry): string {
  if (entry.evidence === 'strong') return 'Strong evidence'
  if (entry.evidence === 'moderate') return 'Moderate evidence'
  if (entry.evidence === 'limited') return 'Limited evidence'
  return 'Not supported by evidence'
}

export function SupplementStackEditor({ date, compact = false }: SupplementStackEditorProps) {
  const { data, upsert, remove, toast } = useStore()
  const { language } = useLanguage()
  const t = (value: string): string => translateInterfaceText(value, language)
  const [showPicker, setShowPicker] = useState(false)
  const [query, setQuery] = useState('')
  const [openInfo, setOpenInfo] = useState<string | null>(null)
  const [pendingArchive, setPendingArchive] = useState<Supplement | null>(null)

  const activeSupplements = useMemo(
    () => data.supplements
      .filter((supplement) => supplement.archived !== true)
      .sort((left, right) => left.sort_order - right.sort_order),
    [data.supplements],
  )
  const doneIDs = useMemo(
    () => new Set(data.supplement_logs.filter((log) => log.date === date).map((log) => log.supplement_id)),
    [data.supplement_logs, date],
  )
  const groups = useMemo(() => {
    const grouped = new Map<string, Supplement[]>()
    for (const supplement of activeSupplements) {
      const label = supplement.group_label.trim() || 'Supplements'
      grouped.set(label, [...(grouped.get(label) ?? []), supplement])
    }
    return [...grouped.entries()]
  }, [activeSupplements])
  const age = ageFromBirthdate(data.profile?.birthdate)
  const results = useMemo(() => searchSupplementCatalogue(query, age), [age, query])

  const toggle = (supplement: Supplement): void => {
    const existing = data.supplement_logs.find((log) => log.date === date && log.supplement_id === supplement.id)
    if (existing) {
      remove('supplement_logs', existing.id)
      return
    }
    upsert('supplement_logs', {
      id: crypto.randomUUID(),
      user_id: data.profile?.user_id ?? '',
      date,
      supplement_id: supplement.id,
      checked_at: new Date().toISOString(),
    })
  }

  const add = (entry: SupplementEntry, dose: number): void => {
    const existing = data.supplements.find((supplement) => supplement.name.toLocaleLowerCase() === entry.name.toLocaleLowerCase())
    const formattedDose = formatSupplementDose(entry, dose)
    if (existing) {
      upsert('supplements', {
        ...existing,
        dose: formattedDose,
        group_label: entry.timing,
        archived: false,
      })
      toast(`${entry.name} ${t('updated')}`, 'ok')
    } else {
      upsert('supplements', {
        id: crypto.randomUUID(),
        user_id: data.profile?.user_id ?? '',
        name: entry.name,
        dose: formattedDose,
        timing: 'training' as const,
        clock_time: null,
        offset_min: 0,
        group_label: entry.timing,
        training_days_only: false,
        sort_order: (data.supplements.reduce((highest, supplement) => Math.max(highest, supplement.sort_order), 0)) + 1,
        archived: false,
      })
      toast(`${entry.name} ${t('added')}`, 'ok')
    }
    setShowPicker(false)
    setQuery('')
    setOpenInfo(null)
  }

  const pickerRows = (entries: SupplementEntry[]) => entries.map((entry) => (
    <article key={entry.id} className="rounded-2xl border border-violet-100 bg-white/85 p-3 shadow-sm">
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <p className="whitespace-normal break-words text-sm font-black leading-snug text-ink">{t(entry.name)}</p>
          <p className="mt-0.5 text-[10px] font-bold text-ink-faint">{t(entry.category)} · {t(evidenceLabel(entry))}</p>
        </div>
        <button
          type="button"
          onClick={() => setOpenInfo((current) => current === entry.id ? null : entry.id)}
          aria-label={`${t('About')} ${t(entry.name)}`}
          className="grid h-8 w-8 shrink-0 place-items-center rounded-full bg-violet-50 text-xs font-black text-violet-700"
        >i</button>
      </div>
      {openInfo === entry.id && (
        <div className="mt-2 rounded-xl bg-slate-50 px-3 py-2 text-xs font-medium leading-relaxed text-ink-soft">
          <p>{t(entry.summary)}</p>
          {entry.youthNote && <p className="mt-1 font-bold text-amber-800">{t(entry.youthNote)}</p>}
          {entry.femaleWarning && <p className="mt-1 font-bold text-rose-700">{t(entry.femaleWarning)}</p>}
        </div>
      )}
      <div className="mt-2 flex flex-wrap gap-2">
        {entry.doses.slice(0, 3).map((dose) => (
          <button
            key={dose}
            type="button"
            onClick={() => add(entry, dose)}
            className="rounded-full bg-violet-100 px-3 py-1.5 font-mono text-[11px] font-black text-violet-900 active:scale-95"
          >+ {formatSupplementDose(entry, dose)}</button>
        ))}
      </div>
    </article>
  ))

  return (
    <div className="min-w-0">
      <div className={`space-y-3 overflow-y-auto pr-0.5 ${compact ? 'max-h-[46vh]' : 'max-h-[34rem]'}`}>
        {groups.map(([label, supplements]) => (
          <section key={label} className="min-w-0">
            <p className="mb-1.5 px-1 text-[9px] font-black tracking-widest text-ink-faint uppercase">{t(label)}</p>
            <div className="space-y-1.5">
              {supplements.map((supplement) => {
                const done = doneIDs.has(supplement.id)
                return (
                  <div key={supplement.id} className="flex min-w-0 items-stretch gap-2 rounded-2xl bg-white/70 p-1.5 shadow-sm">
                    <button
                      type="button"
                      onClick={() => toggle(supplement)}
                      aria-pressed={done}
                      className="flex min-w-0 flex-1 items-center gap-2 rounded-xl px-2 py-2 text-left active:scale-[.99]"
                    >
                      <span className={`grid h-7 w-7 shrink-0 place-items-center rounded-full text-[10px] font-black ${done ? 'bg-emerald text-white' : 'border border-violet-200 bg-white text-transparent'}`}>✓</span>
                      <span className="min-w-0 flex-1">
                        <span className={`block whitespace-normal break-words text-xs font-black leading-snug ${done ? 'text-ink-soft' : 'text-ink'}`}>{t(supplement.name)}</span>
                        <span className="mt-0.5 block whitespace-normal break-words font-mono text-[9px] font-semibold leading-snug text-ink-faint">{t(supplement.dose)}</span>
                      </span>
                    </button>
                    <button
                      type="button"
                      onClick={() => setPendingArchive(supplement)}
                      aria-label={`${t('Remove')} ${t(supplement.name)}`}
                      className="grid w-9 shrink-0 place-items-center rounded-xl bg-rose-50 text-sm font-black text-rose-600"
                    >×</button>
                  </div>
                )
              })}
            </div>
          </section>
        ))}
        {activeSupplements.length === 0 && (
          <p className="rounded-2xl bg-white/70 px-4 py-5 text-center text-xs font-semibold text-ink-soft">{t('No supplements in your stack yet.')}</p>
        )}
      </div>

      <button type="button" onClick={() => setShowPicker(true)} className="mt-3 w-full rounded-2xl bg-violet-100/90 px-3 py-3 text-xs font-black text-violet-900">+ {t('Add supplement')}</button>

      {showPicker && (
        <div className="fixed inset-0 z-[120] flex items-end justify-center bg-black/30 p-3 sm:items-center" role="dialog" aria-modal="true" aria-label={t('Add supplement')}>
          <div className="flex max-h-[88vh] w-full max-w-lg flex-col overflow-hidden rounded-[2rem] border border-white/80 bg-[#f7f7fb] p-4 shadow-2xl">
            <div className="flex items-center gap-3">
              <div className="min-w-0 flex-1"><p className="text-lg font-black text-ink">{t('Add supplement')}</p><p className="text-[10px] font-semibold text-ink-soft">{t('Choose the amount printed on your product.')}</p></div>
              <button type="button" onClick={() => setShowPicker(false)} className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-white text-lg font-black text-ink">×</button>
            </div>
            <input value={query} onChange={(event) => setQuery(event.target.value)} autoFocus placeholder={t('Search supplements')} className="mt-3 w-full rounded-2xl border border-violet-100 bg-white px-4 py-3 text-sm font-bold text-ink outline-none focus:border-violet-400" />
            <div className="mt-3 min-h-0 flex-1 space-y-2 overflow-y-auto pr-1">
              {!query.trim() && results.length >= 2 ? (
                <>
                  <p className="px-1 text-[9px] font-black tracking-widest text-emerald-700 uppercase">{t('Core evidence')}</p>
                  {pickerRows(results.slice(0, 2))}
                  <div className="my-3 border-t border-violet-200" />
                  <p className="px-1 text-[9px] font-black tracking-widest text-ink-faint uppercase">{t('A to Z catalogue')}</p>
                  {pickerRows(results.slice(2))}
                </>
              ) : pickerRows(results)}
              {results.length === 0 && <p className="py-8 text-center text-sm font-bold text-ink-soft">{t('No matching supplements')}</p>}
            </div>
          </div>
        </div>
      )}

      {pendingArchive && (
        <div className="fixed inset-0 z-[130] grid place-items-center bg-black/30 p-5" role="alertdialog" aria-modal="true" aria-label={t('Remove from your plan?')}>
          <div className="w-full max-w-sm rounded-[1.75rem] bg-white p-5 shadow-2xl">
            <p className="text-lg font-black text-ink">{t('Remove from your plan?')}</p>
            <p className="mt-2 text-xs font-medium leading-relaxed text-ink-soft">{t('It stops appearing in your plan. Everything you have already logged is kept.')}</p>
            <div className="mt-4 grid grid-cols-2 gap-2">
              <button type="button" onClick={() => setPendingArchive(null)} className="rounded-2xl bg-slate-100 px-3 py-3 text-xs font-black text-ink">{t('Keep')}</button>
              <button type="button" onClick={() => { upsert('supplements', { ...pendingArchive, archived: true }); setPendingArchive(null) }} className="rounded-2xl bg-rose-600 px-3 py-3 text-xs font-black text-white">{t('Remove')}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
