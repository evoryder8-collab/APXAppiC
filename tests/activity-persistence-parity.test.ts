import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const appStore = readFileSync(new URL('../src/store/AppStore.tsx', import.meta.url), 'utf8')
const liveRun = readFileSync(new URL('../src/orbit/pages/LiveRun.tsx', import.meta.url), 'utf8')

test('automatic daily-log persistence uses the current date wearable total once', () => {
  const start = appStore.indexOf('/* ---------- activity automation shared by every route ---------- */')
  const end = appStore.indexOf('/* ---------- realtime merge from other devices ---------- */', start)
  const automation = appStore.slice(start, end)

  assert.match(
    automation,
    /const wearableActiveCalories = \(data\.settings\?\.addons\.watch_activity_history \?\? \[\]\)[\s\S]*record\.date === date[\s\S]*\.at\(-1\)\?\.active_calories/,
  )
  assert.match(
    automation,
    /estimateActivityDay\(profile, blocks, catalog, undefined, wearableActiveCalories\)/,
  )
  assert.match(automation, /data\.settings, upsert\]\)/)
})

test('automatic activity persistence reads and updates only the active owner rows', () => {
  const start = appStore.indexOf('/* ---------- activity automation shared by every route ---------- */')
  const end = appStore.indexOf('/* ---------- realtime merge from other devices ---------- */', start)
  const automation = appStore.slice(start, end)

  assert.match(
    automation,
    /data\.activity_logs\.filter\(\s*\(log\) => log\.user_id === profile\.user_id && log\.date === date,?\s*\)/,
  )
  assert.match(
    automation,
    /data\.daily_logs\.find\(\s*\(log\) => log\.user_id === profile\.user_id && log\.date === date,?\s*\)/,
  )
})

test('finishing an Orbit run persists the wearable total for that run date once', () => {
  const start = liveRun.indexOf('const finish = async')
  const end = liveRun.indexOf('const cancel = async', start)
  const finish = liveRun.slice(start, end)

  assert.match(
    finish,
    /const wearableActiveCalories = \(app\.data\.settings\?\.addons\.watch_activity_history \?\? \[\]\)[\s\S]*record\.date === completed\.local_date[\s\S]*\.at\(-1\)\?\.active_calories/,
  )
  assert.match(
    finish,
    /estimateActivityDay\(\s*profile,[\s\S]*catalog,\s*undefined,\s*wearableActiveCalories,/,
  )
})
