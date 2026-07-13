function hash32(value: string, seed: number): number {
  let hash = seed >>> 0
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index)
    hash = Math.imul(hash, 16777619)
  }
  hash ^= hash >>> 16
  hash = Math.imul(hash, 0x7feb352d)
  hash ^= hash >>> 15
  return hash >>> 0
}

export function orbitUuid(userId: string, key: string): string {
  const input = `apex-orbit:${userId}:${key}`
  const raw = [
    hash32(input, 0x811c9dc5), hash32(input, 0x9e3779b9),
    hash32(input, 0x85ebca6b), hash32(input, 0xc2b2ae35),
  ].map((part) => part.toString(16).padStart(8, '0')).join('')
  const variant = ((parseInt(raw[16], 16) & 0x3) | 0x8).toString(16)
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-4${raw.slice(13, 16)}-${variant}${raw.slice(17, 20)}-${raw.slice(20, 32)}`
}
