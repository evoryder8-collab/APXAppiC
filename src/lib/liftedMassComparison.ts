import objects from '../../shared/lifted-mass-landmarks.json' with { type: 'json' }
import heroes from '../../shared/hero-lift-landmarks.json' with { type: 'json' }

type Landmark = { name: string; kg: number; source: string }
type ObjectLandmark = Landmark & { singular: string; plural?: string; artwork: string; fact: string; factSource?: string; translations: Record<string, string[]> }
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

export function liftedMassCaption(kilograms: number, locale: string, translate: Translate = s => s): ObjectComparison | undefined {
  if (!Number.isFinite(kilograms) || kilograms <= 0 || !objects.length) return
  const catalog = objects as ObjectLandmark[]
  let match: ObjectLandmark | undefined
  let count = 1
  for (; count <= 6; count++) {
    let closestError = Infinity
    const tolerance = count === 1 ? 0.12 : 0.08
    for (const item of catalog) {
      if (count > 1 && !item.plural) continue
      const error = Math.abs(kilograms - count * item.kg) / kilograms
      if (error <= tolerance && error < closestError) {
        match = item
        closestError = error
      }
    }
    if (match) break
  }
  const milestone = !match
  if (!match) {
    match = catalog[0]
    for (const item of catalog) {
      if (item.kg > kilograms) break
      if (item.kg > match.kg) match = item
    }
  }
  const tag = new Intl.Locale(locale)
  const [name, fact] = match.translations[tag.baseName] ?? match.translations[tag.language] ?? [match.name, match.fact]
  let caption: string
  if (milestone) {
    caption = name + ' · ' + translate(match.kg <= kilograms ? 'Milestone passed' : 'Next milestone')
  } else if (count === 1) {
    caption = tag.language === 'en' ? 'About the weight of ' + match.singular
      : name + ' · ' + translate('About the same weight')
  } else {
    const words = ['two', 'three', 'four', 'five', 'six']
    caption = tag.language === 'en' ? `About ${words[count - 2]} ${match.plural}`
      : name + ' · ' + translate('About %d of these').replace('%d', new Intl.NumberFormat(locale).format(count))
  }
  return { caption, source: match.source, artwork: match.artwork, fact, factSource: match.factSource ?? match.source }
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
