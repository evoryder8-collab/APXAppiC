import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const privateDb = readFileSync(new URL('../src/lib/privateDb.ts', import.meta.url), 'utf8')
const foodStore = readFileSync(new URL('../src/store/FoodStore.tsx', import.meta.url), 'utf8')
const appStore = readFileSync(new URL('../src/store/AppStore.tsx', import.meta.url), 'utf8')
const photoStore = readFileSync(new URL('../src/store/ProgressPhotoStore.tsx', import.meta.url), 'utf8')
const supabaseClient = readFileSync(new URL('../src/lib/supabase.ts', import.meta.url), 'utf8')
const appRoot = readFileSync(new URL('../src/App.tsx', import.meta.url), 'utf8')

test('meal replacement commits the replacement tombstone, snapshots and outbox atomically', () => {
  assert.match(privateDb, /saveMealAtomically\([\s\S]*replaceMealId: string \| null = null/)
  assert.match(privateDb, /mealStore\.delete\(replaceMealId\)/)
  assert.match(privateDb, /entryStore\.index\('meal_id'\).*replaceMealId/)
  assert.match(foodStore, /saveMealAtomically\([\s\S]*input\.replaceMealId \?\? null/)
})

test('remote food hydration paginates fully before pruning one user cache', () => {
  assert.match(foodStore, /fetchAllOwnedFoodRows/)
  assert.match(foodStore, /\.range\(offset, offset \+ pageSize - 1\)/)
  assert.match(foodStore, /replaceFoodUserCacheAtomically\(expectedUserId, replayed\)/)
  assert.match(privateDb, /store\.index\('user_id'\)\.openKeyCursor\(IDBKeyRange\.only\(userId\)\)/)
})

test('generic sync deletes are scoped to the active authenticated user', () => {
  assert.match(appStore, /\.delete\(\)[\s\S]*\.eq\('id',[\s\S]*\.eq\('user_id', scope\)/)
})

test('workout and daily history hydration is fully paginated', () => {
  assert.match(appStore, /fetchAllOwnedRows/)
  assert.match(appStore, /\.range\(offset, offset \+ pageSize - 1\)/)
  assert.match(appStore, /Promise\.all\(LIST_TABLES\.map\(\(table\) => fetchAllOwnedRows/)
})

test('an account switch resumes the newly active outbox after the old request settles', () => {
  const finallyBlock = appStore.slice(appStore.indexOf('if (flushRequested.current)'), appStore.indexOf('}, [toast])'))
  assert.match(finallyBlock, /if \(navigator\.onLine\) window\.setTimeout\(\(\) => void flush\(\), 0\)/)
  assert.doesNotMatch(finallyBlock, /scopeRef\.current === scope/)
})

test('food flush is bearer-bound to its captured account and acknowledges only owned intents', () => {
  assert.match(supabaseClient, /createSessionBoundSupabase\(accessToken: string\)/)
  assert.match(supabaseClient, /accessToken: async \(\) => accessToken/)
  assert.match(foodStore, /syncSession\.user\.id !== syncUserId/)
  assert.match(foodStore, /userIdRef\.current !== syncUserId \|\| !foodOperationBelongsToUser\(operation, syncUserId\)/)
  assert.match(foodStore, /sendOutbox\(syncClient, operation\)/)
  assert.match(foodStore, /privateDeleteForUser\('private_outbox', operation\.id, syncUserId\)/)
  assert.match(privateDb, /value\?\.user_id === userId/)

  const sendStart = foodStore.indexOf('const sendOutbox')
  const sendBlock = foodStore.slice(sendStart, foodStore.indexOf('const flush =', sendStart))
  assert.match(sendBlock, /client: SupabaseClient/)
  assert.doesNotMatch(sendBlock, /\bsupabase\./)
})

test('core sync and hydration use the captured session token instead of mutable global auth', () => {
  const flushStart = appStore.indexOf('const flush =')
  const flushBlock = appStore.slice(flushStart, appStore.indexOf('const enqueue =', flushStart))
  assert.match(flushBlock, /const syncSession = sessionRef\.current/)
  assert.match(flushBlock, /syncSession\?\.user\.id === scope/)
  assert.match(flushBlock, /createSessionBoundSupabase\(syncSession\.access_token\)/)
  assert.match(flushBlock, /syncClient\.from\(op\.table\)/)
  assert.doesNotMatch(flushBlock, /await supabase\.from\(op\.table\)/)

  const fetchStart = appStore.indexOf('const fetchAll =')
  const fetchBlock = appStore.slice(fetchStart, appStore.indexOf('useEffect(() => {', fetchStart))
  assert.match(fetchBlock, /createSessionBoundSupabase\(session\.access_token\)/)
  assert.match(fetchBlock, /fetchAllOwnedRows\(sb, table, sessionUserId\)/)
})

test('food async commits cannot merge an old account into the active account state', () => {
  assert.match(foodStore, /foodMutationBelongsToActiveUser\(userId, userIdRef\.current\)/)

  const logMealStart = foodStore.indexOf('const logMeal =')
  const logMealBlock = foodStore.slice(logMealStart, foodStore.indexOf('const deleteMeal =', logMealStart))
  assert.match(logMealBlock, /await saveMealAtomically/)
  assert.match(logMealBlock, /if \(!foodMutationBelongsToActiveUser\(userId, userIdRef\.current\)\) return meal/)

  const deleteMealStart = foodStore.indexOf('const deleteMeal =')
  const deleteMealBlock = foodStore.slice(deleteMealStart, foodStore.indexOf('const savePreset =', deleteMealStart))
  assert.match(deleteMealBlock, /await deleteMealLocally/)
  assert.match(deleteMealBlock, /if \(!foodMutationBelongsToActiveUser\(userId, userIdRef\.current\)\) return/)

  const savePresetStart = foodStore.indexOf('const savePreset =')
  const savePresetBlock = foodStore.slice(savePresetStart, foodStore.indexOf('const deletePreset =', savePresetStart))
  assert.match(savePresetBlock, /await savePresetAtomically/)
  assert.match(savePresetBlock, /if \(!foodMutationBelongsToActiveUser\(userId, userIdRef\.current\)\) return preset/)
})

test('food hydration reads through a client bound to its captured matching session', () => {
  const ownedRowsStart = foodStore.indexOf('async function fetchAllOwnedFoodRows')
  const ownedRowsBlock = foodStore.slice(ownedRowsStart, foodStore.indexOf('export function FoodStoreProvider', ownedRowsStart))
  assert.match(ownedRowsBlock, /client: SupabaseClient/)
  assert.match(ownedRowsBlock, /await client/)
  assert.doesNotMatch(ownedRowsBlock, /await supabase/)

  const hydrateStart = foodStore.indexOf('const hydrate =')
  const hydrateBlock = foodStore.slice(hydrateStart, foodStore.indexOf('useEffect(() => { void hydrate()', hydrateStart))
  assert.match(hydrateBlock, /const \{ data: \{ session: hydrationSession \}/)
  assert.match(hydrateBlock, /foodSessionBelongsToExpectedUser\(hydrationSession\.user\.id, expectedUserId\)/)
  assert.match(hydrateBlock, /createSessionBoundSupabase\(hydrationSession\.access_token\)/)
  assert.match(hydrateBlock, /hydrationClient\.from\('foods'\)/)
  assert.match(hydrateBlock, /fetchAllOwnedFoodRows\(hydrationClient, 'logged_meals', expectedUserId\)/)
  assert.doesNotMatch(hydrateBlock, /supabase\.from\('foods'\)/)
})

test('photo sync is session-bound and stale acknowledgements cannot consume newer edits', () => {
  assert.match(photoStore, /sessionClientForUser\(syncUserId\)/)
  assert.match(photoStore, /sendOperation\(client, syncUserId, operation\)/)
  assert.match(photoStore, /activeUserId\.current !== syncUserId/)
  assert.match(photoStore, /acknowledgePrivateOutboxOperation\(operation\)/)
  assert.match(photoStore, /replaceProgressPhotoUserCacheAtomically\(hydrationUserId, values\)/)
  assert.match(photoStore, /replayProgressPhotoOutbox\(remote, local, pending\)/)
  assert.match(privateDb, /current\.created_at === operation\.created_at/)
  assert.match(privateDb, /updateProgressPhotoAtomically/)
  assert.match(privateDb, /deleteProgressPhotoLocally\([\s\S]*private_outbox/)
})

test('photo hydration reconciles under the cache write lock and hides stale owners', () => {
  assert.match(privateDb, /transaction\(\['progress_photos', 'photo_blobs', 'private_outbox'\], 'readwrite'\)/)
  assert.match(privateDb, /replayProgressPhotoOutbox\([\s\S]*outboxRows\.filter/)
  assert.match(privateDb, /await completion[\s\S]*return reconciled/)
  assert.match(photoStore, /const ownerMatches = hydratedUserId === userId/)
  assert.match(photoStore, /photos\.filter\(\(photo\) => photo\.user_id === userId\)/)
  assert.match(photoStore, /Object\.entries\(fullUrls\)\.filter\(\(\[id\]\) => visibleIds\.has\(id\)\)/)
})

test('all private domain providers remount at the authenticated owner boundary', () => {
  assert.match(appRoot, /const ownerKey = data\.profile\?\.user_id \?\? 'signed-out'/)
  assert.match(appRoot, /<FoodStoreProvider key=\{ownerKey\}>[\s\S]*<ProgressPhotoStoreProvider>[\s\S]*<OrbitStoreProvider>/)
})
