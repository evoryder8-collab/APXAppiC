import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { parse as parseJavaScript } from '@babel/parser'
import { nativeContentRows } from './native-content-translations.mjs'
import { nativeTrainingRows } from './native-training-translations.mjs'
import { nativeRuntimeGeneralRows } from './native-runtime-general-translations.mjs'
import { nativeRuntimeOrbitRows } from './native-runtime-orbit-translations.mjs'
import { nativeRuntimeMarathonRows } from './native-runtime-marathon-translations.mjs'

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url))
const repository = path.resolve(toolsDirectory, '../../..')
const nativeResources = path.join(repository, 'ios/APEXNative/APEX/Resources')

function parse(file) {
  const body = fs.readFileSync(file, 'utf8')
  return parseJavaScript(body, { sourceType: 'module', plugins: ['typescript', 'jsx'] })
}

function literal(node) {
  if (node?.type === 'StringLiteral') return node.value
  if (node?.type === 'TemplateLiteral' && node.expressions.length === 0) return node.quasis[0]?.value?.cooked ?? null
  return null
}

function variable(source, name) {
  let result = null
  function walk(node) {
    if (!node || typeof node !== 'object' || result != null) return
    if (node.type === 'VariableDeclarator' && node.id?.type === 'Identifier' && node.id.name === name) {
      result = node.init
      return
    }
    for (const value of Object.values(node)) {
      if (Array.isArray(value)) value.forEach(walk)
      else if (value && typeof value === 'object' && typeof value.type === 'string') walk(value)
    }
  }
  walk(source)
  return result
}

function rowsTranslations() {
  const source = parse(path.join(repository, 'src/lib/translations.ts'))
  const initializer = variable(source, 'rows')
  if (!initializer || initializer.type !== 'ArrayExpression') throw new Error('Could not read UI translation rows.')
  const result = new Map()
  for (const element of initializer.elements ?? []) {
    if (element?.type !== 'ArrayExpression' || element.elements.length < 3) continue
    const english = literal(element.elements[0])
    const romanian = literal(element.elements[1])
    const thai = literal(element.elements[2])
    if (english != null && romanian != null && thai != null) result.set(english, { ro: romanian, th: thai })
  }
  return result
}

function tupleTranslations(variableName) {
  const source = parse(path.join(repository, 'src/lib/translations.ts'))
  const initializer = variable(source, variableName)
  if (!initializer || initializer.type !== 'ArrayExpression') {
    throw new Error(`Could not read ${variableName} translation rows.`)
  }
  const result = new Map()
  for (const element of initializer.elements ?? []) {
    if (element?.type !== 'ArrayExpression' || element.elements.length < 3) continue
    const english = literal(element.elements[0])
    const romanian = literal(element.elements[1])
    const thai = literal(element.elements[2])
    if (english != null && romanian != null && thai != null) result.set(english, { ro: romanian, th: thai })
  }
  return result
}

function orbitTranslations() {
  const source = parse(path.join(repository, 'src/orbit/ui/i18n.ts'))
  const initializer = variable(source, 'copy')
  if (!initializer || initializer.type !== 'ObjectExpression') throw new Error('Could not read Orbit translations.')
  const result = new Map()
  for (const property of initializer.properties) {
    if (property.type !== 'ObjectProperty' || property.value?.type !== 'ObjectExpression') continue
    const english = literal(property.key)
    if (english == null) continue
    const languages = {}
    for (const translation of property.value.properties) {
      if (translation.type !== 'ObjectProperty') continue
      const key = translation.key?.type === 'Identifier' ? translation.key.name : literal(translation.key)
      const value = literal(translation.value)
      if (key && value != null) languages[key] = value
    }
    if (languages.ro && languages.th) result.set(english, { ro: languages.ro, th: languages.th })
  }
  return result
}

