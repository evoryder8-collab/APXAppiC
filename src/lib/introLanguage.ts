export type IntroLanguage = 'en' | 'th' | 'ro'
export type SelectableIntroLanguage = Exclude<IntroLanguage, 'en'>

const LANGUAGE_KEY = 'apex.intro-language.v1'

export const LANGUAGE_PROMPTS = [
  'Choose your language',
  'Alege limba',
  'เลือกภาษาของคุณ',
] as const

export const LANGUAGE_OPTIONS: Array<{
  value: SelectableIntroLanguage
  short: string
  nativeName: string
  englishName: string
  glyph: string
}> = [
  { value: 'th', short: 'TH', nativeName: 'ไทย', englishName: 'Thai', glyph: 'ก' },
  { value: 'ro', short: 'RO', nativeName: 'Română', englishName: 'Romanian', glyph: 'R' },
]

export function isSelectableIntroLanguage(value: unknown): value is SelectableIntroLanguage {
  return value === 'th' || value === 'ro'
}

export function getIntroLanguage(): IntroLanguage {
  try {
    const saved = localStorage.getItem(LANGUAGE_KEY)
    if (isSelectableIntroLanguage(saved)) return saved
  } catch {
    /* Private browsing can reject storage. The English entry copy remains safe. */
  }

  try {
    const browserLanguage = navigator.language.toLowerCase()
    if (browserLanguage.startsWith('th')) return 'th'
    if (browserLanguage.startsWith('ro')) return 'ro'
  } catch {
    /* navigator is unavailable during non-browser tests. */
  }

  return 'en'
}

export function setIntroLanguage(language: SelectableIntroLanguage): void {
  try {
    localStorage.setItem(LANGUAGE_KEY, language)
  } catch {
    /* The current session still updates even when persistence is unavailable. */
  }
}

export const INTRO_COPY = {
  en: {
    network: 'Private performance network',
    secure: 'Secure',
    protocol: 'Identity protocol',
    chooseSystem: 'Choose your system',
    selectorLabel: 'Swipe left or right to choose a person',
    previous: 'Previous person',
    next: 'Next person',
    people: 'People',
    bringForward: (name: string) => `Bring ${name} forward`,
    continueAs: (name: string) => `Continue as ${name}`,
    preview: (name: string) => `${name} preview`,
    swipeHint: 'Swipe to orbit · tap centre to enter',
    identitySelected: 'Identity selected',
    enterAs: (name: string) => `Enter as ${name}?`,
    privacy: 'Your private data and progress remain isolated from every other profile.',
    confirm: 'Confirm identity',
    explore: 'Keep exploring',
  },
  ro: {
    network: 'Rețea privată de performanță',
    secure: 'Securizat',
    protocol: 'Protocol de identitate',
    chooseSystem: 'Alege sistemul tău',
    selectorLabel: 'Glisează la stânga sau la dreapta pentru a alege o persoană',
    previous: 'Persoana anterioară',
    next: 'Persoana următoare',
    people: 'Persoane',
    bringForward: (name: string) => `Adu-l pe ${name} în față`,
    continueAs: (name: string) => `Continuă ca ${name}`,
    preview: (name: string) => `Previzualizare ${name}`,
    swipeHint: 'Glisează pentru orbită · atinge centrul pentru acces',
    identitySelected: 'Identitate selectată',
    enterAs: (name: string) => `Intri ca ${name}?`,
    privacy: 'Datele și progresul tău rămân izolate de toate celelalte profiluri.',
    confirm: 'Confirmă identitatea',
    explore: 'Continuă explorarea',
  },
  th: {
    network: 'เครือข่ายสมรรถนะส่วนตัว',
    secure: 'ปลอดภัย',
    protocol: 'ระบบยืนยันตัวตน',
    chooseSystem: 'เลือกระบบของคุณ',
    selectorLabel: 'ปัดซ้ายหรือขวาเพื่อเลือกผู้ใช้',
    previous: 'ผู้ใช้ก่อนหน้า',
    next: 'ผู้ใช้ถัดไป',
    people: 'ผู้ใช้',
    bringForward: (name: string) => `นำ ${name} มาด้านหน้า`,
    continueAs: (name: string) => `เข้าสู่ระบบในชื่อ ${name}`,
    preview: (name: string) => `ดูตัวอย่าง ${name}`,
    swipeHint: 'ปัดเพื่อหมุน · แตะตรงกลางเพื่อเข้าสู่ระบบ',
    identitySelected: 'เลือกตัวตนแล้ว',
    enterAs: (name: string) => `เข้าสู่ระบบในชื่อ ${name}?`,
    privacy: 'ข้อมูลส่วนตัวและความก้าวหน้าของคุณจะแยกจากโปรไฟล์อื่นอย่างสมบูรณ์',
    confirm: 'ยืนยันตัวตน',
    explore: 'เลือกดูต่อ',
  },
} as const

export const LOGIN_COPY = {
  en: {
    encrypted: 'Encrypted session', welcome: (name: string) => `Welcome, ${name}`,
    authenticate: 'Authenticate your private system', email: 'Email address', password: 'Password',
    passwordPlaceholder: 'Enter your password', hide: 'Hide', show: 'Show', verifying: 'Verifying identity…',
    unlock: (name: string) => `Unlock ${name}'s APEX`, back: '← Choose another person', private: 'Private',
    credentials: 'Credentials are sent directly to the authentication service and are never stored in this app.',
  },
  ro: {
    encrypted: 'Sesiune criptată', welcome: (name: string) => `Bine ai venit, ${name}`,
    authenticate: 'Autentifică-te în sistemul tău privat', email: 'Adresă de e-mail', password: 'Parolă',
    passwordPlaceholder: 'Introdu parola', hide: 'Ascunde', show: 'Arată', verifying: 'Se verifică identitatea…',
    unlock: (name: string) => `Deblochează APEX pentru ${name}`, back: '← Alege altă persoană', private: 'Privat',
    credentials: 'Datele de autentificare sunt trimise direct serviciului securizat și nu sunt stocate niciodată în aplicație.',
  },
  th: {
    encrypted: 'เซสชันเข้ารหัส', welcome: (name: string) => `ยินดีต้อนรับ ${name}`,
    authenticate: 'ยืนยันเพื่อเข้าสู่ระบบส่วนตัวของคุณ', email: 'อีเมล', password: 'รหัสผ่าน',
    passwordPlaceholder: 'ป้อนรหัสผ่าน', hide: 'ซ่อน', show: 'แสดง', verifying: 'กำลังตรวจสอบตัวตน…',
    unlock: (name: string) => `เปิด APEX ของ ${name}`, back: '← เลือกผู้ใช้คนอื่น', private: 'ส่วนตัว',
    credentials: 'ข้อมูลเข้าสู่ระบบจะถูกส่งตรงไปยังบริการยืนยันตัวตนและจะไม่ถูกจัดเก็บในแอป',
  },
} as const
