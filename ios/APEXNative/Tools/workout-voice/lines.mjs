// Every line the guided-workout voice speaks, written for speech in each language, with
// Eleven v4 acting tags. The app plays these clips; exercise names are voiced on demand.
// Source of truth for Tools/workout-voice/generate.mjs and the app's clip manifest.

export const voiceLanguages = ['en', 'de', 'de-CH', 'it', 'es', 'pt', 'ja', 'ro', 'th']

// Eleven v4 has no Swiss or European Portuguese code; the voice chosen for each carries the accent.
export const elevenLanguageCode = { en: 'en', de: 'de', 'de-CH': 'de', it: 'it', es: 'es', pt: 'pt', ja: 'ja', ro: 'ro', th: 'th' }

export const maxCount = 30
export const maxSets = 10
export const groupLetters = ['A', 'B', 'C', 'D', 'E', 'F']
export const maxGroupPosition = 4
export const setNouns = ['set', 'hold', 'round', 'exercise']

const numbers = {
  en: ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen',
    'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'twenty-one', 'twenty-two',
    'twenty-three', 'twenty-four', 'twenty-five', 'twenty-six', 'twenty-seven', 'twenty-eight', 'twenty-nine', 'thirty'],
  de: ['eins', 'zwei', 'drei', 'vier', 'fünf', 'sechs', 'sieben', 'acht', 'neun', 'zehn', 'elf', 'zwölf', 'dreizehn',
    'vierzehn', 'fünfzehn', 'sechzehn', 'siebzehn', 'achtzehn', 'neunzehn', 'zwanzig', 'einundzwanzig', 'zweiundzwanzig',
    'dreiundzwanzig', 'vierundzwanzig', 'fünfundzwanzig', 'sechsundzwanzig', 'siebenundzwanzig', 'achtundzwanzig',
    'neunundzwanzig', 'dreißig'],
  it: ['uno', 'due', 'tre', 'quattro', 'cinque', 'sei', 'sette', 'otto', 'nove', 'dieci', 'undici', 'dodici', 'tredici',
    'quattordici', 'quindici', 'sedici', 'diciassette', 'diciotto', 'diciannove', 'venti', 'ventuno', 'ventidue',
    'ventitré', 'ventiquattro', 'venticinque', 'ventisei', 'ventisette', 'ventotto', 'ventinove', 'trenta'],
  es: ['uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve', 'diez', 'once', 'doce', 'trece',
    'catorce', 'quince', 'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve', 'veinte', 'veintiuno', 'veintidós',
    'veintitrés', 'veinticuatro', 'veinticinco', 'veintiséis', 'veintisiete', 'veintiocho', 'veintinueve', 'treinta'],
  pt: ['um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove', 'dez', 'onze', 'doze', 'treze',
    'catorze', 'quinze', 'dezasseis', 'dezassete', 'dezoito', 'dezanove', 'vinte', 'vinte e um', 'vinte e dois',
    'vinte e três', 'vinte e quatro', 'vinte e cinco', 'vinte e seis', 'vinte e sete', 'vinte e oito', 'vinte e nove', 'trinta'],
  ja: ['いち', 'に', 'さん', 'よん', 'ご', 'ろく', 'なな', 'はち', 'きゅう', 'じゅう', 'じゅういち', 'じゅうに', 'じゅうさん',
    'じゅうよん', 'じゅうご', 'じゅうろく', 'じゅうなな', 'じゅうはち', 'じゅうきゅう', 'にじゅう', 'にじゅういち', 'にじゅうに',
    'にじゅうさん', 'にじゅうよん', 'にじゅうご', 'にじゅうろく', 'にじゅうなな', 'にじゅうはち', 'にじゅうきゅう', 'さんじゅう'],
  ro: ['unu', 'doi', 'trei', 'patru', 'cinci', 'șase', 'șapte', 'opt', 'nouă', 'zece', 'unsprezece', 'doisprezece',
    'treisprezece', 'paisprezece', 'cincisprezece', 'șaisprezece', 'șaptesprezece', 'optsprezece', 'nouăsprezece',
    'douăzeci', 'douăzeci și unu', 'douăzeci și doi', 'douăzeci și trei', 'douăzeci și patru', 'douăzeci și cinci',
    'douăzeci și șase', 'douăzeci și șapte', 'douăzeci și opt', 'douăzeci și nouă', 'treizeci'],
  th: ['หนึ่ง', 'สอง', 'สาม', 'สี่', 'ห้า', 'หก', 'เจ็ด', 'แปด', 'เก้า', 'สิบ', 'สิบเอ็ด', 'สิบสอง', 'สิบสาม', 'สิบสี่',
    'สิบห้า', 'สิบหก', 'สิบเจ็ด', 'สิบแปด', 'สิบเก้า', 'ยี่สิบ', 'ยี่สิบเอ็ด', 'ยี่สิบสอง', 'ยี่สิบสาม', 'ยี่สิบสี่', 'ยี่สิบห้า',
    'ยี่สิบหก', 'ยี่สิบเจ็ด', 'ยี่สิบแปด', 'ยี่สิบเก้า', 'สามสิบ'],
}