const nativeRows = [
  ['APEX is offline. Your last synced data and new entries remain available.', 'APEX este offline. Ultimele date sincronizate și înregistrările noi rămân disponibile.', 'APEX ออฟไลน์อยู่ ข้อมูลที่ซิงก์ล่าสุดและรายการใหม่ยังคงใช้งานได้'],
  ['Preferences sync across your APEX clients.', 'Preferințele se sincronizează între aplicațiile tale APEX.', 'การตั้งค่าจะซิงก์ระหว่างแอป APEX ของคุณ'],
  ['Voice coaching', 'Ghidare vocală', 'คำแนะนำด้วยเสียง'],
  ['Haptic ticks', 'Semnale haptice', 'การสั่นตอบสนอง'],
  ['Reminders', 'Mementouri', 'การเตือน'],
  ['Apple Health', 'Apple Health', 'Apple Health'],
  ['Weight, VO₂ max, resting heart rate, workouts, steps and water', 'Greutate, VO₂ max, puls în repaus, antrenamente, pași și apă', 'น้ำหนัก VO₂ max ชีพจรขณะพัก การออกกำลังกาย จำนวนก้าว และน้ำ'],
  ['Sync now', 'Sincronizează acum', 'ซิงก์ตอนนี้'],
  ['Connect Apple Health', 'Conectează Apple Health', 'เชื่อมต่อ Apple Health'],
  ['Language', 'Limbă', 'ภาษา'],
  ['Account', 'Cont', 'บัญชี'],
  ['Log out', 'Deconectare', 'ออกจากระบบ'],
  ['Your records remain private under Supabase row-level security and are shared only between your authenticated APEX clients.', 'Datele tale rămân private prin securitatea pe rânduri Supabase și sunt partajate doar între aplicațiile APEX în care ești autentificat.', 'ข้อมูลของคุณเป็นส่วนตัวด้วยระบบความปลอดภัยระดับแถวของ Supabase และแชร์เฉพาะระหว่างแอป APEX ที่คุณเข้าสู่ระบบไว้'],
  ['The right run,\nfor this body, today.', 'Alergarea potrivită,\npentru corpul tău, azi.', 'การวิ่งที่เหมาะ\nกับร่างกายวันนี้'],
  ['Start today’s run', 'Începe alergarea de azi', 'เริ่มวิ่งวันนี้'],
  ['Free run', 'Alergare liberă', 'วิ่งอิสระ'],
  ['Library', 'Bibliotecă', 'คลัง'],
  ['APEX context', 'Context APEX', 'ข้อมูล APEX'],
  ['Your first route becomes your baseline', 'Primul traseu devine reperul tău', 'เส้นทางแรกจะเป็นค่าพื้นฐานของคุณ'],
  ['Orbit will interpret the mission, pacing and recovery cost after you finish.', 'După finalizare, Orbit va interpreta scopul, ritmul și costul de recuperare.', 'เมื่อวิ่งเสร็จ Orbit จะวิเคราะห์เป้าหมาย เพซ และภาระการฟื้นตัว'],
  ['Plan a route around the mission, not just a line on a map.', 'Planifică traseul după scop, nu doar ca o linie pe hartă.', 'วางแผนเส้นทางตามเป้าหมาย ไม่ใช่แค่เส้นบนแผนที่'],
  ['Run complete', 'Alergare finalizată', 'วิ่งเสร็จแล้ว'],
  ['What this run built', 'Ce a dezvoltat această alergare', 'การวิ่งครั้งนี้พัฒนาอะไร'],
  ['Create route poster', 'Creează afișul traseului', 'สร้างโปสเตอร์เส้นทาง'],
  ['Map, constellation, elevation or minimal. Your exact start and finish stay hidden by default.', 'Hartă, constelație, elevație sau stil minimal. Startul și finalul exact rămân ascunse implicit.', 'เลือกแผนที่ กลุ่มดาว ระดับความสูง หรือแบบมินิมอล โดยซ่อนจุดเริ่มและจุดจบที่แน่นอนไว้เป็นค่าเริ่มต้น'],
  ['Training and Avatar remain coordinated', 'Antrenamentul și Avatarul rămân coordonate', 'การฝึกและ Avatar ยังคงประสานกัน'],
  ['Review and apply exact adjustment', 'Verifică și aplică ajustarea exactă', 'ตรวจสอบและใช้การปรับที่แน่นอน'],
  ['Route poster', 'Afiș de traseu', 'โปสเตอร์เส้นทาง'],
  ['Save image', 'Salvează imaginea', 'บันทึกรูปภาพ'],
  ['Prepare share', 'Pregătește distribuirea', 'เตรียมแชร์'],
  ['Share', 'Distribuie', 'แชร์'],
  ['The precise start and finish are hidden by default.', 'Startul și finalul exact sunt ascunse implicit.', 'จุดเริ่มและจุดจบที่แน่นอนจะถูกซ่อนไว้เป็นค่าเริ่มต้น'],
  ['Include recorded heart rate', 'Include pulsul înregistrat', 'รวมอัตราการเต้นหัวใจที่บันทึกไว้'],
  ['Optional poster note', 'Notă opțională pe afiș', 'บันทึกบนโปสเตอร์แบบไม่บังคับ'],
  ['Marathon Campaign', 'Campanie de maraton', 'แผนมาราธอน'],
  ['Begin induction', 'Începe evaluarea', 'เริ่มการประเมิน'],
  ['No mysterious score. Every conclusion keeps its reason visible.', 'Fără scor misterios. Fiecare concluzie își arată motivul.', 'ไม่มีคะแนนลึกลับ ทุกข้อสรุปจะแสดงเหตุผล'],
  ['Current week', 'Săptămâna curentă', 'สัปดาห์นี้'],
  ['View remaining campaign', 'Vezi restul campaniei', 'ดูแผนที่เหลือ'],
  ['Open Science Ledger', 'Deschide registrul științific', 'เปิดบันทึกหลักฐานวิทยาศาสตร์'],
  ['Science Ledger', 'Registru științific', 'บันทึกหลักฐานวิทยาศาสตร์'],
  ['Private Visual Progress', 'Progres vizual privat', 'ภาพความก้าวหน้าส่วนตัว'],
  ['Before, after and the stats behind the change', 'Înainte, după și statisticile din spatele schimbării', 'ก่อน หลัง และค่าสถิติที่อยู่เบื้องหลังการเปลี่ยนแปลง'],
  ['Your performance body', 'Corpul tău de performanță', 'ร่างกายเพื่อสมรรถนะของคุณ'],
  ['Clear signals, no mystery score', 'Semnale clare, fără scor misterios', 'ข้อมูลชัดเจน ไม่มีคะแนนลึกลับ'],
  ['What your body needs now', 'De ce are nevoie corpul tău acum', 'สิ่งที่ร่างกายต้องการตอนนี้'],
  ['Overall Fitness Level', 'Nivel general de fitness', 'ระดับความฟิตโดยรวม'],
  ['Health', 'Sănătate', 'สุขภาพ'],
  ['Joint Health', 'Sănătatea articulațiilor', 'สุขภาพข้อต่อ'],
  ['Flexibility', 'Flexibilitate', 'ความยืดหยุ่น'],
  ['Endurance & VO₂ max', 'Anduranță și VO₂ max', 'ความทนทานและ VO₂ max'],
  ['Private Visual Progress', 'Progres vizual privat', 'ภาพความก้าวหน้าส่วนตัว'],
  ['Create a new checkpoint', 'Creează un reper nou', 'สร้างจุดบันทึกใหม่'],
  ['Include stats', 'Include statisticile', 'รวมค่าสถิติ'],
  ['Before and after', 'Înainte și după', 'ก่อนและหลัง'],
  ['Select any two checkpoints to compare them.', 'Selectează două repere pentru comparație.', 'เลือกจุดบันทึกสองจุดเพื่อเปรียบเทียบ'],
  ['No synced checkpoints yet', 'Nu există încă repere sincronizate', 'ยังไม่มีจุดบันทึกที่ซิงก์'],
  ['Camera', 'Cameră', 'กล้อง'],
  ['Library', 'Bibliotecă', 'คลังรูปภาพ'],
  ['Save private checkpoint', 'Salvează reperul privat', 'บันทึกจุดเปรียบเทียบส่วนตัว'],
  ['Today’s signal', 'Semnalul de azi', 'สัญญาณวันนี้'],
  ['Full session', 'Sesiune completă', 'การฝึกเต็มรูปแบบ'],
  ['Minimum effective', 'Minimum eficient', 'ขั้นต่ำที่ได้ผล'],
  ['Start session', 'Începe sesiunea', 'เริ่มการฝึก'],
  ['Finish workout', 'Finalizează antrenamentul', 'จบการฝึก'],
  ['Exercise complete', 'Exercițiu finalizat', 'ทำท่านี้เสร็จแล้ว'],
  ['30 min', '30 min', '30 นาที'],
  ['60 min', '60 min', '60 นาที'],
  ['90 min', '90 min', '90 นาที'],
  ['Activity guide', 'Ghid de activitate', 'คู่มือกิจกรรม'],
  ["Activity levels are computed from today's blocks", 'Nivelurile de activitate sunt calculate din activitățile de azi', 'ระดับกิจกรรมคำนวณจากกิจกรรมของวันนี้'],
  ['Add activity block', 'Adaugă activitate', 'เพิ่มกิจกรรม'],
  ['Add food or use a saved meal', 'Adaugă un aliment sau folosește o masă salvată', 'เพิ่มอาหารหรือใช้มื้อที่บันทึกไว้'],
  ['Add the pair you run in', 'Adaugă perechea cu care alergi', 'เพิ่มรองเท้าคู่ที่ใช้วิ่ง'],
  ['Amount', 'Cantitate', 'ปริมาณ'],
  ['APEX counts 80% because wrist estimates commonly run hot. If distance is also present, APEX uses the larger estimate, never both.', 'APEX ia în calcul 80%, deoarece estimările de la încheietură sunt adesea prea mari. Dacă există și distanța, APEX folosește estimarea mai mare, niciodată suma.', 'APEX นับ 80% เพราะค่าจากข้อมือมักสูงเกินจริง หากมีระยะทางด้วย APEX จะใช้ค่าที่มากกว่าและไม่นำมาบวกกัน'],
  ['APEX detects EAN-8, EAN-13 and UPC labels automatically.', 'APEX detectează automat codurile EAN-8, EAN-13 și UPC.', 'APEX ตรวจจับบาร์โค้ด EAN-8, EAN-13 และ UPC อัตโนมัติ'],
  ['APEX ORBIT · RUN INTELLIGENCE', 'APEX ORBIT · INTELIGENȚĂ PENTRU ALERGARE', 'APEX ORBIT · ระบบวิเคราะห์การวิ่ง'],
  ['APEX PERFORMANCE DEBRIEF', 'ANALIZĂ DE PERFORMANȚĂ APEX', 'สรุปสมรรถนะ APEX'],
  ['APEX reuses your age, profile and strength plan. It asks only for missing running context.', 'APEX folosește vârsta, profilul și planul tău de forță. Întreabă doar informațiile lipsă despre alergare.', 'APEX ใช้อายุ โปรไฟล์ และแผนฝึกแรงที่มีอยู่ และถามเฉพาะข้อมูลการวิ่งที่ยังขาด'],
  ['Avoided sections, separated by commas', 'Secțiuni de evitat, separate prin virgule', 'ช่วงที่ต้องการหลีกเลี่ยง คั่นด้วยจุลภาค'],
  ['Barcode read', 'Cod citit', 'อ่านบาร์โค้ดแล้ว'],
  ['Build a route', 'Creează un traseu', 'สร้างเส้นทาง'],
  ['Camera access is off', 'Accesul la cameră este oprit', 'ปิดสิทธิ์การใช้กล้องอยู่'],
  ['Cancel this run?', 'Anulezi această alergare?', 'ยกเลิกการวิ่งครั้งนี้ไหม?'],
  ['Checking APEX Food Memory and Open Food Facts', 'Se verifică APEX Food Memory și Open Food Facts', 'กำลังตรวจสอบ APEX Food Memory และ Open Food Facts'],
  ['Choose portion', 'Alege porția', 'เลือกปริมาณ'],
  ['Complete this saved route to establish a private segment baseline.', 'Finalizează acest traseu salvat pentru a crea un reper privat al segmentului.', 'วิ่งเส้นทางที่บันทึกไว้นี้ให้จบเพื่อสร้างค่าพื้นฐานส่วนตัวของช่วงเส้นทาง'],
  ['Complete this session?', 'Finalizezi această sesiune?', 'จบการฝึกครั้งนี้ไหม?'],
  ['Complete workout', 'Finalizează antrenamentul', 'จบการฝึก'],
  ['Confirm food', 'Confirmă alimentul', 'ยืนยันอาหาร'],
  ['CURRENT PHASE', 'FAZA CURENTĂ', 'ช่วงปัจจุบัน'],
  ['Discard run', 'Șterge alergarea', 'ทิ้งการวิ่ง'],
  ['Draw', 'Desenează', 'วาด'],
  ['Draw route', 'Desenează traseul', 'วาดเส้นทาง'],
  ['Edit', 'Editează', 'แก้ไข'],
  ['Edit route', 'Editează traseul', 'แก้ไขเส้นทาง'],
  ['Enable Camera for APEX in Settings to scan food labels.', 'Activează camera pentru APEX în Configurări pentru a scana etichetele alimentelor.', 'เปิดสิทธิ์กล้องให้ APEX ในการตั้งค่าเพื่อสแกนฉลากอาหาร'],
  ['End', 'Final', 'จุดจบ'],
  ['Evolution', 'Evoluție', 'พัฒนาการ'],
  ['EXAMPLE DAYS', 'EXEMPLE DE ZILE', 'ตัวอย่างวัน'],
  ['Finish and save', 'Finalizează și salvează', 'จบและบันทึก'],
  ['Finish this run?', 'Finalizezi această alergare?', 'จบการวิ่งครั้งนี้ไหม?'],
  ['FITNESS-READINESS CHECK', 'VERIFICAREA PREGĂTIRII FIZICE', 'ตรวจความพร้อมด้านฟิตเนส'],
  ['Food log', 'Jurnal alimentar', 'บันทึกอาหาร'],
  ['Food Memory', 'Memorie alimentară', 'ความจำอาหาร'],
  ['Front', 'Față', 'ด้านหน้า'],
  ['Generate route options', 'Generează opțiuni de traseu', 'สร้างตัวเลือกเส้นทาง'],
  ['GPS READY', 'GPS PREGĂTIT', 'GPS พร้อม'],
  ['Hold the barcode inside the frame', 'Ține codul de bare în interiorul cadrului', 'วางบาร์โค้ดให้อยู่ในกรอบ'],
  ['If a walk or run is logged above, keep this field to incidental steps only.', 'Dacă ai înregistrat mers sau alergare mai sus, folosește aici doar pașii suplimentari.', 'หากบันทึกการเดินหรือวิ่งด้านบนแล้ว ช่องนี้ให้ใส่เฉพาะก้าวทั่วไปที่ยังไม่ถูกนับ'],
  ['Keep run', 'Păstrează alergarea', 'เก็บการวิ่งไว้'],
  ['Keep running', 'Continuă alergarea', 'วิ่งต่อ'],
  ['Keep training', 'Continuă antrenamentul', 'ฝึกต่อ'],
  ['Leave every switch off if none applies.', 'Lasă toate opțiunile oprite dacă niciuna nu se aplică.', 'หากไม่มีข้อใดตรง ให้ปิดทุกตัวเลือกไว้'],
  ['Log food', 'Înregistrează alimentul', 'บันทึกอาหาร'],
  ['Log what you actually ate', 'Înregistrează ce ai mâncat în realitate', 'บันทึกสิ่งที่กินจริง'],
  ['Marathon induction', 'Evaluare pentru maraton', 'การประเมินก่อนเริ่มมาราธอน'],
  ['Mark missed and rebalance', 'Marchează ca ratat și reechilibrează', 'ทำเครื่องหมายว่าพลาดและปรับแผน'],
  ['Meal', 'Masă', 'มื้อ'],
  ['Mileage is shown factually. APEX does not label shoes unsafe from distance alone.', 'Kilometrajul este afișat ca fapt. APEX nu declară pantofii nesiguri doar pe baza distanței.', 'ระยะใช้งานจะแสดงตามจริง APEX จะไม่บอกว่ารองเท้าไม่ปลอดภัยจากระยะทางเพียงอย่างเดียว'],
  ['Minutes', 'Minute', 'นาที'],
  ['Mission', 'Scop', 'เป้าหมาย'],
  ['Mode', 'Mod', 'โหมด'],
  ['MY WATCH SAYS', 'CEASUL MEU ARATĂ', 'ค่าจากนาฬิกา'],
  ['Name', 'Nume', 'ชื่อ'],
  ['NATIVE MAPKIT', 'MAPKIT NATIV', 'MAPKIT แบบเนทีฟ'],
  ['NET ACTIVITY KCAL', 'KCAL NETE DIN ACTIVITATE', 'แคลอรีสุทธิจากกิจกรรม'],
  ['No exercises found', 'Nu s-au găsit exerciții', 'ไม่พบท่าออกกำลังกาย'],
  ['No shoe assigned', 'Niciun pantof atribuit', 'ยังไม่ได้เลือกรองเท้า'],
  ['OK', 'OK', 'ตกลง'],
  ['Only add activity beyond the normal daily floor.', 'Adaugă doar activitatea care depășește baza zilnică normală.', 'เพิ่มเฉพาะกิจกรรมที่เกินจากค่าพื้นฐานประจำวัน'],
  ['Optional note', 'Notă opțională', 'บันทึกเพิ่มเติม'],
  ['Optional private note', 'Notă privată opțională', 'บันทึกส่วนตัวเพิ่มเติม'],
  ['Orbit', 'Orbit', 'Orbit'],
  ['Orbit continues forward without stacking catch-up work. The original prescription stays visible.', 'Orbit continuă fără să îngrămădească sesiuni de recuperat. Prescripția originală rămâne vizibilă.', 'Orbit จะเดินหน้าต่อโดยไม่ยัดการฝึกชดเชย และยังแสดงแผนเดิมไว้'],
  ['Orbit Library', 'Biblioteca Orbit', 'คลัง Orbit'],
  ['Orbit never labels a route guaranteed safe. It can compare map-supported features such as crossings, turns, terrain and surface where data exists.', 'Orbit nu declară niciun traseu garantat sigur. Poate compara informațiile disponibile pe hartă, precum traversări, viraje, teren și suprafață.', 'Orbit จะไม่รับรองว่าเส้นทางปลอดภัยแน่นอน แต่เปรียบเทียบข้อมูลจากแผนที่ เช่น ทางข้าม ทางเลี้ยว ภูมิประเทศ และพื้นผิวได้เมื่อมีข้อมูล'],
  ['Orbit records what you report and can reduce training load. It does not diagnose an injury. Consider professional advice if symptoms persist or concern you.', 'Orbit înregistrează ce raportezi și poate reduce încărcarea. Nu diagnostichează o accidentare. Cere sfatul unui specialist dacă simptomele persistă sau te îngrijorează.', 'Orbit บันทึกสิ่งที่คุณรายงานและลดภาระการฝึกได้ แต่ไม่วินิจฉัยการบาดเจ็บ หากอาการยังอยู่หรือกังวลควรปรึกษาผู้เชี่ยวชาญ'],
  ['Orbit tracks factual use and notes. It does not declare a shoe unsafe from a generic distance threshold.', 'Orbit urmărește utilizarea și notele reale. Nu declară un pantof nesigur pe baza unui prag generic de distanță.', 'Orbit ติดตามการใช้งานและบันทึกตามจริง โดยไม่บอกว่ารองเท้าไม่ปลอดภัยจากเกณฑ์ระยะทางทั่วไป'],
  ['Out & back', 'Dus-întors', 'ไปและกลับ'],
  ['Overlay compact performance bars on comparison photos', 'Suprapune bare compacte de performanță pe fotografiile comparate', 'ซ้อนแถบสมรรถนะแบบย่อบนภาพเปรียบเทียบ'],
  ['Pair', 'Pereche', 'คู่'],
  ['PERCEIVED EFFORT', 'EFORT PERCEPUT', 'ระดับความเหนื่อย'],
  ['Personal segment', 'Segment personal', 'ช่วงเส้นทางส่วนตัว'],
  ['Personal segments remain private. There are no public leaderboards.', 'Segmentele personale rămân private. Nu există clasamente publice.', 'ช่วงเส้นทางส่วนตัวจะไม่เปิดเผยและไม่มีตารางอันดับสาธารณะ'],
  ['Portion', 'Porție', 'ปริมาณ'],
  ['Portions adapt to your activity and goal selection.', 'Porțiile se adaptează la activitatea și obiectivul selectat.', 'ปริมาณอาหารปรับตามกิจกรรมและเป้าหมายที่เลือก'],
  ['Pose', 'Poziție', 'ท่า'],
  ['Preferred and avoided sections inform future route comparison. They are not safety guarantees.', 'Secțiunile preferate și evitate informează comparațiile viitoare. Nu reprezintă garanții de siguranță.', 'ช่วงที่ชอบและหลีกเลี่ยงจะช่วยเปรียบเทียบเส้นทางในอนาคต แต่ไม่ใช่การรับรองความปลอดภัย'],
  ['Preferred sections, separated by commas', 'Secțiuni preferate, separate prin virgule', 'ช่วงที่ชอบ คั่นด้วยจุลภาค'],
  ['Preferred surfaces', 'Suprafețe preferate', 'พื้นผิวที่ชอบ'],
  ['Prepare GPX', 'Pregătește GPX', 'เตรียม GPX'],
  ['Preview unavailable', 'Previzualizare indisponibilă', 'ดูตัวอย่างไม่ได้'],
  ['Private note', 'Notă privată', 'บันทึกส่วนตัว'],
  ['PRIVATE SHOE ROTATION', 'ROTAȚIE PRIVATĂ DE PANTOFI', 'การหมุนเวียนรองเท้าส่วนตัว'],
  ['Private wear or comfort note', 'Notă privată despre uzură sau confort', 'บันทึกส่วนตัวเรื่องการสึกหรือความสบาย'],
  ['QUICK MODE', 'MOD RAPID', 'โหมดด่วน'],
  ["Quick Mode's brain", 'Ghidul Modului rapid', 'คู่มือของโหมดด่วน'],
  ['Reading nutrition data', 'Se citesc datele nutriționale', 'กำลังอ่านข้อมูลโภชนาการ'],
  ['Repeat yesterday', 'Repetă ziua de ieri', 'ทำซ้ำจากเมื่อวาน'],
  ['Save debrief', 'Salvează analiza', 'บันทึกสรุป'],
  ['Save drawn route', 'Salvează traseul desenat', 'บันทึกเส้นทางที่วาด'],
  ['SCAN', 'SCANEAZĂ', 'สแกน'],
  ['Scan another', 'Scanează altul', 'สแกนอีกครั้ง'],
  ['SCAN FOOD BARCODE', 'SCANEAZĂ CODUL ALIMENTULUI', 'สแกนบาร์โค้ดอาหาร'],
  ['Segment name', 'Numele segmentului', 'ชื่อช่วงเส้นทาง'],
  ['Shape', 'Formă', 'รูปแบบ'],
  ['Shoes', 'Pantofi', 'รองเท้า'],
  ['Side', 'Lateral', 'ด้านข้าง'],
  ['Start a free run instead', 'Începe în schimb o alergare liberă', 'เริ่มวิ่งอิสระแทน'],
  ['STEPS NOT ALREADY COVERED BY THE BLOCKS ABOVE.', 'PAȘI CARE NU SUNT DEJA INCLUȘI ÎN ACTIVITĂȚILE DE MAI SUS.', 'จำนวนก้าวที่ยังไม่ถูกนับในกิจกรรมด้านบน'],
  ['Style', 'Stil', 'รูปแบบ'],
  ['Tap the map to place route points', 'Atinge harta pentru a plasa punctele traseului', 'แตะแผนที่เพื่อวางจุดเส้นทาง'],
  ['Target held above the recovery safety floor', 'Obiectivul este menținut peste limita minimă pentru recuperare', 'เป้าหมายถูกคงไว้เหนือค่าต่ำสุดเพื่อการฟื้นตัว'],
  ["The labels are weekly averages. Use steps and hours on your feet when you need a fast choice, or log real blocks for a computed day.", 'Etichetele sunt medii săptămânale. Folosește pașii și orele în picioare pentru o alegere rapidă sau înregistrează activitățile reale pentru calculul zilei.', 'ป้ายระดับเป็นค่าเฉลี่ยรายสัปดาห์ ใช้จำนวนก้าวและชั่วโมงที่ยืนเมื่อต้องการเลือกเร็ว หรือบันทึกกิจกรรมจริงเพื่อคำนวณวันนี้'],
  ['This check assigns a training recommendation. It does not provide medical clearance or diagnose a condition.', 'Această verificare oferă o recomandare de antrenament. Nu oferă autorizare medicală și nu pune un diagnostic.', 'การตรวจนี้ใช้แนะนำการฝึก ไม่ใช่การรับรองทางการแพทย์หรือวินิจฉัยอาการ'],
  ['This is performance guidance, not medical advice.', 'Aceasta este ghidare pentru performanță, nu sfat medical.', 'นี่คือคำแนะนำด้านสมรรถนะ ไม่ใช่คำแนะนำทางการแพทย์'],
  ['Timeline', 'Cronologie', 'ไทม์ไลน์'],
  ["TODAY'S SIGNAL", 'SEMNALUL DE AZI', 'สัญญาณวันนี้'],
  ['Try the exact product name or scan its barcode.', 'Încearcă numele exact al produsului sau scanează codul de bare.', 'ลองค้นหาชื่อสินค้าที่ตรงหรือสแกนบาร์โค้ด'],
  ['Unit', 'Unitate', 'หน่วย'],
  ['Use adapted', 'Folosește varianta adaptată', 'ใช้แผนที่ปรับแล้ว'],
  ['Use the same pose, distance and lighting for the clearest comparison.', 'Folosește aceeași poziție, distanță și lumină pentru cea mai clară comparație.', 'ใช้ท่า ระยะ และแสงแบบเดิมเพื่อให้เปรียบเทียบได้ชัดที่สุด'],
  ['Useful for', 'Util pentru', 'เหมาะสำหรับ'],
  ['Waiting for location permission and a usable GPS fix', 'Se așteaptă permisiunea pentru locație și un semnal GPS utilizabil', 'กำลังรอสิทธิ์ตำแหน่งและสัญญาณ GPS ที่ใช้งานได้'],
  ['WEAK GPS', 'GPS SLAB', 'GPS อ่อน'],
  ['Your existing web progress photos will appear here as soon as their private signed previews are loaded.', 'Fotografiile tale existente din versiunea web vor apărea aici după încărcarea previzualizărilor private semnate.', 'ภาพความก้าวหน้าจากเว็บจะปรากฏที่นี่เมื่อโหลดตัวอย่างส่วนตัวเสร็จ'],
  ['Your photos remain private. Compare your physique and the performance signals behind it.', 'Fotografiile tale rămân private. Compară fizicul și semnalele de performanță din spatele schimbării.', 'ภาพของคุณยังเป็นส่วนตัว เปรียบเทียบรูปร่างและสัญญาณสมรรถนะที่อยู่เบื้องหลังการเปลี่ยนแปลง'],
  ['APEX', 'APEX', 'APEX'],
  ['English, ไทย, Română', 'English, ไทย, Română', 'English, ไทย, Română'],
  ['kcal', 'kcal', 'กิโลแคลอรี'],
  ['kcal net', 'kcal nete', 'กิโลแคลอรีสุทธิ'],
  ['km', 'km', 'กม.'],
  ['KM', 'KM', 'กม.'],
  ['%d min · %@', '%d min · %@', '%d นาที · %@'],
  ['%d sets · %d–%d · rest %d s', '%d seturi · %d–%d · pauză %d s', '%d เซต · %d–%d · พัก %d วินาที'],
  ['%d days remaining · %@', 'Au rămas %d zile · %@', 'เหลือ %d วัน · %@'],
  ['%d minutes · %@', '%d minute · %@', '%d นาที · %@'],
  ['%d-minute minimum', 'Varianta minimă de %d minute', 'แบบขั้นต่ำ %d นาที'],
  ['Today · %@', 'Azi · %@', 'วันนี้ · %@'],
  ['Training at %@', 'Antrenament la %@', 'ฝึกเวลา %@'],
  ['%d kcal target · %d g protein', 'Țintă %d kcal · %d g proteine', 'เป้าหมาย %d กิโลแคลอรี · โปรตีน %d กรัม'],
  ['%d kcal TDEE · PAL %.2f · %@', 'TDEE %d kcal · PAL %.2f · %@', 'TDEE %d กิโลแคลอรี · PAL %.2f · %@'],
  ['Avatar · %d endurance minutes · pacing discipline %d%%', 'Avatar · %d minute de anduranță · disciplina ritmului %d%%', 'Avatar · ความทนทาน %d นาที · วินัยเพซ %d%%'],
  ['%d completions', '%d finalizări', 'ทำสำเร็จ %d ครั้ง'],
  ['%d m from both ends', '%d m de la ambele capete', 'ซ่อน %d เมตรจากทั้งสองด้าน'],
  ['Plan version %@ · review date 15 January 2027', 'Versiunea planului %@ · data revizuirii 15 ianuarie 2027', 'แผนเวอร์ชัน %@ · วันที่ทบทวน 15 มกราคม 2027'],
  ['%.1f km', '%.1f km', '%.1f กม.'],
  ['%.2f km', '%.2f km', '%.2f กม.'],
  ['%.2f km · %@', '%.2f km · %@', '%.2f กม. · %@'],
  ['%@  %d', '%@  %d', '%@  %d'],
  ['%@ %d', '%@ %d', '%@ %d'],
  ['%@ %@', '%@ %@', '%@ %@'],
  ['%@ · %@', '%@ · %@', '%@ · %@'],
  ['%@%d m', '%@%d m', '%@%d เมตร'],
  ['%d', '%d', '%d'],
  ['%d %@', '%d %@', '%d %@'],
  ['%d %@ %@', '%d %@ %@', '%d %@ %@'],
  ['%d BPM', '%d bpm', '%d ครั้ง/นาที'],
  ['%d g', '%d g', '%d กรัม'],
  ['%d kcal', '%d kcal', '%d กิโลแคลอรี'],
  ['%d kcal / 100', '%d kcal / 100', '%d กิโลแคลอรี / 100'],
  ['%d kcal   P %d   F %d   C %d', '%d kcal   P %d   G %d   C %d', '%d กิโลแคลอรี   โปรตีน %d   ไขมัน %d   คาร์บ %d'],
  ['%d kcal · P %d · C %d · F %d', '%d kcal · P %d · C %d · G %d', '%d กิโลแคลอรี · โปรตีน %d · คาร์บ %d · ไขมัน %d'],
  ['%d kcal · P %d · C %d · F %d per 100', '%d kcal · P %d · C %d · G %d per 100', '%d กิโลแคลอรี · โปรตีน %d · คาร์บ %d · ไขมัน %d ต่อ 100'],
  ['%d km · paused and protected', '%d km · pus pe pauză și păstrat', '%d กม. · หยุดไว้และเก็บข้อมูลแล้ว'],
  ['%d m', '%d m', '%d เมตร'],
  ['%d m gain', '%d m urcare', 'ไต่ระดับ %d เมตร'],
  ['%d min', '%d min', '%d นาที'],
  ['%d min × %d', '%d min × %d', '%d นาที × %d'],
  ['%d minutes · campaign session', '%d minute · sesiune din campanie', '%d นาที · การฝึกตามแผน'],
  ['%d s', '%d s', '%d วินาที'],
  ['%d steps', '%d pași', '%d ก้าว'],
  ['%d:%02d /km', '%d:%02d /km', '%d:%02d /กม.'],
  ['%d SETS · %@ %@', '%d SETURI · %@ %@', '%d เซต · %@ %@'],
  ['%d SETS · %@ %@ / SIDE', '%d SETURI · %@ %@ / PARTE', '%d เซต · %@ %@ / ข้าง'],
  ['+%d KCAL · P %d · C %d · F %d', '+%d KCAL · P %d · C %d · G %d', '+%d กิโลแคลอรี · โปรตีน %d · คาร์บ %d · ไขมัน %d'],
  ['+%d kcal · %d g carbs · %d g protein', '+%d kcal · %d g carbohidrați · %d g proteine', '+%d กิโลแคลอรี · คาร์บ %d กรัม · โปรตีน %d กรัม'],
  ['BMR: %d', 'BMR: %d', 'BMR: %d'],
  ['Carb portions adjust to %d%% while protein stays protected.', 'Porțiile de carbohidrați se ajustează la %d%%, iar proteina rămâne protejată.', 'ปรับปริมาณคาร์บเป็น %d%% โดยคงโปรตีนไว้'],
  ['Distance-based energy estimate: about %d kcal.', 'Estimare de energie din distanță: aproximativ %d kcal.', 'พลังงานโดยประมาณจากระยะทาง: ราว %d กิโลแคลอรี'],
  ['GPS confidence was %@.', 'Încrederea GPS a fost %@.', 'ความแม่นยำของ GPS อยู่ในระดับ %@'],
  ['KM %d', 'KM %d', 'กม. %d'],
  ['Kilometre pace variation was %.1f%%.', 'Variația ritmului pe kilometru a fost %.1f%%.', 'เพซแต่ละกิโลเมตรต่างกัน %.1f%%'],
  ['LV %d', 'NIV %d', 'เลเวล %d'],
  ['MISSION FIT %d', 'POTRIVIRE SCOP %d', 'ความเหมาะกับเป้าหมาย %d'],
  ['OPTION %d', 'OPȚIUNEA %d', 'ตัวเลือก %d'],
  ['OPTION %d · %@ KM', 'OPȚIUNEA %d · %@ KM', 'ตัวเลือก %d · %@ กม.'],
  ['Off route by about %d m. Return to the violet line when practical.', 'Ești la aproximativ %d m de traseu. Revino la linia violet când este posibil.', 'ออกนอกเส้นทางประมาณ %d เมตร กลับไปที่เส้นสีม่วงเมื่อทำได้'],
  ['Orbit option %d', 'Opțiunea Orbit %d', 'ตัวเลือก Orbit %d'],
  ['Original: %@ · %d min. Adapted: %@ · %d min.', 'Inițial: %@ · %d min. Adaptat: %@ · %d min.', 'แผนเดิม: %@ · %d นาที แผนปรับแล้ว: %@ · %d นาที'],
  ['Overall %d', 'General %d', 'รวม %d'],
  ['PACE %d:%02d /KM', 'RITM %d:%02d /KM', 'เพซ %d:%02d /กม.'],
  ['PAL %.2f · %d kcal day', 'PAL %.2f · %d kcal pe zi', 'PAL %.2f · %d กิโลแคลอรีต่อวัน'],
  ['Protein coverage is on track for %@.', 'Aportul de proteine este potrivit pentru %@.', 'โปรตีนเป็นไปตามเป้าสำหรับ%@'],
  ['Recovery cost computes as %@.', 'Costul de recuperare este %@.', 'ภาระการฟื้นตัวอยู่ในระดับ%@'],
  ['START AND FINISH PRIVACY TRIM · %d M', 'ASCUNDERE START ȘI FINAL · %d M', 'ซ่อนจุดเริ่มและจุดจบ · %d เมตร'],
  ['TDEE: %d', 'TDEE: %d', 'TDEE: %d'],
  ['Training load was approximately %d AU from minutes × reported effort.', 'Încărcarea a fost de aproximativ %d UA din minute × efort raportat.', 'ภาระการฝึกประมาณ %d หน่วย จากเวลา × ระดับความเหนื่อยที่รายงาน'],
  ['%.1f km · %@ · %@ navigation', '%.1f km · %@ · navigație %@', '%.1f กม. · %@ · การนำทาง %@'],
  ["Today's energy model places you at %@ with a %d kcal target.", 'Modelul energetic de azi te plasează la %@, cu o țintă de %d kcal.', 'แบบจำลองพลังงานวันนี้อยู่ที่ระดับ%@ โดยมีเป้าหมาย %d กิโลแคลอรี'],
  ['Protein is currently the clearest nutrition gap. Aim toward %d g to protect recovery and lean mass.', 'Proteina este acum principalul gol nutrițional. Țintește %d g pentru recuperare și masă slabă.', 'ตอนนี้โปรตีนเป็นจุดที่ขาดชัดที่สุด ตั้งเป้า %d กรัมเพื่อช่วยการฟื้นตัวและรักษามวลกล้ามเนื้อ'],
  ['%@ is currently your clearest asset. %@ is the most useful next opportunity, not a failure. APEX will improve it through consistent training, recovery and nutrition signals while preserving what is already strong.', '%@ este acum punctul tău forte. %@ este următoarea oportunitate utilă, nu un eșec. APEX o va îmbunătăți prin antrenament, recuperare și nutriție consecvente, păstrând ceea ce este deja puternic.', '%@ เป็นจุดแข็งที่ชัดที่สุดตอนนี้ %@ คือโอกาสพัฒนาต่อ ไม่ใช่ความล้มเหลว APEX จะช่วยพัฒนาด้วยการฝึก การฟื้นตัว และโภชนาการที่สม่ำเสมอ พร้อมรักษาจุดแข็งเดิมไว้'],
  ['× %d', '× %d', '× %d'],
  ['BEST FIT', 'CEA MAI BUNĂ POTRIVIRE', 'เหมาะที่สุด'],
  ['Brand not specified', 'Marcă nespecificată', 'ไม่ได้ระบุแบรนด์'],
  ['Choose running shoes', 'Alege pantofii de alergare', 'เลือกรองเท้าวิ่ง'],
  ['Complete your first logs to give the Avatar reliable signals.', 'Completează primele înregistrări pentru ca Avatarul să primească semnale fiabile.', 'บันทึกข้อมูลชุดแรกเพื่อให้ Avatar มีข้อมูลที่เชื่อถือได้'],
  ['FINAL', 'FINAL', 'ช่วงสุดท้าย'],
  ['Hydration is still light in the log. Add water progressively, especially around training or physical work.', 'Hidratarea este încă redusă în jurnal. Adaugă apă treptat, mai ales în jurul antrenamentului sau muncii fizice.', 'ข้อมูลการดื่มน้ำยังน้อย ค่อยๆ เติมน้ำ โดยเฉพาะช่วงฝึกหรือทำงานที่ใช้แรง'],
  ['MAX', 'MAX', 'สูงสุด'],
  ['Orbit recorded the available facts without inventing missing heart-rate or cadence data.', 'Orbit a înregistrat datele disponibile fără să inventeze pulsul sau cadența lipsă.', 'Orbit บันทึกเฉพาะข้อมูลที่มี โดยไม่สร้างค่าอัตราการเต้นหัวใจหรือรอบขาที่หายไป'],
  ['Orbit selected a familiar high-carbohydrate food from your private Food Memory. Nothing changes until you confirm it.', 'Orbit a ales un aliment bogat în carbohidrați și familiar din Memoria alimentară privată. Nimic nu se schimbă până nu confirmi.', 'Orbit เลือกอาหารคาร์บสูงที่คุ้นเคยจาก Food Memory ส่วนตัว จะไม่มีการเปลี่ยนแปลงจนกว่าคุณจะยืนยัน'],
  ['PACE –:––', 'RITM –:––', 'เพซ –:––'],
  ['Poster saved to Photos.', 'Afișul a fost salvat în Poze.', 'บันทึกโปสเตอร์ลงในแอปรูปภาพแล้ว'],
  ['Private checkpoint', 'Reper privat', 'จุดบันทึกส่วนตัว'],
  ['The useful work was completed, with pacing details to refine next time.', 'Munca utilă a fost realizată, cu detalii de ritm de ajustat data viitoare.', 'ทำงานที่มีประโยชน์ครบแล้ว ครั้งหน้าค่อยปรับรายละเอียดเพซให้ดีขึ้น'],
  ['This run was harder than the selected mission. Orbit will protect the next demanding session.', 'Această alergare a fost mai grea decât scopul ales. Orbit va proteja următoarea sesiune solicitantă.', 'การวิ่งครั้งนี้หนักกว่าเป้าหมายที่เลือก Orbit จะช่วยป้องกันภาระของการฝึกหนักครั้งถัดไป'],
  ['TRAINING', 'ANTRENAMENT', 'เวลาฝึก'],
  ['Choose the number of sessions and 30, 60, or 90 minutes each.', 'Alege numărul de ședințe și durata de 30, 60 sau 90 de minute pentru fiecare.', 'เลือกจำนวนครั้งและระยะเวลา 30, 60 หรือ 90 นาทีต่อครั้ง'],
  ['Heavier hands-on work with more sustained force.', 'Muncă manuală mai grea, cu forță susținută.', 'งานนวดที่หนักขึ้นและใช้แรงต่อเนื่องมากกว่า'],
  ['Moving while filming with handheld or stabilized camera equipment.', 'Deplasare în timpul filmării cu camera în mână sau pe stabilizator.', 'เคลื่อนไหวขณะถ่ายด้วยกล้องถือหรืออุปกรณ์กันสั่น'],
  ['Standing for a shoot with limited movement.', 'Stat în picioare la filmare, cu mișcare redusă.', 'ยืนถ่ายโดยเคลื่อนไหวน้อย'],
  ['Repositioning, crouching, and moving around the set.', 'Repoziționare, ghemuire și deplasare pe platou.', 'เปลี่ยนตำแหน่ง ย่อตัว และเดินรอบพื้นที่ถ่าย'],
  ['Bags, rig handling, and moving between venues.', 'Genți, manipularea echipamentului și deplasare între locații.', 'ขนกระเป๋า จัดการริก และเดินทางระหว่างสถานที่'],
  ['Covered by the floor. Log it if useful for context, but it adds no calories.', 'Este inclus în baza zilnică. Îl poți înregistra pentru context, dar nu adaugă calorii.', 'รวมอยู่ในค่าพื้นฐานแล้ว บันทึกเพื่อเป็นข้อมูลได้ แต่ไม่เพิ่มแคลอรี'],
  ['Retail, teaching, reception, or another mostly standing shift.', 'Retail, predare, recepție sau altă tură petrecută în mare parte în picioare.', 'งานร้านค้า สอนหนังสือ ต้อนรับ หรืองานกะที่ยืนเป็นส่วนใหญ่'],
  ['A shift with frequent walking and limited sitting.', 'O tură cu mers frecvent și puțin timp așezat.', 'กะที่เดินบ่อยและได้นั่งน้อย'],
  ['Sustained lifting, carrying, digging, or construction work.', 'Ridicare, transport, săpat sau muncă în construcții susținută.', 'ยกของ ขนของ ขุด หรือทำงานก่อสร้างต่อเนื่อง'],
  ['Playing, carrying, chasing, and moving with children.', 'Joacă, purtat, alergat și mișcare împreună cu copiii.', 'เล่น อุ้ม วิ่งตาม และเคลื่อนไหวกับเด็ก'],
  ['Walking the store and carrying groceries. Count 25 minutes per trip.', 'Mers prin magazin și transportul cumpărăturilor. Se numără 25 de minute per drum.', 'เดินในร้านและถือของ คิด 25 นาทีต่อครั้ง'],
  ['Count in 30-minute blocks.', 'Numără în blocuri de 30 de minute.', 'นับเป็นช่วงละ 30 นาที'],
  ['Use time when distance is not known.', 'Folosește timpul când distanța nu este cunoscută.', 'ใช้เวลาเมื่อไม่ทราบระยะทาง'],
  ['Uses 0.5 kcal per kilogram per kilometre.', 'Folosește 0,5 kcal per kilogram per kilometru.', 'ใช้ 0.5 กิโลแคลอรีต่อน้ำหนัก 1 กก. ต่อระยะ 1 กม.'],
  ['Airport walking, queues, and luggage handling.', 'Mers prin aeroport, cozi și manipularea bagajelor.', 'เดินในสนามบิน ยืนคิว และจัดการสัมภาระ'],
  ['Use only steps that are not part of a logged run, walk, shift, or filming block.', 'Folosește doar pașii care nu fac parte dintr-o alergare, plimbare, tură sau filmare deja înregistrată.', 'ใส่เฉพาะก้าวที่ไม่ได้อยู่ในรายการวิ่ง เดิน กะงาน หรือถ่ายทำที่บันทึกไว้แล้ว'],
  ['Short home strength session, usually 15 to 20 minutes.', 'Sesiune scurtă de forță acasă, de obicei 15-20 de minute.', 'ฝึกแรงต้านที่บ้านแบบสั้น ปกติ 15-20 นาที'],
  ['A complete 45 to 60-minute resistance session.', 'O sesiune completă de rezistență de 45-60 de minute.', 'ฝึกแรงต้านเต็มรูปแบบ 45-60 นาที'],
  ['High-intensity interval work.', 'Antrenament cu intervale de intensitate ridicată.', 'การฝึกแบบช่วงหนักสลับพัก'],
  ['Focused mobility, stretching, or corrective work.', 'Mobilitate, stretching sau exerciții corective concentrate.', 'ฝึกความคล่องตัว ยืดเหยียด หรือแก้ไขการเคลื่อนไหว'],
  ['Uses 1 kcal per kilogram per kilometre, independent of pace.', 'Folosește 1 kcal per kilogram per kilometru, indiferent de ritm.', 'ใช้ 1 กิโลแคลอรีต่อน้ำหนัก 1 กก. ต่อระยะ 1 กม. ไม่ขึ้นกับเพซ'],
  ['APEX counts 80% because wrist estimates often run high.', 'APEX ia în calcul 80%, deoarece estimările de la încheietură sunt adesea prea mari.', 'APEX นับ 80% เพราะค่าประมาณจากข้อมือมักสูงเกินจริง'],
]

