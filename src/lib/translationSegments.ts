function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

export function replaceInterfaceSegment(value: string, source: string, replacement: string): string {
  const escaped = escapeRegExp(source)
  const startsWithWord = /^[\p{L}\p{N}_]/u.test(source)
  const endsWithWord = /[\p{L}\p{N}_]$/u.test(source)
  const pattern = `${startsWithWord ? '(?<![\\p{L}\\p{N}_])' : ''}${escaped}${endsWithWord ? '(?![\\p{L}\\p{N}_])' : ''}`
  return value.replace(new RegExp(pattern, 'gu'), replacement)
}
