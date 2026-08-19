/*
 * Where a user's food data comes from, and how it should be presented.
 *
 * This is detected, never asked. The device already knows: someone sets their
 * region to where they live so dates, temperature and the first day of the
 * week come out right. It is stored so it syncs across devices, and it can be
 * overridden in settings for the case detection cannot see - a person who
 * moved and kept their old App Store country, or who shops across a border.
 *
 * Region decides presentation and ranking. It does NOT decide how a stored
 * food is read: the carbohydrate convention is a property of each row and is
 * resolved from that row's own energy, because one catalogue holds both.
 */

export type FoodRegion = 'europe' | 'united_states' | 'international'

/* EU and EFTA, in alpha-2 and alpha-3, so a device region and an App Store
   storefront code can be classified without a conversion table. */
const EUROPEAN = new Set([
  'AT', 'AUT', 'BE', 'BEL', 'BG', 'BGR', 'CH', 'CHE', 'CY', 'CYP', 'CZ', 'CZE',
  'DE', 'DEU', 'DK', 'DNK', 'EE', 'EST', 'ES', 'ESP', 'FI', 'FIN', 'FR', 'FRA',
  'GB', 'GBR', 'GR', 'GRC', 'HR', 'HRV', 'HU', 'HUN', 'IE', 'IRL', 'IS', 'ISL',
  'IT', 'ITA', 'LI', 'LIE', 'LT', 'LTU', 'LU', 'LUX', 'LV', 'LVA', 'MT', 'MLT',
  'NL', 'NLD', 'NO', 'NOR', 'PL', 'POL', 'PT', 'PRT', 'RO', 'ROU', 'SE', 'SWE',
  'SI', 'SVN', 'SK', 'SVK',
])

const UNITED_STATES = new Set(['US', 'USA'])

export function classifyRegion(code: string | null | undefined): FoodRegion | null {
  const value = (code ?? '').trim().toUpperCase()
  if (!value) return null
  if (EUROPEAN.has(value)) return 'europe'
  if (UNITED_STATES.has(value)) return 'united_states'
  return null
}

/** Region from the device, with an optional storefront as a second opinion. */
export function detectFoodRegion(
  deviceRegion?: string | null,
  storefront?: string | null,
): FoodRegion {
  /* The device region is the stronger signal. An App Store storefront follows
     the payment method, so it lags a move abroad by years. */
  return classifyRegion(deviceRegion)
    ?? classifyRegion(storefront)
    ?? 'international'
}

/** The browser's own region, for the web client. */
export function browserFoodRegion(): FoodRegion {
  if (typeof Intl === 'undefined') return 'international'
  try {
    const locale = new Intl.Locale(Intl.DateTimeFormat().resolvedOptions().locale)
    const region = locale.region ?? (typeof navigator !== 'undefined' ? navigator.language.split('-')[1] : null)
    return detectFoodRegion(region)
  } catch {
    return 'international'
  }
}

export function normalizeFoodRegion(value: unknown): FoodRegion | null {
  return value === 'europe' || value === 'united_states' || value === 'international'
    ? value
    : null
}

/** Stored preference when there is one, otherwise what the device reports. */
export function resolveFoodRegion(stored: unknown, detected: FoodRegion): FoodRegion {
  return normalizeFoodRegion(stored) ?? detected
}

export interface RegionPresentation {
  /** Grams and millilitres, or ounces. */
  metric: boolean
  /** EU labelling leads with kilojoules, so both are shown. */
  showsKilojoules: boolean
  /** Which reference table generic staples should be drawn from. */
  staples: 'swiss_fsvo' | 'usda'
  /** Provider country hint, so local products rank first in search. */
  providerCountry: string | null
}

export function regionPresentation(region: FoodRegion): RegionPresentation {
  switch (region) {
    case 'united_states':
      return { metric: false, showsKilojoules: false, staples: 'usda', providerCountry: 'united-states' }
    case 'europe':
      return { metric: true, showsKilojoules: true, staples: 'swiss_fsvo', providerCountry: null }
    default:
      return { metric: true, showsKilojoules: false, staples: 'usda', providerCountry: null }
  }
}

/** Kilocalories to kilojoules, the factor fixed by EU Regulation 1169/2011. */
export function kilojoules(kcal: number): number {
  return Math.round(kcal * 4.184)
}