const translations = rowsTranslations()
for (const [key, value] of tupleTranslations('ACTIVITY_TRANSLATIONS')) translations.set(key, value)
for (const [key, value] of orbitTranslations()) translations.set(key, value)
for (const [english, romanian, thai] of nativeRows) translations.set(english, { ro: romanian, th: thai })
for (const [english, romanian, thai] of nativeContentRows) translations.set(english, { ro: romanian, th: thai })
for (const [english, romanian, thai] of nativeTrainingRows) translations.set(english, { ro: romanian, th: thai })
for (const [english, romanian, thai] of nativeRuntimeGeneralRows) translations.set(english, { ro: romanian, th: thai })
for (const [english, romanian, thai] of nativeRuntimeOrbitRows) translations.set(english, { ro: romanian, th: thai })
for (const [english, romanian, thai] of nativeRuntimeMarathonRows) translations.set(english, { ro: romanian, th: thai })

function escapeStrings(value) {
  return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r')
}

for (const language of ['ro', 'th']) {
  const directory = path.join(nativeResources, `${language}.lproj`)
  fs.mkdirSync(directory, { recursive: true })
  const lines = [...translations.entries()]
    .sort(([left], [right]) => left.localeCompare(right, 'en'))
    .map(([english, values]) => `"${escapeStrings(english)}" = "${escapeStrings(values[language])}";`)
  fs.writeFileSync(path.join(directory, 'Localizable.strings'), `/* Generated from the production web translation corpus. */\n${lines.join('\n')}\n`)
}

