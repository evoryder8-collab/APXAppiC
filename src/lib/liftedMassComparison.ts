import objects from '../../shared/lifted-mass-landmarks.json' with { type: 'json' }
import heroes from '../../shared/hero-lift-landmarks.json' with { type: 'json' }

type Landmark = { name: string; kg: number; source: string }
type ObjectLandmark = Landmark & { artwork: string; fact: string; factSource?: string; translations: Record<string, string[]> }
type Comparison = { caption: string; source: string }
type ObjectComparison = Comparison & { artwork: string; fact: string; factSource: string }
type Translate = (value: string) => string

const massUnits = ['kg', 't', 'kt', 'Mt', 'Gt', 'Tt', 'Pt', 'Et', 'Zt', 'Yt', 'Rt', 'Qt']

export function formattedMass(kilograms: number, locale: string): string {
  let value = kilograms
  let unit = 0
  while (value >= 1000 && unit + 1 < massUnits.length) {
    value /= 1000
    unit++
  }
  return new Intl.NumberFormat(locale, { maximumSignificantDigits: 5 }).format(value) + ' ' + massUnits[unit]
}

// Stable for a re-export. A new total can surface another comparable landmark.
function pick<T extends Landmark>(matches: T[], kilograms: number): T | undefined {
  if (matches.length === 0) return
  return matches[Math.floor(kilograms) % matches.length]
}

export function liftedMassCaption(kilograms: number, locale: string): ObjectComparison | undefined {
  if (!Number.isFinite(kilograms) || kilograms <= 0 || !objects.length) return
  const distance = (kg: number) => Math.abs(Math.log(kilograms / kg))
  const catalog = (objects as ObjectLandmark[]).filter(item => kilograms / item.kg >= 0.1)
  if (!catalog.length) return
  const best = catalog.reduce((a, b) => distance(a.kg) <= distance(b.kg) ? a : b)
  const close = catalog.filter(o => distance(o.kg) <= Math.log(1.1))
  const multiples = catalog.filter(o => o.kg <= kilograms && o.kg * 8 >= kilograms)
  const match = pick(Math.floor(kilograms) % 3 === 0 && close.length ? close : multiples, kilograms) ?? best
  const ratio = kilograms / match.kg
  const multiplier = new Intl.NumberFormat(locale, { maximumSignificantDigits: 3 }).format(ratio)
  const referenceMass = formattedMass(match.kg, locale)
  const tag = new Intl.Locale(locale)
  const [name, fact] = match.translations[tag.baseName] ?? match.translations[tag.language] ?? [match.name, match.fact]
  return { caption: `≈ ${multiplier} × ${name} (${referenceMass})`, source: match.source,
    artwork: match.artwork, fact, factSource: match.factSource ?? match.source }
}

export function heroLiftCaption(kilograms: number, locale: string, translate: Translate = s => s): Comparison | undefined {
  if (!Number.isFinite(kilograms) || kilograms <= 0) return
  const eligible = (heroes as Landmark[]).filter(hero => hero.kg >= kilograms)
  if (!eligible.length) return
  const tier = eligible.filter(hero => hero.kg <= eligible[0].kg * 1.1)
  const hero = pick(tier, kilograms)!
  const mass = formattedMass(hero.kg, locale)
  const caption = translate('Fictional one-lift benchmark · {hero} · {mass}').replace('{hero}', translate(hero.name))
    .replace('{mass}', mass)
  return { caption, source: hero.source }
}
