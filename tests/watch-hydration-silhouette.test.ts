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
const projectPath = new URL(
  '../ios/APEXNative/APEXNative.xcodeproj/project.pbxproj',
  import.meta.url,
)

function normalizePath(value: string): string {
  return value.trim().replaceAll(/\s+/g, ' ')
}

test('Watch hydration uses the exact canonical FITR MAX body silhouette', () => {
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

test('Watch target packages the icon and hydration silhouette asset catalog', () => {
  const project = readFileSync(projectPath, 'utf8')
  const targetStart = project.indexOf('/* APEXWatch */ = {\n\t\t\tisa = PBXNativeTarget;')
  const targetEnd = project.indexOf('\n\t\t};', targetStart)
  const watchTarget = project.slice(targetStart, targetEnd)
  const resourcesPhaseID = watchTarget.match(/([A-F0-9]{24}) \/\* Resources \*\//)?.[1]

  assert.ok(resourcesPhaseID, 'APEXWatch must have a resources build phase')

  const phaseStart = project.indexOf(`${resourcesPhaseID} /* Resources */ = {`)
  const phaseEnd = project.indexOf('\n\t\t};', phaseStart)
  const resourcesPhase = project.slice(phaseStart, phaseEnd)

  assert.match(resourcesPhase, /Assets\.xcassets in Resources/)

  const appIcon = readFileSync(
    new URL('../ios/APEXNative/APEX/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json', import.meta.url),
    'utf8',
  )
  assert.match(appIcon, /"platform"\s*:\s*"watchos"/)
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

test('Watch figure turns on the spot and never floats vertically', () => {
  const vessel = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchBodyVessel.swift', import.meta.url),
    'utf8',
  )

  assert.match(vessel, /case \.figure: vessel\.eulerAngles\.y = Float\(turn\)/)
  assert.doesNotMatch(vessel, /floatOffset/)
  assert.doesNotMatch(vessel, /vessel\.position\.y\s*=/)
})

test('Watch figure is built from the canonical silhouette asset', () => {
  const project = readFileSync(projectPath, 'utf8')
  const generator = readFileSync(
    new URL('../ios/APEXNative/Tools/generate-watch-body-mesh.py', import.meta.url),
    'utf8',
  )
  const vessel = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchBodyVessel.swift', import.meta.url),
    'utf8',
  )

  assert.match(generator, /WatchHydrationSilhouette\.png/)
  assert.match(vessel, /forResource: "WatchBody", withExtension: "bin"/)
  assert.match(project, /WatchBody\.bin in Resources/)
})

test('Watch figure and horizontal gleam preserve weighted stops in their own orientation', () => {
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  // The liquid counts upwards from the feet, the layout downwards from the surface.
  assert.equal(view.match(/HydrationCompositionLayout\.stops\(/g)?.length, 1)
  assert.match(view, /HydrationCompositionLayout\.stops\(for: bands, mappedInto: 0 \.\.\. 1\)/)
  assert.match(view, /location: 1 - \$0\.location/)
  assert.equal(view.match(/HydrationPalette\.timelineStops\(/g)?.length, 1)
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

test('Watch pages turn with the Digital Crown and keep the clock clear', () => {
  const app = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/APEXWaterWatchApp.swift', import.meta.url),
    'utf8',
  )
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  assert.match(app, /NavigationStack/)
  assert.match(view, /\.tabViewStyle\(\.verticalPage\)/)
  assert.match(view, /\.accessibilityLabel\("Hydration settings"\)/)
  assert.match(view, /\.scrollBounceBehavior\(\.basedOnSize\)/)
  // A title beside the clock overlapped it on every Watch size.
  assert.doesNotMatch(view, /ToolbarItem\(placement: \.topBarTrailing\)/)
  assert.doesNotMatch(view, /\.navigationTitle\("FITR MAX(?: Watch)?"\)/)
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
