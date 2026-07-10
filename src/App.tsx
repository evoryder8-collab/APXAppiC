import { useEffect, useState, type ReactNode } from 'react'
import { HashRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { AmbientBackground } from './components/AmbientBackground'
import { TopBar } from './components/TopBar'
import { Portal } from './pages/Portal'
import { Nutrition } from './pages/Nutrition'
import { WorkoutSection } from './pages/WorkoutSection'
import { AvatarPage } from './pages/AvatarPage'
import { Settings } from './pages/Settings'
import { Player } from './pages/Player'
import { Login } from './pages/Login'
import { PersonaIntro } from './components/PersonaIntro'
import { ProfileSwitcher } from './components/ProfileSwitcher'
import { AppStoreProvider, useStore } from './store/AppStore'
import { Toasts } from './components/ui'
import { ACCENTS } from './lib/theme'
import { startReminderLoop } from './lib/notify'
import {
  clearEntryGrant,
  clearSelectedPersona,
  getSelectedPersona,
  grantEntry,
  hasEntryGrant,
  setSelectedPersona,
  type PersonaSlug,
} from './lib/persona'

const EASE = [0.22, 1, 0.36, 1] as const

function Page({ children }: { children: ReactNode }) {
  return (
    <motion.main
      initial={{ opacity: 0, y: 14 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ duration: 0.26, ease: EASE }}
      className="min-h-dvh px-4 pt-24 pb-[calc(7rem+env(safe-area-inset-bottom))] sm:px-6 sm:pt-28"
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
        <Route path="/" element={<Page><Portal /></Page>} />
        <Route path="/nutrition" element={<Page><Nutrition /></Page>} />
        <Route
          path="/transition"
          element={
            <Page>
              <WorkoutSection slug="transition" accent={ACCENTS.teal} title="Transition Phase" />
            </Page>
          }
        />
        <Route
          path="/main-phase"
          element={
            <Page>
              <WorkoutSection slug="main" accent={ACCENTS.violet} title="Main Phase" />
            </Page>
          }
        />
        <Route path="/avatar" element={<Page><AvatarPage /></Page>} />
        <Route path="/settings" element={<Page><Settings /></Page>} />
        <Route path="/player/:slug/:date" element={<Page><Player /></Page>} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AnimatePresence>
  )
}

/* Meal + supplement reminders run whenever the app is open and signed in */
function Reminders() {
  const { data } = useStore()
  useEffect(() => {
    return startReminderLoop(() => ({
      meals: data.meals,
      supplements: data.supplements,
      trainingTime: data.profile?.training_time ?? '19:00',
      enabled: data.settings?.notifications_on ?? false,
    }))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data.meals, data.supplements, data.profile?.training_time, data.settings?.notifications_on])
  return null
}

function Shell() {
  const { ready, authed, signOut, toasts } = useStore()
  const [selectedPersona, setSelectedPersonaState] = useState<PersonaSlug | null>(() =>
    hasEntryGrant() ? getSelectedPersona() : null,
  )
  const [entryGranted, setEntryGranted] = useState(hasEntryGrant)
  const [switchingPersona, setSwitchingPersona] = useState(false)

  const returnToPersonaIntro = async (): Promise<void> => {
    if (switchingPersona) return
    setSwitchingPersona(true)
    // Move the UI back to the selector before the auth request begins. This
    // keeps the persistent switcher responsive even when sign-out is slow.
    setSelectedPersonaState(null)
    setEntryGranted(false)
    clearSelectedPersona()
    clearEntryGrant()
    window.location.hash = '#/'
    try {
      await signOut()
    } finally {
      setSwitchingPersona(false)
    }
  }

  if (!ready) {
    return (
      <div className="flex min-h-dvh items-center justify-center">
        <div className="glass skeleton h-24 w-64 rounded-3xl" aria-label="Loading APEX" />
      </div>
    )
  }
  if (!selectedPersona) {
    return (
      <>
        <PersonaIntro
          onSelect={(persona) => {
            setSelectedPersona(persona)
            setSelectedPersonaState(persona)
            clearEntryGrant()
            setEntryGranted(false)
          }}
        />
        <Toasts items={toasts} />
      </>
    )
  }
  if (!entryGranted || !authed) {
    return (
      <>
        <Login
          persona={selectedPersona}
          onBack={() => {
            clearSelectedPersona()
            clearEntryGrant()
            setSelectedPersonaState(null)
            setEntryGranted(false)
          }}
          onSuccess={() => {
            grantEntry()
            setEntryGranted(true)
          }}
        />
        <Toasts items={toasts} />
      </>
    )
  }
  return (
    <>
      <TopBar />
      <AnimatedRoutes />
      <ProfileSwitcher
        activePersona={selectedPersona}
        busy={switchingPersona}
        onSwitch={() => void returnToPersonaIntro()}
      />
      <Reminders />
      <Toasts items={toasts} />
    </>
  )
}

export default function App() {
  return (
    <AppStoreProvider>
      <HashRouter>
        <AmbientBackground />
        <Shell />
      </HashRouter>
    </AppStoreProvider>
  )
}
