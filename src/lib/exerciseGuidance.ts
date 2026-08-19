import type { IntroLanguage } from './introLanguage'

interface Cue {
  en: string
  ro: string
  th: string
}

const CUES: Array<{ match: RegExp; cue: Cue }> = [
  {
    match: /focus\s*t25/i,
    cue: {
      en: 'Follow the episode on screen. Choose the modifier whenever form or breathing starts to break down. A completed modifier version still counts as a completed session.',
      ro: 'Urmează episodul de pe ecran. Folosește varianta modificată când tehnica sau respirația se deteriorează. O sesiune terminată cu modificatorul rămâne o sesiune completă.',
      th: 'ทำตามตอนบนหน้าจอ เลือกท่าปรับง่ายเมื่อฟอร์มหรือการหายใจเริ่มเสีย การทำจนจบด้วยท่าปรับง่ายยังนับว่าเสร็จสมบูรณ์',
    },
  },
  {
    match: /bulgarian|split[\s-]?squat|fandare.*bulgar/i,
    cue: {
      en: 'Set the rear foot comfortably, keep the front foot fully planted and lower under control. Drive through the whole front foot without letting the knee collapse inward.',
      ro: 'Așază piciorul din spate confortabil, păstrează toată talpa din față pe sol și coboară controlat. Împinge prin toată talpa fără ca genunchiul să cadă spre interior.',
      th: 'วางเท้าหลังให้สบาย เท้าหน้าวางเต็มพื้น ลดตัวอย่างควบคุม แล้วดันผ่านเท้าหน้าทั้งฝ่าเท้าโดยไม่ให้เข่ายุบเข้าด้านใน',
    },
  },
  {
    match: /romanian deadlift|\brdl\b|îndreptări românești|ยกเดดลิฟต์โรมาเนีย/i,
    cue: {
      en: 'Keep the weight close, soften the knees and push the hips back until the hamstrings are loaded. Keep the spine long and finish by standing tall, not by leaning back.',
      ro: 'Ține greutatea aproape, genunchii ușor flexați și împinge șoldurile înapoi până simți femuralii. Menține coloana lungă și termină drept, fără să te lași pe spate.',
      th: 'ให้น้ำหนักอยู่ใกล้ตัว งอเข่าเล็กน้อย ดันสะโพกไปด้านหลังจนรู้สึกตึงเอ็นหลังเข่า รักษาหลังเป็นกลางและยืนตรงโดยไม่แอ่นหลัง',
    },
  },
  {
    match: /hip thrust|glute bridge|frog pump|împins.*șold|สะพานก้น|ฮิปทรัสต์/i,
    cue: {
      en: 'Brace the ribs down, drive through the feet and finish with the glutes. Stop when the hips are fully extended without arching the lower back.',
      ro: 'Ține coastele coborâte, împinge prin tălpi și finalizează din fesieri. Oprește când șoldurile sunt complet extinse, fără să arcuiești zona lombară.',
      th: 'เก็บซี่โครง ดันผ่านเท้าและบีบก้น หยุดเมื่อสะโพกเหยียดสุดโดยไม่แอ่นหลังส่วนล่าง',
    },
  },
  {
    match: /lunge|fandare|ก้าวย่อ/i,
    cue: {
      en: 'Step to a stable stance, lower with control and keep the working knee tracking over the toes. Push the floor away to return.',
      ro: 'Pășește într-o poziție stabilă, coboară controlat și lasă genunchiul să urmărească direcția degetelor. Împinge podeaua pentru revenire.',
      th: 'ก้าวให้มั่นคง ลดตัวอย่างควบคุม ให้เข่าไปทิศเดียวกับปลายเท้า แล้วดันพื้นเพื่อกลับขึ้น',
    },
  },
  {
    match: /calf|gambe|น่อง/i,
    cue: {
      en: 'Use the full comfortable ankle range. Pause briefly at the top and lower slowly without bouncing.',
      ro: 'Folosește toată amplitudinea confortabilă a gleznei. Oprește scurt sus și coboară lent, fără balans.',
      th: 'ใช้ช่วงการเคลื่อนไหวข้อเท้าที่สบาย หยุดสั้น ๆ ด้านบนและลดลงช้า ๆ โดยไม่เด้ง',
    },
  },
  {
    match: /pull[\s-]?up|chin[\s-]?up|dead hang|tracți|โหน|ดึงข้อ/i,
    cue: {
      en: 'Start from a controlled shoulder position, keep the ribs stacked and pull without swinging. Stop before grip or shoulder position becomes unsafe.',
      ro: 'Pornește cu umerii controlați, coastele aliniate și trage fără balans. Oprește înainte ca priza sau poziția umărului să devină nesigură.',
      th: 'เริ่มด้วยหัวไหล่ที่ควบคุม เก็บลำตัวตรงและดึงโดยไม่เหวี่ยง หยุดก่อนที่แรงจับหรือหัวไหล่จะเสียตำแหน่ง',
    },
  },
  {
    match: /row|ramat|ดึง.*พาย|แมชชีนโรว์/i,
    cue: {
      en: 'Brace the torso, lead with the elbows and pull toward the lower ribs. Let the shoulder blades move naturally without shrugging.',
      ro: 'Stabilizează trunchiul, conduce cu coatele și trage spre coastele inferioare. Lasă omoplații să se miște natural, fără să ridici umerii.',
      th: 'ตรึงลำตัว นำด้วยศอก ดึงเข้าหาซี่โครงล่าง ให้สะบักเคลื่อนไหวตามธรรมชาติโดยไม่ยกไหล่',
    },
  },
  {
    match: /push[\s-]?up|press|împins|flotări|วิดพื้น|เพรส/i,
    cue: {
      en: 'Keep the body braced, lower through a pain-free range and press while keeping the shoulders away from the ears. Maintain steady wrist and elbow alignment.',
      ro: 'Ține corpul stabil, coboară într-o amplitudine fără durere și împinge păstrând umerii departe de urechi. Menține încheieturile și coatele aliniate.',
      th: 'เกร็งลำตัว ลดตัวในช่วงที่ไม่เจ็บ และดันโดยไม่ยกไหล่เข้าหาหู รักษาข้อมือกับศอกให้มั่นคง',
    },
  },
  {
    match: /face pull|band pull|pull-apart|tragere.*band|ยางยืด/i,
    cue: {
      en: 'Keep the ribs quiet and pull with the upper back. Finish with the hands apart and shoulders down rather than forcing extra range.',
      ro: 'Ține coastele stabile și trage din partea superioară a spatelui. Termină cu mâinile depărtate și umerii jos, fără să forțezi amplitudinea.',
      th: 'ตรึงซี่โครง ดึงด้วยหลังส่วนบน จบด้วยมือแยกออกและไหล่ต่ำ โดยไม่ฝืนช่วงการเคลื่อนไหว',
    },
  },
  {
    /* Before the generic curl: "leg curl" contains "curl", so the specific
       machine has to be tested first or a hamstring exercise is handed a
       biceps cue about keeping the upper arm stable. */
    match: /leg curl|flexii femurali|งอขา/i,
    cue: {
      en: 'Keep the hips anchored, curl smoothly and squeeze briefly without lifting the pelvis. Return slowly.',
      ro: 'Ține șoldurile fixate, flexează lin și contractă scurt fără să ridici bazinul. Revino lent.',
      th: 'ตรึงสะโพก งอขาอย่างนุ่มนวล บีบสั้น ๆ โดยไม่ยกเชิงกราน แล้วกลับช้า ๆ',
    },
  },
  {
    match: /curl|flexii|ciocan|ไบเซป|เคิร์ล/i,
    cue: {
      en: 'Keep the upper arm stable and curl without using momentum. Lower under control through the comfortable elbow range.',
      ro: 'Ține brațul superior stabil și flexează fără impuls. Coboară controlat în amplitudinea confortabilă a cotului.',
      th: 'ตรึงต้นแขน งอศอกโดยไม่เหวี่ยง และลดน้ำหนักอย่างควบคุมในช่วงที่ข้อศอกสบาย',
    },
  },
  {
    match: /bird dog|side plank|plank|wall slide|mobil|stretch|posture|planș|แพลงก์|ยืด/i,
    cue: {
      en: 'Move only through the range you can control while breathing normally. Keep the trunk quiet and stop if the movement causes sharp pain.',
      ro: 'Mișcă-te doar în amplitudinea pe care o poți controla, respirând normal. Menține trunchiul stabil și oprește-te dacă apare durere ascuțită.',
      th: 'เคลื่อนไหวเฉพาะช่วงที่ควบคุมได้พร้อมหายใจตามปกติ รักษาลำตัวให้นิ่งและหยุดหากมีอาการเจ็บแปลบ',
    },
  },
  {
    match: /squat|genuflex|สควอต/i,
    cue: {
      en: 'Set a stable foot position, brace before descending and keep the knees tracking with the toes. Use the deepest pain-free range you can control.',
      ro: 'Așază tălpile stabil, încordează trunchiul înainte de coborâre și aliniază genunchii cu degetele. Folosește cea mai adâncă amplitudine fără durere pe care o controlezi.',
      th: 'วางเท้าให้มั่นคง เกร็งลำตัวก่อนลง ให้เข่าไปทิศเดียวกับปลายเท้า และใช้ช่วงลึกที่สุดที่ควบคุมได้โดยไม่เจ็บ',
    },
  },
]

const FALLBACK: Cue = {
  en: 'Use a controlled, pain-free range with stable alignment. Follow the prescribed tempo, stop on sharp pain and leave the planned repetitions in reserve.',
  ro: 'Folosește o amplitudine controlată, fără durere și cu aliniere stabilă. Respectă tempoul, oprește-te la durere ascuțită și păstrează repetările prescrise în rezervă.',
  th: 'ใช้ช่วงการเคลื่อนไหวที่ควบคุมได้และไม่เจ็บ รักษาแนวร่างกาย ทำตามจังหวะ หยุดเมื่อเจ็บแปลบ และเหลือจำนวนครั้งตามแผน',
}

export function exerciseExecutionCue(name: string, language: IntroLanguage): string {
  const found = CUES.find((entry) => entry.match.test(name))
  return (found?.cue ?? FALLBACK)[language]
}
