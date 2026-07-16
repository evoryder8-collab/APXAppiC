import type {
  FoodPreference,
  FoodRecord,
  LoggedFoodEntry,
  LoggedMeal,
  MealPreset,
  MealPresetItem,
} from './food'
import { replayProgressPhotoOutbox, type ProgressPhoto } from './progressPhoto.ts'

const DB_NAME = 'apex-private-v1'
const DB_VERSION = 2

export type PrivateStoreName =
  | 'foods'
  | 'food_preferences'
  | 'meal_presets'
  | 'meal_preset_items'
  | 'logged_meals'
  | 'logged_food_entries'
  | 'progress_photos'
  | 'photo_blobs'
  | 'private_outbox'

export interface StoredPhotoBlob {
  id: string
  user_id: string
  photo_id: string
  kind: 'full' | 'thumbnail'
  blob: Blob
  updated_at: string
}

export interface PrivateOutboxOp {
  id: string
  user_id: string
  domain: 'food' | 'photo'
  operation: string
  entity_id: string
  payload: unknown
  created_at: string
  attempts: number
  last_attempt_at?: string | null
  last_error?: string | null
}

let dbPromise: Promise<IDBDatabase> | null = null

export function resetPrivateDbConnection(): void {
  const current = dbPromise
  dbPromise = null
  if (current) void current.then((database) => database.close()).catch(() => undefined)
}

function requestResult<T>(request: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error ?? new Error('IndexedDB request failed'))
  })
}

function transactionDone(transaction: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve()
    transaction.onerror = () => reject(transaction.error ?? new Error('IndexedDB transaction failed'))
    transaction.onabort = () => reject(transaction.error ?? new Error('IndexedDB transaction aborted'))
  })
}

export function openPrivateDb(): Promise<IDBDatabase> {
  if (!('indexedDB' in globalThis)) return Promise.reject(new Error('IndexedDB is unavailable'))
  if (dbPromise) return dbPromise
  const opening = new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION)
    let settled = false
    const fail = (error: Error) => {
      if (settled) return
      settled = true
      if (dbPromise === opening) dbPromise = null
      reject(error)
    }
    request.onupgradeneeded = () => {
      const database = request.result
      const definitions: Array<{ name: PrivateStoreName; userIndex: boolean }> = [
        { name: 'foods', userIndex: false },
        { name: 'food_preferences', userIndex: true },
        { name: 'meal_presets', userIndex: true },
        { name: 'meal_preset_items', userIndex: true },
        { name: 'logged_meals', userIndex: true },
        { name: 'logged_food_entries', userIndex: true },
        { name: 'progress_photos', userIndex: true },
        { name: 'photo_blobs', userIndex: true },
        { name: 'private_outbox', userIndex: true },
      ]
      for (const definition of definitions) {
        const store = database.objectStoreNames.contains(definition.name)
          ? request.transaction!.objectStore(definition.name)
          : database.createObjectStore(definition.name, { keyPath: 'id' })
        if (definition.userIndex && !store.indexNames.contains('user_id')) {
          store.createIndex('user_id', 'user_id', { unique: false })
        }
        if (definition.name === 'logged_food_entries' && !store.indexNames.contains('meal_id')) {
          store.createIndex('meal_id', 'meal_id', { unique: false })
        }
        if (definition.name === 'meal_preset_items' && !store.indexNames.contains('preset_id')) {
          store.createIndex('preset_id', 'preset_id', { unique: false })
        }
        if (definition.name === 'photo_blobs' && !store.indexNames.contains('photo_id')) {
          store.createIndex('photo_id', 'photo_id', { unique: false })
        }
      }
    }
    request.onsuccess = () => {
      if (settled) {
        request.result.close()
        return
      }
      settled = true
      const database = request.result
      database.onversionchange = () => {
        database.close()
        if (dbPromise === opening) dbPromise = null
      }
      database.onclose = () => {
        if (dbPromise === opening) dbPromise = null
      }
      resolve(database)
    }
    request.onerror = () => fail(request.error ?? new Error('Could not open APEX private storage'))
    request.onblocked = () => fail(new Error('APEX private storage is blocked by another open app tab. Close the other tab and retry.'))
  })
  dbPromise = opening
  return opening
}

