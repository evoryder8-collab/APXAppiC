import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { EMPTY_DATA, type AppData, type ImportedActivity, type WorkoutLog, type WorkoutSession } from '../src/lib/types.ts'
import type { IntroLanguage } from '../src/lib/introLanguage.ts'
import { ACTIVITY_TRANSLATIONS, UI_TRANSLATIONS } from '../src/lib/translations.ts'
import * as completedWorkoutHistoryModule from '../src/lib/completedWorkoutHistory.ts'
import {
  collapsedWorkoutDeleteTrayVisible,
  completedWorkoutDeletionPlan,
  completedWorkoutHistoryForDate,
  externalWorkoutHidePlan,
  finishedWorkoutHistoryForDate,
} from '../src/lib/completedWorkoutHistory.ts'
import { manualWorkoutNotes } from '../src/lib/manualWorkout.ts'

function session(overrides: Partial<WorkoutSession> & Pick<WorkoutSession, 'id' | 'date' | 'program_day_id'>): WorkoutSession {
  return {
    id: overrides.id,
    user_id: overrides.user_id ?? 'owner',
    date: overrides.date,
    program_day_id: overrides.program_day_id,
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: overrides.completed ?? true,
    quality_score: 1,
    started_at: overrides.started_at ?? `${overrides.date}T08:00:00.000Z`,
    completed_at: overrides.completed_at ?? `${overrides.date}T09:00:00.000Z`,
    notes: overrides.notes ?? 'Completed in tracked mode',
  }
}

function log(id: string, sessionId: string, userId = 'owner'): WorkoutLog {
  return {
    id, user_id: userId, session_id: sessionId, exercise_id: null,
    exercise_name: 'Front Lunge', set_no: 1, weight_kg: 25, reps: 12, rir: 2,
    skipped: false, override_flag: false, created_at: '2026-08-26T08:15:00.000Z',
  }
}

function externalWorkout(overrides: Partial<ImportedActivity> & Pick<ImportedActivity, 'id'>): ImportedActivity {
  return {
    id: overrides.id,
    user_id: overrides.user_id ?? 'owner',
    date: overrides.date ?? '2026-08-26',
    kind: overrides.kind ?? 'endurance',
    activity: overrides.activity ?? 'Outdoor Run',
    duration_min: overrides.duration_min ?? 42,
    source: overrides.source ?? 'Constantin’s Apple Watch',
    healthkit_workout_id: 'healthkit_workout_id' in overrides ? overrides.healthkit_workout_id : `hk-${overrides.id}`,
    started_at: overrides.started_at ?? '2026-08-26T10:00:00.000Z',
    ended_at: overrides.ended_at ?? '2026-08-26T10:42:00.000Z',
    workout_name_key: overrides.workout_name_key ?? 'health.workout.outdoor_run',
    distance_km: overrides.distance_km ?? 7.25,
    active_energy_kcal: overrides.active_energy_kcal ?? 510,
    source_bundle_id: overrides.source_bundle_id ?? 'com.apple.health',
    activity_type_raw: overrides.activity_type_raw ?? 37,
    apex_workout_session_id: overrides.apex_workout_session_id ?? null,
    hidden_at: overrides.hidden_at ?? null,
  }
}

