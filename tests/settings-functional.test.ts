import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const root = new URL('../src/', import.meta.url)
const source = (path: string): string => readFileSync(new URL(path, root), 'utf8')

test('settings timezone has an explicit searchable selection and commit action', () => {
  const settings = source('pages/Settings.tsx')
  assert.match(settings, /searchTimeZoneOptions/)
  assert.match(settings, /commitTimeZone/)
  assert.match(settings, /Set timezone/)
  assert.match(settings, /Use device timezone/)
  assert.doesNotMatch(settings, /list="apex-time-zones"/)
})

test('selected SIMPLE mode remains a working route back home', () => {
  const topBar = source('components/TopBar.tsx')
  assert.match(topBar, /if \(mode !== uiMode\) setSettings/)
  assert.match(topBar, /navigate\('\/'\)/)
  assert.doesNotMatch(topBar, /mode === uiMode\) return/)
})

test('Simple Mode full-schedule link uses a real application route', () => {
  const simple = source('pages/SimpleHome.tsx')
  assert.match(simple, /guidedScheduleRoute = guidedProgramSlug === 'main' \? '\/main-phase' : '\/transition'/)
  assert.doesNotMatch(simple, /to={`\/\$\{guidedProgramSlug\}`}/)
})

test('meal editor exposes and persists a finished-at time', () => {
  const composer = source('components/food/MealComposer.tsx')
  const store = source('store/FoodStore.tsx')
  assert.match(composer, /Meal finished at/)
  assert.match(composer, /zonedDateTimeToIso/)
  assert.match(composer, /finishedAt:/)
  assert.match(store, /finishedAt\?: string \| null/)
  assert.match(store, /logged_at: finishedAt/)
})

test('meal recommendation memory can switch between daily and same-weekday history', () => {
  const settings = source('pages/Settings.tsx')
  const composer = source('components/food/MealComposer.tsx')
  const experience = source('lib/mealExperience.ts')
  assert.match(settings, /meal_memory_mode/)
  assert.match(settings, /\(\['daily', 'weekly'\] as const\)/)
  assert.match(composer, /memoryMode: data\.settings\?\.addons\.meal_memory_mode \?\? 'daily'/)
  assert.match(experience, /memoryMode === 'weekly' && sameWeekdayMeals\.length > 0/)
})

test('day-level automation and Avatar rollover follow the configured meal timezone', () => {
  const appStore = source('store/AppStore.tsx')
  assert.match(appStore, /zonedClock\(new Date\(\), timeZoneFromSettings\(data\.settings\)\)\.date/)
  assert.doesNotMatch(appStore, /computeEngine\(data, todayIso\(\)\)/)
})
