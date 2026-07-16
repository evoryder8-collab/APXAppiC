import type {
  FoodPreference,
  FoodRecord,
  LoggedFoodEntry,
  LoggedMeal,
  MealPreset,
  MealPresetItem,
} from './food'
import type { ProgressPhoto } from './progressPhoto'

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

export async function cacheVisibleFoods(userId: string, foods: FoodRecord[]): Promise<void> {
  await privatePutMany('foods', foods.filter((food) => food.owner_user_id == null || food.owner_user_id === userId))
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
): Promise<void> {
  const database = await openPrivateDb()
  const stores: PrivateStoreName[] = ['logged_meals', 'logged_food_entries', 'food_preferences']
  if (outbox) stores.push('private_outbox')
  const transaction = database.transaction(stores, 'readwrite')
  transaction.objectStore('logged_meals').put(meal)
  for (const entry of entries) transaction.objectStore('logged_food_entries').put(entry)
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

export async function deleteProgressPhotoLocally(photoId: string): Promise<void> {
  const database = await openPrivateDb()
  const transaction = database.transaction(['progress_photos', 'photo_blobs'], 'readwrite')
  transaction.objectStore('progress_photos').delete(photoId)
  transaction.objectStore('photo_blobs').delete(`${photoId}:full`)
  transaction.objectStore('photo_blobs').delete(`${photoId}:thumbnail`)
  await transactionDone(transaction)
}

export async function deleteMealLocally(mealId: string): Promise<void> {
  const database = await openPrivateDb()
  const transaction = database.transaction(['logged_meals', 'logged_food_entries'], 'readwrite')
  transaction.objectStore('logged_meals').delete(mealId)
  const entryStore = transaction.objectStore('logged_food_entries')
  const cursor = entryStore.index('meal_id').openKeyCursor(IDBKeyRange.only(mealId))
  cursor.onsuccess = () => {
    const result = cursor.result
    if (!result) return
    entryStore.delete(result.primaryKey)
    result.continue()
  }
  await transactionDone(transaction)
}

export async function deletePresetLocally(presetId: string): Promise<void> {
  const database = await openPrivateDb()
  const transaction = database.transaction(['meal_presets', 'meal_preset_items'], 'readwrite')
  transaction.objectStore('meal_presets').delete(presetId)
  const itemStore = transaction.objectStore('meal_preset_items')
  const cursor = itemStore.index('preset_id').openKeyCursor(IDBKeyRange.only(presetId))
  cursor.onsuccess = () => {
    const result = cursor.result
    if (!result) return
    itemStore.delete(result.primaryKey)
    result.continue()
  }
  await transactionDone(transaction)
}