test('history returns every completed quick and tracked workout on the date, independent of the active plan day', () => {
  const tracked = session({
    id: 'tracked', date: '2026-08-26', program_day_id: 'old-generated-day',
    completed_at: '2026-08-26T09:00:00.000Z',
  })
  const quick = session({
    id: 'quick', date: '2026-08-26', program_day_id: 'custom-day',
    notes: manualWorkoutNotes('Lunch break lift'),
    completed_at: '2026-08-26T12:00:00.000Z',
  })
  const incomplete = session({
    id: 'unfinished', date: '2026-08-26', program_day_id: 'active-day', completed: false,
  })
  const otherDate = session({
    id: 'yesterday', date: '2026-08-25', program_day_id: 'active-day',
  })
  const foreign = session({
    id: 'foreign', user_id: 'someone-else', date: '2026-08-26', program_day_id: 'active-day',
  })
  const data: AppData = {
    ...EMPTY_DATA,
    profile: {
      id: 'profile', user_id: 'owner', persona: 'constantine', display_name: 'Owner', sex: 'male',
      weight_kg: 80, body_fat_pct: 15, custom_bmr: null, height_cm: 180, birthdate: '1990-01-01',
      activity_level: 'moderate', goal: 'maintain', target_kcal: null, target_protein_g: null,
      target_fat_g: null, target_carbs_g: null, training_time: '18:00', baseline_date: '2026-01-01',
      profile_note: '', seed_version: 1, calibration_k: 1, calibration_history: [],
      updated_at: '2026-08-26T00:00:00.000Z',
    },
    program_days: [{
      id: 'old-generated-day', user_id: 'owner', program_id: 'program', weekday: 3,
      name: 'Tracked legs', day_type: 'legs_a', est_minutes: 45, warmup_note: '', sort_order: 0,
    }],
    workout_sessions: [tracked, quick, incomplete, otherDate, foreign],
  }

  const history = completedWorkoutHistoryForDate(data, '2026-08-26')
  assert.deepEqual(history.map((item) => item.session.id), ['quick', 'tracked'])
  assert.equal(history[0]?.title, 'Lunch break lift')
  assert.equal(history[0]?.isQuickLog, true)
  assert.equal(history[1]?.title, 'Tracked legs')
  assert.equal(history[1]?.isQuickLog, false)
})

test('recent history crosses calendar dates while remaining owner-scoped and bounded', () => {
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: 'owner',
      theme: 'dark',
      language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    workout_sessions: [
      session({ id: 'newest', date: '2026-08-27', program_day_id: 'day', completed_at: '2026-08-27T19:00:00.000Z' }),
      session({ id: 'older', date: '2026-08-25', program_day_id: 'day', completed_at: '2026-08-25T19:00:00.000Z' }),
      session({ id: 'foreign', user_id: 'someone-else', date: '2026-08-28', program_day_id: 'day' }),
    ],
  }

  assert.deepEqual(
    completedWorkoutHistoryForDate(data, undefined, 1).map((item) => item.session.id),
    ['newest'],
  )
})

test('unbounded recent history returns every owned completed workout instead of hiding older receipts', () => {
  const workouts = Array.from({ length: 10 }, (_, index) => session({
    id: `workout-${index + 1}`,
    date: `2026-08-${String(index + 1).padStart(2, '0')}`,
    program_day_id: 'day',
    completed_at: `2026-08-${String(index + 1).padStart(2, '0')}T19:00:00.000Z`,
  }))
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: 'owner',
      theme: 'dark',
      language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    workout_sessions: workouts,
  }

  const history = completedWorkoutHistoryForDate(data)

  assert.equal(history.length, 10)
  assert.deepEqual(history.map((item) => item.session.id), workouts.toReversed().map((item) => item.id))
})

test('finished history merges owned visible HealthKit workouts with APEX receipts before applying its limit', () => {
  const apex = session({
    id: 'apex-workout', date: '2026-08-26', program_day_id: 'day',
    completed_at: '2026-08-26T09:00:00.000Z',
  })
  const external = externalWorkout({ id: 'external-newest' })
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: 'owner', theme: 'dark', language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    workout_sessions: [apex],
    imported_activities: [
      external,
      externalWorkout({ id: 'hidden', hidden_at: '2026-08-27T00:00:00.000Z' }),
      externalWorkout({ id: 'foreign', user_id: 'someone-else' }),
      externalWorkout({ id: 'legacy-xml', healthkit_workout_id: null }),
    ],
  }

  const all = finishedWorkoutHistoryForDate(data, '2026-08-26')
  assert.deepEqual(all.map((item) => `${item.kind}:${item.id}`), [
    'external:external-newest',
    'apex:apex-workout',
  ])
  assert.deepEqual(
    finishedWorkoutHistoryForDate(data, '2026-08-26', 1).map((item) => `${item.kind}:${item.id}`),
    ['external:external-newest'],
  )
})