export async function privatePut<T>(storeName: PrivateStoreName, value: T): Promise<void> {
  const database = await openPrivateDb()
  const transaction = database.transaction(storeName, 'readwrite')
  transaction.objectStore(storeName).put(value)
  await transactionDone(transaction)
}

export async function privatePutMany<T>(storeName: PrivateStoreName, values: T[]): Promise<void> {
  if (values.length === 0) return
  const database = await openPrivateDb()
  const transaction = database.transaction(storeName, 'readwrite')
  const store = transaction.objectStore(storeName)
  for (const value of values) store.put(value)
  await transactionDone(transaction)
}

export async function privateGet<T>(storeName: PrivateStoreName, id: string): Promise<T | null> {
  const database = await openPrivateDb()
  const transaction = database.transaction(storeName, 'readonly')
  const result = await requestResult(transaction.objectStore(storeName).get(id))
  return (result as T | undefined) ?? null
}

export async function privateGetAll<T>(storeName: PrivateStoreName): Promise<T[]> {
  const database = await openPrivateDb()
  const transaction = database.transaction(storeName, 'readonly')
  return requestResult(transaction.objectStore(storeName).getAll()) as Promise<T[]>
}

export async function privateGetAllForUser<T extends { user_id: string }>(
  storeName: Exclude<PrivateStoreName, 'foods'>,
  userId: string,
): Promise<T[]> {
  const database = await openPrivateDb()
  const transaction = database.transaction(storeName, 'readonly')
  return requestResult(transaction.objectStore(storeName).index('user_id').getAll(userId)) as Promise<T[]>
}

export async function privateDelete(storeName: PrivateStoreName, id: string): Promise<void> {
  const database = await openPrivateDb()
  const transaction = database.transaction(storeName, 'readwrite')
  transaction.objectStore(storeName).delete(id)
  await transactionDone(transaction)
}

/**
 * Delete an account-owned row only when the durable row still belongs to the
 * account that completed the request. The ownership check and delete share an
 * IndexedDB transaction, preventing a late acknowledgement from another
 * session from consuming the active account's intent.
 */
export async function privateDeleteForUser(
  storeName: Exclude<PrivateStoreName, 'foods'>,
  id: string,
  userId: string,
): Promise<boolean> {
  const database = await openPrivateDb()
  const transaction = database.transaction(storeName, 'readwrite')
  const store = transaction.objectStore(storeName)
  let deleted = false
  const cursorRequest = store.openCursor(IDBKeyRange.only(id))
  cursorRequest.onsuccess = () => {
    const cursor = cursorRequest.result
    const value = cursor?.value as { user_id?: unknown } | undefined
    if (cursor && value?.user_id === userId) {
      cursor.delete()
      deleted = true
    }
  }
  cursorRequest.onerror = () => transaction.abort()
  await transactionDone(transaction)
  return deleted
}

/**
 * Acknowledge only the exact durable intent that was sent. Photo operations
 * deliberately reuse stable ids so repeated edits coalesce; matching the
 * creation timestamp prevents an older in-flight request from deleting a
 * newer replacement stored under the same id.
 */
export async function acknowledgePrivateOutboxOperation(
  operation: PrivateOutboxOp,
): Promise<boolean> {
  const database = await openPrivateDb()
  const transaction = database.transaction('private_outbox', 'readwrite')
  const store = transaction.objectStore('private_outbox')
  const request = store.get(operation.id)
  let acknowledged = false
  request.onsuccess = () => {
    const current = request.result as PrivateOutboxOp | undefined
    if (
      current?.user_id === operation.user_id
      && current.domain === operation.domain
      && current.operation === operation.operation
      && current.entity_id === operation.entity_id
      && current.created_at === operation.created_at
    ) {
      store.delete(operation.id)
      acknowledged = true
    }
  }
  request.onerror = () => transaction.abort()
  await transactionDone(transaction)
  return acknowledged
}

