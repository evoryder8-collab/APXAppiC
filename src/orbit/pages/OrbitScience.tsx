import { GlassCard } from '../../components/ui.tsx'
import { ACCENTS } from '../../lib/theme.ts'
import { ORBIT_PLAN_VERSION, ORBIT_SCIENCE_REVIEW_DATE } from '../domain/config.ts'
import { OrbitFrame, OrbitPill } from '../components/OrbitFrame.tsx'
import { useOrbitText } from '../ui/i18n.ts'

const ledger = [
  {
    principle: 'Predominantly controlled low-intensity running', confidence: 'Moderate',
    application: 'Most campaign sessions remain conversational. Quality work is limited and purposeful rather than added every time recovery looks good.',
    intended: 'Adult recreational runners across Foundation and marathon-specific families.',
    limitation: 'Research does not identify one universally superior intensity distribution for every runner or intervention duration.',
    source: 'Rosenblat et al. 2025 network meta-analysis', href: 'https://pubmed.ncbi.nlm.nih.gov/39888556/',
  },
  {
    principle: 'Progressive exposure with cutback periods', confidence: 'Moderate',
    application: 'Duration rises conservatively, every fourth week is reduced, and Orbit does not raise volume and intensity aggressively together.',
    intended: 'All campaign families, with slower growth for low consistency or a returning base.',
    limitation: 'No single progression rule guarantees injury prevention. Training-load metrics have important conceptual limitations.',
    source: 'Impellizzeri et al. 2020 training-load framework critique', href: 'https://pubmed.ncbi.nlm.nih.gov/32991699/',
  },
  {
    principle: 'Strength work can support running economy', confidence: 'Moderate to high',
    application: 'Hybrid Athlete campaigns preserve useful strength while separating demanding lower-body work and quality running when possible.',
    intended: 'Runners already using APEX Transition or Main Phase.',
    limitation: 'Intervention methods and athlete populations vary. Orbit coordinates load rather than promising a specific performance gain.',
    source: '2024 systematic review and meta-analysis', href: 'https://pubmed.ncbi.nlm.nih.gov/38165636/',
  },
  {
    principle: 'Taper by reducing volume while retaining rhythm', confidence: 'Moderate',
    application: 'The final weeks reduce volume, preserve familiar controlled running and avoid compensatory catch-up sessions.',
    intended: 'Campaigns reaching taper and race week.',
    limitation: 'The best taper depends on prior load, event and individual response.',
    source: 'Wang et al. 2023 taper meta-analysis', href: 'https://pubmed.ncbi.nlm.nih.gov/37163550/',
  },
  {
    principle: 'Practise familiar fueling before race day', confidence: 'Moderate',
    application: 'Long-run sessions introduce explicit rehearsals using familiar foods and products. Exact changes are reviewed before application.',
    intended: 'Long-duration sessions and Marathon Campaign race preparation.',
    limitation: 'Tolerance and needs vary. APEX does not automatically introduce new race-day products.',
    source: '2022 food-first carbohydrate review', href: 'https://pubmed.ncbi.nlm.nih.gov/35231883/',
  },
  {
    principle: 'Readiness screening is not medical clearance', confidence: 'High boundary confidence',
    application: 'Current concerning symptoms or an existing restriction lead to professional review before strenuous campaign assignment. Old resolved history does not automatically block training.',
    intended: 'Adults entering Marathon Campaign.',
    limitation: 'A questionnaire cannot diagnose, clear, or determine medical fitness for exercise.',
    source: 'ACSM and FIMS preparticipation consensus', href: 'https://pubmed.ncbi.nlm.nih.gov/25391096/',
  },
]

export function OrbitScience() {
  const t = useOrbitText()
  return <OrbitFrame title="Science ledger" subtitle="Why this plan is built this way" backTo="/orbit/campaign" action={<OrbitPill tone="ice">{ORBIT_PLAN_VERSION}</OrbitPill>}>
    <div className="space-y-4">
      <GlassCard accent={ACCENTS.ice} className="p-5"><h2 className="font-display text-xl font-bold text-ink">{t('Transparent, evidence-informed, never infallible.')}</h2><p className="mt-2 text-sm leading-relaxed text-ink-soft">{t('Orbit uses established endurance principles shared across reputable sports science and coaching practice. It does not copy proprietary plans, claim endorsement or convert uncertain evidence into false precision.')}</p><p className="mt-3 font-mono text-[10px] text-sky-800">{t('PLAN')} {ORBIT_PLAN_VERSION} · {t('REVIEW BY')} {ORBIT_SCIENCE_REVIEW_DATE}</p></GlassCard>
      {ledger.map((item) => <GlassCard key={item.principle} className="p-5"><div className="flex flex-wrap items-start justify-between gap-2"><h3 className="max-w-xl font-display text-lg font-bold text-ink">{t(item.principle)}</h3><OrbitPill tone={item.confidence.startsWith('High') ? 'emerald' : 'ice'}>{t(item.confidence).toUpperCase()}</OrbitPill></div><div className="mt-3 space-y-2 text-xs leading-relaxed"><p><strong className="text-ink">{t('How APEX applies it:')}</strong> <span className="text-ink-soft">{t(item.application)}</span></p><p><strong className="text-ink">{t('Intended for:')}</strong> <span className="text-ink-soft">{t(item.intended)}</span></p><p><strong className="text-ink">{t('Known limitation:')}</strong> <span className="text-ink-soft">{t(item.limitation)}</span></p></div><a href={item.href} target="_blank" rel="noreferrer" className="mt-3 inline-flex min-h-10 items-center text-xs font-bold text-sky-700 underline decoration-sky-300 underline-offset-4">{item.source}</a></GlassCard>)}
      <GlassCard accent={ACCENTS.amber} className="p-5"><p className="font-display text-base font-bold text-ink">{t('Intended purpose')}</p><p className="mt-2 text-xs leading-relaxed text-ink-soft">{t('APEX Orbit Marathon Campaign provides personalized fitness training, educational guidance and performance tracking for adults preparing for endurance events. It does not diagnose, treat, monitor, predict or prevent disease or injury and does not determine medical fitness for exercise.')}</p></GlassCard>
      <p className="text-center text-[10px] text-ink-faint">{t('No mysterious score. Every conclusion keeps its reason visible.')}</p>
    </div>
  </OrbitFrame>
}
