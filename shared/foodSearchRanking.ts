export interface FoodSearchCandidate {
  name?: string | null
  names_i18n?: Record<string, string> | null
  brand?: string | null
  search_aliases?: string[] | null
  kcal_100?: number | null
  protein_100?: number | null
  carbs_100?: number | null
  fat_100?: number | null
}

const FOOD_SEARCH_CORRECTIONS: Array<[RegExp, string]> = [
  [/\b(?:airfryer|airfried)\b/g, 'air fryer'],
  [/\bulei(?: de)? masine\b/g, 'ulei de masline'],
  [/\bextra vergin\b/g, 'extra virgin'],
  [/\boliv oil\b/g, 'olive oil'],
  [/\bweinerli\b/g, 'wienerli'],
  [/\bam teig\b/g, 'im teig'],
  [/\bomlette\b/g, 'omelette'],
  [/\braviolli\b/g, 'ravioli'],
]

export function normalizeFoodSearchText(value: string): string {
  let normalized = value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase()
    .replace(/[^\p{L}\p{N}\p{M}]+/gu, ' ')
    .trim()
  for (const [pattern, replacement] of FOOD_SEARCH_CORRECTIONS) {
    normalized = normalized.replace(pattern, replacement)
  }
  return normalized.replace(/\s+/g, ' ').trim()
}

function editDistance(left: string, right: string, limit: number): number {
  if (Math.abs(left.length - right.length) > limit) return limit + 1
  let previous = Array.from({ length: right.length + 1 }, (_, index) => index)
  for (let leftIndex = 1; leftIndex <= left.length; leftIndex += 1) {
    const current = [leftIndex]
    let rowMinimum = current[0]
    for (let rightIndex = 1; rightIndex <= right.length; rightIndex += 1) {
      const cost = left[leftIndex - 1] === right[rightIndex - 1] ? 0 : 1
      current[rightIndex] = Math.min(
        current[rightIndex - 1] + 1,
        previous[rightIndex] + 1,
        previous[rightIndex - 1] + cost,
      )
      rowMinimum = Math.min(rowMinimum, current[rightIndex])
    }
    if (rowMinimum > limit) return limit + 1
    previous = current
  }
  return previous[right.length]
}

function tokenForms(tokens: string[]): string[] {
  const forms = new Set<string>()
  for (const token of tokens) {
    forms.add(token)
    if (token.endsWith('ies') && token.length > 4) forms.add(`${token.slice(0, -3)}y`)
    if (token.endsWith('oes') && token.length > 4) forms.add(token.slice(0, -2))
    if (token.endsWith('o') && token.length > 3) forms.add(`${token}es`)
  }
  for (let start = 0; start < tokens.length; start += 1) {
    for (let length = 2; length <= 3 && start + length <= tokens.length; length += 1) {
      forms.add(tokens.slice(start, start + length).join(''))
    }
  }
  return [...forms]
}

function queryTokenGroups(tokens: string[]): string[][] {
  const groups: string[][] = []
  const walk = (index: number, current: string[]) => {
    if (index >= tokens.length) {
      groups.push(current)
      return
    }
    walk(index + 1, [...current, tokens[index]])
    if (index + 1 < tokens.length) {
      const joined = `${tokens[index]}${tokens[index + 1]}`
      if (joined.length >= 4 && joined.length <= 18) {
        walk(index + 2, [...current, joined])
      }
    }
  }
  walk(0, [])
  return groups
}

function tokenSimilarity(queryToken: string, candidateToken: string): number {
  if (queryToken === candidateToken) return 1
  if (
    queryToken.length >= 3
    && candidateToken.length >= 3
    && candidateToken.startsWith(queryToken)
  ) return 0.92
  if (
    queryToken.length >= 3
    && candidateToken.length >= 3
    && queryToken.startsWith(candidateToken)
    && queryToken.length - candidateToken.length <= 2
  ) return 0.88
  if (queryToken.length < 4 || candidateToken.length < 4) return 0
  if (queryToken[0] !== candidateToken[0]) return 0
  const limit = queryToken.length >= 9 || (queryToken.length >= 5 && queryToken.length <= 6) ? 2 : 1
  const distance = editDistance(queryToken, candidateToken, limit)
  if (distance > limit) return 0
  const similarity = 1 - distance / Math.max(queryToken.length, candidateToken.length)
  const minimum = queryToken.length >= 5 ? 0.66 : 0.74
  return similarity >= minimum ? similarity : 0
}

