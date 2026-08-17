import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case thai = "th"
    case romanian = "ro"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .english: "English"
        case .thai: "ไทย"
        case .romanian: "Română"
        }
    }

    var flag: String {
        switch self {
        case .english: "🇬🇧"
        case .thai: "🇹🇭"
        case .romanian: "🇷🇴"
        }
    }

    var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_GB")
        case .thai: Locale(identifier: "th_TH")
        case .romanian: Locale(identifier: "ro_RO")
        }
    }
}

@Observable
@MainActor
final class LanguageState {
    static let shared = LanguageState()

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "apex.language") }
    }

    private init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "apex.language") ?? "en") ?? .english
    }

    func text(_ key: LocalizedKey) -> String {
        key.value(for: language)
    }

    /// Translates runtime strings such as Supabase-backed programme names,
    /// exercise notes and adaptive coaching copy. SwiftUI localizes static
    /// literals automatically; this path covers content that arrives as data.
    func text(_ value: String) -> String {
        guard language != .english,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return value }
        let exact = bundle.localizedString(forKey: value, value: value, table: "Localizable")
        if exact != value { return exact }
        return translatedRuntimePattern(value) ?? value
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: language.locale,
            arguments: arguments
        )
    }

    func lowercased(_ value: String) -> String {
        text(value).lowercased(with: language.locale)
    }

    func dateKey(_ value: String) -> String {
        guard let date = ISO8601DateFormatter.apexDateOnly.date(from: value) else { return value }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(language.locale))
    }

    /// Campaigns and debriefs intentionally persist canonical English copy so
    /// web and iOS share one contract. This translates the small set of
    /// numeric/date-bearing sentences that cannot use an exact strings key.
    private func translatedRuntimePattern(_ value: String) -> String? {
        if let values = captures(#"^(.+) day: oats ([0-9]+) g instead of ([0-9]+) g\.$"#, in: value) {
            let day = text(values[0])
            return language == .thai
                ? "ระดับ\(day): ปรับข้าวโอ๊ตเป็น \(values[1]) กรัม แทน \(values[2]) กรัม"
                : "Nivel \(day.lowercased(with: language.locale)): \(values[1]) g de ovăz în loc de \(values[2]) g."
        }
        if let values = captures(#"^(.+) day: dry bulgur ([0-9]+) g instead of ([0-9]+) g\.$"#, in: value) {
            let day = text(values[0])
            return language == .thai
                ? "ระดับ\(day): ปรับบัลเกอร์แห้งเป็น \(values[1]) กรัม แทน \(values[2]) กรัม"
                : "Nivel \(day.lowercased(with: language.locale)): \(values[1]) g de bulgur uscat în loc de \(values[2]) g."
        }
        if let values = captures(#"^(.+) day: sweet potato ([0-9]+) g instead of ([0-9]+) g\.$"#, in: value) {
            let day = text(values[0])
            return language == .thai
                ? "ระดับ\(day): ปรับมันหวานเป็น \(values[1]) กรัม แทน \(values[2]) กรัม"
                : "Nivel \(day.lowercased(with: language.locale)): \(values[1]) g de cartof dulce în loc de \(values[2]) g."
        }
        if let values = captures(#"^(.+) day: protein stays pinned; nut mix adjusts to ([0-9]+) g\.$"#, in: value) {
            let day = text(values[0])
            return language == .thai
                ? "ระดับ\(day): โปรตีนคงเดิม และปรับถั่วรวมเป็น \(values[1]) กรัม"
                : "Nivel \(day.lowercased(with: language.locale)): proteina rămâne fixă, iar mixul de nuci se ajustează la \(values[1]) g."
        }
        if let values = captures(#"^(.+) day: casein remains protein-led at ([0-9]+) g\.$"#, in: value) {
            let day = text(values[0])
            return language == .thai
                ? "ระดับ\(day): เคซีนยังเน้นโปรตีนที่ \(values[1]) กรัม"
                : "Nivel \(day.lowercased(with: language.locale)): cazeina rămâne orientată spre proteină la \(values[1]) g."
        }
        if let values = captures(#"^(.+) day: carbohydrate portions move first; protein moves last\.$"#, in: value) {
            let day = text(values[0])
            return language == .thai
                ? "ระดับ\(day): ปรับปริมาณคาร์โบไฮเดรตก่อน และปรับโปรตีนเป็นลำดับสุดท้าย"
                : "Nivel \(day.lowercased(with: language.locale)): porțiile de carbohidrați se modifică primele, iar proteina ultima."
        }
        if let values = captures(#"^Aerobic decoupling was approximately ([0-9.]+)%\.$"#, in: value) {
            return language == .thai
                ? "ความแยกตัวของแอโรบิกประมาณ \(values[0])%"
                : "Decuplarea aerobă a fost de aproximativ \(values[0])%."
        }
        if let values = captures(#"^Optional ([0-9]+) g carbohydrate adjustment around the run\. Review the exact change before applying it\.$"#, in: value) {
            return language == .thai
                ? "ปรับคาร์โบไฮเดรตรอบการวิ่งได้อีก \(values[0]) กรัม โปรดตรวจการเปลี่ยนแปลงก่อนยืนยัน"
                : "Ajustare opțională de \(values[0]) g carbohidrați în jurul alergării. Verifică schimbarea exactă înainte de aplicare."
        }
        if let values = captures(#"^Long-run rehearsal: ([0-9]+) g carbohydrate across familiar pre-run, during-run and recovery foods, plus ([0-9]+) g recovery protein\. Nothing changes until you apply it\.$"#, in: value) {
            return language == .thai
                ? "ซ้อมวิ่งยาว: คาร์โบไฮเดรต \(values[0]) กรัมจากอาหารที่คุ้นเคยก่อนวิ่ง ระหว่างวิ่ง และช่วงฟื้นตัว พร้อมโปรตีนฟื้นตัว \(values[1]) กรัม จะไม่มีอะไรเปลี่ยนจนกว่าคุณจะยืนยัน"
                : "Repetiție pentru alergarea lungă: \(values[0]) g carbohidrați din alimente familiare înainte, în timpul și după alergare, plus \(values[1]) g proteine pentru recuperare. Nimic nu se schimbă până nu aplici."
        }
        if let values = captures(#"^The run carried high recovery cost and the next lower-body session is (.+)\. Orbit proposes protecting that session rather than silently moving it\.$"#, in: value) {
            return language == .thai
                ? "การวิ่งนี้ใช้การฟื้นตัวสูง และการฝึกช่วงล่างครั้งถัดไปคือ \(dateKey(values[0])) Orbit เสนอให้ปกป้องเซสชันนั้นแทนการย้ายโดยไม่บอก"
                : "Alergarea a avut un cost mare de recuperare, iar următoarea sesiune pentru partea inferioară este pe \(dateKey(values[0])). Orbit propune protejarea ei, nu mutarea fără explicație."
        }
        if let values = captures(#"^Orbit contributes ([0-9]+) recorded endurance minutes\. The Avatar receives one authoritative endurance record, not raw GPS points\.$"#, in: value) {
            return language == .thai
                ? "Orbit เพิ่มเวลาความอึดที่บันทึกไว้ \(values[0]) นาที Avatar รับข้อมูลความอึดที่เชื่อถือได้หนึ่งรายการ ไม่ใช่จุด GPS ดิบ"
                : "Orbit adaugă \(values[0]) minute de anduranță înregistrate. Avatarul primește o singură înregistrare autorizată, nu puncte GPS brute."
        }
        if let values = captures(#"^There are ([0-9-]+) days until the race, which is shorter than Orbit’s 12-week marathon-specific block\. Choose a later event or change the objective rather than compressing the progression\.$"#, in: value) {
            return language == .thai
                ? "เหลือ \(values[0]) วันถึงวันแข่ง ซึ่งสั้นกว่าบล็อกเฉพาะมาราธอน 12 สัปดาห์ของ Orbit ควรเลือกรายการที่ช้ากว่าหรือเปลี่ยนเป้าหมายแทนการบีบแผน"
                : "Mai sunt \(values[0]) zile până la cursă, mai puțin decât blocul Orbit de 12 săptămâni. Alege un eveniment mai târziu sau schimbă obiectivul, în loc să comprimi progresia."
        }
        if let values = captures(#"^The race is ([0-9-]+) days away, but a credible Foundation plus marathon-specific journey needs approximately ([0-9]+) days\. A later race is recommended\.$"#, in: value) {
            return language == .thai
                ? "เหลือ \(values[0]) วันถึงวันแข่ง แต่เส้นทางพื้นฐานต่อด้วยแผนเฉพาะมาราธอนที่สมเหตุสมผลต้องใช้ราว \(values[1]) วัน แนะนำให้เลือกรายการที่ช้ากว่า"
                : "Cursa este peste \(values[0]) zile, dar o fundație credibilă urmată de pregătirea specifică necesită aproximativ \(values[1]) zile. Se recomandă o cursă mai târziu."
        }
        if let values = captures(#"^Foundation to First Marathon was selected because the recent base is below the marathon-specific gate: ([0-9]+) run days per week, approximately ([0-9]+) km per week and a longest recent run near ([0-9]+) km\.$"#, in: value) {
            return language == .thai
                ? "เลือกแผนจากพื้นฐานสู่มาราธอนแรก เพราะฐานล่าสุดยังไม่ถึงเกณฑ์เฉพาะมาราธอน: วิ่ง \(values[0]) วันต่อสัปดาห์ ราว \(values[1]) กม.ต่อสัปดาห์ และวิ่งยาวล่าสุดประมาณ \(values[2]) กม."
                : "A fost ales traseul De la bază la primul maraton deoarece baza recentă este sub pragul specific: \(values[0]) zile de alergare pe săptămână, aproximativ \(values[1]) km pe săptămână și o alergare lungă recentă de aproape \(values[2]) km."
        }
        if let values = captures(#"^([0-9]+) campaign sessions are recorded as completed\.$"#, in: value) {
            return language == .thai ? "บันทึกว่าเสร็จแล้ว \(values[0]) เซสชันตามแผน" : "Sunt înregistrate \(values[0]) sesiuni de campanie finalizate."
        }
        if let values = captures(#"^([0-9]+) recent long runs are available for comparison\.$"#, in: value) {
            return language == .thai ? "มีการวิ่งยาวล่าสุด \(values[0]) ครั้งให้เปรียบเทียบ" : "Sunt disponibile \(values[0]) alergări lungi recente pentru comparație."
        }
        if let values = captures(#"^([0-9]+) recent runs were completed at controlled perceived effort\.$"#, in: value) {
            return language == .thai ? "การวิ่งล่าสุด \(values[0]) ครั้งเสร็จด้วยระดับแรงที่ควบคุมได้" : "\(values[0]) alergări recente au fost finalizate cu efort perceput controlat."
        }
        if let values = captures(#"^([0-9]+) long-run notes mention fueling practice\.$"#, in: value) {
            return language == .thai ? "บันทึกวิ่งยาว \(values[0]) รายการกล่าวถึงการซ้อมเติมพลัง" : "\(values[0]) note de alergare lungă menționează practica alimentării."
        }
        if let values = captures(#"^([0-9]+) minutes at controlled marathon effort inside the session\.$"#, in: value) {
            return language == .thai ? "วิ่งที่แรงระดับมาราธอนแบบคุมได้ \(values[0]) นาทีภายในเซสชัน" : "\(values[0]) minute la efort de maraton controlat în cadrul sesiunii."
        }
        if let values = captures(#"^([0-9]+) minutes at comfortably hard, controlled effort\.$"#, in: value) {
            return language == .thai ? "วิ่งหนักแบบยังคุมได้ \(values[0]) นาที" : "\(values[0]) minute la un efort susținut, dar controlat."
        }
        if let values = captures(#"^3 controlled blocks of ([0-9]+) minutes with easy recovery\.$"#, in: value) {
            return language == .thai ? "3 ช่วง ช่วงละ \(values[0]) นาทีแบบคุมแรง คั่นด้วยการพักเบา" : "3 blocuri controlate de câte \(values[0]) minute, cu recuperare ușoară."
        }
        if let values = captures(#"^(.+) phase · (.+) campaign · placed to preserve recovery around demanding work\.$"#, in: value) {
            let phase = text(values[0].replacingOccurrences(of: "_", with: " ").capitalized)
            let family = text(values[1].replacingOccurrences(of: "_", with: " ").capitalized)
            return language == .thai
                ? "ช่วง \(phase) · แผน \(family) · จัดตำแหน่งเพื่อรักษาการฟื้นตัวรอบงานหนัก"
                : "Faza \(phase) · campania \(family) · plasată pentru a proteja recuperarea în jurul efortului solicitant."
        }
        if let values = captures(#"^(.+) moved from ([0-9-]+) to ([0-9-]+) because (.+) occupies the original date\. The original prescription remains visible\.$"#, in: value) {
            let title = text(values[0])
            return language == .thai
                ? "ย้าย \(title) จาก \(dateKey(values[1])) ไป \(dateKey(values[2])) เพราะ \(values[3]) อยู่ในวันเดิม แผนเดิมยังมองเห็นได้"
                : "\(title) a fost mutată din \(dateKey(values[1])) în \(dateKey(values[2])) deoarece \(values[3]) ocupă data inițială. Planul original rămâne vizibil."
        }
        return nil
    }

    private func captures(_ pattern: String, in value: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ),
              match.range.location != NSNotFound
        else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }
}

