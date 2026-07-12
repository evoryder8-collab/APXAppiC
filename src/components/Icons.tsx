interface IconProps {
  className?: string
  strokeWidth?: number
}

function base(className?: string) {
  return {
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeLinecap: 'round' as const,
    strokeLinejoin: 'round' as const,
    className,
  }
}

export function LeafIcon({ className, strokeWidth = 1.9 }: IconProps) {
  return (
    <svg {...base(className)} strokeWidth={strokeWidth}>
      <path d="M12 21c-4.6 0-8-3.2-8-7.6C4 8 9.5 3.8 20 3c.6 6.2-1 12.2-5.4 15.6A9.4 9.4 0 0 1 12 21Z" />
      <path d="M4.5 20.5c3-5.2 7-9 11.5-11.5" />
    </svg>
  )
}

export function TransitionIcon({ className, strokeWidth = 1.9 }: IconProps) {
  return (
    <svg {...base(className)} strokeWidth={strokeWidth}>
      <path d="M5.5 5.5 12 12l-6.5 6.5" />
      <path d="M13 5.5 19.5 12 13 18.5" opacity={0.55} />
    </svg>
  )
}

export function BoltIcon({ className, strokeWidth = 1.9 }: IconProps) {
  return (
    <svg {...base(className)} strokeWidth={strokeWidth}>
      <path d="M13 2.5 4.5 13.5H11l-1 8 8.5-11H12l1-8Z" />
    </svg>
  )
}

export function AvatarIcon({ className, strokeWidth = 1.9 }: IconProps) {
  return (
    <svg {...base(className)} strokeWidth={strokeWidth}>
      <path d="M12 2.2 20 6.9v10.2L12 21.8 4 17.1V6.9L12 2.2Z" />
      <path d="M7.2 12h2.3l1.3-2.6 2 5.2 1.4-2.6h2.6" />
    </svg>
  )
}

export function BarcodeIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 32 20" fill="none" className={className} aria-hidden>
      <path d="M2 2v16M5 2v16M8 2v16M12 2v16M14.5 2v16M19 2v16M22 2v16M24.5 2v16M29 2v16" stroke="currentColor" strokeWidth="1.8" />
      <path d="M1 1h4M1 1v4M31 1h-4M31 1v4M1 19h4M1 19v-4M31 19h-4M31 19v-4" stroke="currentColor" strokeWidth="1.25" strokeLinecap="round" />
    </svg>
  )
}

export function CameraIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="currentColor" className={className} aria-hidden>
      <path d="M8.35 4.5a1.7 1.7 0 0 1 1.52-.94h4.26a1.7 1.7 0 0 1 1.52.94l.77 1.54h2.33A2.75 2.75 0 0 1 21.5 8.8v8.45A2.75 2.75 0 0 1 18.75 20H5.25a2.75 2.75 0 0 1-2.75-2.75V8.8a2.75 2.75 0 0 1 2.75-2.75h2.33l.77-1.54ZM12 17.35a4.35 4.35 0 1 0 0-8.7 4.35 4.35 0 0 0 0 8.7Zm0-1.9a2.45 2.45 0 1 1 0-4.9 2.45 2.45 0 0 1 0 4.9Zm6.05-5.8a1.05 1.05 0 1 0 0-2.1 1.05 1.05 0 0 0 0 2.1Z" />
    </svg>
  )
}

export function SlidersIcon({ className, strokeWidth = 1.9 }: IconProps) {
  return (
    <svg {...base(className)} strokeWidth={strokeWidth}>
      <path d="M4 7h16" />
      <circle cx="14.5" cy="7" r="2.4" />
      <path d="M4 16h16" />
      <circle cx="8.5" cy="16" r="2.4" />
    </svg>
  )
}

export function DropletIcon({ className, strokeWidth = 1.9 }: IconProps) {
  return (
    <svg {...base(className)} strokeWidth={strokeWidth}>
      <path d="M12 3.2c3.2 3.9 6 7.2 6 10.4a6 6 0 1 1-12 0c0-3.2 2.8-6.5 6-10.4Z" />
      <path d="M9.5 14.5a2.6 2.6 0 0 0 2 2.4" opacity={0.6} />
    </svg>
  )
}

export function ChevronRightIcon({ className, strokeWidth = 2 }: IconProps) {
  return (
    <svg {...base(className)} strokeWidth={strokeWidth}>
      <path d="m9 5.5 6.5 6.5L9 18.5" />
    </svg>
  )
}

export function ChevronLeftIcon({ className, strokeWidth = 2 }: IconProps) {
  return (
    <svg {...base(className)} strokeWidth={strokeWidth}>
      <path d="M15 5.5 8.5 12 15 18.5" />
    </svg>
  )
}

export function ApexMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 32 32" fill="none" className={className}>
      <defs>
        <linearGradient id="apex-mark-g" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#f59e0b" />
          <stop offset="0.5" stopColor="#8b5cf6" />
          <stop offset="1" stopColor="#10b981" />
        </linearGradient>
      </defs>
      <path d="M16 4 27 28h-5.1L16 14.9 10.1 28H5L16 4Z" fill="url(#apex-mark-g)" />
    </svg>
  )
}