// Japanese counters change the number's sound (いっかい, ろっかい, はっかい, じゅっかい).
const jaTimes = ['いっかい', 'にかい', 'さんかい', 'よんかい', 'ごかい', 'ろっかい', 'ななかい', 'はっかい', 'きゅうかい', 'じゅっかい']

const capital = (text) => text.charAt(0).toLocaleUpperCase() + text.slice(1)

// Spoken wording; the on-screen labels stay as they are.
const copy = {
  en: {
    cue: { warmup: 'Warm-up started.', thirty: 'Thirty seconds.', rest: 'Rest.', left: 'Left side.', right: 'Right side.',
      review: 'Review the final set.', complete: 'Session complete.' },
    noun: { set: 'Set', hold: 'Hold', round: 'Round', exercise: 'Exercise' },
    set: (noun, n, total) => `${noun} ${n} of ${total}.`,
    group: (letter, n) => `${letter} ${n}.`,
    countLead: 'Nice and controlled. Keep the tempo.',
    pushLead: 'Last reps now. Dig in, finish strong!',
    setLead: 'Next exercise coming up.',
  },
  de: {
    cue: { warmup: 'Aufwärmen gestartet.', thirty: 'Noch dreißig Sekunden.', rest: 'Pause.', left: 'Linke Seite.',
      right: 'Rechte Seite.', review: 'Letzten Satz prüfen.', complete: 'Einheit abgeschlossen.' },
    noun: { set: 'Satz', hold: 'Halten', round: 'Runde', exercise: 'Übung' },
    set: (noun, n, total) => noun === 'Halten' ? `Halten: ${n} von ${total}.` : `${noun} ${n} von ${total}.`,
    group: (letter, n) => `${letter} ${n}.`,
    countLead: 'Schön kontrolliert. Halte das Tempo.',
    pushLead: 'Die letzten Wiederholungen. Beiß dich durch!',
    setLead: 'Gleich geht es weiter.',
  },
  it: {
    cue: { warmup: 'Riscaldamento iniziato.', thirty: 'Trenta secondi.', rest: 'Recupero.', left: 'Lato sinistro.',
      right: 'Lato destro.', review: "Rivedi l'ultima serie.", complete: 'Sessione completata.' },
    noun: { set: 'Serie', hold: 'Tenuta', round: 'Giro', exercise: 'Esercizio' },
    set: (noun, n, total) => `${noun} ${n} di ${total}.`,
    group: (letter, n) => `${letter} ${n}.`,
    countLead: 'Bene, controllato. Mantieni il ritmo.',
    pushLead: 'Ultime ripetizioni. Non mollare adesso!',
    setLead: 'Si riparte tra poco.',
  },
  es: {
    cue: { warmup: 'Calentamiento iniciado.', thirty: 'Treinta segundos.', rest: 'Descanso.', left: 'Lado izquierdo.',
      right: 'Lado derecho.', review: 'Revisa la última serie.', complete: 'Sesión completada.' },
    noun: { set: 'Serie', hold: 'Mantener', round: 'Ronda', exercise: 'Ejercicio' },
    set: (noun, n, total) => noun === 'Mantener' ? `Mantener: ${n} de ${total}.` : `${noun} ${n} de ${total}.`,
    group: (letter, n) => `${letter} ${n}.`,
    countLead: 'Bien, controlado. Mantén el ritmo.',
    pushLead: 'Últimas repeticiones. ¡Aprieta, que ya lo tienes!',
    setLead: 'Seguimos enseguida.',
  },
  pt: {
    cue: { warmup: 'Aquecimento iniciado.', thirty: 'Trinta segundos.', rest: 'Descanso.', left: 'Lado esquerdo.',
      right: 'Lado direito.', review: 'Revê a última série.', complete: 'Sessão concluída.' },
    noun: { set: 'Série', hold: 'Manter', round: 'Ronda', exercise: 'Exercício' },
    set: (noun, n, total) => noun === 'Manter' ? `Manter: ${n} de ${total}.` : `${noun} ${n} de ${total}.`,
    group: (letter, n) => `${letter} ${n}.`,
    countLead: 'Isso, controlado. Mantém o ritmo.',
    pushLead: 'Últimas repetições. Força, já está quase!',
    setLead: 'Já vamos continuar.',
  },
  ja: {
    cue: { warmup: 'ウォームアップ、スタート。', thirty: '残り、さんじゅうびょう。', rest: '休憩。', left: '左側。', right: '右側。',
      review: '最終セットを確認してください。', complete: 'セッション完了。' },
    // Japanese states the total first, then which one this is.
    jaSet: { set: (n, t) => `ぜん${t}セットちゅう、${n}セットめ。`, round: (n, t) => `ぜん${t}ラウンドちゅう、${n}ラウンドめ。`,
      exercise: (n, t) => `ぜん${t}しゅもくちゅう、${n}しゅもくめ。`,
      hold: (n, t) => `キープ。ぜん${jaTimes[t - 1]}ちゅう、${jaTimes[n - 1]}め。` },
    group: (letter, n) => `${letter}の${n}。`,
    countLead: 'いいですね、コントロールして。テンポをキープ。',
    pushLead: 'ラスト、もうひと踏ん張り！',
    setLead: 'まもなく次にいきます。',
  },
  ro: {
    cue: { warmup: 'Încălzirea a început.', thirty: 'Treizeci de secunde.', rest: 'Pauză.', left: 'Partea stângă.',
      right: 'Partea dreaptă.', review: 'Verifică ultimul set.', complete: 'Sesiune finalizată.' },
    noun: { set: 'Setul', hold: 'Menținere', round: 'Runda', exercise: 'Exercițiul' },
    set: (noun, n, total) => noun === 'Menținere' ? `Menținere: ${n} din ${total}.` : `${noun} ${n} din ${total}.`,
    group: (letter, n) => `${letter} ${n}.`,
    countLead: 'Bine, controlat. Păstrează ritmul.',
    pushLead: 'Ultimele repetări. Hai, încă puțin!',
    setLead: 'Continuăm imediat.',
  },
  th: {
    cue: { warmup: 'เริ่มวอร์มอัปแล้ว', thirty: 'อีกสามสิบวินาที', rest: 'พัก', left: 'ข้างซ้าย', right: 'ข้างขวา',
      review: 'ตรวจทานเซตสุดท้าย', complete: 'ฝึกเสร็จแล้ว' },
    thSet: { set: (n, t) => `เซตที่${n} จากทั้งหมด${t}เซต`, round: (n, t) => `รอบที่${n} จากทั้งหมด${t}รอบ`,
      exercise: (n, t) => `ท่าที่${n} จากทั้งหมด${t}ท่า`, hold: (n, t) => `ค้างไว้ ครั้งที่${n} จากทั้งหมด${t}ครั้ง` },
    group: (letter, n) => `${letter} ${n}`,
    countLead: 'ดีมาก ควบคุมจังหวะไว้',
    pushLead: 'ครั้งสุดท้ายแล้ว สู้อีกนิด!',
    setLead: 'เดี๋ยวไปต่อกัน',
  },
}