/** Record a failure only when the sent operation is still current. */
export async function recordPrivateOutboxFailure(
  operation: PrivateOutboxOp,
  message: string,
): Promise<boolean> {
  const database = await openPrivateDb()
  const transaction = database.transaction(['private_outbox', 'progress_photos'], 'readwrite')
  const store = transaction.objectStore('private_outbox')
  const request = store.get(operation.id)
  let retained = false
  request.onsuccess = () => {
    const current = request.result as PrivateOutboxOp | undefined
    if (
      current?.user_id !== operation.user_id
      || current.domain !== operation.domain
      || current.operation !== operation.operation
      || current.entity_id !== operation.entity_id
      || current.created_at !== operation.created_at
    ) return
    store.put({
      ...current,
      attempts: Number(current.attempts ?? 0) + 1,
      last_attempt_at: new Date().toISOString(),
      last_error: message,
    } satisfies PrivateOutboxOp)
    if (operation.domain === 'photo') {
      const photoStore = transaction.objectStore('progress_photos')
      const photoRequest = photoStore.get(operation.entity_id)
      photoRequest.onsuccess = () => {
        const photo = photoRequest.result as ProgressPhoto | undefined
        if (photo?.user_id === operation.user_id) photoStore.put({ ...photo, sync_status: 'failed' })
      }
      photoRequest.onerror = () => transaction.abort()
    }
    retained = true
  }
  request.onerror = () => transaction.abort()
  await transactionDone(transaction)
  return retained
}

export async function cacheVisibleFoods(userId: string, foods: FoodRecord[]): Promise<void> {
  await privatePutMany('foods', foods.filter((food) => food.owner_user_id == null || food.owner_user_id === userId))
}

export interface FoodUserCacheSnapshot {
  preferences: FoodPreference[]
  presets: MealPreset[]
  presetItems: MealPresetItem[]
  meals: LoggedMeal[]
  entries: LoggedFoodEntry[]
}

/**
 * Replace one account's complete food cache in a single transaction. The
 * caller replays its durable outbox over a fully paginated server snapshot
 * first, so pending offline edits remain while rows deleted on another device
 * cannot resurrect during a later offline launch.
 */
export async function replaceFoodUserCacheAtomically(
  userId: string,
  snapshot: FoodUserCacheSnapshot,
): Promise<void> {
  const database = await openPrivateDb()
  const replacements: Array<[Exclude<PrivateStoreName, 'foods' | 'progress_photos' | 'photo_blobs' | 'private_outbox'>, Array<{ id: string }>]> = [
    ['food_preferences', snapshot.preferences],
    ['meal_presets', snapshot.presets],
    ['meal_preset_items', snapshot.presetItems],
    ['logged_meals', snapshot.meals],
    ['logged_food_entries', snapshot.entries],
  ]
  const transaction = database.transaction(replacements.map(([store]) => store), 'readwrite')
  for (const [storeName, rows] of replacements) {
    const store = transaction.objectStore(storeName)
    const cursorRequest = store.index('user_id').openKeyCursor(IDBKeyRange.only(userId))
    cursorRequest.onsuccess = () => {
      const cursor = cursorRequest.result
      if (cursor) {
        store.delete(cursor.primaryKey)
        cursor.continue()
        return
      }
      for (const row of rows) store.put(row)
    }
    cursorRequest.onerror = () => transaction.abort()
  }
  await transactionDone(transaction)
}

export async function loadVisibleFoods(userId: string): Promise<FoodRecord[]> {
  const foods = await privateGetAll<FoodRecord>('foods')
  return foods.filter((food) => food.owner_user_id == null || food.owner_user_id === userId)
}

