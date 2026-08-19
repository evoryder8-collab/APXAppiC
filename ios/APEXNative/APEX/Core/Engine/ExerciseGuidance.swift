import Foundation

/*
 * Port of src/lib/exerciseGuidance.ts.
 *
 * One execution cue per exercise, matched by name. The list is ordered and
 * first match wins, so a specific movement must always be tested before the
 * generic one it contains: "leg curl" contains "curl", "bulgarian split
 * squat" contains "squat".
 */
enum ExerciseGuidance {
    struct Cue: Sendable {
        let pattern: String
        let en: String
        let ro: String
        let th: String

        func text(_ language: AppLanguage) -> String {
            switch language {
            case .english: en
            case .romanian: ro
            case .thai: th
            }
        }
    }

    static let cues: [Cue] = [
        Cue(
            pattern: "focus\\s*t25",
            en: "Follow the episode on screen. Choose the modifier whenever form or breathing starts to break down. A completed modifier version still counts as a completed session.",
            ro: "Urmează episodul de pe ecran. Folosește varianta modificată când tehnica sau respirația se deteriorează. O sesiune terminată cu modificatorul rămâne o sesiune completă.",
            th: "ทำตามตอนบนหน้าจอ เลือกท่าปรับง่ายเมื่อฟอร์มหรือการหายใจเริ่มเสีย การทำจนจบด้วยท่าปรับง่ายยังนับว่าเสร็จสมบูรณ์"
        ),
        Cue(
            pattern: "bulgarian|split[\\s-]?squat|fandare.*bulgar",
            en: "Set the rear foot comfortably, keep the front foot fully planted and lower under control. Drive through the whole front foot without letting the knee collapse inward.",
            ro: "Așază piciorul din spate confortabil, păstrează toată talpa din față pe sol și coboară controlat. Împinge prin toată talpa fără ca genunchiul să cadă spre interior.",
            th: "วางเท้าหลังให้สบาย เท้าหน้าวางเต็มพื้น ลดตัวอย่างควบคุม แล้วดันผ่านเท้าหน้าทั้งฝ่าเท้าโดยไม่ให้เข่ายุบเข้าด้านใน"
        ),
        Cue(
            pattern: "romanian deadlift|\\brdl\\b|îndreptări românești|ยกเดดลิฟต์โรมาเนีย",
            en: "Keep the weight close, soften the knees and push the hips back until the hamstrings are loaded. Keep the spine long and finish by standing tall, not by leaning back.",
            ro: "Ține greutatea aproape, genunchii ușor flexați și împinge șoldurile înapoi până simți femuralii. Menține coloana lungă și termină drept, fără să te lași pe spate.",
            th: "ให้น้ำหนักอยู่ใกล้ตัว งอเข่าเล็กน้อย ดันสะโพกไปด้านหลังจนรู้สึกตึงเอ็นหลังเข่า รักษาหลังเป็นกลางและยืนตรงโดยไม่แอ่นหลัง"
        ),
        Cue(
            pattern: "hip thrust|glute bridge|frog pump|împins.*șold|สะพานก้น|ฮิปทรัสต์",
            en: "Brace the ribs down, drive through the feet and finish with the glutes. Stop when the hips are fully extended without arching the lower back.",
            ro: "Ține coastele coborâte, împinge prin tălpi și finalizează din fesieri. Oprește când șoldurile sunt complet extinse, fără să arcuiești zona lombară.",
            th: "เก็บซี่โครง ดันผ่านเท้าและบีบก้น หยุดเมื่อสะโพกเหยียดสุดโดยไม่แอ่นหลังส่วนล่าง"
        ),
        Cue(
            pattern: "lunge|fandare|ก้าวย่อ",
            en: "Step to a stable stance, lower with control and keep the working knee tracking over the toes. Push the floor away to return.",
            ro: "Pășește într-o poziție stabilă, coboară controlat și lasă genunchiul să urmărească direcția degetelor. Împinge podeaua pentru revenire.",
            th: "ก้าวให้มั่นคง ลดตัวอย่างควบคุม ให้เข่าไปทิศเดียวกับปลายเท้า แล้วดันพื้นเพื่อกลับขึ้น"
        ),
        Cue(
            pattern: "calf|gambe|น่อง",
            en: "Use the full comfortable ankle range. Pause briefly at the top and lower slowly without bouncing.",
            ro: "Folosește toată amplitudinea confortabilă a gleznei. Oprește scurt sus și coboară lent, fără balans.",
            th: "ใช้ช่วงการเคลื่อนไหวข้อเท้าที่สบาย หยุดสั้น ๆ ด้านบนและลดลงช้า ๆ โดยไม่เด้ง"
        ),
        Cue(
            pattern: "pull[\\s-]?up|chin[\\s-]?up|dead hang|tracți|โหน|ดึงข้อ",
            en: "Start from a controlled shoulder position, keep the ribs stacked and pull without swinging. Stop before grip or shoulder position becomes unsafe.",
            ro: "Pornește cu umerii controlați, coastele aliniate și trage fără balans. Oprește înainte ca priza sau poziția umărului să devină nesigură.",
            th: "เริ่มด้วยหัวไหล่ที่ควบคุม เก็บลำตัวตรงและดึงโดยไม่เหวี่ยง หยุดก่อนที่แรงจับหรือหัวไหล่จะเสียตำแหน่ง"
        ),
        Cue(
            pattern: "row|ramat|ดึง.*พาย|แมชชีนโรว์",
            en: "Brace the torso, lead with the elbows and pull toward the lower ribs. Let the shoulder blades move naturally without shrugging.",
            ro: "Stabilizează trunchiul, conduce cu coatele și trage spre coastele inferioare. Lasă omoplații să se miște natural, fără să ridici umerii.",
            th: "ตรึงลำตัว นำด้วยศอก ดึงเข้าหาซี่โครงล่าง ให้สะบักเคลื่อนไหวตามธรรมชาติโดยไม่ยกไหล่"
        ),
        Cue(
            pattern: "push[\\s-]?up|press|împins|flotări|วิดพื้น|เพรส",
            en: "Keep the body braced, lower through a pain-free range and press while keeping the shoulders away from the ears. Maintain steady wrist and elbow alignment.",
            ro: "Ține corpul stabil, coboară într-o amplitudine fără durere și împinge păstrând umerii departe de urechi. Menține încheieturile și coatele aliniate.",
            th: "เกร็งลำตัว ลดตัวในช่วงที่ไม่เจ็บ และดันโดยไม่ยกไหล่เข้าหาหู รักษาข้อมือกับศอกให้มั่นคง"
        ),
        Cue(
            pattern: "face pull|band pull|pull-apart|tragere.*band|ยางยืด",
            en: "Keep the ribs quiet and pull with the upper back. Finish with the hands apart and shoulders down rather than forcing extra range.",
            ro: "Ține coastele stabile și trage din partea superioară a spatelui. Termină cu mâinile depărtate și umerii jos, fără să forțezi amplitudinea.",
            th: "ตรึงซี่โครง ดึงด้วยหลังส่วนบน จบด้วยมือแยกออกและไหล่ต่ำ โดยไม่ฝืนช่วงการเคลื่อนไหว"
        ),
        Cue(
            pattern: "leg curl|flexii femurali|งอขา",
            en: "Keep the hips anchored, curl smoothly and squeeze briefly without lifting the pelvis. Return slowly.",
            ro: "Ține șoldurile fixate, flexează lin și contractă scurt fără să ridici bazinul. Revino lent.",
            th: "ตรึงสะโพก งอขาอย่างนุ่มนวล บีบสั้น ๆ โดยไม่ยกเชิงกราน แล้วกลับช้า ๆ"
        ),
        Cue(
            pattern: "curl|flexii|ciocan|ไบเซป|เคิร์ล",
            en: "Keep the upper arm stable and curl without using momentum. Lower under control through the comfortable elbow range.",
            ro: "Ține brațul superior stabil și flexează fără impuls. Coboară controlat în amplitudinea confortabilă a cotului.",
            th: "ตรึงต้นแขน งอศอกโดยไม่เหวี่ยง และลดน้ำหนักอย่างควบคุมในช่วงที่ข้อศอกสบาย"
        ),
        Cue(
            pattern: "bird dog|side plank|plank|wall slide|mobil|stretch|posture|planș|แพลงก์|ยืด",
            en: "Move only through the range you can control while breathing normally. Keep the trunk quiet and stop if the movement causes sharp pain.",
            ro: "Mișcă-te doar în amplitudinea pe care o poți controla, respirând normal. Menține trunchiul stabil și oprește-te dacă apare durere ascuțită.",
            th: "เคลื่อนไหวเฉพาะช่วงที่ควบคุมได้พร้อมหายใจตามปกติ รักษาลำตัวให้นิ่งและหยุดหากมีอาการเจ็บแปลบ"
        ),
        Cue(
            pattern: "squat|genuflex|สควอต",
            en: "Set a stable foot position, brace before descending and keep the knees tracking with the toes. Use the deepest pain-free range you can control.",
            ro: "Așază tălpile stabil, încordează trunchiul înainte de coborâre și aliniază genunchii cu degetele. Folosește cea mai adâncă amplitudine fără durere pe care o controlezi.",
            th: "วางเท้าให้มั่นคง เกร็งลำตัวก่อนลง ให้เข่าไปทิศเดียวกับปลายเท้า และใช้ช่วงลึกที่สุดที่ควบคุมได้โดยไม่เจ็บ"
        ),
    ]

    static let fallback = Cue(
        pattern: "",
        en: "Use a controlled, pain-free range with stable alignment. Follow the prescribed tempo, stop on sharp pain and leave the planned repetitions in reserve.",
        ro: "Folosește o amplitudine controlată, fără durere și cu aliniere stabilă. Respectă tempoul, oprește-te la durere ascuțită și păstrează repetările prescrise în rezervă.",
        th: "ใช้ช่วงการเคลื่อนไหวที่ควบคุมได้และไม่เจ็บ รักษาแนวร่างกาย ทำตามจังหวะ หยุดเมื่อเจ็บแปลบ และเหลือจำนวนครั้งตามแผน"
    )

    /// The cue for an exercise, or the general one when nothing matches.
    static func executionCue(_ name: String, language: AppLanguage) -> String {
        let match = cues.first { cue in
            name.range(of: cue.pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return (match ?? fallback).text(language)
    }
}
