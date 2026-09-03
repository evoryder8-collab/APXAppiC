import { lazy, Suspense, useEffect, useState, type ReactNode } from 'react'
import { HashRouter, Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { AnimatePresence, motion } from 'framer-motion'
import { AmbientBackground } from './components/AmbientBackground'
import { TopBar } from './components/TopBar'
import { ProfileSwitcher } from './components/ProfileSwitcher'
import { AccessRecovery } from './components/AccessRecovery'
import { AppStoreProvider, useStore } from './store/AppStore'
import { FoodStoreProvider } from './store/FoodStore'
import { ProgressPhotoStoreProvider } from './store/ProgressPhotoStore'
import { OrbitStoreProvider } from './orbit/store/OrbitStore'
import { Toasts } from './components/ui'
import { ACCENTS } from './lib/theme'
import { startReminderLoop } from './lib/notify'
import { LanguageProvider } from './lib/i18n'
import { uiModeFromSettings } from './lib/simpleMode'
import {
  accountAccessAllowsRoute,
  accountAccessHasAppAccess,
  clientPolicyForAccount,
} from './lib/coachAccess'
import type { CoachClientPolicy } from './lib/coachPlatform'
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

/* Keep the 3D identity gate and each feature page out of the initial bundle.
   Returning users now reach the portal without downloading the hologram
   renderer, and opening one feature does not parse every other feature. */
const Portal = lazy(() => import('./pages/Portal').then((module) => ({ default: module.Portal })))
const SimpleHome = lazy(() => import('./pages/SimpleHome').then((module) => ({ default: module.SimpleHome })))
const Nutrition = lazy(() => import('./pages/Nutrition').then((module) => ({ default: module.Nutrition })))
const WorkoutSection = lazy(() => import('./pages/WorkoutSection').then((module) => ({ default: module.WorkoutSection })))
const AvatarPage = lazy(() => import('./pages/AvatarPage').then((module) => ({ default: module.AvatarPage })))
const Settings = lazy(() => import('./pages/Settings').then((module) => ({ default: module.Settings })))
const Player = lazy(() => import('./pages/Player').then((module) => ({ default: module.Player })))
const TrackedSession = lazy(() => import('./pages/TrackedSession').then((module) => ({ default: module.TrackedSession })))
const Login = lazy(() => import('./pages/Login').then((module) => ({ default: module.Login })))
const VisualProgress = lazy(() => import('./pages/VisualProgress').then((module) => ({ default: module.VisualProgress })))
const NeutralEntry = lazy(() => import('./components/NeutralEntry').then((module) => ({ default: module.NeutralEntry })))
const OrbitHome = lazy(() => import('./orbit/pages/OrbitHome').then((module) => ({ default: module.OrbitHome })))
const RoutePlanner = lazy(() => import('./orbit/pages/RoutePlanner').then((module) => ({ default: module.RoutePlanner })))
const LiveRun = lazy(() => import('./orbit/pages/LiveRun').then((module) => ({ default: module.LiveRun })))
const RunDebrief = lazy(() => import('./orbit/pages/RunDebrief').then((module) => ({ default: module.RunDebrief })))
const OrbitLibrary = lazy(() => import('./orbit/pages/OrbitLibrary').then((module) => ({ default: module.OrbitLibrary })))
const MarathonInductionPage = lazy(() => import('./orbit/pages/MarathonInduction').then((module) => ({ default: module.MarathonInductionPage })))
const MarathonCampaignPage = lazy(() => import('./orbit/pages/MarathonCampaign').then((module) => ({ default: module.MarathonCampaignPage })))
const OrbitScience = lazy(() => import('./orbit/pages/OrbitScience').then((module) => ({ default: module.OrbitScience })))
const CoachWorkspace = lazy(() => import('./pages/CoachWorkspace').then((module) => ({ default: module.CoachWorkspace })))
const CoachInvitation = lazy(() => import('./pages/CoachInvitation').then((module) => ({ default: module.CoachInvitation })))
const CoachPlan = lazy(() => import('./pages/CoachPlan').then((module) => ({ default: module.CoachPlan })))

function AccountFeature({ capability, children }: { capability: keyof CoachClientPolicy; children: ReactNode }) {
  const { appAccess, coachContext } = useStore()
  return clientPolicyForAccount(appAccess, coachContext)[capability]
    ? children
    : <Navigate to="/coach-plan" replace />
}

function LoadingSurface({ page = false }: { page?: boolean }) {
  return (
    <div className={`flex items-center justify-center px-6 ${page ? 'min-h-[55dvh] pt-24' : 'min-h-dvh'}`}>
      <div className="h-20 w-56 animate-pulse rounded-3xl border border-white/80 bg-white/75 shadow-lg" aria-label="Loading APEX" />
    </div>
  )
}

function Page({ children, immersive = false }: { children: ReactNode; immersive?: boolean }) {
  return (
    <motion.main
      initial={{ opacity: 0, y: 14 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -10 }}
      transition={{ duration: 0.26, ease: EASE }}
      className={`min-h-dvh px-4 pt-24 sm:px-6 sm:pt-28 ${immersive ? 'pb-[max(1rem,env(safe-area-inset-bottom))]' : 'pb-[calc(7rem+env(safe-area-inset-bottom))]'}`}
    >
      {children}
    </motion.main>
  )
}

function AnimatedRoutes() {
  const location = useLocation()
  const { data } = useStore()
  const simple = uiModeFromSettings(data.settings) === 'simple'
  const settingsOnly = !data.profile && Boolean(data.settings)
  return (
    <AnimatePresence mode="wait">
      <Routes location={location} key={location.pathname}>
        <Route path="/" element={<Page>{settingsOnly ? <AccountFeature capability="can_rebuild_fitness_plan"><WorkoutSection slug="transition" accent={ACCENTS.teal} title="Transition Phase" /></AccountFeature> : simple ? <SimpleHome /> : <Portal />}</Page>} />
        <Route path="/nutrition" element={<AccountFeature capability="can_use_nutrition"><Page><Nutrition /></Page></AccountFeature>} />
        <Route
          path="/transition"
          element={
            <Page>
              <AccountFeature capability="can_rebuild_fitness_plan"><WorkoutSection slug="transition" accent={ACCENTS.teal} title="Transition Phase" /></AccountFeature>
            </Page>
          }
        />
        <Route
          path="/main-phase"
          element={
            <Page>
              <AccountFeature capability="can_rebuild_fitness_plan"><WorkoutSection slug="main" accent={ACCENTS.violet} title="Main Phase" /></AccountFeature>
            </Page>
          }
        />
        <Route
          path="/custom-workouts"
          element={
            <Page>
              <AccountFeature capability="can_create_custom_workouts"><WorkoutSection slug="custom" accent={ACCENTS.violet} title="Custom workouts" /></AccountFeature>
            </Page>
          }
        />
        <Route path="/avatar" element={<AccountFeature capability="can_use_avatar"><Page><AvatarPage /></Page></AccountFeature>} />
        <Route path="/progress" element={<AccountFeature capability="can_view_visual_progress"><Page><VisualProgress /></Page></AccountFeature>} />
        <Route path="/orbit" element={<AccountFeature capability="can_use_orbit"><Page><OrbitHome /></Page></AccountFeature>} />
        <Route path="/orbit/plan" element={<AccountFeature capability="can_use_orbit"><Page><RoutePlanner /></Page></AccountFeature>} />
        <Route path="/orbit/run" element={<AccountFeature capability="can_use_orbit"><Page><LiveRun /></Page></AccountFeature>} />
        <Route path="/orbit/debrief/:runId" element={<AccountFeature capability="can_use_orbit"><Page><RunDebrief /></Page></AccountFeature>} />
        <Route path="/orbit/library" element={<AccountFeature capability="can_use_orbit"><Page><OrbitLibrary /></Page></AccountFeature>} />
        <Route path="/orbit/induction" element={<AccountFeature capability="can_use_orbit"><Page><MarathonInductionPage /></Page></AccountFeature>} />
        <Route path="/orbit/campaign" element={<AccountFeature capability="can_use_orbit"><Page><MarathonCampaignPage /></Page></AccountFeature>} />
        <Route path="/orbit/science" element={<AccountFeature capability="can_use_orbit"><Page><OrbitScience /></Page></AccountFeature>} />
        <Route path="/settings" element={<Page><Settings /></Page>} />
        <Route path="/coach" element={<Page><CoachWorkspace /></Page>} />
        <Route path="/coach/invite/:token" element={<Page><CoachInvitation /></Page>} />
        <Route path="/coach-plan" element={<Page><CoachPlan /></Page>} />
        <Route path="/coach-workouts" element={<AccountFeature capability="can_follow_coach_plan"><Page><WorkoutSection slug="coach" accent={ACCENTS.violet} title="Coach plan" /></Page></AccountFeature>} />
        <Route path="/player/:slug/:date" element={<Page immersive><Player /></Page>} />
        <Route path="/log/:slug/:date" element={<Page><TrackedSession /></Page>} />
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
  const { appAccess, coachContext, ready, authed, signOut, toasts } = useStore()
  const location = useLocation()
  const workoutPlayerOpen = location.pathname.startsWith('/player/')
  const [selectedPersona, setSelectedPersonaState] = useState<PersonaSlug | null>(() =>
    hasEntryGrant() ? getSelectedPersona() : null,
  )
  const [entryGranted, setEntryGranted] = useState(hasEntryGrant)
  const [entrySurface, setEntrySurface] = useState<'neutral' | 'login'>('neutral')
  const [switchingPersona, setSwitchingPersona] = useState(false)

  const returnToPersonaIntro = async (): Promise<void> => {
    if (switchingPersona) return
    setSwitchingPersona(true)
    // Move the UI back to the selector before the auth request begins. This
    // keeps the persistent switcher responsive even when sign-out is slow.
    setSelectedPersonaState(null)
    setEntryGranted(false)
    setEntrySurface('neutral')
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
  const needsEntry = !selectedPersona || !entryGranted || !authed
  if (needsEntry && entrySurface === 'neutral') {
    return (
      <>
        <Suspense fallback={<LoadingSurface />}>
          <NeutralEntry
            onLogin={() => {
              clearSelectedPersona()
              clearEntryGrant()
              setSelectedPersonaState(null)
              setEntryGranted(false)
              setEntrySurface('login')
            }}
          />
        </Suspense>
        <Toasts items={toasts} />
      </>
    )
  }
  if (needsEntry) {
    return (
      <>
        <Suspense fallback={<LoadingSurface />}>
          <Login
            onBack={() => {
              clearSelectedPersona()
              clearEntryGrant()
              setSelectedPersonaState(null)
              setEntryGranted(false)
              setEntrySurface('neutral')
            }}
            onSuccess={(persona) => {
              setSelectedPersona(persona)
              setSelectedPersonaState(persona)
              grantEntry()
              setEntryGranted(true)
            }}
          />
        </Suspense>
        <Toasts items={toasts} />
      </>
    )
  }
  if (appAccess.status === 'pending') {
    return <LoadingSurface />
  }
  const gracePlanOnly = clientPolicyForAccount(appAccess, coachContext).coach_plan_read_only
  const appUnlocked = accountAccessHasAppAccess(appAccess)
  if (!accountAccessAllowsRoute(appAccess, coachContext, location.pathname)) {
    if (gracePlanOnly || appUnlocked) return <Navigate to="/coach-plan" replace />
    return (
      <>
        <AccessRecovery />
        <Toasts items={toasts} />
      </>
    )
  }
  return (
    <>
      <TopBar />
      <Suspense fallback={<LoadingSurface page />}>
        <AnimatedRoutes />
      </Suspense>
      {!workoutPlayerOpen && (
        <ProfileSwitcher
          activePersona={selectedPersona}
          busy={switchingPersona}
          onSwitch={() => void returnToPersonaIntro()}
        />
      )}
      <Reminders />
      <Toasts items={toasts} />
    </>
  )
}

function PrivateStoreScope({ children }: { children: ReactNode }) {
  const { appAccess, data } = useStore()
  if (!accountAccessHasAppAccess(appAccess)) return <>{children}</>
  const ownerKey = appAccess.owner_user_id ?? data.profile?.user_id ?? data.settings?.user_id ?? 'signed-out'
  /* Food, photo and Orbit stores contain private owner-scoped state. Remount
     the complete subtree at the account boundary so React can never render a
     previous owner's rows while the next owner's IndexedDB hydration begins. */
  return (
    <FoodStoreProvider key={ownerKey}>
      <ProgressPhotoStoreProvider>
        <OrbitStoreProvider>{children}</OrbitStoreProvider>
      </ProgressPhotoStoreProvider>
    </FoodStoreProvider>
  )
}

export default function App() {
  return (
    <LanguageProvider>
      <AppStoreProvider>
        <PrivateStoreScope>
          <HashRouter>
            <AmbientBackground />
            <Shell />
          </HashRouter>
        </PrivateStoreScope>
      </AppStoreProvider>
    </LanguageProvider>
  )
}