export async function saveMealAtomically(
  meal: LoggedMeal,
  entries: LoggedFoodEntry[],
  preferenceUpdates: FoodPreference[],
  outbox: PrivateOutboxOp | null,
  replaceMealId: string | null = null,
): Promise<void> {
  const database = await openPrivateDb()
  const stores: PrivateStoreName[] = ['logged_meals', 'logged_food_entries', 'food_preferences']
  if (outbox) stores.push('private_outbox')
  const transaction = database.transaction(stores, 'readwrite')
  const mealStore = transaction.objectStore('logged_meals')
  const entryStore = transaction.objectStore('logged_food_entries')
  if (replaceMealId && replaceMealId !== meal.id) {
    mealStore.delete(replaceMealId)
    const replacedEntries = entryStore.index('meal_id').openKeyCursor(IDBKeyRange.only(replaceMealId))
    replacedEntries.onsuccess = () => {
      const cursor = replacedEntries.result
      if (!cursor) return
      entryStore.delete(cursor.primaryKey)
      cursor.continue()
    }
    replacedEntries.onerror = () => transaction.abort()
  }
  mealStore.put(meal)
  for (const entry of entries) entryStore.put(entry)
  for (const preference of preferenceUpdates) transaction.objectStore('food_preferences').put(preference)
  if (outbox) transaction.objectStore('private_outbox').put(outbox)
  await transactionDone(transaction)
}

export async function savePresetAtomically(
  preset: MealPreset,
  items: MealPresetItem[],
  outbox: PrivateOutboxOp | null,
): Promise<void> {
  const database = await openPrivateDb()
  const stores: PrivateStoreName[] = ['meal_presets', 'meal_preset_items']
  if (outbox) stores.push('private_outbox')
  const transaction = database.transaction(stores, 'readwrite')
  transaction.objectStore('meal_presets').put(preset)
  const itemStore = transaction.objectStore('meal_preset_items')
  const cursorRequest = itemStore.index('preset_id').openKeyCursor(IDBKeyRange.only(preset.id))
  cursorRequest.onsuccess = () => {
    const cursor = cursorRequest.result
    if (cursor) {
      itemStore.delete(cursor.primaryKey)
      cursor.continue()
      return
    }
    for (const item of items) itemStore.put(item)
    if (outbox) transaction.objectStore('private_outbox').put(outbox)
  }
  cursorRequest.onerror = () => transaction.abort()
  await transactionDone(transaction)
}

export async function saveProgressPhotoAtomically(
  photo: ProgressPhoto,
  full: Blob,
  thumbnail: Blob,
  outbox: PrivateOutboxOp | null,
): Promise<void> {
  if (outbox && (outbox.user_id !== photo.user_id || outbox.entity_id !== photo.id || outbox.domain !== 'photo')) {
    throw new Error('APEX refused a mismatched photo save intent.')
  }
  const commit = async () => {
    const database = await openPrivateDb()
    const stores: PrivateStoreName[] = ['progress_photos', 'photo_blobs']
    if (outbox) stores.push('private_outbox')
    const transaction = database.transaction(stores, 'readwrite')
    transaction.objectStore('progress_photos').put(photo)
    const updated = new Date().toISOString()
    transaction.objectStore('photo_blobs').put({
      id: `${photo.id}:full`, user_id: photo.user_id, photo_id: photo.id, kind: 'full', blob: full, updated_at: updated,
    } satisfies StoredPhotoBlob)
    transaction.objectStore('photo_blobs').put({
      id: `${photo.id}:thumbnail`, user_id: photo.user_id, photo_id: photo.id, kind: 'thumbnail', blob: thumbnail, updated_at: updated,
    } satisfies StoredPhotoBlob)
    if (outbox) transaction.objectStore('private_outbox').put(outbox)
    await transactionDone(transaction)
  }
  try {
    await commit()
  } catch (error) {
    if (!(error instanceof DOMException) || error.name !== 'InvalidStateError') throw error
    // A backgrounded iOS tab can leave a resolved promise pointing at a
    // closed IndexedDB connection. Reopen once; the transaction is atomic, so
    // this retry cannot create a partial or duplicate photo.
    resetPrivateDbConnection()
    await commit()
  }
}

