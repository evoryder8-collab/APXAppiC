import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import test from 'node:test'

import {
  stageCustomWorkoutSave,
  stageCustomWorkoutArchive,
  customWorkoutArchiveRows,
  customWorkoutDraftForDay,
  customWorkoutReplacementDecision,
  customWorkoutSaveDayID,
  customWorkoutStaleExerciseIDs,
  customWorkoutSyncWrites,
} from '../src/lib/customWorkout.ts'
import { completedWorkoutHistoryForDate } from '../src/lib/completedWorkoutHistory.ts'
import {
  OwnerBoundMutationBusyError,
  OwnerBoundMutationAccountError,
  OwnerBoundMutationCoordinator,
  OwnerBoundMutationPersistenceError,
  commitOwnerBoundMutationAtomically,
  orderedOwnerMutationQueue,
} from '../src/lib/ownerBoundMutation.ts'
import { loadCache, loadQueue, saveCacheAndQueueAtomically, type SyncOp } from '../src/lib/local.ts'
import { nextPendingSyncOperation } from '../src/lib/sync.ts'
import { EMPTY_DATA, type AppData, type Exercise, type ProgramDay, type WorkoutSession } from '../src/lib/types.ts'

const ownerA = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
const ownerB = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
const programID = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'

function day(id: string, userID = ownerA, weekday = 1): ProgramDay {
  return {
    id,
    user_id: userID,
    program_id: programID,
    weekday,
    name: `Workout ${weekday}`,
    day_type: 'custom',
    est_minutes: 30,
    warmup_note: '',
    sort_order: weekday,
    session_mode: 'tracked',
  }
}

function exercise(
  id: string,
  dayID: string,
  movementID: string,
  sortOrder: number,
  workGroupID: string | null = null,
): Exercise {
  return {
    id,
    user_id: ownerA,
    program_day_id: dayID,
    name: movementID === 'barbell_bench_press' ? 'Barbell Bench Press' : 'Neutral-Grip Lat Pulldown',
    movement_id: movementID,
    sets: sortOrder + 3,
    rep_min: 8 + sortOrder,
    rep_max: 8 + sortOrder,
    rep_unit: 'reps',
    per_side: false,
    rest_sec: 90,
    work_group_id: workGroupID,
    work_group_position: workGroupID ? sortOrder + 1 : null,
    tempo_up_s: 1,
    tempo_down_s: 2,
    tempo_pause_s: 0,
    tempo_note: '',
    notes: '',
    increment_kg: 2.5,
    is_lite: false,
    optional: false,
    sort_order: sortOrder,
  }
}

test('saved custom workouts reopen as an ordered, fully prefilled editable draft', () => {
  const savedDay = day('dddddddd-dddd-4ddd-8ddd-dddddddddddd')
  const unavailable = {
    ...exercise('99999999-9999-4999-8999-999999999999', savedDay.id, 'retired_movement', 1, 'group-a'),
    name: 'Retired movement',
    work_group_position: 2,
  }
  const draft = customWorkoutDraftForDay(savedDay, [
    exercise('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', savedDay.id, 'lat_pulldown', 2, 'group-a'),
    { ...exercise('abababab-abab-4bab-8bab-abababababab', savedDay.id, 'lat_pulldown', 3), user_id: ownerB },
    unavailable,
    exercise('ffffffff-ffff-4fff-8fff-ffffffffffff', savedDay.id, 'barbell_bench_press', 0, 'group-a'),
  ])

  assert.equal(draft.name, savedDay.name)
  assert.equal(draft.weekday, 1)
  assert.equal(draft.sessionMode, 'tracked')
  assert.equal(draft.omittedExerciseCount, 1)
  assert.deepEqual(draft.selected.map(({ id, sets, target, rest, linkedToNext }) => ({ id, sets, target, rest, linkedToNext })), [
    { id: 'barbell_bench_press', sets: 3, target: 8, rest: 90, linkedToNext: false },
    { id: 'lat_pulldown', sets: 5, target: 10, rest: 90, linkedToNext: false },
  ])
})