test('linked wearable evidence nests under its APEX receipt instead of appearing twice', () => {
  const apex = session({
    id: 'apex-workout', date: '2026-08-26', program_day_id: 'day',
    started_at: '2026-08-26T10:00:00.000Z',
    completed_at: '2026-08-26T11:00:00.000Z',
  })
  const linked = externalWorkout({
    id: 'linked-watch',
    apex_workout_session_id: apex.id,
    started_at: '2026-08-26T09:58:00.000Z',
    ended_at: '2026-08-26T10:58:00.000Z',
  })
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: 'owner', theme: 'dark', language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    workout_sessions: [apex],
    imported_activities: [linked],
  }

  const history = finishedWorkoutHistoryForDate(data, '2026-08-26')
  assert.equal(history.length, 1)
  assert.equal(history[0].kind, 'apex')
  if (history[0].kind === 'apex') assert.equal(history[0].linkedWearable?.id, linked.id)
})

test('finished history defensively omits a nearby APEX HealthKit mirror without crossing owner boundaries', () => {
  const owned = session({
    id: 'owned-apex',
    date: '2026-08-26',
    program_day_id: 'day',
    started_at: '2026-08-26T08:00:00.000Z',
    completed_at: '2026-08-26T08:45:00.000Z',
  })
  const foreign = session({
    id: 'foreign-apex',
    user_id: 'someone-else',
    date: '2026-08-26',
    program_day_id: 'day',
    started_at: '2026-08-26T10:00:00.000Z',
    completed_at: '2026-08-26T10:45:00.000Z',
  })
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: 'owner', theme: 'dark', language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    workout_sessions: [owned, foreign],
    imported_activities: [
      externalWorkout({
        id: 'owned-apex-mirror',
        source_bundle_id: 'ch.apexperformance.APEX.watchkitapp',
        apex_workout_session_id: null,
        started_at: '2026-08-26T08:04:59.000Z',
      }),
      externalWorkout({
        id: 'near-foreign-only',
        source_bundle_id: 'ch.apexperformance.APEX.watchkitapp',
        apex_workout_session_id: null,
        started_at: '2026-08-26T10:00:20.000Z',
      }),
    ],
  }

  assert.deepEqual(
    finishedWorkoutHistoryForDate(data, '2026-08-26').map((item) => `${item.kind}:${item.id}`),
    ['external:near-foreign-only', 'apex:owned-apex'],
  )
})

test('APEX time matching is strict at five minutes and does not hide lookalike bundle identifiers', () => {
  const owned = session({
    id: 'owned-apex',
    date: '2026-08-26',
    program_day_id: 'day',
    started_at: '2026-08-26T08:00:00.000Z',
    completed_at: '2026-08-26T08:45:00.000Z',
  })
  const exactBoundaryDecoy = session({
    id: 'exact-boundary-decoy',
    date: '2026-08-26',
    program_day_id: 'day',
    started_at: '2026-08-26T07:55:00.000Z',
    completed_at: '2026-08-26T07:59:00.000Z',
  })
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: 'owner', theme: 'dark', language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    workout_sessions: [owned, exactBoundaryDecoy],
    imported_activities: [
      externalWorkout({
        id: 'multiple-session-match',
        source_bundle_id: 'ch.apexperformance.APEX',
        started_at: '2026-08-26T08:00:00.000Z',
      }),
      externalWorkout({
        id: 'inside-boundary',
        source_bundle_id: 'ch.apexperformance.APEX.watchkitapp',
        started_at: '2026-08-26T08:04:59.999Z',
      }),
      externalWorkout({
        id: 'exact-boundary',
        source_bundle_id: 'ch.apexperformance.APEX.watchkitapp',
        started_at: '2026-08-26T08:05:00.000Z',
      }),
      externalWorkout({
        id: 'lookalike-bundle',
        source_bundle_id: 'ch.apexperformance.APEXFake',
        started_at: '2026-08-26T08:00:01.000Z',
      }),
    ],
  }

  assert.deepEqual(
    finishedWorkoutHistoryForDate(data, '2026-08-26')
      .filter((item) => item.kind === 'external')
      .map((item) => item.id)
      .toSorted(),
    ['exact-boundary', 'lookalike-bundle'],
  )
})