/** Replace one owner's authoritative photo metadata and prune orphaned local
 * blobs in the same transaction. Current owner-scoped intents are reread and
 * replayed while the write lock is held so hydration cannot erase a mutation. */
export async function replaceProgressPhotoUserCacheAtomically(
  userId: string,
  photos: ProgressPhoto[],
): Promise<ProgressPhoto[]> {
  if (photos.some((photo) => photo.user_id !== userId)) throw new Error('APEX refused a cross-account photo cache replace.')
  const database = await openPrivateDb()
  const transaction = database.transaction(['progress_photos', 'photo_blobs', 'private_outbox'], 'readwrite')
  const completion = transactionDone(transaction)
  const photoStore = transaction.objectStore('progress_photos')
  const blobStore = transaction.objectStore('photo_blobs')
  const outboxStore = transaction.objectStore('private_outbox')
  const ownerRange = IDBKeyRange.only(userId)
  const localRequest = photoStore.index('user_id').getAll(ownerRange)
  const outboxRequest = outboxStore.index('user_id').getAll(ownerRange)
  let localRows: ProgressPhoto[] | null = null
  let outboxRows: PrivateOutboxOp[] | null = null
  let reconciled = photos

  const reconcileAndReplace = (): void => {
    if (!localRows || !outboxRows) return
    try {
      /* Re-read local rows and intents while holding the same write lock used
         for replacement. Any save/edit/delete committed before this
         transaction is replayed here; anything started later queues behind it. */
      reconciled = replayProgressPhotoOutbox(
        photos,
        localRows,
        outboxRows.filter((operation) => operation.domain === 'photo' && operation.user_id === userId),
      )
      const retainedIds = new Set(reconciled.map((photo) => photo.id))
      const photoCursor = photoStore.index('user_id').openKeyCursor(ownerRange)
      photoCursor.onsuccess = () => {
        const cursor = photoCursor.result
        if (cursor) {
          photoStore.delete(cursor.primaryKey)
          cursor.continue()
          return
        }
        for (const photo of reconciled) photoStore.put(photo)
      }
      photoCursor.onerror = () => transaction.abort()
      const blobCursor = blobStore.index('user_id').openCursor(ownerRange)
      blobCursor.onsuccess = () => {
        const cursor = blobCursor.result
        if (!cursor) return
        const blob = cursor.value as StoredPhotoBlob
        if (!retainedIds.has(blob.photo_id)) cursor.delete()
        cursor.continue()
      }
      blobCursor.onerror = () => transaction.abort()
    } catch {
      transaction.abort()
    }
  }

  localRequest.onsuccess = () => {
    localRows = (localRequest.result as ProgressPhoto[]).filter((photo) => photo.user_id === userId)
    reconcileAndReplace()
  }
  localRequest.onerror = () => transaction.abort()
  outboxRequest.onsuccess = () => {
    outboxRows = (outboxRequest.result as PrivateOutboxOp[]).filter((operation) => operation.user_id === userId)
    reconcileAndReplace()
  }
  outboxRequest.onerror = () => transaction.abort()
  await completion
  return reconciled
}

/** Store a photo edit and its durable intent as one save boundary. */
export async function updateProgressPhotoAtomically(
  photo: ProgressPhoto,
  outbox: PrivateOutboxOp | null,
): Promise<void> {
  if (outbox && (outbox.user_id !== photo.user_id || outbox.entity_id !== photo.id || outbox.domain !== 'photo')) {
    throw new Error('APEX refused a mismatched photo update intent.')
  }
  const database = await openPrivateDb()
  const stores: PrivateStoreName[] = ['progress_photos']
  if (outbox) stores.push('private_outbox')
  const transaction = database.transaction(stores, 'readwrite')
  transaction.objectStore('progress_photos').put(photo)
  if (outbox) transaction.objectStore('private_outbox').put(outbox)
  await transactionDone(transaction)
}