test('same-weekday replacement confirms the exact active owner-scoped conflict set', () => {
  const monday = day('11111111-1111-4111-8111-111111111111')
  const duplicateMonday = day('33333333-3333-4333-8333-333333333333')
  const archivedMonday = { ...day('44444444-4444-4444-8444-444444444444'), is_active: false }
  const otherOwnerMonday = day('22222222-2222-4222-8222-222222222222', ownerB)

  assert.deepEqual(customWorkoutReplacementDecision(
    [duplicateMonday, archivedMonday, otherOwnerMonday, monday],
    { ownerID: ownerA, programID, weekday: 1, editingDayID: null, confirmedReplacementDayIDs: [] },
  ), { kind: 'confirmation-required', replacingDayIDs: [monday.id, duplicateMonday.id] })
  assert.deepEqual(customWorkoutReplacementDecision(
    [monday, duplicateMonday, archivedMonday, otherOwnerMonday],
    { ownerID: ownerA, programID, weekday: 1, editingDayID: null, confirmedReplacementDayIDs: [monday.id] },
  ), { kind: 'confirmation-required', replacingDayIDs: [monday.id, duplicateMonday.id] })
  assert.deepEqual(customWorkoutReplacementDecision(
    [monday, duplicateMonday, archivedMonday, otherOwnerMonday],
    {
      ownerID: ownerA,
      programID,
      weekday: 1,
      editingDayID: null,
      confirmedReplacementDayIDs: [duplicateMonday.id, monday.id],
    },
  ), { kind: 'save', replacingDayIDs: [monday.id, duplicateMonday.id] })
  assert.deepEqual(customWorkoutReplacementDecision(
    [archivedMonday, otherOwnerMonday],
    { ownerID: ownerA, programID, weekday: 1, editingDayID: null, confirmedReplacementDayIDs: [] },
  ), { kind: 'save', replacingDayIDs: [] })
})

test('replacement and deletion archive owned days while their completed receipt keeps its original identity', () => {
  const original = { ...day('11111111-1111-4111-8111-111111111111'), name: 'Original Monday' }
  const duplicate = { ...day('33333333-3333-4333-8333-333333333333'), name: 'Original Monday B' }
  const alreadyArchived = { ...day('44444444-4444-4444-8444-444444444444'), is_active: false }
  const foreign = day('22222222-2222-4222-8222-222222222222', ownerB)
  const archived = customWorkoutArchiveRows(
    [original, duplicate, alreadyArchived, foreign],
    {
      ownerID: ownerA,
      programID,
      dayIDs: [original.id, duplicate.id, alreadyArchived.id, foreign.id],
    },
  )
  assert.deepEqual(archived.map((row) => [row.id, row.is_active]), [
    [original.id, false],
    [duplicate.id, false],
  ])
  assert.equal(original.is_active, undefined, 'archiving must not mutate the historical row in place')

  const freshID = customWorkoutSaveDayID(null, () => '55555555-5555-4555-8555-555555555555')
  assert.equal(freshID, '55555555-5555-4555-8555-555555555555')
  assert.notEqual(freshID, original.id, 'a fresh replacement must never reuse a historical day identity')
  assert.equal(customWorkoutSaveDayID(original.id, () => 'unused'), original.id, 'an explicit edit keeps its identity')

  const completed: WorkoutSession = {
    id: '66666666-6666-4666-8666-666666666666',
    user_id: ownerA,
    date: '2026-09-01',
    program_day_id: original.id,
    is_lite: false,
    is_deload: false,
    is_event_recovery: false,
    completed: true,
    quality_score: 1,
    started_at: '2026-09-01T08:00:00.000Z',
    completed_at: '2026-09-01T09:00:00.000Z',
    notes: '',
  }
  const replacement = { ...day(freshID), name: 'Replacement Monday', is_active: true }
  const data: AppData = {
    ...EMPTY_DATA,
    settings: {
      user_id: ownerA,
      theme: 'light',
      language: 'en',
      addons: { endurance1: false, endurance2: false, endurance3: false },
    },
    program_days: [archived[0], archived[1], replacement],
    workout_sessions: [completed],
  }
  assert.equal(completedWorkoutHistoryForDate(data, completed.date)[0]?.title, 'Original Monday')
})

test('a fresh replacement retains historical exercises while an explicit edit replaces only its owned prescription', () => {
  const historical = exercise('historical', 'historical-day', 'barbell_bench_press', 0)
  const edited = exercise('edited', 'editing-day', 'lat_pulldown', 0)
  const foreign = { ...exercise('foreign', 'editing-day', 'lat_pulldown', 1), user_id: ownerB }
  const rows = [historical, edited, foreign]

  assert.deepEqual(customWorkoutStaleExerciseIDs(rows, ownerA, null), [])
  assert.deepEqual(customWorkoutStaleExerciseIDs(rows, ownerA, 'editing-day'), [edited.id])
})