// Swiss users get Swiss Standard German, as the app writes it: German without the eszett, spoken by a Swiss voice.
const swiss = (value) => typeof value === 'string' ? value.replaceAll('ß', 'ss')
  : typeof value === 'function' ? (...args) => swiss(value(...args))
  : Array.isArray(value) ? value.map(swiss)
  : Object.fromEntries(Object.entries(value).map(([key, inner]) => [key, swiss(inner)]))
numbers['de-CH'] = swiss(numbers.de)
copy['de-CH'] = swiss(copy.de)

// Eleven v4 acting tags (English works for every language), one emotion per phrase.
const tag = {
  count: '[steady, focused]',
  push: '[intense, encouraging]',
  setFirst: '[upbeat, confident]',
  setMiddle: '[focused, encouraging]',
  setFinal: '[determined, rallying]',
  warmup: '[warm, upbeat]',
  thirty: '[calm, attentive]',
  rest: '[relaxed, reassuring]',
  left: '[clear, encouraging]',
  right: '[clear, encouraging]',
  review: '[calm, satisfied]',
  complete: '[proud, warm]',
  group: '[clear, energetic]',
}

/** Every clip for one language: `id` names the file, `text` is what is sent, `previousText` sets the mood unspoken. */
export function linesFor(language) {
  const c = copy[language]
  const num = numbers[language]
  if (!c || !num || num.length !== maxCount) throw new Error(`No voice script for ${language}`)
  const lines = []
  for (let n = 1; n <= maxCount; n += 1) {
    lines.push({ id: `count.${n}`, text: `${tag.count} ${capital(num[n - 1])}.`, previousText: c.countLead })
    lines.push({ id: `count.${n}.push`, text: `${tag.push} ${capital(num[n - 1])}!`, previousText: c.pushLead })
  }
  for (const [key, text] of Object.entries(c.cue)) {
    lines.push({ id: `cue.${key}`, text: `${tag[key]} ${text}` })
  }
  for (const noun of setNouns) {
    for (let total = 1; total <= maxSets; total += 1) {
      for (let n = 1; n <= total; n += 1) {
        const mood = n === 1 ? tag.setFirst : n === total ? tag.setFinal : tag.setMiddle
        let text
        if (language === 'ja') text = c.jaSet[noun](num[n - 1], num[total - 1])
        else if (language === 'th') text = c.thSet[noun](num[n - 1], num[total - 1])
        else text = c.set(c.noun[noun], num[n - 1], num[total - 1])
        lines.push({ id: `set.${noun}.${n}.${total}`, text: `${mood} ${text}`, previousText: c.setLead })
      }
    }
  }
  for (const letter of groupLetters) {
    for (let n = 1; n <= maxGroupPosition; n += 1) {
      lines.push({ id: `group.${letter}${n}`, text: `${tag.group} ${c.group(letter, num[n - 1])}` })
    }
  }
  return lines
}

// Exercise names are voiced by supabase/functions/workout-voice (`nameLine`), with the same model, voice and seed.
