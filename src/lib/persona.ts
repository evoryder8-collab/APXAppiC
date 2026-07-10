import constantinePortrait from '../../constantine.webp'
import junePortrait from '../../june.webp'
import matthewPortrait from '../../matthew.webp'

export type PersonaSlug = 'june' | 'matthew' | 'constantine'

export interface PersonaDefinition {
  slug: PersonaSlug
  name: string
  firstName: string
  title: string
  signature: string
  mission: string
  portrait: string
  color: string
  colorSoft: string
  halo: string
  gradient: string
}

/* Order is intentional: June begins left, Matthew centre, Constantine right. */
export const PERSONAS: PersonaDefinition[] = [
  {
    slug: 'june',
    name: 'June',
    firstName: 'June',
    title: 'THE FORCE',
    signature: 'Strength shaped by a lifetime of movement.',
    mission: 'Glute architecture · athletic longevity · calisthenics',
    portrait: junePortrait,
    color: '#22d3ee',
    colorSoft: '#a5f3fc',
    halo: 'rgba(34,211,238,0.42)',
    gradient: 'linear-gradient(135deg, #0891b2 0%, #22d3ee 48%, #a5f3fc 100%)',
  },
  {
    slug: 'matthew',
    name: 'Matthew Hua',
    firstName: 'Matthew',
    title: 'THE CATALYST',
    signature: 'Calm intensity. Endurance with purpose.',
    mission: 'Lean power · morning performance · resilient conditioning',
    portrait: matthewPortrait,
    color: '#c4ff4d',
    colorSoft: '#ecfccb',
    halo: 'rgba(190,242,100,0.42)',
    gradient: 'linear-gradient(135deg, #65a30d 0%, #a3e635 48%, #d9f99d 100%)',
  },
  {
    slug: 'constantine',
    name: 'Constantine',
    firstName: 'Constantine',
    title: 'THE ARCHITECT',
    signature: 'Build the system. Become the proof.',
    mission: 'Recomposition · intelligent progression · complete performance',
    portrait: constantinePortrait,
    color: '#a78bfa',
    colorSoft: '#ddd6fe',
    halo: 'rgba(167,139,250,0.44)',
    gradient: 'linear-gradient(135deg, #6d28d9 0%, #8b5cf6 48%, #c4b5fd 100%)',
  },
]

const SELECTED_KEY = 'apex.selected-persona.v1'
const ENTRY_KEY = 'apex.entry-granted.v1'

export function isPersonaSlug(value: unknown): value is PersonaSlug {
  return value === 'june' || value === 'matthew' || value === 'constantine'
}

export function personaBySlug(slug: PersonaSlug): PersonaDefinition {
  return PERSONAS.find((persona) => persona.slug === slug) ?? PERSONAS[1]
}

export function getSelectedPersona(): PersonaSlug | null {
  try {
    const value = localStorage.getItem(SELECTED_KEY)
    return isPersonaSlug(value) ? value : null
  } catch {
    return null
  }
}

export function setSelectedPersona(slug: PersonaSlug): void {
  try {
    localStorage.setItem(SELECTED_KEY, slug)
  } catch {
    /* Private browsing can reject storage; in-memory UI still works. */
  }
}

export function clearSelectedPersona(): void {
  try {
    localStorage.removeItem(SELECTED_KEY)
  } catch {
    /* no-op */
  }
}

export function hasEntryGrant(): boolean {
  try {
    return sessionStorage.getItem(ENTRY_KEY) === '1'
  } catch {
    return false
  }
}

export function grantEntry(): void {
  try {
    sessionStorage.setItem(ENTRY_KEY, '1')
  } catch {
    /* no-op */
  }
}

export function clearEntryGrant(): void {
  try {
    sessionStorage.removeItem(ENTRY_KEY)
  } catch {
    /* no-op */
  }
}

export function personaFromUserMetadata(metadata: Record<string, unknown> | undefined): PersonaSlug {
  return isPersonaSlug(metadata?.persona) ? metadata.persona : 'constantine'
}