class FaultInjectingStorage {
  private readonly values = new Map<string, string>()
  failWhen: ((key: string, value: string) => boolean) | null = null
  failRemoveWhen: ((key: string) => boolean) | null = null

  getItem(key: string): string | null {
    return this.values.get(key) ?? null
  }

  setItem(key: string, value: string): void {
    if (this.failWhen?.(key, value)) throw new Error('storage full')
    this.values.set(key, value)
  }

  removeItem(key: string): void {
    if (this.failRemoveWhen?.(key)) throw new Error('storage removal failed')
    this.values.delete(key)
  }
}

test('custom save stages against the latest store and preserves unrelated edits and historical rows', () => {
  const historical = { ...day('historical-day'), is_active: false }
  const editing = day('editing-day')
  const oldExercise = exercise('old-exercise', editing.id, 'lat_pulldown', 0)
  const historicalExercise = exercise('historical-exercise', historical.id, 'lat_pulldown', 0)
  const program = { id: programID, user_id: ownerA, slug: 'custom' as const, name: 'Custom workouts', description: '' }
  const current = { ...EMPTY_DATA, programs: [program], program_days: [historical, editing], exercises: [oldExercise, historicalExercise], events: [{ id: 'unrelated-event' }] } as AppData
  const replacementExercise = exercise('new-exercise', editing.id, 'barbell_bench_press', 0)
  const plan = stageCustomWorkoutSave(current, {
    program, day: { ...editing, name: 'Updated' }, exercises: [replacementExercise],
    editingDayID: editing.id, confirmedReplacementDayIDs: [],
  })
  assert.deepEqual(plan.data.events, [{ id: 'unrelated-event' }])
  assert.deepEqual(plan.data.program_days.map((row) => [row.id, row.name]), [['historical-day', 'Workout 1'], ['editing-day', 'Updated']])
  assert.deepEqual(plan.data.exercises.map((row) => row.id), ['historical-exercise', 'new-exercise'])
  assert.deepEqual(current.exercises.map((row) => row.id), ['old-exercise', 'historical-exercise'])
  assert.deepEqual(plan.writes.map((op) => [op.table, op.type]), [['programs', 'upsert'], ['program_days', 'upsert'], ['exercises', 'upsert'], ['exercises', 'delete']])

  const archive = stageCustomWorkoutArchive(plan.data, { ownerID: ownerA, programID, dayID: editing.id })
  assert.equal(archive.data.program_days.find((row) => row.id === editing.id)?.is_active, false)
  assert.deepEqual(archive.data.exercises, plan.data.exercises)
  assert.deepEqual(archive.writes.map((op) => [op.table, op.type]), [['program_days', 'upsert']])
})

test('staging rechecks replacement consent and refuses archived or foreign edit targets', () => {
  const program = { id: programID, user_id: ownerA, slug: 'custom' as const, name: 'Custom workouts', description: '' }
  const current = { ...EMPTY_DATA, programs: [program], program_days: [day('new-conflict')] }
  const input = { program, day: day('new-day'), exercises: [exercise('new-exercise', 'new-day', 'lat_pulldown', 0)], editingDayID: null, confirmedReplacementDayIDs: [] }
  assert.throws(() => stageCustomWorkoutSave(current, input), { name: 'CustomWorkoutReplacementRequiredError' })
  const saved = stageCustomWorkoutSave(current, { ...input, confirmedReplacementDayIDs: ['new-conflict'] })
  assert.deepEqual(saved.data.program_days.map((row) => [row.id, row.is_active]), [['new-conflict', false], ['new-day', true]])
  assert.throws(() => stageCustomWorkoutSave(saved.data, { ...input, editingDayID: 'new-conflict' }))
  assert.throws(() => stageCustomWorkoutArchive(current, { ownerID: ownerB, programID, dayID: 'new-conflict' }))
})

