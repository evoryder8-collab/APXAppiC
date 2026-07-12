import type { IntroLanguage } from './introLanguage.ts'
import { UI_TRANSLATIONS } from './translations.ts'

type LocalizedLanguage = Exclude<IntroLanguage, 'en'>

function exact(value: string, language: LocalizedLanguage): string {
  return UI_TRANSLATIONS[value]?.[language] ?? value
}

function translateAssessmentTrend(value: string, language: LocalizedLanguage): string {
  const rising = value.match(/^Your Overall score has risen ([\d.]+) points over the comparison window, so the current direction is productive\.$/)
  if (rising) return language === 'ro'
    ? `Scorul general a crescut cu ${rising[1]} puncte în perioada comparată, deci direcția actuală este bună.`
    : `คะแนนรวมเพิ่มขึ้น ${rising[1]} จุดในช่วงที่เปรียบเทียบ แสดงว่าทิศทางปัจจุบันกำลังได้ผล`

  const falling = value.match(/^Your Overall score has fallen ([\d.]+) points over the comparison window, which points to an underfed training or recovery input\.$/)
  if (falling) return language === 'ro'
    ? `Scorul general a scăzut cu ${falling[1]} puncte în perioada comparată, ceea ce indică alimentație sau recuperare insuficientă.`
    : `คะแนนรวมลดลง ${falling[1]} จุดในช่วงที่เปรียบเทียบ ซึ่งชี้ว่าอาหารหรือการฟื้นตัวยังไม่พอ`

  return exact(value, language)
}

export function translateAvatarAssessmentSummary(value: string, language: IntroLanguage): string | null {
  if (language === 'en') return value

  const limiter = value.match(/^(.+) is the clearest limiter at ([\d.]+), while (.+) currently leads at ([\d.]+)\. (.+)$/)
  if (limiter) {
    const weak = exact(limiter[1], language)
    const strong = exact(limiter[3], language)
    const trend = translateAssessmentTrend(limiter[5], language)
    return language === 'ro'
      ? `${weak} este limita principală la ${limiter[2]}, iar ${strong} conduce la ${limiter[4]}. ${trend}`
      : `${weak} เป็นข้อจำกัดหลักที่ ${limiter[2]} ส่วน ${strong} นำที่ ${limiter[4]} ${trend}`
  }

  const balanced = value.match(/^(The profile is relatively balanced, with no single quality dramatically behind the rest\.) (.+)$/)
  if (balanced) return `${exact(balanced[1], language)} ${translateAssessmentTrend(balanced[2], language)}`

  return null
}
