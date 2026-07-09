import type { ReactNode } from 'react'
import { HashRouter, Route, Routes, useLocation } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { AmbientBackground } from './components/AmbientBackground'
import { TopBar } from './components/TopBar'
import { Portal } from './pages/Portal'
import { SectionPlaceholder } from './pages/SectionPlaceholder'
import { ACCENTS } from './lib/theme'
import { AvatarIcon, BoltIcon, LeafIcon, SlidersIcon, TransitionIcon } from './components/Icons'

const EASE = [0.22, 1, 0.36, 1] as const

function Page({ children }: { children: ReactNode }) {
  return (
    <motion.main
      initial={{ opacity: 0, y: 14 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ duration: 0.26, ease: EASE }}
      className="min-h-dvh px-4 pt-24 pb-[max(3rem,env(safe-area-inset-bottom))] sm:px-6 sm:pt-28"
    >
      {children}
    </motion.main>
  )
}

function AnimatedRoutes() {
  const location = useLocation()
  return (
    <AnimatePresence mode="wait">
      <Routes location={location} key={location.pathname}>
        <Route
          path="/"
          element={
            <Page>
              <Portal />
            </Page>
          }
        />
        <Route
          path="/nutrition"
          element={
            <Page>
              <SectionPlaceholder
                accent={ACCENTS.amber}
                title="Nutrition"
                phase="ARRIVES IN PHASE 3"
                description="Targets, meal reminders, your supplement timeline and the fast evening log. All of it lands here."
                icon={<LeafIcon className="h-7 w-7" />}
              />
            </Page>
          }
        />
        <Route
          path="/transition"
          element={
            <Page>
              <SectionPlaceholder
                accent={ACCENTS.teal}
                title="Transition Phase"
                phase="ARRIVES IN PHASE 4"
                description="Your current home program. Calendar, guided player, streaks and smart progression are on the way."
                icon={<TransitionIcon className="h-7 w-7" />}
              />
            </Page>
          }
        />
        <Route
          path="/main-phase"
          element={
            <Page>
              <SectionPlaceholder
                accent={ACCENTS.violet}
                title="Main Phase"
                phase="ARRIVES IN PHASE 4"
                description="Elite V6, full and Lite variants. It waits here until the transition is done."
                icon={<BoltIcon className="h-7 w-7" />}
              />
            </Page>
          }
        />
        <Route
          path="/avatar"
          element={
            <Page>
              <SectionPlaceholder
                accent={ACCENTS.emerald}
                title="Avatar"
                phase="ARRIVES IN PHASE 7"
                description="Six stat bars, the radar chart, your level and the recommendation engine. The game lives here."
                icon={<AvatarIcon className="h-7 w-7" />}
              />
            </Page>
          }
        />
        <Route
          path="/settings"
          element={
            <Page>
              <SectionPlaceholder
                accent={ACCENTS.violet}
                title="Settings"
                phase="ARRIVES IN PHASE 3"
                description="Profile, body stats, targets and notification preferences arrive together with the Nutrition build."
                icon={<SlidersIcon className="h-7 w-7" />}
              />
            </Page>
          }
        />
      </Routes>
    </AnimatePresence>
  )
}

export default function App() {
  return (
    <HashRouter>
      <AmbientBackground />
      <TopBar />
      <AnimatedRoutes />
    </HashRouter>
  )
}