test('an unfinished rollback never exposes a failed mutation through cache or sync queue reads', () => {
  const storage = new FaultInjectingStorage()
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'localStorage')
  Object.defineProperty(globalThis, 'localStorage', { configurable: true, value: storage })
  try {
    const oldData = { ...EMPTY_DATA, program_days: [day('old-day')] }
    const oldQueue: SyncOp[] = [{ id: 'old-op', table: 'settings', type: 'upsert', payload: { user_id: ownerA }, ts: 1 }]
    const nextQueue: SyncOp[] = [{ id: 'failed-op', table: 'program_days', type: 'upsert', payload: day('new-day'), ts: 2 }]
    storage.setItem(`apex.cache.v2.${ownerA}`, JSON.stringify(oldData))
    storage.setItem(`apex.queue.v2.${ownerA}`, JSON.stringify(oldQueue))
    storage.failWhen = (key) => key === `apex.cache.v2.${ownerA}`
    assert.equal(saveCacheAndQueueAtomically({ ...oldData, program_days: [day('new-day')] }, nextQueue, ownerA), false)
    assert.deepEqual(loadQueue(ownerA), oldQueue, 'a failed rollback must not sync the staged queue')
    assert.deepEqual(loadCache(ownerA)?.program_days, oldData.program_days)
    assert.equal(saveCacheAndQueueAtomically(oldData, oldQueue, ownerA), false, 'cannot overwrite an unfinished recovery journal')
    storage.failWhen = null
    assert.deepEqual(loadQueue(ownerA), oldQueue)
    assert.equal(storage.getItem(`apex.atomic-mutation.v1.${ownerA}`), null)
  } finally {
    if (descriptor) Object.defineProperty(globalThis, 'localStorage', descriptor)
    else Reflect.deleteProperty(globalThis, 'localStorage')
  }
})

test('an account reset cancels a pending commit, including sign-out and return to the same owner', async () => {
  const coordinator = new OwnerBoundMutationCoordinator()
  let owner: string | null = ownerA
  let writes = 0
  const start = () => commitOwnerBoundMutationAtomically({
    coordinator, expectedOwnerID: ownerA, currentOwnerID: () => owner,
    stage: () => ({ state: 'saved', result: 'saved' }),
    persist: () => { writes++; return true }, publish: () => {},
  })
  const first = start()
  owner = ownerB
  coordinator.reset()
  await assert.rejects(first, OwnerBoundMutationAccountError)
  owner = ownerA
  const stale = start()
  coordinator.reset()
  const fresh = start()
  await assert.rejects(stale, OwnerBoundMutationAccountError)
  assert.equal(await fresh, 'saved')
  assert.equal(writes, 1)
})

async function verifyAtomicCheckpointFailure(
  fail: (storage: FaultInjectingStorage) => void,
): Promise<void> {
  const storage = new FaultInjectingStorage()
  const oldData: AppData = { ...EMPTY_DATA, program_days: [day('old-day')] }
  const oldQueue: SyncOp[] = [{
    id: 'old-operation',
    table: 'settings',
    type: 'upsert',
    payload: { id: ownerA, user_id: ownerA },
    ts: 1,
  }]
  storage.setItem(`apex.cache.v2.${ownerA}`, JSON.stringify(oldData))
  storage.setItem(`apex.queue.v2.${ownerA}`, JSON.stringify(oldQueue))
  fail(storage)

  let published: AppData | null = null
  let stagedQueue: SyncOp[] | null = null
  const nextData: AppData = { ...oldData, program_days: [day('new-day')] }
  const coordinator = new OwnerBoundMutationCoordinator()

  await assert.rejects(
    commitOwnerBoundMutationAtomically({
      coordinator,
      expectedOwnerID: ownerA,
      currentOwnerID: () => ownerA,
      stage: () => ({ state: nextData, result: 'saved' as const }),
      persist: (stage) => {
        stagedQueue = orderedOwnerMutationQueue(oldQueue, [{
          ownerID: ownerA,
          table: 'program_days',
          type: 'upsert',
          payload: stage.state.program_days,
        }], 'failed-save', () => 'new-operation', () => 2)
        return saveCacheAndQueueAtomically(stage.state, stagedQueue, ownerA, storage)
      },
      publish: (state) => { published = state },
    }),
    OwnerBoundMutationPersistenceError,
  )

  assert.equal(published, null, 'failed durability must not publish optimistic state')
  assert.equal(storage.getItem(`apex.cache.v2.${ownerA}`), JSON.stringify(oldData))
  assert.equal(storage.getItem(`apex.queue.v2.${ownerA}`), JSON.stringify(oldQueue))
  assert.equal(stagedQueue?.at(-1)?.id, 'new-operation', 'the test must exercise a real staged outbox')
}

