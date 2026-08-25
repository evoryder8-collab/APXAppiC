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
  assert.match(view, /@Environment\(\\\.scenePhase\)/)
  assert.match(view, /@Environment\(\\\.isLuminanceReduced\)/)
  assert.match(view, /\.onChange\(of: scenePhase\)/)
})

test('Watch history offers deliberate tap and swipe deletion', () => {
  const view = readFileSync(
    new URL('../ios/APEXNative/APEXWatch/WatchHydrationView.swift', import.meta.url),
    'utf8',
  )

  assert.match(view, /\.swipeActions\(edge: \.trailing/)
  assert.match(view, /\.confirmationDialog\("Remove water entry\?"/)
})
