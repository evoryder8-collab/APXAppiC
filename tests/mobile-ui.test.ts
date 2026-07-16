import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const glance = readFileSync(new URL('../src/components/food/NutritionGlance.tsx', import.meta.url), 'utf8')
const simple = readFileSync(new URL('../src/pages/SimpleHome.tsx', import.meta.url), 'utf8')
const nutrition = readFileSync(new URL('../src/pages/Nutrition.tsx', import.meta.url), 'utf8')
const styles = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')

test('NutritionGlance keeps calorie figures inside bounded responsive columns', () => {
  assert.match(glance, /grid-cols-\[minmax\(0,\.9fr\)_minmax\(7rem,1\.25fr\)_minmax\(0,\.9fr\)\]/)
  assert.match(glance, /whitespace-nowrap font-mono text-\[clamp\(1\.15rem,5\.8vw,1\.5rem\)\]/)
  assert.match(glance, /whitespace-nowrap font-mono text-\[clamp\(1\.35rem,7vw,1\.875rem\)\]/)
})

test('both date surfaces gate interactive starts and cancel tracked gestures on touch changes', () => {
  for (const source of [simple, nutrition]) {
    assert.match(source, /isDaySwipeInteractiveTarget\(event\.target\)/)
    assert.match(source, /canStartDaySwipe\(event\.touches\.length/)
    assert.match(source, /onTouchMove=/)
    assert.match(source, /daySwipeHasSingleTrackedTouch/)
    assert.match(source, /canFinishDaySwipe\(event\.touches\.length/)
    assert.match(source, /touch-pinch-zoom/)
    assert.match(source, /ios-focus-safe/)
    assert.match(source, /<FloatingActiveDate label=/)
  }
  assert.match(styles, /\.ios-focus-safe input[\s\S]*?font-size: 16px !important/)
})