test('owner-bound custom mutation publishes nothing when queue, cache, or commit-marker durability fails', async () => {
  const queueKey = `apex.queue.v2.${ownerA}`
  const cacheKey = `apex.cache.v2.${ownerA}`
  const journalKey = `apex.atomic-mutation.v1.${ownerA}`

  await verifyAtomicCheckpointFailure((storage) => {
    let failed = false
    storage.failWhen = (key) => {
      if (key !== queueKey || failed) return false
      failed = true
      return true
    }
  })
  await verifyAtomicCheckpointFailure((storage) => {
    let failed = false
    storage.failWhen = (key) => {
      if (key !== cacheKey || failed) return false
      failed = true
      return true
    }
  })
  await verifyAtomicCheckpointFailure((storage) => {
    let failed = false
    storage.failRemoveWhen = (key) => {
      if (key !== journalKey || failed) return false
      failed = true
      return true
    }
  })
})

test('replacement stages parent and replacement rows before grouped stale deletes can reach sync', () => {
  const program = {
    id: programID,
    user_id: ownerA,
    slug: 'custom' as const,
    name: 'Custom workouts',
    description: '',
  }
  const editingDay = day('editing-day')
  const replacementExercise = exercise('replacement-exercise', editingDay.id, 'barbell_bench_press', 0)
  const writes = customWorkoutSyncWrites({
    program,
    days: [editingDay],
    exercises: [replacementExercise],
    staleExerciseIDs: ['old-exercise-a', 'old-exercise-b'],
  })
  const ids = ['program-write', 'day-write', 'exercise-write', 'delete-a', 'delete-b']
  let idIndex = 0
  const queue = orderedOwnerMutationQueue([], writes, 'replacement-group', () => ids[idIndex++], () => 10)

  assert.deepEqual(queue.map((operation) => [operation.table, operation.type]), [
    ['programs', 'upsert'],
    ['program_days', 'upsert'],
    ['exercises', 'upsert'],
    ['exercises', 'delete'],
    ['exercises', 'delete'],
  ])
  assert.equal(new Set(queue.map((operation) => operation.sync_group)).size, 1)

  const first = nextPendingSyncOperation(queue, new Set(), new Set(), new Set())
  assert.equal(first?.id, 'program-write')
  const failedGroup = new Set([first?.sync_group ?? ''])
  const afterFailure = nextPendingSyncOperation(queue, new Set([first!.id]), new Set(), failedGroup)
  assert.equal(afterFailure, undefined, 'a failed replacement row must hold every stale delete behind it')
})

test('real save and archive transactions publish only durable state, reject overlaps, and retain intervening changes', async () => {
  const storage = new FaultInjectingStorage()
  const coordinator = new OwnerBoundMutationCoordinator()
  const program = { id: programID, user_id: ownerA, slug: 'custom' as const, name: 'Custom workouts', description: '' }
  let live: AppData = { ...EMPTY_DATA, programs: [program], program_days: [day('editing-day')], exercises: [exercise('old-exercise', 'editing-day', 'lat_pulldown', 0)] }
  let queue: SyncOp[] = [{ id: 'unrelated-op', table: 'settings', type: 'upsert', payload: { user_id: ownerA }, ts: 1 }]
  const commit = (stagePlan: (current: AppData) => ReturnType<typeof stageCustomWorkoutSave>) => commitOwnerBoundMutationAtomically({
    coordinator, expectedOwnerID: ownerA, currentOwnerID: () => ownerA,
    stage: () => ({ state: stagePlan(live), result: undefined }),
    persist: ({ state }) => saveCacheAndQueueAtomically(state.data, orderedOwnerMutationQueue(queue, state.writes, 'workout-group'), ownerA, storage),
    publish: ({ data: next }) => {
      assert.deepEqual(JSON.parse(storage.getItem(`apex.cache.v2.${ownerA}`)!), next, 'publication must follow the durable cache')
      live = next
      queue = JSON.parse(storage.getItem(`apex.queue.v2.${ownerA}`)!)
    },
  })
  const save = commit((current) => stageCustomWorkoutSave(current, {
    program, day: { ...day('editing-day'), name: 'Updated' },
    exercises: [exercise('new-exercise', 'editing-day', 'barbell_bench_press', 0)],
    editingDayID: 'editing-day', confirmedReplacementDayIDs: [],
  }))
  const overlap = commit((current) => stageCustomWorkoutArchive(current, { ownerID: ownerA, programID, dayID: 'editing-day' }))
  live = { ...live, program_days: [...live.program_days, day('unrelated-day', ownerA, 2)] }
  await assert.rejects(overlap, OwnerBoundMutationBusyError)
  await save
  assert.equal(live.program_days.find((row) => row.id === 'editing-day')?.name, 'Updated')
  assert.equal(live.program_days.find((row) => row.id === 'unrelated-day')?.weekday, 2)
  assert.deepEqual(queue.map((row) => row.table), ['settings', 'programs', 'program_days', 'exercises', 'exercises'])
  const saved = live
  const savedQueue = [...queue]
  storage.failWhen = (key) => key === `apex.cache.v2.${ownerA}`
  await assert.rejects(commit((current) => stageCustomWorkoutArchive(current, {
    ownerID: ownerA, programID, dayID: 'editing-day',
  })), OwnerBoundMutationPersistenceError)
  assert.equal(live, saved, 'failed archive keeps the visible workout available for retry')
  assert.deepEqual(queue, savedQueue, 'failed archive never publishes a sync operation')
  storage.failWhen = null
  await commit((current) => stageCustomWorkoutArchive(current, { ownerID: ownerA, programID, dayID: 'editing-day' }))
  assert.equal(live.program_days.find((row) => row.id === 'editing-day')?.is_active, false)
  assert.deepEqual(live.exercises, saved.exercises, 'archive retains the historic prescription')
})

