import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react'
import {
  processProgressPhoto,
  progressFramingMode,
  progressPhotoIdempotencyKey,
  progressPhotoSaveError,
  progressStoragePaths,
  mergeProgressPhotoPendingOperations,
  replayProgressPhotoOutbox,
  type NormalizedCrop,
  type ProcessedProgressPhoto,
  type ProgressPhoto,
  type ProgressFramingMode,
  type ProgressPose,
} from '../lib/progressPhoto'
import type { SupabaseClient } from '@supabase/supabase-js'
import {
  acknowledgePrivateOutboxOperation,
  deleteProgressPhotoLocally,
  privateGet,
  privateGetAllForUser,
  markProgressPhotoSyncedIfCurrent,
  recordPrivateOutboxFailure,
  replaceProgressPhotoUserCacheAtomically,
  saveProgressPhotoAtomically,
  updateProgressPhotoAtomically,
  type PrivateOutboxOp,
  type StoredPhotoBlob,
} from '../lib/privateDb'
import { createSessionBoundSupabase, isLocalMode, supabase } from '../lib/supabase'
import { todayIso } from '../lib/plan'
import { useStore } from './AppStore'

interface SavePhotoInput {
  raw: Blob
  processed?: ProcessedProgressPhoto
  pose: ProgressPose
  framingMode?: ProgressFramingMode
  localDate?: string
  weightKg?: number | null
  note?: string
  referencePhotoId?: string | null
}

interface PhotoStoreValue {
  ready: boolean
  syncing: boolean
  photos: ProgressPhoto[]
  fullUrls: Record<string, string>
  thumbnailUrls: Record<string, string>
  savePhoto: (input: SavePhotoInput) => Promise<ProgressPhoto>
  deletePhoto: (photoId: string) => Promise<void>
  updatePhoto: (photoId: string, patch: Partial<Pick<ProgressPhoto, 'note' | 'weight_kg' | 'crop_x' | 'crop_y' | 'crop_scale'>>) => Promise<void>
  setCrop: (photoId: string, crop: NormalizedCrop) => Promise<void>
  ensurePhotoUrl: (photo: ProgressPhoto, thumbnail?: boolean) => Promise<string | null>
  retrySync: () => Promise<void>
}

const Ctx = createContext<PhotoStoreValue | null>(null)
let lastPhotoClockMs = 0

function nextPhotoTimestamp(): string {
  lastPhotoClockMs = Math.max(Date.now(), lastPhotoClockMs + 1)
  return new Date(lastPhotoClockMs).toISOString()
}

function photoOutbox(userId: string, operation: 'upload_photo' | 'delete_photo' | 'update_photo', photoId: string): PrivateOutboxOp {
  return {
    id: `photo:${operation}:${photoId}`, user_id: userId, domain: 'photo', operation,
    entity_id: photoId, payload: null, created_at: nextPhotoTimestamp(), attempts: 0,
  }
}

async function fetchAllProgressPhotos(client: SupabaseClient, userId: string): Promise<Record<string, unknown>[]> {
  const pageSize = 500
  const rows: Record<string, unknown>[] = []
  for (let offset = 0; ; offset += pageSize) {
    const { data: page, error } = await client
      .from('progress_photos')
      .select('*')
      .eq('user_id', userId)
      .order('captured_at', { ascending: false })
      .range(offset, offset + pageSize - 1)
    if (error) throw error
    rows.push(...((page ?? []).filter((row) => row.user_id === userId) as Record<string, unknown>[]))
    if ((page?.length ?? 0) < pageSize) return rows
  }
}

function remotePhoto(photo: ProgressPhoto): Omit<ProgressPhoto, 'sync_status' | 'framing_mode'> {
  const { sync_status: _syncStatus, framing_mode: _framingMode, ...row } = photo
  return row
}

function normalizedPhoto(photo: ProgressPhoto): ProgressPhoto {
  return { ...photo, framing_mode: progressFramingMode(photo) }
}

