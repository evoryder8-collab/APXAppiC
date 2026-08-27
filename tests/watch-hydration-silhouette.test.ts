import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const canonicalPath = new URL(
  '../ios/APEXNative/APEX/Resources/Hydration/hydration-male.html',
  import.meta.url,
)
const watchPath = new URL(
  '../ios/APEXNative/APEX/Resources/Assets.xcassets/HydrationMaleSilhouette.imageset/HydrationMaleSilhouette.svg',
  import.meta.url,
)

function normalizePath(value: string): string {
  return value.trim().replaceAll(/\s+/g, ' ')
}

test('Watch hydration uses the exact canonical APEX body silhouette', () => {
  const canonical = readFileSync(canonicalPath, 'utf8')
  const watchAsset = readFileSync(watchPath, 'utf8')
  const canonicalBody = canonical.match(
    /<clipPath id="hydrationMale">[\s\S]*?<path\s+d="([^"]+)"/,
  )?.[1]
  const watchBody = watchAsset.match(/<path\s+d="([^"]+)"/)?.[1]

  assert.ok(canonicalBody, 'canonical phone silhouette path must exist')
  assert.ok(watchBody, 'Watch silhouette path must exist')
  assert.equal(normalizePath(watchBody), normalizePath(canonicalBody))
  assert.match(watchAsset, /viewBox="-150 -150 583\.6 1015"/)
})

test('Watch hydration refresh and animation remain event-driven', () => {
  const store = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationStore.swift', import.meta.url),
    'utf8',
  )
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  assert.doesNotMatch(store, /enableBackgroundDelivery|Timer\s*[.(]/)
  assert.match(store, /guard observerQuery == nil/)
  assert.match(store, /\[weak self\]/)
  assert.match(store, /synchronizeReminderSchedule/)
  assert.doesNotMatch(store, /DispatchSourceTimer|while\s+true/)
  assert.match(view, /@Environment\(\\\.scenePhase\)/)
  assert.match(view, /@Environment\(\\\.isLuminanceReduced\)/)
  assert.match(view, /\.onChange\(of: scenePhase\)/)
})

test('Watch hydration motion uses a smooth continuous animation clock', () => {
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  assert.match(view, /TimelineView\(\.animation\(paused:/)
  assert.doesNotMatch(view, /minimumInterval:/)
  assert.doesNotMatch(view, /truncatingRemainder/)
})

test('Watch hydration silhouette never floats vertically', () => {
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  const silhouette = view.slice(view.indexOf('private struct HydrationSilhouetteGauge'))
  assert.doesNotMatch(silhouette, /floatOffset/)
  assert.doesNotMatch(silhouette, /\.offset\(y:/)
})

test('Watch silhouette and horizontal gleam preserve weighted stops in their own orientation', () => {
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  assert.equal(view.match(/HydrationPalette\.stops\(/g)?.length, 1)
  assert.equal(view.match(/HydrationPalette\.timelineStops\(/g)?.length, 1)
  assert.match(view, /mappedInto: fillState\.baseWaterline \.\.\. 1/)
  assert.match(view, /startPoint: \.top,\s*endPoint: \.bottom/)
  assert.match(view, /timelineStops\(for: composition, fallback: \[violet, aqua\]\)/)
  assert.match(view, /startPoint: \.leading,\s*endPoint: \.trailing/)
})

test('Watch history offers deliberate tap and swipe deletion', () => {
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  assert.match(view, /\.swipeActions\(edge: \.trailing/)
  assert.match(view, /\.confirmationDialog\("Remove water entry\?"/)
})

test('Watch hydration keeps its title and settings in the native top bar', () => {
  const app = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/APEXWaterWatchApp.swift', import.meta.url),
    'utf8',
  )
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  assert.match(app, /NavigationStack/)
  assert.match(view, /ToolbarItem\(placement: \.topBarTrailing\)/)
  assert.match(view, /Label\("APEX HYDRATION", systemImage: "drop.fill"\)/)
  assert.match(view, /\.accessibilityLabel\("Hydration settings"\)/)
  assert.match(view, /\.scrollBounceBehavior\(\.basedOnSize\)/)
  assert.doesNotMatch(view, /\.navigationTitle\("APEX HYDRATION"\)/)
})

test('Watch hydration exposes configurable low-power presentation settings', () => {
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  assert.match(view, /struct WatchHydrationSettingsView/)
  assert.match(view, /Toggle\("Show preset names"/)
  assert.match(view, /Toggle\("Confirmation haptics"/)
  assert.match(view, /Toggle\("Hydration reminders"/)
  assert.match(view, /Picker\("Motion"/)
  assert.match(view, /Picker\("Units"/)
  assert.match(view, /HydrationProgressGleam/)
})
