import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const launcher = readFileSync(new URL('../src/components/workout/QuickWorkoutLauncher.tsx', import.meta.url), 'utf8')
const logger = readFileSync(new URL('../src/components/workout/ManualWorkoutLogger.tsx', import.meta.url), 'utf8')
const workoutDomain = readFileSync(new URL('../src/lib/manualWorkout.ts', import.meta.url), 'utf8')

test('compact launcher is reusable in either Simple Mode and opens ranked presets or the full logger', () => {
  assert.match(launcher, /export interface QuickWorkoutLauncherProps/)
  assert.match(launcher, /date: string/)
  assert.match(launcher, /data-simple-local-gesture/)
  assert.match(launcher, /rankManualWorkoutPresets\(data, date\)\.slice\(0, QUICK_WORKOUT_PRESET_LIMIT\)/)
  assert.match(launcher, /onClick=\{\(\) => openLogger\(preset\.signature\)\}/)
  assert.match(launcher, /initialPresetSignature=\{initialPresetSignature\}/)
  assert.match(launcher, /\{t\('Expand'\)\}/)
  assert.match(launcher, /<ManualWorkoutLogger/)
})

test('launcher uses the seven-preset product contract and does not introduce transient workout storage', () => {
  assert.match(workoutDomain, /QUICK_WORKOUT_PRESET_LIMIT = 7/)
  assert.match(workoutDomain, /\.slice\(0, QUICK_WORKOUT_PRESET_LIMIT\)/)
  assert.doesNotMatch(launcher, /localStorage|sessionStorage|indexedDB/)
  assert.match(logger, /upsert\('workout_sessions', session\)/)
  assert.match(logger, /bulkUpsert\('workout_logs', reconciled\.logs\)/)
})

test('whole-workout removal is confirmed and queues child deletes before session deletes', () => {
  assert.match(logger, /Delete whole workout\?/)
  assert.match(logger, /\{t\('Cancel'\)\}/)
  assert.match(logger, /\{t\('Yes'\)\}/)
  const deleteStart = logger.indexOf('const deleteWholeWorkout')
  const deleteBlock = logger.slice(deleteStart, logger.indexOf("if (timeline.length === 0)", deleteStart))
  assert.ok(deleteStart >= 0)
  assert.ok(deleteBlock.indexOf("remove('workout_logs'") < deleteBlock.indexOf("remove('workout_sessions'"))
  assert.match(workoutDomain, /manualWorkoutDeletionPlan[\s\S]*manualSessionsForDate\(data, dateIso\)/)
})

test('a chosen preset preloads its title and editable exercise draft', () => {
  assert.match(logger, /initialPresetSignature\?: string \| null/)
  assert.match(logger, /presets\.find\(\(preset\) => preset\.signature === initialPresetSignature\)/)
  assert.match(logger, /setTitle\(editorDraft\?\.title \?\? \(initialPreset/)
  assert.match(logger, /clonePreset\(initialPreset\.exercises\)/)
})
