# Premium Information Hierarchy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Deliver a consistent identity card, the requested Simple and Avatar ordering, and a premium inline Fitness Plan disclosure with account-persistent first-view guidance.

**Architecture:** Keep all existing routes and domain data intact. Add small pure disclosure-state contracts on native and web, then compose the new disclosure from existing portal destinations and settings persistence. Treat the remaining requests as presentation-order changes guarded by source contracts and one pure web legacy-order migration.

**Tech Stack:** Swift 6.2, SwiftUI, XCTest, TypeScript 7, React 19, Framer Motion, Node test runner, Vite, existing APEX offline settings outboxes.

**Spec:** docs/superpowers/specs/2026-08-28-premium-information-hierarchy-design.md

## Global Constraints

- Preserve every existing destination, installed plan, recovery path, workout history, camera privacy rule, and account-owned record.
- Do not add third-party frameworks.
- Use the existing settings add-ons key fitness_plan_intro_seen; do not add a table or schema migration.
- First expansion shows both subtitles for that whole expansion; later expansions show information controls; never show both at once.
- Persist seen only after both introductory cards have completed their reveal.
- Native copy must be authored in English, Romanian, Thai, Japanese, German, Swiss German, Spanish, Portuguese, and Italian.
- Web copy must cover every language offered by its selector.
- Every new string in a width-constrained control must have an authored LocalizableShort.strings value in all nine native languages.
- Do not use minimumScaleFactor; tests enforce the repository Dynamic Type layout contract.
- Respect Reduce Motion, use touch targets of at least 44 points, and expose expanded/collapsed state to assistive technology.
- Write tests before implementation, append the completed result to docs/REPAIR-NOTES.md, push both required refs, confirm GitHub Pages, install the final signed device build, then pause.

## File map