const info = {
  NSCameraUsageDescription: {
    ro: 'APEX folosește camera pentru scanarea codurilor de bare și pentru fotografii private de progres.',
    th: 'APEX ใช้กล้องเพื่อสแกนบาร์โค้ดอาหารและถ่ายภาพความก้าวหน้าส่วนตัว',
  },
  NSPhotoLibraryUsageDescription: {
    ro: 'APEX poate importa o fotografie de progres aleasă de tine.',
    th: 'APEX สามารถนำเข้าภาพความก้าวหน้าที่คุณเลือก',
  },
  NSPhotoLibraryAddUsageDescription: {
    ro: 'APEX poate salva afișele traseelor și exporturile de progres pe care le soliciți.',
    th: 'APEX สามารถบันทึกโปสเตอร์เส้นทางและไฟล์ความก้าวหน้าที่คุณขอ',
  },
  NSHealthShareUsageDescription: {
    ro: 'APEX citește datele de sănătate și activitate pe care le alegi pentru a coordona nutriția, recuperarea, Avatarul și Orbit.',
    th: 'APEX อ่านข้อมูลสุขภาพและกิจกรรมที่คุณอนุญาต เพื่อประสานโภชนาการ การฟื้นตัว Avatar และ Orbit',
  },
  NSHealthUpdateUsageDescription: {
    ro: 'APEX scrie antrenamentele finalizate și apa doar când alegi sincronizarea cu Apple Health.',
    th: 'APEX จะเขียนข้อมูลการออกกำลังกายที่เสร็จแล้วและการดื่มน้ำเมื่อคุณเลือกซิงก์กับ Apple Health เท่านั้น',
  },
  NSLocationWhenInUseUsageDescription: {
    ro: 'APEX Orbit folosește locația pentru a înregistra alergări și a planifica trasee cât timp aplicația este deschisă.',
    th: 'APEX Orbit ใช้ตำแหน่งเพื่อบันทึกการวิ่งและวางแผนเส้นทางขณะเปิดแอป',
  },
  NSLocationAlwaysAndWhenInUseUsageDescription: {
    ro: 'APEX Orbit continuă înregistrarea unei alergări active când ecranul este blocat.',
    th: 'APEX Orbit จะบันทึกการวิ่งต่อเมื่อหน้าจอล็อก',
  },
}

for (const language of ['ro', 'th']) {
  const directory = path.join(nativeResources, `${language}.lproj`)
  const lines = Object.entries(info).map(([key, values]) => `"${key}" = "${escapeStrings(values[language])}";`)
  fs.writeFileSync(path.join(directory, 'InfoPlist.strings'), `${lines.join('\n')}\n`)
}

console.log(`Generated ${translations.size} native translations for Romanian and Thai.`)
