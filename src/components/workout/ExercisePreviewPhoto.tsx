import { previewPhotoID } from '../../lib/guidedPreviewPhoto'

// Reuse the lightweight transparent frames shipped to the guided player.
const files = import.meta.glob<string>([
  '../../../ios/APEXNative/APEX/Resources/GuidedArtwork/*.webp',
  '!../../../ios/APEXNative/APEX/Resources/GuidedArtwork/*-2.webp',
], { eager: true, import: 'default', query: '?url&no-inline' })
const photos = new Map(Object.entries(files).map(([path, url]) => [path.split('/').pop()!.replace(/(?:-1)?\.webp$/, ''), url]))

export function ExercisePreviewPhoto({ exercise, className }: { exercise: { name: string; movement_id?: string | null }; className: string }) {
  const id = previewPhotoID(exercise)
  const src = id && photos.get(id)
  return src ? <img src={src} alt="" loading="lazy" decoding="async" className={className + ' object-contain'} /> : null
}