- ios/APEXNative/APEX/Features/Portal/PortalUIMode.swift: pure native disclosure state and existing Simple logic.
- ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift: Advanced ordering and premium native disclosure UI.
- ios/APEXNative/APEX/Features/Settings/SettingsView.swift: native identity hierarchy and persona-duplication rule.
- ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift: native quick-action placement.
- ios/APEXNative/APEX/Features/Avatar/AvatarView.swift: native Visual Progress placement.
- ios/APEXNative/APEXTests/SimpleHomeLogicTests.swift: native state and identity unit regressions.
- ios/APEXNative/APEXTests/LocalisationCoverageTests.swift: compact-table count and required-key contract.
- ios/APEXNative/APEX/Resources/*.lproj/Localizable.strings: authored full native copy.
- ios/APEXNative/APEX/Resources/*.lproj/LocalizableShort.strings: authored compact native copy.
- src/lib/fitnessPlanDisclosure.ts: pure web disclosure reducer.
- src/lib/simpleBlockOrder.ts: canonical/default Simple order and exact legacy-stock migration.
- src/lib/profileIdentity.ts: web duplicate-persona decision.
- src/components/FitnessPlanDisclosure.tsx: premium inline web disclosure UI.
- src/pages/Portal.tsx: Advanced ordering and disclosure composition.
- src/pages/Settings.tsx: web identity hierarchy.
- src/pages/SimpleHome.tsx: consume the extracted Simple order resolver.
- src/lib/types.ts: additive settings add-on flag.
- src/lib/translations.ts: Romanian and Thai web copy.
- tests/portal-information-hierarchy.test.ts: web behavior and native/web source contracts.

---

### Task 1: Cross-platform Fitness Plan disclosure state

**Files:**
- Modify: ios/APEXNative/APEX/Features/Portal/PortalUIMode.swift
- Modify: ios/APEXNative/APEXTests/SimpleHomeLogicTests.swift
- Create: src/lib/fitnessPlanDisclosure.ts
- Modify: src/lib/types.ts
- Create: tests/portal-information-hierarchy.test.ts

**Interfaces:**
- Produces native FitnessPlanPhase and FitnessPlanDisclosureState.
- Produces web FitnessPlanPhase, FitnessPlanDisclosureState, toggleFitnessPlanDisclosure(), recordFitnessPlanIntroPresentation(), and selectFitnessPlanInfo().
- Produces settings.addons.fitness_plan_intro_seen?: boolean.

- [ ] **Step 1: Write failing native state tests**

Append these XCTest cases to SimpleHomeLogicTests:

~~~swift
func testFitnessPlanFirstRevealKeepsGuidanceAndPersistsOnlyAfterBothCardsAppear() {
    var state = FitnessPlanDisclosureState()

    state.toggle(introSeen: false)
    XCTAssertTrue(state.isExpanded)
    XCTAssertTrue(state.showsIntroduction)
    XCTAssertFalse(state.showsInfoControls)
    XCTAssertFalse(state.recordIntroductionPresented(for: .transition))
    XCTAssertTrue(state.recordIntroductionPresented(for: .main))
    XCTAssertFalse(state.recordIntroductionPresented(for: .main), "seen persistence is one-shot")
    XCTAssertTrue(state.showsIntroduction, "persisting seen must not replace this visit's subtitles")
    XCTAssertFalse(state.showsInfoControls)
}

func testFitnessPlanLaterRevealUsesInformationControlsAndCollapseClearsTransientState() {
    var state = FitnessPlanDisclosureState()

    state.toggle(introSeen: true)
    XCTAssertTrue(state.showsInfoControls)
    XCTAssertFalse(state.showsIntroduction)
    state.selectInfo(.transition)
    XCTAssertEqual(state.activeInfo, .transition)

    state.toggle(introSeen: true)
    XCTAssertFalse(state.isExpanded)
    XCTAssertNil(state.activeInfo)
    XCTAssertFalse(state.recordIntroductionPresented(for: .main))
}
~~~

- [ ] **Step 2: Write failing web state tests**

Create portal-information-hierarchy.test.ts with:

~~~typescript
import assert from 'node:assert/strict'
import test from 'node:test'
import {
  collapsedFitnessPlanDisclosure,
  recordFitnessPlanIntroPresentation,
  selectFitnessPlanInfo,
  toggleFitnessPlanDisclosure,
} from '../src/lib/fitnessPlanDisclosure.ts'

test('first Fitness Plan reveal keeps both subtitles and persists seen only after both cards appear', () => {
  let state = toggleFitnessPlanDisclosure(collapsedFitnessPlanDisclosure(), false)
  assert.equal(state.expanded, true)
  assert.equal(state.showsIntroduction, true)
  assert.equal(state.showsInfoControls, false)

  let result = recordFitnessPlanIntroPresentation(state, 'transition')
  assert.equal(result.shouldPersistSeen, false)
  result = recordFitnessPlanIntroPresentation(result.state, 'main')
  assert.equal(result.shouldPersistSeen, true)
  result = recordFitnessPlanIntroPresentation(result.state, 'main')
  assert.equal(result.shouldPersistSeen, false)
  assert.equal(result.state.showsIntroduction, true)
  assert.equal(result.state.showsInfoControls, false)
})

test('later Fitness Plan reveals use one information tooltip and collapse clears it', () => {
  let state = toggleFitnessPlanDisclosure(collapsedFitnessPlanDisclosure(), true)
  assert.equal(state.showsIntroduction, false)
  assert.equal(state.showsInfoControls, true)
  state = selectFitnessPlanInfo(state, 'main')
  assert.equal(state.activeInfo, 'main')
  state = toggleFitnessPlanDisclosure(state, true)
  assert.deepEqual(state, collapsedFitnessPlanDisclosure())
})
~~~

- [ ] **Step 3: Run both focused tests and confirm red**

Run:

~~~bash
node --test --test-force-exit --test-isolation=none tests/portal-information-hierarchy.test.ts
xcodebuild -quiet -project ios/APEXNative/APEXNative.xcodeproj -scheme APEX -destination 'platform=iOS Simulator,id=6907359A-18D1-46B0-87F1-13CED5CE1C46' -derivedDataPath build/codex-portal-hierarchy -only-testing:APEXTests/SimpleHomeLogicTests test
~~~

Expected: web fails because fitnessPlanDisclosure.ts does not exist; native fails because FitnessPlanDisclosureState is undefined.

- [ ] **Step 4: Implement the native state contract**

Add to PortalUIMode.swift above SimpleHomeLogic:

~~~swift
enum FitnessPlanPhase: String, CaseIterable, Hashable, Sendable {
    case transition
    case main
}

struct FitnessPlanDisclosureState: Equatable, Sendable {
    private(set) var isExpanded = false
    private(set) var showsIntroduction = false
    private(set) var presentedIntroductionPhases: Set<FitnessPlanPhase> = []
    private(set) var activeInfo: FitnessPlanPhase?

    var showsInfoControls: Bool { isExpanded && !showsIntroduction }

    mutating func toggle(introSeen: Bool) {
        if isExpanded {
            self = Self()
            return
        }
        isExpanded = true
        showsIntroduction = !introSeen
        presentedIntroductionPhases = []
        activeInfo = nil
    }

    mutating func recordIntroductionPresented(for phase: FitnessPlanPhase) -> Bool {
        guard isExpanded, showsIntroduction else { return false }
        let wasComplete = presentedIntroductionPhases == Set(FitnessPlanPhase.allCases)
        presentedIntroductionPhases.insert(phase)
        return !wasComplete && presentedIntroductionPhases == Set(FitnessPlanPhase.allCases)
    }

    mutating func selectInfo(_ phase: FitnessPlanPhase?) {
        guard showsInfoControls else {
            activeInfo = nil
            return
        }
        activeInfo = activeInfo == phase ? nil : phase
    }
}
~~~

- [ ] **Step 5: Implement the web reducer and settings type**

Create fitnessPlanDisclosure.ts:

~~~typescript
export type FitnessPlanPhase = 'transition' | 'main'

export interface FitnessPlanDisclosureState {
  expanded: boolean
  showsIntroduction: boolean
  showsInfoControls: boolean
  presentedIntroductionPhases: FitnessPlanPhase[]
  activeInfo: FitnessPlanPhase | null
}

export interface FitnessPlanIntroPresentationResult {
  state: FitnessPlanDisclosureState
  shouldPersistSeen: boolean
}

export function collapsedFitnessPlanDisclosure(): FitnessPlanDisclosureState {
  return {
    expanded: false,
    showsIntroduction: false,
    showsInfoControls: false,
    presentedIntroductionPhases: [],
    activeInfo: null,
  }
}

export function toggleFitnessPlanDisclosure(
  state: FitnessPlanDisclosureState,
  introSeen: boolean,
): FitnessPlanDisclosureState {
  if (state.expanded) return collapsedFitnessPlanDisclosure()
  return {
    expanded: true,
    showsIntroduction: !introSeen,
    showsInfoControls: introSeen,
    presentedIntroductionPhases: [],
    activeInfo: null,
  }
}

export function recordFitnessPlanIntroPresentation(
  state: FitnessPlanDisclosureState,
  phase: FitnessPlanPhase,
): FitnessPlanIntroPresentationResult {
  if (!state.expanded || !state.showsIntroduction) {
    return { state, shouldPersistSeen: false }
  }
  const phases = Array.from(new Set([...state.presentedIntroductionPhases, phase]))
  return {
    state: { ...state, presentedIntroductionPhases: phases },
    shouldPersistSeen: state.presentedIntroductionPhases.length < 2 && phases.length === 2,
  }
}

export function selectFitnessPlanInfo(
  state: FitnessPlanDisclosureState,
  phase: FitnessPlanPhase | null,
): FitnessPlanDisclosureState {
  if (!state.showsInfoControls) return { ...state, activeInfo: null }
  return { ...state, activeInfo: state.activeInfo === phase ? null : phase }
}
~~~

Add this optional property beside simple_block_order in src/lib/types.ts:

~~~typescript
fitness_plan_intro_seen?: boolean
~~~

- [ ] **Step 6: Run focused tests and confirm green**

Run the two Step 3 commands.

Expected: both focused suites pass.

- [ ] **Step 7: Commit the state contract**

~~~bash
git add ios/APEXNative/APEX/Features/Portal/PortalUIMode.swift ios/APEXNative/APEXTests/SimpleHomeLogicTests.swift src/lib/fitnessPlanDisclosure.ts src/lib/types.ts tests/portal-information-hierarchy.test.ts
git commit -m 'Add Fitness Plan disclosure state contract'
~~~

---

### Task 2: Premium Advanced disclosure, ordering, and authored copy

**Files:**
- Modify: ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift
- Modify: ios/APEXNative/APEXTests/LocalisationCoverageTests.swift
- Modify: ios/APEXNative/APEX/Resources/de-CH.lproj/Localizable.strings
- Modify: ios/APEXNative/APEX/Resources/de.lproj/Localizable.strings
- Modify: ios/APEXNative/APEX/Resources/es.lproj/Localizable.strings
- Modify: ios/APEXNative/APEX/Resources/it.lproj/Localizable.strings
- Modify: ios/APEXNative/APEX/Resources/ja.lproj/Localizable.strings
- Modify: ios/APEXNative/APEX/Resources/pt.lproj/Localizable.strings
- Modify: ios/APEXNative/APEX/Resources/ro.lproj/Localizable.strings
- Modify: ios/APEXNative/APEX/Resources/th.lproj/Localizable.strings
- Modify: all nine ios/APEXNative/APEX/Resources/*.lproj/LocalizableShort.strings files
- Create: src/components/FitnessPlanDisclosure.tsx
- Modify: src/pages/Portal.tsx
- Modify: src/lib/translations.ts
- Modify: tests/portal-information-hierarchy.test.ts

**Interfaces:**
- Consumes the Task 1 native and web disclosure contracts.
- Uses the existing native AppSession.updateSettings() and web setSettings() optimistic outboxes.
- Produces accessibility identifiers portal.fitness-plan, portal.transition, portal.main, fitness-plan.info.transition, and fitness-plan.info.main.

- [ ] **Step 1: Add failing source-order and persistence contracts**

Append to portal-information-hierarchy.test.ts:

~~~typescript
import { readFileSync } from 'node:fs'

test('Advanced leads with Avatar and groups both phase routes under Fitness Plan', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift', import.meta.url), 'utf8')
  const web = readFileSync(new URL('../src/pages/Portal.tsx', import.meta.url), 'utf8')
  const webDisclosure = readFileSync(new URL('../src/components/FitnessPlanDisclosure.tsx', import.meta.url), 'utf8')

  assert.ok(native.indexOf('ProfilePortalTile()') < native.indexOf('title: language.text(.nutrition)'))
  assert.ok(native.indexOf('title: language.text(.nutrition)') < native.indexOf('FitnessPlanDisclosure'))
  assert.doesNotMatch(native, /PortalTile\([\s\S]{0,180}destination: \.transition[\s\S]{0,260}PortalTile\([\s\S]{0,180}destination: \.mainPhase/)

  assert.ok(web.indexOf('to="/avatar"') < web.indexOf('to="/nutrition"'))
  assert.ok(web.indexOf('to="/nutrition"') < web.indexOf('<FitnessPlanDisclosure'))
  assert.match(web, /slug === 'custom'[\s\S]*to="\/custom-workouts"/)
  assert.match(webDisclosure, /navigate\('\/transition'\)/)
  assert.match(webDisclosure, /navigate\('\/main-phase'\)/)
  assert.match(webDisclosure, /fitness_plan_intro_seen/)
  assert.match(webDisclosure, /showsIntroduction[\s\S]*showsInfoControls/)
})

test('Fitness Plan persists first-view completion through each platform settings outbox', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift', import.meta.url), 'utf8')
  const web = readFileSync(new URL('../src/components/FitnessPlanDisclosure.tsx', import.meta.url), 'utf8')
  assert.match(native, /updateSettings[\s\S]*fitness_plan_intro_seen[\s\S]*\.bool\(true\)/)
  assert.match(web, /setSettings\(\{[\s\S]*fitness_plan_intro_seen: true/)
  assert.match(native, /accessibilityValue[\s\S]*(Expanded|Collapsed)/)
  assert.match(web, /aria-expanded=\{state\.expanded\}/)
})
~~~

- [ ] **Step 2: Strengthen compact localization coverage before adding strings**

Change the expected compact-table count from 30 to 37 in LocalisationCoverageTests and add:

~~~swift
let requiredPortalKeys: Set<String> = [
    "Fitness Plan",
    "Transition Phase",
    "Main Phase",
    "If you haven't trained in a long time.",
    "Fit enough to start the main journey.",
    "Return here after a long break to rebuild consistency, movement quality and training tolerance.",
    "Choose this when regular training feels manageable and you're ready to build strength, muscle and performance.",
]
XCTAssertTrue(requiredPortalKeys.isSubset(of: keys), "Missing compact Fitness Plan copy for \(language)")
~~~

Run:

~~~bash
node --test --test-force-exit --test-isolation=none tests/portal-information-hierarchy.test.ts
xcodebuild -quiet -project ios/APEXNative/APEXNative.xcodeproj -scheme APEX -destination 'platform=iOS Simulator,id=6907359A-18D1-46B0-87F1-13CED5CE1C46' -derivedDataPath build/codex-portal-hierarchy -only-testing:APEXTests/LocalisationCoverageTests/testEveryOfferedLanguageHasTheAuthoredCompactTable test
~~~

Expected: the source tests fail because the disclosure UI is absent; the native compact test fails at 30 versus 37.

- [ ] **Step 3: Add authored full copy**

Add the five English keys below to every non-English Localizable.strings table with these authored values. English uses source-key fallback.

| Locale | Fitness Plan | Transition first view | Main first view |
|---|---|---|---|
| en | Fitness Plan | If you haven't trained in a long time. | Fit enough to start the main journey. |
| ro | Plan de antrenament | Revii la antrenamente după o pauză lungă. | Ai baza necesară pentru etapa principală. |
| th | แผนการฝึก | กลับมาฝึกหลังหยุดไปนาน | ฟิตพอที่จะเริ่มช่วงหลัก |
| ja | トレーニングプラン | しばらく運動から離れていた人向け | メインフェーズを始められる体力がある人向け |
| de | Trainingsplan | Wenn du lange nicht trainiert hast. | Deine Basis reicht für den Einstieg in die Hauptphase. |
| de-CH | Trainingsplan | Wenn du lang nüm trainiert hesch. | Dini Basis längt für de Start i d Hauptphase. |
| es | Plan de entrenamiento | Si llevas mucho tiempo sin entrenar. | Tienes base para empezar la fase principal. |
| pt | Plano de treino | Se já não treinas há muito tempo. | Tens base para começar a fase principal. |
| it | Piano di allenamento | Se non ti alleni da molto tempo. | Hai la base per iniziare la fase principale. |

Use these two tooltip values:

| Locale | Transition information | Main information |
|---|---|---|
| en | Return here after a long break to rebuild consistency, movement quality and training tolerance. | Choose this when regular training feels manageable and you're ready to build strength, muscle and performance. |
| ro | Revino aici după o pauză lungă ca să-ți refaci ritmul, tehnica și toleranța la efort. | Alege etapa asta când te antrenezi deja constant și ești gata să crești în forță, masă musculară și performanță. |
| th | ถ้าหยุดฝึกไปนาน ให้เริ่มตรงนี้เพื่อเรียกความสม่ำเสมอ ฟอร์มการเคลื่อนไหว และความพร้อมรับการฝึกกลับมา | เลือกช่วงนี้เมื่อฝึกเป็นประจำได้สบายแล้ว และพร้อมพัฒนาความแข็งแรง กล้ามเนื้อ และสมรรถนะ |
| ja | 長いブランク明けはここから。習慣、フォーム、トレーニングに耐える力を取り戻します。 | 継続して運動できる土台があり、筋力・筋肉・パフォーマンスを伸ばしたい人はこちら。 |
| de | Starte hier nach einer längeren Pause und finde zurück zu Rhythmus, sauberer Technik und Belastbarkeit. | Wähle diese Phase, wenn regelmäßiges Training gut klappt und du Kraft, Muskeln und Leistung weiterentwickeln willst. |
| de-CH | Fang nach ere längere Pause da aa und find zrugg zu Rhythmus, sauberer Technik und Belastbarkeit. | Wähl die Phase, wenn regelmässigs Training guet klappt und du Chraft, Muskle und Leistig witerentwickle wotsch. |
| es | Vuelve aquí tras un parón largo para recuperar constancia, técnica y tolerancia al entrenamiento. | Elige esta fase cuando entrenar con regularidad ya te resulte llevadero y estés listo para ganar fuerza, músculo y rendimiento. |
| pt | Começa aqui depois de uma pausa longa para recuperares consistência, técnica e tolerância ao treino. | Escolhe esta fase quando treinar com regularidade já for confortável e estiveres pronto para desenvolver força, músculo e desempenho. |
| it | Riparti da qui dopo una lunga pausa per ritrovare costanza, tecnica e tolleranza all'allenamento. | Scegli questa fase quando allenarti con regolarità ti risulta gestibile e sei pronto a sviluppare forza, massa muscolare e prestazione. |

- [ ] **Step 4: Add authored compact copy**

Add all seven required keys to every LocalizableShort.strings file. The values are listed in this order: Fitness Plan; Transition Phase; Main Phase; Transition first view; Main first view; Transition information; Main information.

| Locale | Seven compact values |
|---|---|
| en | Fitness Plan; Transition; Main; Back after a long break?; Ready for the main phase.; Rebuild your base after a break.; Ready to build strength and muscle. |
| ro | Plan de antrenament; Tranziție; Principală; Revii după o pauză lungă.; Ești gata pentru etapa principală.; Reia ritmul după o pauză lungă.; Gata pentru forță și masă. |
| th | แผนการฝึก; ช่วงเปลี่ยนผ่าน; ช่วงหลัก; กลับมาฝึกหลังพักนาน; พร้อมเริ่มช่วงหลัก; เรียกพื้นฐานกลับมาหลังพักนาน; พร้อมเพิ่มแรงและกล้ามเนื้อ |
| ja | トレーニングプラン; 移行期; メイン; ブランク明けはここから; メイン開始の準備OK; ブランク後の土台づくり; 筋力と筋肉を伸ばす |
| de | Trainingsplan; Übergang; Hauptphase; Nach längerer Pause; Bereit für die Hauptphase; Zurück in Rhythmus und Technik; Kraft und Muskeln aufbauen |
| de-CH | Trainingsplan; Übergang; Hauptphase; Nach ere längere Pause; Bereit für d Hauptphase; Zrugg zu Rhythmus und Technik; Chraft und Muskle ufbaue |
| es | Plan de entrenamiento; Transición; Principal; Vuelves tras un parón largo; Listo para la fase principal; Recupera tu base tras el parón; A por fuerza y músculo |
| pt | Plano de treino; Transição; Principal; Regresso após uma pausa longa; Pronto para a fase principal; Recupera a base após a pausa; Força e músculo a seguir |
| it | Piano di allenamento; Transizione; Principale; Rientro dopo una lunga pausa; Pronto per la fase principale; Ritrova la base dopo la pausa; Forza e massa, si parte |

Add the Romanian and Thai full values from Step 3 to UI_TRANSLATIONS for web. Also add the compact English keys Back after a long break? and Ready for the main phase. with Romanian values Revii după o pauză lungă. and Ești gata pentru etapa principală. and Thai values กลับมาฝึกหลังพักนาน and พร้อมเริ่มช่วงหลัก. Add Sessions you built yourself with Romanian Sesiuni create de tine and Thai เซสชันที่คุณสร้างเอง for the restored web Custom Workouts tile. Do not add literal English output branches; English remains the key.

- [ ] **Step 5: Implement the native premium disclosure and reorder Advanced**

In PortalHomeView:

1. Move ProfilePortalTile() above the Nutrition PortalTile.
2. Delete the two top-level Transition and Main PortalTile calls.
3. Insert FitnessPlanDisclosure immediately after Nutrition.
4. Leave Custom Workouts and APEX Orbit below.

Add a private FitnessPlanDisclosure view in the same file. It must:

- own FitnessPlanDisclosureState and a cancellable reveal Task;
- call state.toggle(introSeen:) from a parent button with no chevron;
- show language.shortText("Fitness Plan") and the localized phase names;
- animate a clipped inset tray with teal Transition and violet Main buttons;
- schedule transition and main presentation marks at their completed stagger points;
- write settings.addons["fitness_plan_intro_seen"] = .bool(true) only when the second mark returns true;
- keep state.showsIntroduction captured for the current expansion;
- animate the first-view subtitle itself beneath each title after that card arrives, using language.shortText(first-view key);
- render that subtitle or the circled information button, never both;
- anchor a native SwiftUI popover to each information button and use presentationCompactAdaptation(.popover) so iPhone does not turn the explanation into a sheet;
- cancel the reveal task on collapse/disappearance;
- use reduceMotion to replace movement with opacity;
- expose the required identifiers and language.text(state.isExpanded ? "Expanded" : "Collapsed") as accessibility value.

The persistence closure is:

~~~swift
private func persistIntroductionSeen() {
    Task {
        await session.updateSettings { settings in
            settings.addons["fitness_plan_intro_seen"] = .bool(true)
        }
    }
}
~~~

Drive the first reveal with cancellable main-actor timing that matches the card stagger:

~~~swift
private func toggleDisclosure() {
    revealTask?.cancel()
    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.88)) {
        state.toggle(introSeen: introSeen)
    }
    guard state.isExpanded, state.showsIntroduction else { return }
    revealTask = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 360))
        guard !Task.isCancelled else { return }
        _ = state.recordIntroductionPresented(for: .transition)
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 120))
        guard !Task.isCancelled else { return }
        if state.recordIntroductionPresented(for: .main) {
            persistIntroductionSeen()
        }
    }
}
~~~

Use a Binding derived from state.activeInfo for each native .popover. Outside-tap dismissal sets the binding to false and calls state.selectInfo(nil). Give the circled information control a masked diagonal highlight whose repeating animation runs only when reduceMotion is false; otherwise retain a static phase-colored glow.

- [ ] **Step 6: Implement the web premium disclosure and reorder Advanced**

Create FitnessPlanDisclosure.tsx. It receives:

~~~typescript
interface FitnessPlanDisclosureProps {
  introSeen: boolean
  onIntroSeen: () => void
  transitionTitle: string
  mainTitle: string
  text: (value: string) => string
}
~~~

Use useReducedMotion(), AnimatePresence, the Task 1 reducer, a timeout cleared on collapse/unmount, and useNavigate(). Stagger each card, then separately summon its compact subtitle beneath the title. The second completed presentation mark invokes onIntroSeen without changing showsIntroduction in the current reducer state. Parent button has aria-expanded and no chevron. Each information button stops propagation, has a 44-pixel hit area, and selects only its own anchored role=tooltip panel. Give each destination and information control the identifiers listed above as data-testid values.

Record both completed arrivals in a cancellable effect and persist from a separate guarded effect:

~~~typescript
const persistedThisExpansion = useRef(false)

useEffect(() => {
  if (!state.expanded || !state.showsIntroduction) return
  const timer = window.setTimeout(() => {
    setState((current) => {
      const transition = recordFitnessPlanIntroPresentation(current, 'transition')
      return recordFitnessPlanIntroPresentation(transition.state, 'main').state
    })
  }, reducedMotion ? 0 : 520)
  return () => window.clearTimeout(timer)
}, [reducedMotion, state.expanded, state.showsIntroduction])

useEffect(() => {
  if (
    state.showsIntroduction
    && state.presentedIntroductionPhases.length === 2
    && !persistedThisExpansion.current
  ) {
    persistedThisExpansion.current = true
    onIntroSeen()
  }
}, [onIntroSeen, state.presentedIntroductionPhases.length, state.showsIntroduction])
~~~

Reset persistedThisExpansion only when opening an unseen introduction, before its presentation timer starts. Do not reset it on collapse or after the settings mutation, so a parent rerender cannot enqueue the same persistence write twice. Keep a wrapper ref and a pointerdown listener while activeInfo is non-null; dismiss only when the event target is outside that wrapper. Animate a diagonal highlight across each circled information control with a short Framer Motion pass and a repeatDelay of at least four seconds; render only its static glow under Reduce Motion.

In Portal.tsx:

- import FitnessPlanDisclosure and DumbbellIcon, remove the now-unused top-level phase icon imports, and destructure const { data, setSettings } = useStore();
- move the Avatar PortalCard before Nutrition;
- keep Nutrition second;
- replace top-level Transition/Main PortalCards with FitnessPlanDisclosure third;
- render the existing Custom Workouts destination immediately after Fitness Plan when a custom programme exists, then preserve APEX Orbit below it;
- pass Boolean(data.settings?.addons.fitness_plan_intro_seen);
- delete the obsolete transition/main lookup variables after their top-level cards are removed;
- persist from the nullable settings snapshot with:

~~~typescript
onIntroSeen={() => setSettings({
  addons: {
    ...(data.settings?.addons ?? {}),
    fitness_plan_intro_seen: true,
  },
})}
~~~

Restore the existing web destination with DumbbellIcon and this conditional card immediately after FitnessPlanDisclosure:

~~~tsx
{data.programs.some((program) => program.slug === 'custom') && (
  <PortalCard
    to="/custom-workouts"
    accent={ACCENTS.violet}
    title={portalText('Custom workouts').toUpperCase()}
    subtitle={portalText('Sessions you built yourself')}
    icon={<DumbbellIcon className="h-7 w-7" />}
    index={3}
  />
)}
~~~

- [ ] **Step 7: Validate copy and focused behavior**

Run:

~~~bash
node --test --test-force-exit --test-isolation=none tests/portal-information-hierarchy.test.ts tests/i18n.test.ts tests/localisation-layout-policy.test.ts
xcodebuild -quiet -project ios/APEXNative/APEXNative.xcodeproj -scheme APEX -destination 'platform=iOS Simulator,id=6907359A-18D1-46B0-87F1-13CED5CE1C46' -derivedDataPath build/codex-portal-hierarchy -only-testing:APEXTests/SimpleHomeLogicTests -only-testing:APEXTests/LocalisationCoverageTests test
find ios/APEXNative/APEX/Resources -name 'Localizable*.strings' -print0 | xargs -0 -n1 plutil -lint
~~~

Expected: all commands pass, every compact table reports 37 keys, and no minimumScaleFactor source violation appears.

- [ ] **Step 8: Commit Advanced disclosure and copy**

~~~bash
git add ios/APEXNative/APEX/Features/Portal/PortalHomeView.swift ios/APEXNative/APEXTests/LocalisationCoverageTests.swift ios/APEXNative/APEX/Resources src/components/FitnessPlanDisclosure.tsx src/pages/Portal.tsx src/lib/translations.ts tests/portal-information-hierarchy.test.ts
git commit -m 'Build premium Fitness Plan disclosure'
~~~

---

### Task 3: Consistent Settings identity

**Files:**
- Modify: ios/APEXNative/APEX/Features/Settings/SettingsView.swift
- Modify: ios/APEXNative/APEXTests/SimpleHomeLogicTests.swift
- Create: src/lib/profileIdentity.ts
- Modify: src/pages/Settings.tsx
- Modify: tests/portal-information-hierarchy.test.ts

**Interfaces:**
- Produces native ProfileIdentityPresentation.showsPersona(displayName:personaName:).
- Produces web showsPersonaLabel(displayName, personaName).

- [ ] **Step 1: Write failing duplicate-persona tests**

Append to SimpleHomeLogicTests:

~~~swift
func testIdentityHidesOnlyAPersonaThatDuplicatesTheDisplayName() {
    XCTAssertFalse(ProfileIdentityPresentation.showsPersona(
        displayName: "Constantine", personaName: "CONSTANTINE"
    ))
    XCTAssertFalse(ProfileIdentityPresentation.showsPersona(
        displayName: "Iulian", personaName: "IULIÁN"
    ))
    XCTAssertTrue(ProfileIdentityPresentation.showsPersona(
        displayName: "Iulian-Andrei", personaName: "Iulian"
    ))
}
~~~

Append web behavior/source tests:

~~~typescript
import { showsPersonaLabel } from '../src/lib/profileIdentity.ts'

test('Settings hides only a persona label that repeats the display name', () => {
  assert.equal(showsPersonaLabel('Constantine', 'CONSTANTINE'), false)
  assert.equal(showsPersonaLabel('Iulian', 'IULIÁN'), false)
  assert.equal(showsPersonaLabel('Iulian-Andrei', 'Iulian'), true)
})

test('Settings gives the name its own non-hyphenating row on native and web', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Settings/SettingsView.swift', import.meta.url), 'utf8')
  const web = readFileSync(new URL('../src/pages/Settings.tsx', import.meta.url), 'utf8')
  assert.match(native, /Text\(profile\?\.displayName \?\? "APEX"\)[\s\S]*\.lineLimit\(1\)[\s\S]*\.allowsTightening\(true\)/)
  assert.doesNotMatch(native, /minimumScaleFactor/)
  assert.match(web, /whitespace-nowrap/)
  assert.match(web, /\[hyphens:none\]/)
  assert.match(native, /ProfileIdentityPresentation\.showsPersona/)
  assert.match(web, /showsPersonaLabel/)
})
~~~

- [ ] **Step 2: Run focused tests and confirm red**

Run the Task 1 focused native and web commands.

Expected: both fail because the identity helpers and layouts are absent.

- [ ] **Step 3: Implement normalized duplicate detection**

Add at file scope in SettingsView.swift:

~~~swift
enum ProfileIdentityPresentation {
    static func showsPersona(displayName: String, personaName: String) -> Bool {
        normalized(displayName) != normalized(personaName)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    }
}
~~~

Create profileIdentity.ts:

~~~typescript
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
~~~

- [ ] **Step 4: Recompose both Settings identity cards**

Native:

- remove the trailing duplicate persona capsule from the HStack;
- keep portrait plus a flexible VStack;
- put the name in that VStack with lineLimit(1), allowsTightening(true), truncationMode(.tail), and maxWidth infinity;
- put the existing persona capsule below the name only when showsPersona() returns true;
- do not use minimumScaleFactor.

Web:

- remove flex-wrap and the trailing AccentChip;
- make the content column min-w-0 and full width;
- add whitespace-nowrap, overflow-hidden, text-ellipsis, and [hyphens:none] to the name;
- render AccentChip beneath the name only when showsPersonaLabel() is true.

- [ ] **Step 5: Run focused tests and commit**

Run the Task 1 focused commands, then:

~~~bash
git add ios/APEXNative/APEX/Features/Settings/SettingsView.swift ios/APEXNative/APEXTests/SimpleHomeLogicTests.swift src/lib/profileIdentity.ts src/pages/Settings.tsx tests/portal-information-hierarchy.test.ts
git commit -m 'Fix Settings identity hierarchy'
~~~

---

### Task 4: Move Simple quick actions above the Dayline

**Files:**
- Create: src/lib/simpleBlockOrder.ts
- Modify: src/pages/SimpleHome.tsx
- Modify: ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift
- Modify: tests/portal-information-hierarchy.test.ts

**Interfaces:**
- Produces SIMPLE_BLOCK_IDS, SimpleBlockId, and resolveSimpleBlockOrder(value).
- resolveSimpleBlockOrder returns { order: SimpleBlockId[]; migratedLegacyDefault: boolean }.

- [ ] **Step 1: Write failing default/migration tests**

Append:

~~~typescript
import {
  LEGACY_SIMPLE_BLOCK_ORDER,
  SIMPLE_BLOCK_IDS,
  resolveSimpleBlockOrder,
} from '../src/lib/simpleBlockOrder.ts'

test('Simple defaults place quick actions between Nutrition and Dayline', () => {
  const result = resolveSimpleBlockOrder(undefined)
  assert.equal(result.migratedLegacyDefault, false)
  assert.ok(result.order.indexOf('nutrition') < result.order.indexOf('quick-actions'))
  assert.ok(result.order.indexOf('quick-actions') < result.order.indexOf('dayline'))
})

test('Simple upgrades only the former stock order and preserves custom drag order', () => {
  const legacy = resolveSimpleBlockOrder(LEGACY_SIMPLE_BLOCK_ORDER)
  assert.equal(legacy.migratedLegacyDefault, true)
  assert.deepEqual(legacy.order, [...SIMPLE_BLOCK_IDS])

  const custom = ['dayline', 'nutrition', 'quick-actions', ...SIMPLE_BLOCK_IDS.filter(
    (item) => !['dayline', 'nutrition', 'quick-actions'].includes(item),
  )]
  const resolved = resolveSimpleBlockOrder(custom)
  assert.equal(resolved.migratedLegacyDefault, false)
  assert.deepEqual(resolved.order, custom)
})

test('native Simple places the existing metrics between glance and Dayline', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift', import.meta.url), 'utf8')
  assert.match(native, /NutritionGlanceCard\([\s\S]*\n\s*metrics\n[\s\S]*APEXDaylineView\(/)
})
~~~

- [ ] **Step 2: Run focused web tests and confirm red**

Run:

~~~bash
node --test --test-force-exit --test-isolation=none tests/portal-information-hierarchy.test.ts
~~~

Expected: module-not-found for simpleBlockOrder.ts and native source-order failure.

- [ ] **Step 3: Implement the web order resolver**

Create simpleBlockOrder.ts:

~~~typescript
export const LEGACY_SIMPLE_BLOCK_ORDER = [
  'recovery', 'nutrition', 'dayline', 'quick-actions', 'activity',
  'manual-workout', 'next-action', 'guided-plan', 'orbit', 'body-index', 'links',
] as const

export const SIMPLE_BLOCK_IDS = [
  'recovery', 'nutrition', 'quick-actions', 'dayline', 'activity',
  'manual-workout', 'next-action', 'guided-plan', 'orbit', 'body-index', 'links',
] as const

export type SimpleBlockId = (typeof SIMPLE_BLOCK_IDS)[number]

export interface SimpleBlockOrderResolution {
  order: SimpleBlockId[]
  migratedLegacyDefault: boolean
}

function sameOrder(left: readonly string[], right: readonly string[]): boolean {
  return left.length === right.length && left.every((item, index) => item === right[index])
}

export function resolveSimpleBlockOrder(value: unknown): SimpleBlockOrderResolution {
  const known = new Set<string>(SIMPLE_BLOCK_IDS)
  const saved = Array.isArray(value)
    ? value.filter((item): item is SimpleBlockId => typeof item === 'string' && known.has(item))
    : []
  const normalized = Array.from(new Set<SimpleBlockId>([
    ...saved,
    ...SIMPLE_BLOCK_IDS,
  ]))
  if (sameOrder(normalized, LEGACY_SIMPLE_BLOCK_ORDER)) {
    return { order: [...SIMPLE_BLOCK_IDS], migratedLegacyDefault: true }
  }
  return { order: normalized, migratedLegacyDefault: false }
}
~~~

- [ ] **Step 4: Consume and persist the resolved web order**

Remove the local SIMPLE_BLOCK_IDS, SimpleBlockId, and normalizedSimpleBlockOrder declarations from SimpleHome.tsx and import the new contract.

Initialize with resolveSimpleBlockOrder(...).order. In the settings-order effect:

~~~typescript
const resolution = resolveSimpleBlockOrder(settings?.addons.simple_block_order)
simpleBlockOrderRef.current = resolution.order
setSimpleBlockOrder(resolution.order)
if (resolution.migratedLegacyDefault) {
  setSettings({
    addons: { ...settings.addons, simple_block_order: resolution.order },
  })
}
~~~

The second render sees the new order and does not write again.

- [ ] **Step 5: Move the existing native metrics view**

Inside the existing if let targets block, render:

~~~swift
NutritionGlanceCard(
    date: selectedDate,
    targets: targets,
    onEditTargets: { showTargetEditor = true },
    onOpenCalendar: { showCalendar = true },
    completion: completion
)
metrics
APEXDaylineView(
~~~

Delete the later metrics call. Do not change the metrics computed property or any action/sheet wiring.

- [ ] **Step 6: Run tests and commit**

Run:

~~~bash
node --test --test-force-exit --test-isolation=none tests/portal-information-hierarchy.test.ts tests/simple-mode.test.ts tests/simple-home-cleanup.test.ts
~~~

Then:

~~~bash
git add src/lib/simpleBlockOrder.ts src/pages/SimpleHome.tsx ios/APEXNative/APEX/Features/Portal/SimpleHomeView.swift tests/portal-information-hierarchy.test.ts
git commit -m 'Move Simple quick actions above Dayline'
~~~

---

### Task 5: Move Private Visual Progress beneath the portrait

**Files:**
- Modify: ios/APEXNative/APEX/Features/Avatar/AvatarView.swift
- Modify: tests/portal-information-hierarchy.test.ts

**Interfaces:**
- No new interface; moves the existing visualProgressLink only.

- [ ] **Step 1: Write the failing cross-platform placement contract**

Append:

~~~typescript
test('Private Visual Progress sits immediately below the Avatar portrait on native and web', () => {
  const native = readFileSync(new URL('../ios/APEXNative/APEX/Features/Avatar/AvatarView.swift', import.meta.url), 'utf8')
  const web = readFileSync(new URL('../src/pages/AvatarPage.tsx', import.meta.url), 'utf8')
  assert.match(native, /AvatarHero\(profile: session\.profile\)\s*visualProgressLink\s*bodyIndexCard/)
  assert.match(web, /AvatarPortraitHero profile=\{profile\}[\s\S]*navigate\('\/progress'[\s\S]*Performance identity/)
})
~~~

- [ ] **Step 2: Run focused test and confirm native failure**

Run the focused portal-information-hierarchy test.

Expected: web placement passes; native fails because visualProgressLink is below assessmentCard.

- [ ] **Step 3: Move the existing native link and retest**

Move visualProgressLink directly after AvatarHero(profile: session.profile), and remove its old occurrence after assessmentCard. Make no changes to the link, route, copy, or camera behavior.

Run the focused test and expect pass.

- [ ] **Step 4: Commit**

~~~bash
git add ios/APEXNative/APEX/Features/Avatar/AvatarView.swift tests/portal-information-hierarchy.test.ts
git commit -m 'Move visual progress beneath Avatar portrait'
~~~

---

### Task 6: Integrated visual verification and release delivery

**Files:**
- Modify: docs/REPAIR-NOTES.md
- Modify: ios/APEXNative/APEXNative.xcodeproj/project.pbxproj

**Interfaces:**
- Produces Apple Release build 380 from the final implementation commit.

- [ ] **Step 1: Run focused contracts**

~~~bash
node --test --test-force-exit --test-isolation=none tests/portal-information-hierarchy.test.ts tests/i18n.test.ts tests/localisation-layout-policy.test.ts tests/simple-mode.test.ts tests/simple-home-cleanup.test.ts
xcodebuild -quiet -project ios/APEXNative/APEXNative.xcodeproj -scheme APEX -destination 'platform=iOS Simulator,id=6907359A-18D1-46B0-87F1-13CED5CE1C46' -derivedDataPath build/codex-portal-hierarchy -only-testing:APEXTests/SimpleHomeLogicTests -only-testing:APEXTests/LocalisationCoverageTests test
~~~

Expected: all focused contracts pass.

- [ ] **Step 2: Run full verification**

Run independently:

~~~bash
npm test
npm run build
xcodebuild -quiet -project ios/APEXNative/APEXNative.xcodeproj -scheme APEX -destination 'platform=iOS Simulator,id=6907359A-18D1-46B0-87F1-13CED5CE1C46' -derivedDataPath build/codex-portal-hierarchy -only-testing:APEXTests test
find ios/APEXNative/APEX/Resources -name 'Localizable*.strings' -print0 | xargs -0 -n1 plutil -lint
git diff --check
~~~

Expected: every suite/build/lint succeeds with zero failed or skipped native tests.

- [ ] **Step 3: Verify the four visual flows**

Use the run-simulator/xcodebuildmcp workflow with the debug fixture:

1. Advanced: Avatar first, Nutrition second, Fitness Plan third; first open reveals both subtitles in the inline glass tray.
2. Collapse/reopen: no subtitles; separate gleaming information controls; tapping one opens only its own short explanation.
3. Settings: Constantine is one uninterrupted line and has no duplicate persona chip.
4. Simple and Avatar: quick actions sit above the Dayline; Visual Progress sits directly below the portrait.

Capture screenshots of all four states in build/codex-portal-hierarchy/visual-verification and inspect them at original detail. Verify Reduce Motion produces no translating/staggering animation and retains the hierarchy.

- [ ] **Step 4: Record the result and bump build 379 to 380**

Append a dated REPAIR-NOTES entry with root causes, preserved behavior, focused/full counts, localization validation, and simulator screenshot evidence. Change both CURRENT_PROJECT_VERSION entries from 379 to 380. Deployment and device evidence belong in the final handoff because they occur after this commit.

- [ ] **Step 5: Commit delivery metadata**

~~~bash
git add docs/REPAIR-NOTES.md ios/APEXNative/APEXNative.xcodeproj/project.pbxproj
git commit -m 'Record premium hierarchy delivery'
~~~

- [ ] **Step 6: Push both required refs and verify Pages**

~~~bash
git push origin HEAD:codex/main-critical-repair
git push origin HEAD:main
gh run list --workflow 310189698 --limit 3 --json databaseId,headSha,status,conclusion,url
delivery_sha="$(git rev-parse HEAD)"
pages_run_id="$(gh run list --workflow 310189698 --limit 10 --json databaseId,headSha --jq ".[] | select(.headSha == \"$delivery_sha\") | .databaseId" | head -1)"
test -n "$pages_run_id"
gh run watch "$pages_run_id" --exit-status
curl -sS -o /dev/null -w '%{http_code}\n' https://evoryder8-collab.github.io/APXAppiC/
~~~

Expected: both refs equal local HEAD, the exact-HEAD Pages run succeeds, and the live URL returns 200.

- [ ] **Step 7: Build, sign, install, and verify Apple Release 380**

~~~bash
xcodebuild -quiet -project ios/APEXNative/APEXNative.xcodeproj -scheme APEX -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build/codex-release-380 -allowProvisioningUpdates build
codesign --verify --deep --strict build/codex-release-380/Build/Products/Release-iphoneos/APEX.app
plutil -extract CFBundleVersion raw build/codex-release-380/Build/Products/Release-iphoneos/APEX.app/Info.plist
xcrun devicectl device install app --device A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6 --timeout 300 build/codex-release-380/Build/Products/Release-iphoneos/APEX.app
xcrun devicectl device info apps --device A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6 --bundle-id ch.apexperformance.APEX --columns '*' --timeout 120
xcrun devicectl device process launch --terminate-existing --device A1A6A3B7-CB35-5FE0-ADA7-4924BCB196D6 --timeout 120 ch.apexperformance.APEX
~~~

Expected: signature valid, bundle version 380, device app listing reports 380, and launch succeeds. If iOS denies launch solely because the phone is locked, record that exact external condition after confirming installation.

- [ ] **Step 8: Final clean-state audit and pause**

~~~bash
git status --short --branch
git rev-parse HEAD
git rev-parse origin/codex/main-critical-repair
git rev-parse origin/main
~~~

Expected: clean worktree and all three SHAs identical. Report the live URL, Pages run, test/build counts, device result, and exact SHA; do not resume roadmap work.
