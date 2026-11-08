import { useId, useMemo, useRef, useState } from 'react'
import { useOrbitStore } from '../../orbit/store/OrbitStore'
import { trainingProfile } from '../../lib/trainingProfile'
import { useStore } from '../../store/AppStore'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { todayIso } from '../../lib/plan'
import { buildExerciseFamilies } from '../../lib/strengthProgress'
import { downloadableAvatarReport, reportBodyweight, reportSessionBodyweights } from '../../lib/avatarReport'
import { avatarReportRange, earliestReportDate, reportPeriods, type ReportPeriod } from '../../lib/avatarReportRange'

export function AvatarReportButton() {
  const { data, snapshots, avatarDomainScores } = useStore()
  const { language } = useLanguage()
  const { state: { runs } } = useOrbitStore()
  const today = todayIso()
  const earliest = useMemo(() => earliestReportDate(data, runs, snapshots, today), [data, runs, snapshots, today])
  const [period, setPeriod] = useState<ReportPeriod>('all')
  const [customFrom, setCustomFrom] = useState(earliest)
  const [customTo, setCustomTo] = useState(today)
  const [exporting, setExporting] = useState(false)
  const dialog = useRef<HTMLDialogElement>(null)
  const titleID = useId()
  const range = avatarReportRange(period, today, earliest, customFrom, customTo)
  const t = (s: string) => translateInterfaceText(s, language)
  if (!data.profile) return null
  const profile = data.profile
  async function download() {
    if (!range || exporting) return
    setExporting(true)
    try {
      const html = await downloadableAvatarReport({
        name: profile.display_name, locale: language, today, range, currentBodyweight: range.to === today ? reportBodyweight(data, today) : null,
        sessionBodyweights: reportSessionBodyweights(data, range.to), families: buildExerciseFamilies(data, range),
        training: trainingProfile(data, runs, range.to, range.allTime ? undefined : range.from),
        snapshots: snapshots.filter(s => s.user_id === profile.user_id && s.date >= range.from && s.date <= range.to),
        observed: range.allTime ? avatarDomainScores : {}, translate: t,
      }, import.meta.env.BASE_URL)
      const url = URL.createObjectURL(new Blob([html], { type: 'text/html;charset=utf-8' }))
      const link = document.createElement('a')
      link.href = url
      link.download = 'FITR-MAX-Avatar-' + range.from + '-' + range.to + '.html'
      document.body.append(link)
      link.click()
      link.remove()
      setTimeout(() => URL.revokeObjectURL(url), 60_000)
      dialog.current?.close()
    } finally {
      setExporting(false)
    }
  }
  return <>
    <button type="button" onClick={() => dialog.current?.showModal()}
      className="inline-flex min-h-11 items-center gap-2 rounded-full border border-violet-200 bg-violet-50 px-4 py-2 text-sm font-bold text-violet-900">
      <span aria-hidden="true">↓</span>{t('Export Avatar report')}<small className="font-mono">HTML</small>
    </button>
    <dialog ref={dialog} aria-labelledby={titleID} className="fixed inset-0 m-auto w-[min(92vw,26rem)] rounded-2xl border border-violet-200 bg-white p-5 text-ink shadow-xl backdrop:bg-black/45">
      <h2 id={titleID} className="font-display text-xl font-bold">{t('Export Avatar report')}</h2>
      <form className="mt-4 space-y-4" onSubmit={event => { event.preventDefault(); void download() }}>
        <label className="block text-sm font-semibold">{t('Date range')}
          <select className="mt-1 block min-h-11 w-full rounded-lg border border-ink/25 px-3" value={period}
            onChange={event => setPeriod(event.target.value as ReportPeriod)}>
            {(Object.entries(reportPeriods) as Array<[ReportPeriod, string]>).map(([key, label]) => <option key={key} value={key}>{t(label)}</option>)}
          </select>
        </label>
        {period === 'custom' ? <div className="grid grid-cols-2 gap-2">
          <label className="text-sm font-semibold">{t('From')}<input type="date" required max={today} value={customFrom}
            onChange={event => setCustomFrom(event.target.value)} className="mt-1 block min-h-11 w-full min-w-0 rounded-lg border border-ink/25 px-2" /></label>
          <label className="text-sm font-semibold">{t('To')}<input type="date" required min={customFrom} max={today} value={customTo}
            onChange={event => setCustomTo(event.target.value)} className="mt-1 block min-h-11 w-full min-w-0 rounded-lg border border-ink/25 px-2" /></label>
        </div> : range && <p className="text-sm text-ink-soft">{range.from} – {range.to}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" className="min-h-11 rounded-full px-4 font-bold" onClick={() => dialog.current?.close()}>{t('Cancel')}</button>
          <button type="submit" disabled={!range || exporting} aria-busy={exporting} className="min-h-11 rounded-full bg-violet-800 px-4 text-sm font-bold text-white disabled:opacity-50">{t('Export Avatar report')}</button>
        </div>
      </form>
    </dialog>
  </>
}
