function normalizedIdentity(value: string): string {
  return value
    .normalize('NFKD')
    .replace(/\p{M}/gu, '')
    .trim()
    .toLocaleLowerCase('en')
}

export function showsPersonaLabel(displayName: string, personaName: string): boolean {
  return normalizedIdentity(displayName) !== normalizedIdentity(personaName)
}