function syncErrorSummary(cause: unknown): string {
  if (!cause || typeof cause !== 'object') return String(cause || 'Unknown sync error').slice(0, 300)
  const value = cause as { code?: unknown; statusCode?: unknown; message?: unknown }
  return [value.code, value.statusCode, value.message]
    .filter((part) => part != null && String(part).trim())
    .map(String)
    .join(' · ')
    .slice(0, 300) || 'Unknown sync error'
}

export function ProgressPhotoStoreProvider({ children }: { children: ReactNode }) {
  const { data, toast } = useStore()
  const userId = data.profile?.user_id ?? null
  const [ready, setReady] = useState(false)
  const [hydrationRetry, setHydrationRetry] = useState(0)
  const [syncing, setSyncing] = useState(false)
  const [photos, setPhotos] = useState<ProgressPhoto[]>([])
  const [hydratedUserId, setHydratedUserId] = useState<string | null>(null)
  const [fullUrls, setFullUrls] = useState<Record<string, string>>({})
  const [thumbnailUrls, setThumbnailUrls] = useState<Record<string, string>>({})
  const flushing = useRef(false)
  const flushRequested = useRef(false)
  const activeUserId = useRef(userId)
  const latestFlush = useRef<() => Promise<void>>(async () => undefined)
  const hydrationGeneration = useRef(0)
  const mutationRevision = useRef(0)
  const objectUrls = useRef(new Set<string>())
  activeUserId.current = userId

  const sessionClientForUser = useCallback(async (expectedUserId: string): Promise<SupabaseClient | null> => {
    if (!supabase) return null
    const { data: { session }, error } = await supabase.auth.getSession()
    if (error || !session || session.user.id !== expectedUserId) return null
    return createSessionBoundSupabase(session.access_token)
  }, [])

  const installLocalUrl = useCallback(async (photoId: string, thumbnail: boolean): Promise<string | null> => {
    const key = `${photoId}:${thumbnail ? 'thumbnail' : 'full'}`
    const record = await privateGet<StoredPhotoBlob>('photo_blobs', key)
    if (!record || record.user_id !== activeUserId.current) return null
    const url = URL.createObjectURL(record.blob)
    objectUrls.current.add(url)
    if (thumbnail) setThumbnailUrls((current) => ({ ...current, [photoId]: url }))
    else setFullUrls((current) => ({ ...current, [photoId]: url }))
    return url
  }, [])

  const ensurePhotoUrl = useCallback(async (photo: ProgressPhoto, thumbnail = false): Promise<string | null> => {
    if (photo.user_id !== activeUserId.current) return null
    const current = thumbnail ? thumbnailUrls[photo.id] : fullUrls[photo.id]
    if (current) return current
    const local = await installLocalUrl(photo.id, thumbnail)
    if (local) return local
    if (!supabase || !navigator.onLine) return null
    const client = await sessionClientForUser(photo.user_id)
    if (!client || photo.user_id !== activeUserId.current) return null
    const path = thumbnail ? photo.thumbnail_path : photo.storage_path
    const { data: signed, error } = await client.storage.from('apex-progress').createSignedUrl(path, 3600)
    if (error || !signed?.signedUrl || photo.user_id !== activeUserId.current) return null
    if (thumbnail) setThumbnailUrls((values) => ({ ...values, [photo.id]: signed.signedUrl }))
    else setFullUrls((values) => ({ ...values, [photo.id]: signed.signedUrl }))
    return signed.signedUrl
  }, [fullUrls, installLocalUrl, sessionClientForUser, thumbnailUrls])

  const hydrate = useCallback(async () => {
    const hydrationUserId = userId
    const generation = ++hydrationGeneration.current
    const revision = mutationRevision.current
    const current = (): boolean => (
      hydrationGeneration.current === generation && activeUserId.current === hydrationUserId
    )
    for (const url of objectUrls.current) URL.revokeObjectURL(url)
    objectUrls.current.clear()
    setFullUrls({})
    setThumbnailUrls({})
    if (!hydrationUserId) {
      setPhotos([])
      setHydratedUserId(null)
      setSyncing(false)
      setReady(true)
      return
    }
    setReady(false)
    try {
      const [localRows, pendingBefore] = await Promise.all([
        privateGetAllForUser<ProgressPhoto>('progress_photos', hydrationUserId),
        privateGetAllForUser<PrivateOutboxOp>('private_outbox', hydrationUserId),
      ])
      const local = localRows.map((value) => {
        const photo = normalizedPhoto(value)
        return photo.sync_status === 'syncing' ? { ...photo, sync_status: 'queued' as const } : photo
      })
      if (!current()) return
      setHydratedUserId(hydrationUserId)
      setPhotos(local.sort((a, b) => b.captured_at.localeCompare(a.captured_at)))
      for (const photo of local.slice(0, 24)) void installLocalUrl(photo.id, true)
      if (supabase) {
        setSyncing(true)
        const client = await sessionClientForUser(hydrationUserId)
        if (!client || !current()) return
        const rows = await fetchAllProgressPhotos(client, hydrationUserId)
        const pendingAfter = await privateGetAllForUser<PrivateOutboxOp>('private_outbox', hydrationUserId)
        if (!current()) return
        if (mutationRevision.current !== revision) {
          setHydrationRetry((value) => value + 1)
          return
        }
        const pending = mergeProgressPhotoPendingOperations(
          pendingBefore.filter((operation) => operation.domain === 'photo'),
          pendingAfter.filter((operation) => operation.domain === 'photo'),
        )
        const remote = rows.map((row) => normalizedPhoto({ ...row, sync_status: 'synced' } as ProgressPhoto))
        const values = replayProgressPhotoOutbox(remote, local, pending)
        const committedValues = await replaceProgressPhotoUserCacheAtomically(hydrationUserId, values)
        if (!current()) return
        if (mutationRevision.current !== revision) {
          setHydrationRetry((value) => value + 1)
          return
        }
        setPhotos(committedValues)
      }
    } catch (error) {
      console.warn('Progress photos refresh failed; using private offline cache', error)
    } finally {
      if (current()) {
        setSyncing(false)
        setReady(true)
      }
    }
  }, [hydrationRetry, installLocalUrl, sessionClientForUser, userId])

  useEffect(() => { void hydrate() }, [hydrate])
  useEffect(() => {
    if (!supabase || !userId) return
    let timer: number | null = null
    const refresh = (): void => {
      if (timer !== null) window.clearTimeout(timer)
      timer = window.setTimeout(() => setHydrationRetry((value) => value + 1), 240)
    }
    const channel = supabase
      .channel(`apex-progress-photo-sync-${userId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'progress_photos' }, refresh)
      .subscribe()
    const onVisibility = (): void => {
      if (document.visibilityState === 'visible') refresh()
    }
    document.addEventListener('visibilitychange', onVisibility)
    return () => {
      if (timer !== null) window.clearTimeout(timer)
      document.removeEventListener('visibilitychange', onVisibility)
      void supabase?.removeChannel(channel)
    }
  }, [userId])
  useEffect(() => () => {
    for (const url of objectUrls.current) URL.revokeObjectURL(url)
    objectUrls.current.clear()
  }, [])

  const sendOperation = useCallback(async (
    client: SupabaseClient,
    syncUserId: string,
    operation: PrivateOutboxOp,
  ): Promise<ProgressPhoto | null> => {
    if (operation.user_id !== syncUserId) throw new Error('APEX refused a cross-account photo operation.')
    if (operation.operation === 'upload_photo') {
      const photo = await privateGet<ProgressPhoto>('progress_photos', operation.entity_id)
      const full = await privateGet<StoredPhotoBlob>('photo_blobs', `${operation.entity_id}:full`)
      const thumbnail = await privateGet<StoredPhotoBlob>('photo_blobs', `${operation.entity_id}:thumbnail`)
      if (!photo || !full || !thumbnail || photo.user_id !== syncUserId || full.user_id !== syncUserId || thumbnail.user_id !== syncUserId) {
        throw new Error('Private photo upload is missing an owner-scoped local asset')
      }
      const options = { upsert: true, contentType: full.blob.type || 'image/webp', cacheControl: '31536000' }
      const { error: fullError } = await client.storage.from('apex-progress').upload(photo.storage_path, full.blob, options)
      if (fullError) throw fullError
      const { error: thumbError } = await client.storage.from('apex-progress').upload(photo.thumbnail_path, thumbnail.blob, {
        ...options, contentType: thumbnail.blob.type || 'image/webp',
      })
      if (thumbError) throw thumbError
      let sentPhoto = photo
      let { error: metadataError } = await client.from('progress_photos').upsert(remotePhoto(sentPhoto), { onConflict: 'user_id,client_idempotency_key' })
      if (metadataError?.code === '23503' && sentPhoto.reference_photo_id) {
        // A deleted or never-synced guide image must not poison every later
        // capture through the optional self-reference foreign key.
        sentPhoto = { ...sentPhoto, reference_photo_id: null }
        const retry = await client.from('progress_photos').upsert(remotePhoto(sentPhoto), { onConflict: 'user_id,client_idempotency_key' })
        metadataError = retry.error
      }
      if (metadataError) throw metadataError
      return sentPhoto
    }
    if (operation.operation === 'update_photo') {
      const photo = await privateGet<ProgressPhoto>('progress_photos', operation.entity_id)
      if (!photo) return null
      if (photo.user_id !== syncUserId) throw new Error('APEX refused a cross-account photo update.')
      const { error } = await client.from('progress_photos').upsert(remotePhoto(photo), { onConflict: 'id' })
      if (error) throw error
      return photo
    }
    if (operation.operation === 'delete_photo') {
      const payload = operation.payload as { storage_path?: string; thumbnail_path?: string } | null
      const paths = [payload?.storage_path, payload?.thumbnail_path]
        .filter((path): path is string => typeof path === 'string' && path.startsWith(`${syncUserId}/`))
      if (paths.length) {
        const { error: storageError } = await client.storage.from('apex-progress').remove(paths)
        if (storageError) throw storageError
      }
      const { error } = await client.from('progress_photos').delete().eq('id', operation.entity_id).eq('user_id', syncUserId)
      if (error) throw error
    }
    return null
  }, [])

  const flush = useCallback(async () => {
    if (!userId || !supabase || !navigator.onLine) return
    if (flushing.current) {
      flushRequested.current = true
      return
    }
    flushing.current = true
    const syncUserId = userId
    if (activeUserId.current === syncUserId) setSyncing(true)
    try {
      const client = await sessionClientForUser(syncUserId)
      if (!client) return
      do {
        flushRequested.current = false
        const operations = (await privateGetAllForUser<PrivateOutboxOp>('private_outbox', syncUserId))
          .filter((operation) => operation.domain === 'photo')
          .sort((a, b) => a.created_at.localeCompare(b.created_at))
        const blockedPhotoIds = new Set<string>()
        for (const operation of operations) {
          if (activeUserId.current !== syncUserId || operation.user_id !== syncUserId) break
          if (blockedPhotoIds.has(operation.entity_id)) continue
          if (activeUserId.current === syncUserId) {
            setPhotos((current) => current.map((photo) => photo.id === operation.entity_id
              ? { ...photo, sync_status: 'syncing' }
              : photo))
          }
          try {
            const sentPhoto = await sendOperation(client, syncUserId, operation)
            /* If the user switched while the request was in flight, leave the
               exact operation queued. Its idempotent retry will reconcile the
               captured account the next time it becomes active. */
            if (activeUserId.current !== syncUserId) break
            const acknowledged = await acknowledgePrivateOutboxOperation(operation)
            if (!acknowledged) {
              flushRequested.current = true
              break
            }
            const pending = (await privateGetAllForUser<PrivateOutboxOp>('private_outbox', syncUserId))
              .some((value) => value.domain === 'photo' && value.entity_id === operation.entity_id)
            if (sentPhoto && !pending) {
              const synced = await markProgressPhotoSyncedIfCurrent(
                syncUserId,
                sentPhoto.id,
                sentPhoto.updated_at,
                { reference_photo_id: sentPhoto.reference_photo_id },
              )
              if (synced && activeUserId.current === syncUserId) {
                mutationRevision.current += 1
                setPhotos((current) => current.map((value) => value.id === synced.id ? synced : value))
              }
            }
          } catch (cause) {
            if (activeUserId.current !== syncUserId) break
            blockedPhotoIds.add(operation.entity_id)
            const retained = await recordPrivateOutboxFailure(operation, syncErrorSummary(cause))
            if (retained) {
              mutationRevision.current += 1
              const failed = await privateGet<ProgressPhoto>('progress_photos', operation.entity_id)
              if (failed?.user_id === syncUserId && activeUserId.current === syncUserId) {
                setPhotos((current) => current.map((value) => value.id === failed.id ? failed : value))
              }
            }
            console.warn('Private photo sync remains queued', cause)
          }
        }
      } while (flushRequested.current && navigator.onLine && activeUserId.current === syncUserId)
    } finally {
      flushing.current = false
      if (activeUserId.current === syncUserId) setSyncing(false)
      else queueMicrotask(() => { void latestFlush.current() })
    }
  }, [sendOperation, sessionClientForUser, userId])
  latestFlush.current = flush

  useEffect(() => {
    const retry = () => {
      if (document.visibilityState === 'hidden') return
      void flush()
    }
    window.addEventListener('online', retry)
    document.addEventListener('visibilitychange', retry)
    void flush()
    return () => {
      window.removeEventListener('online', retry)
      document.removeEventListener('visibilitychange', retry)
    }
  }, [flush])

  const savePhoto = useCallback(async (input: SavePhotoInput): Promise<ProgressPhoto> => {
    if (!userId) throw new Error('Sign in before saving a progress photo')
    let processed: ProcessedProgressPhoto
    try {
      processed = input.processed ?? await processProgressPhoto(input.raw)
    } catch (cause) {
      throw progressPhotoSaveError(cause)
    }
    if (activeUserId.current !== userId) throw new Error('The active account changed before this photo was saved. Please retry.')
    mutationRevision.current += 1
    const id = crypto.randomUUID()
    const paths = progressStoragePaths(userId, id)
    const now = nextPhotoTimestamp()
    const photo: ProgressPhoto = {
      id, user_id: userId, local_date: input.localDate ?? todayIso(), captured_at: now,
      pose: input.pose, framing_mode: input.framingMode ?? 'full', storage_path: paths.full, thumbnail_path: paths.thumbnail,
      width: processed.width, height: processed.height, aspect_ratio: processed.aspect_ratio,
      crop_x: 0.5, crop_y: 0.5, crop_scale: 1, reference_photo_id: input.referencePhotoId ?? null,
      weight_kg: input.weightKg ?? null, note: input.note ?? '', client_idempotency_key: progressPhotoIdempotencyKey(input.framingMode ?? 'full'),
      created_at: now, updated_at: now, sync_status: isLocalMode ? 'local' : 'queued',
    }
    const operation = isLocalMode ? null : photoOutbox(userId, 'upload_photo', id)
    try {
      await saveProgressPhotoAtomically(photo, processed.full, processed.thumbnail, operation)
    } catch (cause) {
      throw progressPhotoSaveError(cause)
    }
    if (activeUserId.current === userId) setPhotos((current) => [photo, ...current])
    // The atomic IndexedDB transaction is the save boundary. URL hydration and
    // remote sync are best-effort follow-ups, so a transient server error can
    // never make the review UI create a duplicate photo on retry.
    await Promise.allSettled([installLocalUrl(id, false), installLocalUrl(id, true)])
    if (!isLocalMode && navigator.onLine) void flush()
    if (activeUserId.current === userId) toast('Progress photo saved privately', 'ok')
    return photo
  }, [flush, installLocalUrl, toast, userId])

  const updatePhoto = useCallback(async (
    photoId: string,
    patch: Partial<Pick<ProgressPhoto, 'note' | 'weight_kg' | 'crop_x' | 'crop_y' | 'crop_scale'>>,
  ) => {
    if (!userId) return
    const current = photos.find((photo) => photo.id === photoId)
    if (!current || current.user_id !== userId || activeUserId.current !== userId) return
    mutationRevision.current += 1
    const next: ProgressPhoto = { ...current, ...patch, updated_at: nextPhotoTimestamp(), sync_status: isLocalMode ? 'local' : 'queued' }
    await updateProgressPhotoAtomically(next, isLocalMode ? null : photoOutbox(userId, 'update_photo', photoId))
    if (activeUserId.current === userId) setPhotos((values) => values.map((photo) => photo.id === photoId ? next : photo))
    if (!isLocalMode && navigator.onLine) void flush()
  }, [flush, photos, userId])

  const setCrop = useCallback(async (photoId: string, crop: NormalizedCrop) => {
    await updatePhoto(photoId, { crop_x: crop.x, crop_y: crop.y, crop_scale: crop.scale })
  }, [updatePhoto])

  const deletePhoto = useCallback(async (photoId: string) => {
    if (!userId) return
    const current = photos.find((photo) => photo.id === photoId)
    if (!current || current.user_id !== userId || activeUserId.current !== userId) return
    mutationRevision.current += 1
    const operation = photoOutbox(userId, 'delete_photo', photoId)
    operation.payload = { storage_path: current.storage_path, thumbnail_path: current.thumbnail_path }
    await deleteProgressPhotoLocally(photoId, userId, isLocalMode ? null : operation)
    if (activeUserId.current === userId) {
      setPhotos((values) => values.filter((photo) => photo.id !== photoId))
      setFullUrls((values) => { const next = { ...values }; delete next[photoId]; return next })
      setThumbnailUrls((values) => { const next = { ...values }; delete next[photoId]; return next })
    }
    if (!isLocalMode && navigator.onLine) void flush()
    if (activeUserId.current === userId) toast('Progress photo deleted', 'ok')
  }, [flush, photos, toast, userId])

  const value = useMemo<PhotoStoreValue>(() => {
    /* React can render once with the previous provider state before the new
       owner's hydration effect runs. Never expose metadata or signed/blob
       URLs unless the state was explicitly loaded for the active owner. */
    const ownerMatches = hydratedUserId === userId
    const visiblePhotos = ownerMatches && userId
      ? photos.filter((photo) => photo.user_id === userId)
      : []
    const visibleIds = new Set(visiblePhotos.map((photo) => photo.id))
    const visibleFullUrls = Object.fromEntries(Object.entries(fullUrls).filter(([id]) => visibleIds.has(id)))
    const visibleThumbnailUrls = Object.fromEntries(Object.entries(thumbnailUrls).filter(([id]) => visibleIds.has(id)))
    return {
      ready: ready && ownerMatches,
      syncing: ownerMatches && syncing,
      photos: visiblePhotos,
      fullUrls: visibleFullUrls,
      thumbnailUrls: visibleThumbnailUrls,
      savePhoto,
      deletePhoto,
      updatePhoto,
      setCrop,
      ensurePhotoUrl,
      retrySync: flush,
    }
  }, [deletePhoto, ensurePhotoUrl, flush, fullUrls, hydratedUserId, photos, ready, savePhoto, setCrop, syncing, thumbnailUrls, updatePhoto, userId])

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useProgressPhotoStore(): PhotoStoreValue {
  const value = useContext(Ctx)
  if (!value) throw new Error('useProgressPhotoStore outside ProgressPhotoStoreProvider')
  return value
}
