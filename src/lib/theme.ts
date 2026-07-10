import type { CSSProperties } from 'react'

export type AccentKey = 'amber' | 'teal' | 'violet' | 'emerald' | 'ice'

export interface Accent {
  key: AccentKey
  /* Deepened shade, safe for small text and icons on light glass */
  deep: string
  /* Vibrant mid shade for gradients and fills */
  bright: string
  /* Lighter sibling, the top end of joyful gradients */
  soft: string
  /* Colored halo shadows for the breathing glow */
  glowSoft: string
  glowStrong: string
  /* Joyful gradient fill, bright to soft */
  gradient: string
  /* Faint wash used to tint glass panels */
  wash: string
}

export const ACCENTS: Record<AccentKey, Accent> = {
  amber: {
    key: 'amber',
    deep: '#b45309',
    bright: '#f59e0b',
    soft: '#fbbf24',
    glowSoft: 'rgba(245, 158, 11, 0.26)',
    glowStrong: 'rgba(245, 158, 11, 0.5)',
    gradient: 'linear-gradient(135deg, #f59e0b 0%, #fbbf24 100%)',
    wash: 'rgba(245, 158, 11, 0.07)',
  },
  teal: {
    key: 'teal',
    deep: '#0f766e',
    bright: '#14b8a6',
    soft: '#2dd4bf',
    glowSoft: 'rgba(20, 184, 166, 0.26)',
    glowStrong: 'rgba(20, 184, 166, 0.5)',
    gradient: 'linear-gradient(135deg, #0d9488 0%, #2dd4bf 100%)',
    wash: 'rgba(20, 184, 166, 0.07)',
  },
  violet: {
    key: 'violet',
    deep: '#6d28d9',
    bright: '#8b5cf6',
    soft: '#a78bfa',
    glowSoft: 'rgba(139, 92, 246, 0.26)',
    glowStrong: 'rgba(139, 92, 246, 0.5)',
    gradient: 'linear-gradient(135deg, #7c3aed 0%, #a78bfa 100%)',
    wash: 'rgba(139, 92, 246, 0.07)',
  },
  emerald: {
    key: 'emerald',
    deep: '#047857',
    bright: '#10b981',
    soft: '#34d399',
    glowSoft: 'rgba(16, 185, 129, 0.26)',
    glowStrong: 'rgba(16, 185, 129, 0.5)',
    gradient: 'linear-gradient(135deg, #059669 0%, #34d399 100%)',
    wash: 'rgba(16, 185, 129, 0.07)',
  },
  ice: {
    key: 'ice',
    deep: '#0369a1',
    bright: '#38bdf8',
    soft: '#7dd3fc',
    glowSoft: 'rgba(56, 189, 248, 0.26)',
    glowStrong: 'rgba(56, 189, 248, 0.5)',
    gradient: 'linear-gradient(135deg, #0ea5e9 0%, #7dd3fc 100%)',
    wash: 'rgba(56, 189, 248, 0.07)',
  },
}

/* Inline CSS custom properties consumed by .glass and .breathe */
export function accentVars(accent: Accent): CSSProperties {
  return {
    '--glow-soft': accent.glowSoft,
    '--glow-strong': accent.glowStrong,
  } as CSSProperties
}