/** Mark the exact photo snapshot as synced without overwriting a newer edit. */
export async function markProgressPhotoSyncedIfCurrent(
  userId: string,
  photoId: string,
  expectedUpdatedAt: string,
  patch: Partial<ProgressPhoto> = {},
): Promise<ProgressPhoto | null> {
  const database = await openPrivateDb()
  const transaction = database.transaction('progress_photos', 'readwrite')
  const store = transaction.objectStore('progress_photos')
  const request = store.get(photoId)
  let synced: ProgressPhoto | null = null
  request.onsuccess = () => {
    const current = request.result as ProgressPhoto | undefined
    if (!current || current.user_id !== userId || current.updated_at !== expectedUpdatedAt) return
    synced = { ...current, ...patch, sync_status: 'synced' }
    store.put(synced)
  }
  request.onerror = () => transaction.abort()
  await transactionDone(transaction)
  return synced
}

export async function deleteProgressPhotoLocally(
  photoId: string,
  userId?: string,
  outbox: PrivateOutboxOp | null = null,
): Promise<void> {
  if (outbox && (!userId || outbox.user_id !== userId || outbox.entity_id !== photoId || outbox.domain !== 'photo')) {
    throw new Error('APEX refused a mismatched photo delete intent.')
  }
  const database = await openPrivateDb()
  const stores: PrivateStoreName[] = ['progress_photos', 'photo_blobs']
  if (outbox) stores.push('private_outbox')
  const transaction = database.transaction(stores, 'readwrite')
  transaction.objectStore('progress_photos').delete(photoId)
  transaction.objectStore('photo_blobs').delete(`${photoId}:full`)
  transaction.objectStore('photo_blobs').delete(`${photoId}:thumbnail`)
  if (outbox) {
    const outboxStore = transaction.objectStore('private_outbox')
    if (userId) {
      const cursor = outboxStore.index('user_id').openCursor(IDBKeyRange.only(userId))
      cursor.onsuccess = () => {
        const row = cursor.result
        if (!row) {
          outboxStore.put(outbox)
          return
        }
        const pending = row.value as PrivateOutboxOp
        if (pending.domain === 'photo' && pending.entity_id === photoId) row.delete()
        row.continue()
      }
      cursor.onerror = () => transaction.abort()
    } else {
      outboxStore.put(outbox)
    }
  }
  await transactionDone(transaction)
}

export async function deleteMealLocally(
  mealId: string,
  outbox: PrivateOutboxOp | null = null,
): Promise<void> {
  const database = await openPrivateDb()
  const stores: PrivateStoreName[] = ['logged_meals', 'logged_food_entries']
  if (outbox) stores.push('private_outbox')
  const transaction = database.transaction(stores, 'readwrite')
  transaction.objectStore('logged_meals').delete(mealId)
  const entryStore = transaction.objectStore('logged_food_entries')
  const cursor = entryStore.index('meal_id').openKeyCursor(IDBKeyRange.only(mealId))
  cursor.onsuccess = () => {
    const result = cursor.result
    if (!result) return
    entryStore.delete(result.primaryKey)
    result.continue()
  }
  cursor.onerror = () => transaction.abort()
  if (outbox) transaction.objectStore('private_outbox').put(outbox)
  await transactionDone(transaction)
}

export async function deletePresetLocally(
  presetId: string,
  outbox: PrivateOutboxOp | null = null,
): Promise<void> {
  const database = await openPrivateDb()
  const stores: PrivateStoreName[] = ['meal_presets', 'meal_preset_items']
  if (outbox) stores.push('private_outbox')
  const transaction = database.transaction(stores, 'readwrite')
  transaction.objectStore('meal_presets').delete(presetId)
  const itemStore = transaction.objectStore('meal_preset_items')
  const cursor = itemStore.index('preset_id').openKeyCursor(IDBKeyRange.only(presetId))
  cursor.onsuccess = () => {
    const result = cursor.result
    if (!result) return
    itemStore.delete(result.primaryKey)
    result.continue()
  }
  cursor.onerror = () => transaction.abort()
  if (outbox) transaction.objectStore('private_outbox').put(outbox)
  await transactionDone(transaction)
}