test('hiding an external receipt stays owner-scoped and preserves the original Apple Health identity', () => {
  const owned = externalWorkout({ id: 'owned' })
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: 'owner', theme: 'dark', language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    imported_activities: [
      owned,
      externalWorkout({ id: 'foreign', user_id: 'someone-else' }),
      externalWorkout({ id: 'legacy-xml', healthkit_workout_id: null }),
    ],
  }

  const hidden = externalWorkoutHidePlan(data, 'owned', '2026-08-29T12:00:00.000Z')
  assert.equal(hidden?.hidden_at, '2026-08-29T12:00:00.000Z')
  assert.equal(hidden?.healthkit_workout_id, owned.healthkit_workout_id)
  assert.equal(externalWorkoutHidePlan(data, 'foreign'), null)
  assert.equal(externalWorkoutHidePlan(data, 'legacy-xml'), null)
})

test('completed workout history is rendered without a visibility cap below Simple Mode metrics and in phase pages', () => {
  const simple = readFileSync(new URL('../src/pages/SimpleHome.tsx', import.meta.url), 'utf8')
  const phase = readFileSync(new URL('../src/pages/WorkoutSection.tsx', import.meta.url), 'utf8')
  const nativeSimple = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift', import.meta.url), 'utf8')
  const nativePhase = readFileSync(new URL('../ios/APEXNative/APEX/Features/Training/TrainingProgramView.swift', import.meta.url), 'utf8')
  assert.match(simple, /simple-summary-actions[\s\S]*CompletedWorkoutHistoryCards/)
  assert.match(phase, /CompletedWorkoutHistoryCards/)
  assert.match(simple, /CompletedWorkoutHistoryCards date=\{undefined\} accent=\{ACCENTS\.teal\}/)
  assert.match(phase, /CompletedWorkoutHistoryCards date=\{undefined\} accent=\{accent\} includeQuickLogs=\{false\}/)
  assert.doesNotMatch(simple, /CompletedWorkoutHistoryCards date=\{undefined\} limit=/)
  assert.doesNotMatch(phase, /CompletedWorkoutHistoryCards date=\{undefined\} limit=/)
  assert.match(nativeSimple, /CompletedWorkoutHistoryCards\(date: nil, accent: APEXColor\.teal\)/)
  assert.match(nativePhase, /CompletedWorkoutHistoryCards\(date: nil, accent: accent\)/)
  assert.doesNotMatch(nativeSimple, /CompletedWorkoutHistoryCards\(date: nil,[^\n]*limit:/)
  assert.doesNotMatch(nativePhase, /CompletedWorkoutHistoryCards\(date: nil,[^\n]*limit:/)
})

test("Nutrition Today's Activities reuses the same date-owned finished workout receipts", () => {
  const nutrition = readFileSync(new URL('../src/pages/Nutrition.tsx', import.meta.url), 'utf8')
  const activities = readFileSync(new URL('../src/components/TodaysActivities.tsx', import.meta.url), 'utf8')
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Nutrition/NutritionView.swift', import.meta.url), 'utf8')

  assert.match(nutrition, /<TodaysActivities[\s\S]*date=\{selectedLogDate\}/)
  assert.match(activities, /<CompletedWorkoutHistoryCards date=\{date\}/)
  assert.match(native, /TodaysActivitiesPanel\([\s\S]*CompletedWorkoutHistoryCards\(\s*date: date\.apexDateKey/)
})

test('deleting a finished workout targets the owned session and all of its owned set rows only', () => {
  const owned = session({ id: 'owned', date: '2026-08-26', program_day_id: 'day' })
  const foreign = session({ id: 'foreign', user_id: 'someone-else', date: '2026-08-26', program_day_id: 'day' })
  const data: AppData = {
    ...EMPTY_DATA,
    profile: {
      id: 'profile', user_id: 'owner', persona: 'constantine', display_name: 'Owner', sex: 'male',
      weight_kg: 80, body_fat_pct: 15, custom_bmr: null, height_cm: 180, birthdate: '1990-01-01',
      activity_level: 'moderate', goal: 'maintain', target_kcal: null, target_protein_g: null,
      target_fat_g: null, target_carbs_g: null, training_time: '18:00', baseline_date: '2026-01-01',
      profile_note: '', seed_version: 1, calibration_k: 1, calibration_history: [],
      updated_at: '2026-08-26T00:00:00.000Z',
    },
    workout_sessions: [owned, foreign],
    workout_logs: [log('set-a', 'owned'), log('set-b', 'owned'), log('foreign-set', 'owned', 'someone-else')],
  }

  assert.deepEqual(completedWorkoutDeletionPlan(data, 'owned'), {
    sessionId: 'owned',
    logIds: ['set-a', 'set-b'],
  })
  assert.equal(completedWorkoutDeletionPlan(data, 'foreign'), null)
})

test('a collapsed workout delete tray does not exist until a deliberate left swipe reveals it', () => {
  assert.equal(collapsedWorkoutDeleteTrayVisible(false, 0), false)
  assert.equal(collapsedWorkoutDeleteTrayVisible(false, 18), false)
  assert.equal(collapsedWorkoutDeleteTrayVisible(false, -1), true)
  assert.equal(collapsedWorkoutDeleteTrayVisible(true, -88), false)
})

test('expanded finished-workout cards show the receipt inline with one edit action and confirmed deletion', () => {
  const cards = readFileSync(new URL('../src/components/workout/CompletedWorkoutHistoryCards.tsx', import.meta.url), 'utf8')
  assert.match(cards, /workoutLogFactSummary/)
  assert.match(cards, /Delete this finished workout\?/)
  assert.match(cards, /onPointerDown/)
  assert.match(cards, /collapsedWorkoutDeleteTrayVisible\(open, swipeOffset\)/)
  assert.match(cards, />\{t\('Edit receipt'\)\}</)
  assert.doesNotMatch(cards, /View & edit receipt|Edit workout structure/)
})

test('external HealthKit cards are read-only receipts with Hide from APEX as their only destructive action', () => {
  const cards = readFileSync(new URL('../src/components/workout/CompletedWorkoutHistoryCards.tsx', import.meta.url), 'utf8')
  assert.match(cards, /finishedWorkoutHistoryForDate/)
  assert.match(cards, /Hide from APEX/)
  assert.match(cards, /The original workout stays in Apple Health\./)
  assert.match(cards, /READ-ONLY RECEIPT/)
  assert.doesNotMatch(cards, /remove\('imported_activities'/)
  assert.doesNotMatch(cards, /deleteHealthKitWorkout/)
})

test('every HealthWorkoutCatalog name key has authored Romanian and Thai web copy', () => {
  const healthManager = readFileSync(
    new URL('../ios/APEXNative/APEX/Features/Health/HealthKitManager.swift', import.meta.url),
    'utf8',
  )
  const workoutNameKeys = [...healthManager.matchAll(/return item\("[^"]+", "([^"]+)", "[^"]+"\)/g)]
    .map((match) => `health.workout.${match[1]}`)

  assert.equal(new Set(workoutNameKeys).size, 91, 'HealthWorkoutCatalog key extraction changed')
  for (const key of workoutNameKeys) {
    const translation = UI_TRANSLATIONS[key]
    assert.ok(translation?.ro && translation.ro !== key, `missing authored Romanian workout name: ${key}`)
    assert.ok(translation?.th && translation.th !== key, `missing authored Thai workout name: ${key}`)
  }
})

test('external workout presentation uses the authored key and selected APEX locale for its full timestamp and numbers', () => {
  type Presentation = {
    title: string
    moment: string
    duration: string
    energy: string | null
    distance: string | null
  }
  type Present = (
    activity: ImportedActivity,
    language: IntroLanguage,
    timeZone: string,
    translate: (value: string) => string,
  ) => Presentation
  const present = (completedWorkoutHistoryModule as unknown as {
    externalWorkoutReceiptPresentation?: Present
  }).externalWorkoutReceiptPresentation
  assert.equal(typeof present, 'function', 'external workout presentation formatter is missing')
  if (!present) return

  const activityMap = Object.fromEntries(
    ACTIVITY_TRANSLATIONS.map(([english, romanian, thai]) => [english, { ro: romanian, th: thai }]),
  ) as Record<string, { ro: string; th: string }>
  const translator = (language: IntroLanguage) => (value: string): string => {
    if (language === 'en') return value
    return UI_TRANSLATIONS[value]?.[language] ?? activityMap[value]?.[language] ?? value
  }
  const activity = externalWorkout({
    id: 'locale-proof',
    date: '2026-08-29',
    activity: 'Server fallback run',
    workout_name_key: 'health.workout.outdoor_run',
    started_at: '2026-08-29T22:05:00.000Z',
    duration_min: 1234.4,
    active_energy_kcal: 1234.6,
    distance_km: 1234.5,
  })

  assert.deepEqual(present(activity, 'ro', 'Europe/Zurich', translator('ro')), {
    title: 'Alergare în aer liber',
    moment: '30 aug. 2026, 00:05',
    duration: '1.234 min',
    energy: '1.235 kcal',
    distance: '1.234,5 km',
  })
  assert.deepEqual(present(activity, 'th', 'Europe/Zurich', translator('th')), {
    title: 'วิ่งกลางแจ้ง',
    moment: '30 ส.ค. 2569 00:05',
    duration: '1,234 นาที',
    energy: '1,235 กิโลแคลอรี',
    distance: '1,234.5 กม.',
  })

  const unknownKey = externalWorkout({
    id: 'fallback-proof',
    activity: 'Fallback workout title',
    workout_name_key: 'health.workout.not_authored',
  })
  assert.equal(
    present(unknownKey, 'en', 'UTC', translator('en')).title,
    'Fallback workout title',
  )
})

test('external workout title and receipt metadata remain fully wrapping rather than truncated', () => {
  const cards = readFileSync(new URL('../src/components/workout/CompletedWorkoutHistoryCards.tsx', import.meta.url), 'utf8')
  const start = cards.indexOf("if (entry.kind === 'external')")
  const end = cards.indexOf('const { session, title, isQuickLog, linkedWearable }', start)
  assert.ok(start >= 0 && end > start, 'external workout card branch is missing')
  const externalCard = cards.slice(start, end)

  assert.match(externalCard, /break-words/)
  assert.doesNotMatch(externalCard, /\btruncate\b|line-clamp-/)
})

test('calendar activity pulses ignore hidden imports without removing them from health-import deduplication', () => {
  const calendar = readFileSync(new URL('../src/components/Calendar.tsx', import.meta.url), 'utf8')
  const healthImport = readFileSync(new URL('../src/lib/healthImport.ts', import.meta.url), 'utf8')
  const importedDatesStart = calendar.indexOf('const importedDates')
  const importedDatesEnd = calendar.indexOf('const pressTimer', importedDatesStart)
  assert.ok(importedDatesStart >= 0 && importedDatesEnd > importedDatesStart, 'calendar imported-date selector is missing')

  assert.match(calendar.slice(importedDatesStart, importedDatesEnd), /visibleImportedActivitiesForOwner\(data\)/)
  assert.doesNotMatch(calendar.slice(importedDatesStart, importedDatesEnd), /new Set\(data\.imported_activities/)
  assert.match(healthImport, /data\.imported_activities\.map\(\(a\) => `\$\{a\.date\}\|\$\{a\.kind\}\|\$\{a\.duration_min\}`\)/)
  assert.doesNotMatch(healthImport, /imported_activities\.filter\([^\n]*hidden_at/)
})
