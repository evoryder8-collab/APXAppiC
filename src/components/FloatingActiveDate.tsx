import { AnimatePresence, motion } from 'framer-motion'
import { useEffect, useState } from 'react'
import { floatingActiveDateVisible } from '../lib/simpleMode'

export function FloatingActiveDate({
  label,
  revealAfter = 220,
  tone = 'violet',
}: {
  label: string
  revealAfter?: number
  tone?: 'violet' | 'amber'
}) {
  const [visible, setVisible] = useState(false)

  useEffect(() => {
    let frame = 0
    const update = (): void => {
      frame = 0
      setVisible(floatingActiveDateVisible(window.scrollY, revealAfter))
    }
    const onScroll = (): void => {
      if (!frame) frame = window.requestAnimationFrame(update)
    }
    update()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => {
      window.removeEventListener('scroll', onScroll)
      if (frame) window.cancelAnimationFrame(frame)
    }
  }, [revealAfter])

  const toneClass = tone === 'amber'
    ? 'border-amber-200/65 text-amber-950 shadow-amber-900/10'
    : 'border-violet-200/65 text-violet-950 shadow-violet-900/10'

  return (
    <AnimatePresence initial={false}>
      {visible && (
        <motion.div
          aria-hidden="true"
          className="pointer-events-none fixed top-[calc(4.45rem+env(safe-area-inset-top))] left-1/2 z-30 max-w-[78vw] -translate-x-1/2"
          initial={{ opacity: 0, y: -8, scale: 0.96 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: -6, scale: 0.97 }}
          transition={{ duration: 0.18, ease: [0.22, 1, 0.36, 1] }}
        >
          <div className={`truncate rounded-full border bg-white/72 px-3 py-1.5 text-center font-mono text-[9px] font-black tracking-[0.1em] uppercase shadow-lg backdrop-blur-xl ${toneClass}`}>
            {label}
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
