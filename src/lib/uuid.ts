const nativeRandomUuid =
  typeof globalThis.crypto?.randomUUID === 'function'
    ? globalThis.crypto.randomUUID.bind(globalThis.crypto)
    : null

type RandomValues = (bytes: Uint8Array) => Uint8Array

function fillFallbackBytes(bytes: Uint8Array) {
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Math.floor(Math.random() * 256)
  }
  return bytes
}

export function createUuidV4(randomValues?: RandomValues) {
  const bytes = new Uint8Array(16)
  const secureRandomValues = randomValues
    ?? (typeof globalThis.crypto?.getRandomValues === 'function'
      ? globalThis.crypto.getRandomValues.bind(globalThis.crypto) as RandomValues
      : fillFallbackBytes)

  secureRandomValues(bytes)
  bytes[6] = (bytes[6] & 0x0f) | 0x40
  bytes[8] = (bytes[8] & 0x3f) | 0x80

  const hex = Array.from(bytes, (value) => value.toString(16).padStart(2, '0'))
  return `${hex.slice(0, 4).join('')}-${hex.slice(4, 6).join('')}-${hex.slice(6, 8).join('')}-${hex.slice(8, 10).join('')}-${hex.slice(10).join('')}`
}

export function randomUuid() {
  return nativeRandomUuid?.() ?? createUuidV4()
}

export function installRandomUuidFallback() {
  if (typeof globalThis.crypto === 'undefined' || typeof globalThis.crypto.randomUUID === 'function') {
    return false
  }

  try {
    Object.defineProperty(globalThis.crypto, 'randomUUID', {
      configurable: true,
      value: randomUuid as Crypto['randomUUID'],
    })
  } catch {
    return false
  }

  return typeof globalThis.crypto.randomUUID === 'function'
}