enum LocalizedKey {
    case chooseLanguage
    case chooseWhoEnters
    case swipeToRotate
    case enterApex
    case signIn
    case email
    case password
    case back
    case nutrition
    case transition
    case mainPhase
    case orbit
    case settings
    case profiles
    case logoutWarning
    case cancel
    case yesLogout
    case mealsSupplementsLog
    case currentProgram
    case eliteProgram
    case runIntelligence
    case statsBodyNeeds
    case today

    func value(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.chooseLanguage, .english): "Choose your language"
        case (.chooseLanguage, .thai): "เลือกภาษาของคุณ"
        case (.chooseLanguage, .romanian): "Alege limba"
        case (.chooseWhoEnters, .english): "Choose who enters APEX"
        case (.chooseWhoEnters, .thai): "เลือกผู้ที่จะเข้าสู่ APEX"
        case (.chooseWhoEnters, .romanian): "Alege cine intră în APEX"
        case (.swipeToRotate, .english): "Swipe to rotate · tap to select"
        case (.swipeToRotate, .thai): "ปัดเพื่อหมุน · แตะเพื่อเลือก"
        case (.swipeToRotate, .romanian): "Glisează pentru rotire · apasă pentru selectare"
        case (.enterApex, .english): "Enter APEX"
        case (.enterApex, .thai): "เข้าสู่ APEX"
        case (.enterApex, .romanian): "Intră în APEX"
        case (.signIn, .english): "Sign in"
        case (.signIn, .thai): "เข้าสู่ระบบ"
        case (.signIn, .romanian): "Autentificare"
        case (.email, .english): "Email"
        case (.email, .thai): "อีเมล"
        case (.email, .romanian): "E-mail"
        case (.password, .english): "Password"
        case (.password, .thai): "รหัสผ่าน"
        case (.password, .romanian): "Parolă"
        case (.back, .english): "Back"
        case (.back, .thai): "กลับ"
        case (.back, .romanian): "Înapoi"
        case (.nutrition, .english): "Nutrition"
        case (.nutrition, .thai): "โภชนาการ"
        case (.nutrition, .romanian): "Nutriție"
        case (.transition, .english): "Transition Phase"
        case (.transition, .thai): "ช่วงเปลี่ยนผ่าน"
        case (.transition, .romanian): "Faza de tranziție"
        case (.mainPhase, .english): "Main Phase"
        case (.mainPhase, .thai): "ช่วงหลัก"
        case (.mainPhase, .romanian): "Faza principală"
        case (.orbit, .english): "APEX Orbit"
        case (.orbit, .thai): "APEX Orbit"
        case (.orbit, .romanian): "APEX Orbit"
        case (.settings, .english): "Settings"
        case (.settings, .thai): "การตั้งค่า"
        case (.settings, .romanian): "Setări"
        case (.profiles, .english): "Profiles"
        case (.profiles, .thai): "โปรไฟล์"
        case (.profiles, .romanian): "Profiluri"
        case (.logoutWarning, .english): "You are about to log out. Are you sure?"
        case (.logoutWarning, .thai): "คุณกำลังจะออกจากระบบ ยืนยันหรือไม่"
        case (.logoutWarning, .romanian): "Urmează să te deconectezi. Ești sigur?"
        case (.cancel, .english): "Cancel"
        case (.cancel, .thai): "ยกเลิก"
        case (.cancel, .romanian): "Anulează"
        case (.yesLogout, .english): "Yes, log out"
        case (.yesLogout, .thai): "ใช่ ออกจากระบบ"
        case (.yesLogout, .romanian): "Da, deconectează-mă"
        case (.mealsSupplementsLog, .english): "Meals, supplement stack, daily log"
        case (.mealsSupplementsLog, .thai): "มื้ออาหาร อาหารเสริม และบันทึกประจำวัน"
        case (.mealsSupplementsLog, .romanian): "Mese, suplimente și jurnal zilnic"
        case (.currentProgram, .english): "Current programme, home training"
        case (.currentProgram, .thai): "โปรแกรมปัจจุบัน ฝึกที่บ้าน"
        case (.currentProgram, .romanian): "Programul actual, antrenament acasă"
        case (.eliteProgram, .english): "Elite programme, ready when you are"
        case (.eliteProgram, .thai): "โปรแกรมระดับสูง พร้อมเมื่อคุณพร้อม"
        case (.eliteProgram, .romanian): "Program avansat, pregătit când ești și tu"
        case (.runIntelligence, .english): "Run intelligence and marathon conditioning"
        case (.runIntelligence, .thai): "ระบบวิ่งอัจฉริยะและเตรียมมาราธอน"
        case (.runIntelligence, .romanian): "Inteligență pentru alergare și pregătire de maraton"
        case (.statsBodyNeeds, .english): "Stats, level and what your body needs"
        case (.statsBodyNeeds, .thai): "สถิติ ระดับ และสิ่งที่ร่างกายต้องการ"
        case (.statsBodyNeeds, .romanian): "Statistici, nivel și ce are nevoie corpul tău"
        case (.today, .english): "Today"
        case (.today, .thai): "วันนี้"
        case (.today, .romanian): "Astăzi"
        }
    }
}

struct PortalLanguagePicker: View {
    @State private var state = LanguageState.shared

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { state.language = language }
                } label: {
                    Text("\(language.flag)  \(language.nativeName)")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(state.language.flag)
                Text(state.language.nativeName)
                    .font(APEXFont.body(13, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(APEXColor.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(.white.opacity(0.65), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.85)))
        }
    }
}