function bestTokenAlignment(query: string, candidate: string): number {
  const queryTokens = query.split(' ').filter(Boolean)
  const candidateTokens = tokenForms(candidate.split(' ').filter(Boolean))
  if (!queryTokens.length || !candidateTokens.length) return 0
  let best = 0
  for (const groups of queryTokenGroups(queryTokens)) {
    const scores = groups.map((queryToken) =>
      candidateTokens.reduce(
        (highest, candidateToken) => Math.max(highest, tokenSimilarity(queryToken, candidateToken)),
        0,
      ),
    )
    /* every_query_token_matches: a multi-word query is never accepted merely
       because one generic word resembles the candidate. */
    if (scores.every((score) => score > 0)) {
      best = Math.max(best, scores.reduce((sum, score) => sum + score, 0) / scores.length)
    }
  }
  return best
}

export function foodSearchTokenMatch(query: string, candidate: string): boolean {
  const needle = normalizeFoodSearchText(query)
  const haystack = normalizeFoodSearchText(candidate)
  if (!needle || !haystack) return false
  if (haystack === needle || haystack.includes(needle)) return true
  return bestTokenAlignment(needle, haystack) > 0
}

export function foodSearchTextRelevance(query: string, candidate: string): number {
  const needle = normalizeFoodSearchText(query)
  const haystack = normalizeFoodSearchText(candidate)
  if (!needle || !haystack) return -Infinity
  if (haystack === needle) return 12_000
  if (haystack.startsWith(`${needle} `)) return 9_000
  if (haystack.includes(` ${needle} `) || haystack.endsWith(` ${needle}`)) return 8_200
  if (haystack.includes(needle)) return 7_400
  const alignment = bestTokenAlignment(needle, haystack)
  return alignment > 0 ? 4_600 + Math.round(alignment * 600) : -Infinity
}

function foodSearchFields(food: FoodSearchCandidate): string[] {
  const names = [food.name, ...Object.values(food.names_i18n ?? {})]
  const branded = food.brand
    ? names.map((name) => name ? `${food.brand} ${name}` : '')
    : []
  return [...names, ...branded, ...(food.search_aliases ?? [])]
    .filter((value): value is string => typeof value === 'string' && value.trim().length > 0)
}

function categoryScore(query: string, food: FoodSearchCandidate): number {
  const tokens = normalizeFoodSearchText(query).split(' ').filter(Boolean)
  const broadOilQuery = tokens.length === 1 && ['oil', 'ulei', 'ol', 'huile', 'olio', 'aceite'].includes(tokens[0])
  if (!broadOilQuery) return 0
  const text = normalizeFoodSearchText(foodSearchFields(food).join(' '))
  const isPureOil = (food.fat_100 ?? 0) >= 90
    && (food.protein_100 ?? 0) <= 1
    && (food.carbs_100 ?? 0) <= 1
    && /(?:^| )(?:oil|ulei|ol|huile|olio|aceite)(?: |$)/.test(text)
  if (isPureOil && /(?:extra virgin olive|olive extra virgin|evoo)/.test(text)) return 5_000
  if (isPureOil && /(?:olive oil|oil olive|vegetable oil|oil vegetable)/.test(text)) return 4_200
  if (isPureOil) return 3_000
  if (/(?:^| )(?:margarine|margarin|margarina)(?: |$)/.test(text)) return -1_600
  return 0
}

export function rankFoodLookupResults<T extends FoodSearchCandidate>(query: string, foods: T[]): T[] {
  return foods
    .map((food, index) => {
      const relevance = foodSearchFields(food).reduce(
        (highest, field) => Math.max(highest, foodSearchTextRelevance(query, field)),
        -Infinity,
      )
      return {
        food,
        index,
        score: Number.isFinite(relevance) ? relevance + categoryScore(query, food) : -Infinity,
      }
    })
    .filter(({ score }) => Number.isFinite(score))
    .sort((left, right) => right.score - left.score || left.index - right.index)
    .map(({ food }) => food)
}