test('one owner-bound lease serializes overlapping save, replace and delete mutations', async () => {
  const coordinator = new OwnerBoundMutationCoordinator()
  let releaseFirst: (() => void) | null = null
  const held = new Promise<void>((resolve) => { releaseFirst = resolve })
  const events: string[] = []

  const save = coordinator.run(ownerA, () => ownerA, async () => {
    events.push('save-start')
    await held
    events.push('save-finish')
  })
  await Promise.resolve()

  await assert.rejects(
    coordinator.run(ownerA, () => ownerA, () => { events.push('replace') }),
    OwnerBoundMutationBusyError,
  )
  await assert.rejects(
    coordinator.run(ownerA, () => ownerA, () => { events.push('delete') }),
    OwnerBoundMutationBusyError,
  )
  assert.deepEqual(events, ['save-start'])

  releaseFirst?.()
  await save
  await coordinator.run(ownerA, () => ownerA, () => { events.push('delete-after-save') })
  assert.deepEqual(events, ['save-start', 'save-finish', 'delete-after-save'])
})

test('web custom workout lifecycle waits for durable persistence and exposes edit and confirmed delete', async () => {
  const [builder, section, store, local] = await Promise.all([
    readFile(new URL('../src/components/CustomWorkoutBuilder.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/WorkoutSection.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/store/AppStore.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/lib/local.ts', import.meta.url), 'utf8'),
  ])

  assert.match(builder, /editingDayId/)
  assert.match(builder, /const draftKey = `\$\{data\.profile\?\.user_id \?\? 'signed-out'\}:\$\{editingDayId \?\? 'new'\}`/)
  assert.match(builder, /customWorkoutDraftForDay/)
  assert.match(builder, /customWorkoutReplacementDecision/)
  assert.match(builder, /activeCustomWorkoutDays/)
  assert.match(builder, /stageCustomWorkoutSave/)
  assert.match(builder, /customWorkoutSaveDayID/)
  assert.match(builder, /replacementConflictDays\.map/)
  assert.match(builder, /if \(unavailableSavedMovements > 0\)[\s\S]*?return/)
  assert.match(builder, /await commitOwnerBoundMutation\(profile\.user_id[\s\S]*?toast\(t\(editingDay \? 'Custom workout updated' : 'Custom workout saved'\), 'ok'\)/)
  assert.match(builder, /Replace this workout\?/)
  assert.match(builder, /Save as replacement/)
  assert.doesNotMatch(builder, /remove\(['"]program_days['"]/, 'replacement must never cascade-delete completed history')
  assert.match(section, /data-custom-workout-id=/)
  assert.match(section, /activeCustomWorkoutDays/)
  assert.match(section, /stageCustomWorkoutArchive/)
  assert.match(section, /setEditingCustomDayId/)
  assert.match(section, /Delete this workout\?/)
  assert.match(section, /await commitOwnerBoundMutation\(ownerId,/)
  assert.doesNotMatch(section, /remove\(['"]program_days['"]/, 'deletion must archive the day instead of cascading through receipts')
  assert.doesNotMatch(section, /remove\(['"]exercises['"]/, 'deletion must retain the historical prescription')
  assert.match(store, /commitOwnerBoundMutationAtomically/)
  assert.match(store, /queuePersistenceDurable\.current = saveQueue\(nextQueue, scopeRef\.current\)/)
  assert.match(local, /export function saveCache\([\s\S]*?\): boolean \{[\s\S]*?catch \{[\s\S]*?return false/)
  assert.match(local, /export function saveQueue\([\s\S]*?\): boolean \{[\s\S]*?volatileQueues\.set\(scope, \[\.\.\.queue\]\)[\s\S]*?return false/)
})

test('sponsored-client policy is applied at Simple, Advanced, Settings, Avatar, and builder boundaries', async () => {
  const [simple, portal, settings, avatar, builder] = await Promise.all([
    readFile(new URL('../src/pages/SimpleHome.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/Portal.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/Settings.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/pages/AvatarPage.tsx', import.meta.url), 'utf8'),
    readFile(new URL('../src/components/CustomWorkoutBuilder.tsx', import.meta.url), 'utf8'),
  ])

  assert.match(simple, /canCreateManualWorkouts && <QuickWorkoutLauncher/)
  assert.match(simple, /showOrbitShortcut && coachPolicy\.can_use_orbit/)
  assert.match(portal, /coachPolicy\.can_rebuild_fitness_plan &&/)
  assert.match(portal, /coachPolicy\.can_create_custom_workouts &&/)
  assert.match(portal, /coachPolicy\.can_use_orbit &&/)
  assert.match(settings, /const coachPolicy = clientPolicyForAccount\(appAccess, coachContext\)/)
  assert.match(settings, /coachPolicy\.can_use_orbit &&/)
  assert.match(settings, /coachPolicy\.can_create_custom_workouts &&/)
  assert.match(settings, /coachPolicy\.can_rebuild_fitness_plan &&/)
  assert.match(avatar, /coachPolicy\.can_view_visual_progress &&/)
  assert.match(avatar, /coachPolicy\.can_use_orbit/)
  assert.match(avatar, /coachPolicy\.can_rebuild_fitness_plan/)
  assert.match(builder, /if \(!policy\.can_create_custom_workouts\)/)
})

test('emptying an existing meal changes the action to an owner/date-bound confirmed deletion', async () => {
  const composer = await readFile(new URL('../src/components/food/MealComposer.tsx', import.meta.url), 'utf8')

  assert.match(composer, /const \[confirmEmptyMealDeletion, setConfirmEmptyMealDeletion\] = useState\(false\)/)
  assert.match(composer, /replacedMeal\.user_id !== activeOwnerId/)
  assert.match(composer, /replacedMeal\.local_date !== mealDate/)
  assert.match(composer, /const log = async \(\) => \{[\s\S]*?replacedMeal\.local_date !== mealDate[\s\S]*?return[\s\S]*?if \(replaceMealId && items\.length === 0\)/)
  assert.match(composer, /Delete saved meal\?/)
  assert.match(composer, /Removing every food will delete this meal from this day\./)
  assert.match(composer, /t\('Delete meal'\)/)
  assert.match(composer, /await store\.deleteMeal\(replaceMealId\)/)
})

test('new Task 5 actions have authored Romanian and Thai copy', async () => {
  const translations = await readFile(new URL('../src/lib/translations.ts', import.meta.url), 'utf8')
  for (const key of [
    'Edit workout',
    'Delete workout',
    'Delete this workout?',
    'Replace this workout?',
    'Replace these workouts?',
    'These workouts already use this training day. Replace them only if that is what you intend.',
    'Save as replacement',
    'Delete saved meal?',
    'Removing every food will delete this meal from this day.',
    'Delete meal',
    'Meal could not be deleted.',
    'Keep editing',
    'This removes the saved custom workout from your active plan. Completed workout history and its prescription stay intact.',
  ]) {
    const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    assert.match(translations, new RegExp(`\\[['"]${escaped}['"],\\s*['"][^'"]+['"],\\s*['"][^'"]+['"]\\]`), key)
  }
})
