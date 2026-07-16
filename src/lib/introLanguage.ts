export type IntroLanguage = 'en' | 'th' | 'ro'
export type SelectableIntroLanguage = IntroLanguage

const LANGUAGE_KEY = 'apex.intro-language.v1'
export const LANGUAGE_CHANGE_EVENT = 'apex-language-change'

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
  { value: 'en', short: 'EN', nativeName: 'English', englishName: 'English', glyph: 'A' },
  { value: 'th', short: 'TH', nativeName: 'ไทย', englishName: 'Thai', glyph: 'ก' },
  { value: 'ro', short: 'RO', nativeName: 'Română', englishName: 'Romanian', glyph: 'R' },
]

export function isSelectableIntroLanguage(value: unknown): value is SelectableIntroLanguage {
  return value === 'en' || value === 'th' || value === 'ro'
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
  try {
    document.documentElement.lang = language
    window.dispatchEvent(new CustomEvent(LANGUAGE_CHANGE_EVENT, { detail: language }))
  } catch {
    /* document and window are unavailable during non-browser tests. */
  }
}

export const INTRO_COPY = {
  en: {
    network: 'Private performance network',
    secure: 'Secure',
    neutralEyebrow: 'Private performance, one account',
    neutralTitle: 'Your system, privately yours.',
    neutralBody: 'Sign in first. APEX reveals only the identity attached to the authenticated account.',
    enter: 'Enter APEX',
    browse: 'Browse profiles',
    browseBack: 'Back to secure entry',
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
    neutralEyebrow: 'Performanță privată, un singur cont',
    neutralTitle: 'Sistemul tău, doar al tău.',
    neutralBody: 'Autentifică-te mai întâi. APEX dezvăluie doar identitatea asociată contului autentificat.',
    enter: 'Intră în APEX',
    browse: 'Vezi profilurile',
    browseBack: 'Înapoi la accesul securizat',
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
    neutralEyebrow: 'ประสิทธิภาพส่วนตัว หนึ่งบัญชี',
    neutralTitle: 'ระบบของคุณ เป็นส่วนตัวสำหรับคุณ',
    neutralBody: 'เข้าสู่ระบบก่อน APEX จะแสดงเฉพาะตัวตนที่เชื่อมกับบัญชีซึ่งยืนยันแล้วเท่านั้น',
    enter: 'เข้าสู่ APEX',
    browse: 'ดูโปรไฟล์',
    browseBack: 'กลับไปยังการเข้าสู่ระบบที่ปลอดภัย',
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
    encrypted: 'Encrypted session', access: 'Private access', title: 'Enter your private system', welcome: (name: string) => `Welcome, ${name}`,
    authenticate: 'Your identity appears only after successful authentication.', email: 'Email address', password: 'Password',
    passwordPlaceholder: 'Enter your password', hide: 'Hide', show: 'Show', verifying: 'Verifying identity…',
    unlock: 'Enter APEX', back: '← Back', private: 'Private', verified: 'Identity verified', ready: 'Your private system is ready.',
    credentials: 'Credentials are sent directly to the authentication service and are never stored in this app.',
  },
  ro: {
    encrypted: 'Sesiune criptată', access: 'Acces privat', title: 'Intră în sistemul tău privat', welcome: (name: string) => `Bine ai venit, ${name}`,
    authenticate: 'Identitatea ta apare doar după autentificarea reușită.', email: 'Adresă de e-mail', password: 'Parolă',
    passwordPlaceholder: 'Introdu parola', hide: 'Ascunde', show: 'Arată', verifying: 'Se verifică identitatea…',
    unlock: 'Intră în APEX', back: '← Înapoi', private: 'Privat', verified: 'Identitate confirmată', ready: 'Sistemul tău privat este pregătit.',
    credentials: 'Datele de autentificare sunt trimise direct serviciului securizat și nu sunt stocate niciodată în aplicație.',
  },
  th: {
    encrypted: 'เซสชันเข้ารหัส', access: 'การเข้าถึงส่วนตัว', title: 'เข้าสู่ระบบส่วนตัวของคุณ', welcome: (name: string) => `ยินดีต้อนรับ ${name}`,
    authenticate: 'ตัวตนของคุณจะแสดงหลังจากยืนยันสำเร็จเท่านั้น', email: 'อีเมล', password: 'รหัสผ่าน',
    passwordPlaceholder: 'ป้อนรหัสผ่าน', hide: 'ซ่อน', show: 'แสดง', verifying: 'กำลังตรวจสอบตัวตน…',
    unlock: 'เข้าสู่ APEX', back: '← กลับ', private: 'ส่วนตัว', verified: 'ยืนยันตัวตนแล้ว', ready: 'ระบบส่วนตัวของคุณพร้อมแล้ว',
    credentials: 'ข้อมูลเข้าสู่ระบบจะถูกส่งตรงไปยังบริการยืนยันตัวตนและจะไม่ถูกจัดเก็บในแอป',
  },
} as const

export function localizedLoginError(message: string, language: IntroLanguage): string {
  const normalized = message.trim().toLocaleLowerCase('en')
  const profileMismatch = /^Those credentials belong to .+\. Choose that profile to continue\.$/.test(message)
  const invalidCredentials = (): string => {
    if (language === 'ro') return 'Adresa de e-mail sau parola sunt incorecte.'
    if (language === 'th') return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง'
    return 'The email address or password is incorrect.'
  }

  if (profileMismatch || normalized.includes('invalid login credentials') || normalized.includes('invalid email or password') || normalized.includes('email not confirmed')) return invalidCredentials()
  if (normalized.includes('too many requests') || normalized.includes('rate limit')) {
    if (language === 'ro') return 'Prea multe încercări. Așteaptă puțin, apoi încearcă din nou.'
    if (language === 'th') return 'มีการลองเข้าสู่ระบบมากเกินไป โปรดรอสักครู่แล้วลองอีกครั้ง'
    return 'Too many attempts. Wait a moment, then try again.'
  }
  if (normalized.includes('failed to fetch') || normalized.includes('network')) {
    if (language === 'ro') return 'Conexiunea nu este disponibilă. Verifică internetul și încearcă din nou.'
    if (language === 'th') return 'ไม่สามารถเชื่อมต่อได้ โปรดตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง'
    return 'The connection is unavailable. Check your internet and try again.'
  }

  if (language === 'ro') return 'Autentificarea nu a reușit. Verifică datele și încearcă din nou.'
  if (language === 'th') return 'เข้าสู่ระบบไม่สำเร็จ โปรดตรวจสอบข้อมูลแล้วลองอีกครั้ง'
  return 'Sign-in failed. Check your details and try again.'
}
