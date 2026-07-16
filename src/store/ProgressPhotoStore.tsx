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
  runProgressPhotoSyncBatch,
  type NormalizedCrop,
  type ProcessedProgressPhoto,
  type ProgressPhoto,
  type ProgressFramingMode,
  type ProgressPose,
} from '../lib/progressPhoto'
import {
  deleteProgressPhotoLocally,
  privateDelete,
  privateGet,
  privateGetAllForUser,
  privatePut,
  saveProgressPhotoAtomically,
  type PrivateOutboxOp,
  type StoredPhotoBlob,
} from '../lib/privateDb'
import { isLocalMode, supabase } from '../lib/supabase'
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

function photoOutbox(userId: string, operation: 'upload_photo' | 'delete_photo' | 'update_photo', photoId: string): PrivateOutboxOp {
  return {
    id: `photo:${operation}:${photoId}`, user_id: userId, domain: 'photo', operation,
    entity_id: photoId, payload: null, created_at: new Date().toISOString(), attempts: 0,
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
  const [syncing, setSyncing] = useState(false)
  const [photos, setPhotos] = useState<ProgressPhoto[]>([])
  const [fullUrls, setFullUrls] = useState<Record<string, string>>({})
  const [thumbnailUrls, setThumbnailUrls] = useState<Record<string, string>>({})
  const flushing = useRef(false)
  const flushRequested = useRef(false)
  const activeUserId = useRef(userId)
  const latestFlush = useRef<() => Promise<void>>(async () => undefined)
  const objectUrls = useRef(new Set<string>())
  activeUserId.current = userId

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
    const path = thumbnail ? photo.thumbnail_path : photo.storage_path
    const { data: signed, error } = await supabase.storage.from('apex-progress').createSignedUrl(path, 3600)
    if (error || !signed?.signedUrl || photo.user_id !== activeUserId.current) return null
    if (thumbnail) setThumbnailUrls((values) => ({ ...values, [photo.id]: signed.signedUrl }))
    else setFullUrls((values) => ({ ...values, [photo.id]: signed.signedUrl }))
    return signed.signedUrl
  }, [fullUrls, installLocalUrl, thumbnailUrls])

  const hydrate = useCallback(async () => {
    flushRequested.current = false
    for (const url of objectUrls.current) URL.revokeObjectURL(url)
    objectUrls.current.clear()
    setFullUrls({})
    setThumbnailUrls({})
    if (!userId) {
      setPhotos([])
      setSyncing(false)
      setReady(true)
      return
    }
    const hydrationUserId = userId
    setReady(false)
    try {
      const local = (await privateGetAllForUser<ProgressPhoto>('progress_photos', userId)).map((value) => {
        const photo = normalizedPhoto(value)
        return photo.sync_status === 'syncing' ? { ...photo, sync_status: 'queued' as const } : photo
      })
      if (activeUserId.current !== hydrationUserId) return
      setPhotos(local.sort((a, b) => b.captured_at.localeCompare(a.captured_at)))
      for (const photo of local.slice(0, 24)) void installLocalUrl(photo.id, true)
      if (supabase) {
        setSyncing(true)
        const { data: rows, error } = await supabase.from('progress_photos').select('*').eq('user_id', userId).order('captured_at', { ascending: false })
        if (error) throw error
        if (activeUserId.current !== hydrationUserId) return
        const remote = (rows ?? []).map((row) => normalizedPhoto({ ...row, sync_status: 'synced' } as ProgressPhoto))
        const merged = new Map(remote.map((photo) => [photo.id, photo]))
        for (const photo of local) if (photo.sync_status !== 'synced') merged.set(photo.id, photo)
        const values = [...merged.values()].sort((a, b) => b.captured_at.localeCompare(a.captured_at))
        setPhotos(values)
        for (const photo of remote) await privatePut('progress_photos', photo)
      }
    } catch (error) {
      console.warn('Progress photos refresh failed; using private offline cache', error)
    } finally {
      if (activeUserId.current === hydrationUserId) {
        setSyncing(false)
        setReady(true)
      }
    }
  }, [installLocalUrl, userId])

  useEffect(() => { void hydrate() }, [hydrate])
  useEffect(() => () => {
    for (const url of objectUrls.current) URL.revokeObjectURL(url)
    objectUrls.current.clear()
  }, [])

  const sendOperation = useCallback(async (operation: PrivateOutboxOp): Promise<void> => {
    if (!supabase || !userId) return
    if (operation.operation === 'upload_photo') {
      const photo = await privateGet<ProgressPhoto>('progress_photos', operation.entity_id)
      const full = await privateGet<StoredPhotoBlob>('photo_blobs', `${operation.entity_id}:full`)
      const thumbnail = await privateGet<StoredPhotoBlob>('photo_blobs', `${operation.entity_id}:thumbnail`)
      if (!photo || !full || !thumbnail) throw new Error('Private photo upload is missing a local asset')
      const options = { upsert: true, contentType: full.blob.type || 'image/webp', cacheControl: '31536000' }
      const { error: fullError } = await supabase.storage.from('apex-progress').upload(photo.storage_path, full.blob, options)
      if (fullError) throw fullError
      const { error: thumbError } = await supabase.storage.from('apex-progress').upload(photo.thumbnail_path, thumbnail.blob, {
        ...options, contentType: thumbnail.blob.type || 'image/webp',
      })
      if (thumbError) throw thumbError
      let synced: ProgressPhoto = { ...photo, sync_status: 'synced', updated_at: new Date().toISOString() }
      let { error: metadataError } = await supabase.from('progress_photos').upsert(remotePhoto(synced), { onConflict: 'user_id,client_idempotency_key' })
      if (metadataError?.code === '23503' && synced.reference_photo_id) {
        // A deleted or never-synced guide image must not poison every later
        // capture through the optional self-reference foreign key.
        synced = { ...synced, reference_photo_id: null }
        const retry = await supabase.from('progress_photos').upsert(remotePhoto(synced), { onConflict: 'user_id,client_idempotency_key' })
        metadataError = retry.error
      }
      if (metadataError) throw metadataError
      await privatePut('progress_photos', synced)
      if (activeUserId.current === userId) setPhotos((current) => current.map((value) => value.id === synced.id ? synced : value))
      return
    }
    if (operation.operation === 'update_photo') {
      const photo = await privateGet<ProgressPhoto>('progress_photos', operation.entity_id)
      if (!photo) return
      const { error } = await supabase.from('progress_photos').upsert(remotePhoto(photo), { onConflict: 'id' })
      if (error) throw error
      const synced: ProgressPhoto = { ...photo, sync_status: 'synced' }
      await privatePut('progress_photos', synced)
      if (activeUserId.current === userId) setPhotos((current) => current.map((value) => value.id === synced.id ? synced : value))
      return
    }
    if (operation.operation === 'delete_photo') {
      const payload = operation.payload as { storage_path?: string; thumbnail_path?: string } | null
      const paths = [payload?.storage_path, payload?.thumbnail_path].filter(Boolean) as string[]
      if (paths.length) {
        const { error: storageError } = await supabase.storage.from('apex-progress').remove(paths)
        if (storageError) throw storageError
      }
      const { error } = await supabase.from('progress_photos').delete().eq('id', operation.entity_id).eq('user_id', userId)
      if (error) throw error
    }
  }, [userId])

  const flush = useCallback(async () => {
    if (!userId || !supabase || !navigator.onLine) return
    if (flushing.current) {
      flushRequested.current = true
      return
    }
    flushing.current = true
    if (activeUserId.current === userId) setSyncing(true)
    try {
      do {
        flushRequested.current = false
        const operations = (await privateGetAllForUser<PrivateOutboxOp>('private_outbox', userId))
          .filter((operation) => operation.domain === 'photo')
          .sort((a, b) => a.created_at.localeCompare(b.created_at))
        const result = await runProgressPhotoSyncBatch(operations, async (operation) => {
          if (activeUserId.current === userId) {
            setPhotos((current) => current.map((photo) => photo.id === operation.entity_id
              ? { ...photo, sync_status: 'syncing' }
              : photo))
          }
          await sendOperation(operation)
        })
        for (const operation of result.succeeded) await privateDelete('private_outbox', operation.id)
        for (const { operation, cause } of result.failed) {
          await privatePut('private_outbox', {
            ...operation,
            attempts: operation.attempts + 1,
            last_attempt_at: new Date().toISOString(),
            last_error: syncErrorSummary(cause),
          })
          const photo = await privateGet<ProgressPhoto>('progress_photos', operation.entity_id)
          if (photo) {
            const failed: ProgressPhoto = { ...photo, sync_status: 'failed' }
            await privatePut('progress_photos', failed)
            if (activeUserId.current === userId) {
              setPhotos((current) => current.map((value) => value.id === failed.id ? failed : value))
            }
          }
          console.warn('Private photo sync remains queued', cause)
        }
      } while (flushRequested.current && navigator.onLine && activeUserId.current === userId)
    } finally {
      flushing.current = false
      if (activeUserId.current === userId) setSyncing(false)
      else queueMicrotask(() => { void latestFlush.current() })
    }
  }, [sendOperation, userId])
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
    const id = crypto.randomUUID()
    const paths = progressStoragePaths(userId, id)
    const now = new Date().toISOString()
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
    setPhotos((current) => [photo, ...current])
    // The atomic IndexedDB transaction is the save boundary. URL hydration and
    // remote sync are best-effort follow-ups, so a transient server error can
    // never make the review UI create a duplicate photo on retry.
    await Promise.allSettled([installLocalUrl(id, false), installLocalUrl(id, true)])
    if (!isLocalMode && navigator.onLine) void flush()
    toast('Progress photo saved privately', 'ok')
    return photo
  }, [flush, installLocalUrl, toast, userId])

  const updatePhoto = useCallback(async (
    photoId: string,
    patch: Partial<Pick<ProgressPhoto, 'note' | 'weight_kg' | 'crop_x' | 'crop_y' | 'crop_scale'>>,
  ) => {
    if (!userId) return
    const current = photos.find((photo) => photo.id === photoId)
    if (!current) return
    const next: ProgressPhoto = { ...current, ...patch, updated_at: new Date().toISOString(), sync_status: isLocalMode ? 'local' : 'queued' }
    await privatePut('progress_photos', next)
    if (!isLocalMode) {
      const pending = await privateGetAllForUser<PrivateOutboxOp>('private_outbox', userId)
      for (const operation of pending) {
        if (operation.domain === 'photo' && operation.entity_id === photoId && operation.operation === 'update_photo') {
          await privateDelete('private_outbox', operation.id)
        }
      }
      await privatePut('private_outbox', photoOutbox(userId, 'update_photo', photoId))
    }
    setPhotos((values) => values.map((photo) => photo.id === photoId ? next : photo))
    if (!isLocalMode && navigator.onLine) void flush()
  }, [flush, photos, userId])

  const setCrop = useCallback(async (photoId: string, crop: NormalizedCrop) => {
    await updatePhoto(photoId, { crop_x: crop.x, crop_y: crop.y, crop_scale: crop.scale })
  }, [updatePhoto])

  const deletePhoto = useCallback(async (photoId: string) => {
    if (!userId) return
    const current = photos.find((photo) => photo.id === photoId)
    if (!current) return
    const pending = await privateGetAllForUser<PrivateOutboxOp>('private_outbox', userId)
    for (const operation of pending) {
      if (operation.domain === 'photo' && operation.entity_id === photoId) {
        await privateDelete('private_outbox', operation.id)
      }
    }
    const operation = photoOutbox(userId, 'delete_photo', photoId)
    operation.payload = { storage_path: current.storage_path, thumbnail_path: current.thumbnail_path }
    if (!isLocalMode) await privatePut('private_outbox', operation)
    await deleteProgressPhotoLocally(photoId)
    setPhotos((values) => values.filter((photo) => photo.id !== photoId))
    if (!isLocalMode && navigator.onLine) void flush()
    toast('Progress photo deleted', 'ok')
  }, [flush, photos, toast, userId])

  const value = useMemo<PhotoStoreValue>(() => ({
    ready, syncing, photos, fullUrls, thumbnailUrls, savePhoto, deletePhoto, updatePhoto, setCrop, ensurePhotoUrl, retrySync: flush,
  }), [deletePhoto, ensurePhotoUrl, flush, fullUrls, photos, ready, savePhoto, setCrop, syncing, thumbnailUrls, updatePhoto])

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useProgressPhotoStore(): PhotoStoreValue {
  const value = useContext(Ctx)
  if (!value) throw new Error('useProgressPhotoStore outside ProgressPhotoStoreProvider')
  return value
}
