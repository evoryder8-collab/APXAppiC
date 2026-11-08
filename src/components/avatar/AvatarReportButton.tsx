import { useOrbitStore } from '../../orbit/store/OrbitStore'
import { trainingProfile } from '../../lib/trainingProfile'
import { useStore } from '../../store/AppStore'
import { translateInterfaceText, useLanguage } from '../../lib/i18n'
import { todayIso } from '../../lib/plan'
import { buildExerciseFamilies } from '../../lib/strengthProgress'
import { avatarReportHTML } from '../../lib/avatarReport'

export function AvatarReportButton() {
  const { data, snapshots, avatarDomainScores } = useStore()
  const { language } = useLanguage()
  const { state: { runs } } = useOrbitStore()
  const t = (s: string) => translateInterfaceText(s, language)
  if (!data.profile) return null
  const profile = data.profile
  function download() {
    const today = todayIso()
    const families = buildExerciseFamilies(data)
    const html = avatarReportHTML({ name: profile.display_name, locale: language, today, families, training: trainingProfile(data, runs, today),
      snapshots: snapshots.filter(s => s.user_id === profile.user_id), observed: avatarDomainScores, translate: t })
    const url = URL.createObjectURL(new Blob([html], { type: 'text/html;charset=utf-8' }))
    const link = document.createElement('a')
    link.href = url
    link.download = 'FITR-MAX-Avatar-' + today + '.html'
    document.body.append(link)
    link.click()
    link.remove()
    setTimeout(() => URL.revokeObjectURL(url), 60_000)
  }
  return <button type="button" onClick={download}
    className="inline-flex min-h-11 items-center gap-2 rounded-full border border-violet-200 bg-violet-50 px-4 py-2 text-sm font-bold text-violet-900">
    <span aria-hidden="true">↓</span>{t('Export Avatar report')}<small className="font-mono">HTML</small>
  </button>
}
