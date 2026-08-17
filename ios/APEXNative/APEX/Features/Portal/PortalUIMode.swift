import Foundation
import SwiftUI
import UIKit

enum PortalUIMode: String, CaseIterable, Identifiable, Sendable {
    case simple
    case advanced

    var id: String { rawValue }

    static func current(from settings: UserSettings?) -> PortalUIMode {
        settings?.addons["uiMode"]?.stringValue == PortalUIMode.simple.rawValue ? .simple : .advanced
    }
}

enum SimpleHomeLogic {
    static func completion(completed: Int, total: Int) -> Int {
        guard total > 0 else { return 100 }
        return min(100, max(0, Int((Double(completed) / Double(total) * 100).rounded())))
    }

    static func nextCandidateIndex(times: [Int], nowMinutes: Int) -> Int? {
        let ordered = times.enumerated().sorted { left, right in
            if left.element == right.element { return left.offset < right.offset }
            return left.element < right.element
        }
        return ordered.last(where: { $0.element <= nowMinutes })?.offset ?? ordered.first?.offset
    }
}

struct PortalModeSwitcher: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared

    var body: some View {
        HStack(spacing: 3) {
            ForEach(PortalUIMode.allCases) { mode in
                Button {
                    guard session.interfaceMode != mode else { return }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    Task { await session.setInterfaceMode(mode) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode == .simple ? "sparkle" : "slider.horizontal.3")
                            .font(.system(size: 9, weight: .bold))
                        Text(language.text(mode == .simple ? "Simple" : "Advanced").uppercased(with: language.language.locale))
                            .font(APEXFont.mono(9))
                            .tracking(0.7)
                    }
                    .foregroundStyle(session.interfaceMode == mode ? .white : APEXColor.secondaryInk)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(
                        session.interfaceMode == mode ? APEXColor.ink : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(session.interfaceMode == mode ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.white.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.9)))
        .shadow(color: .black.opacity(0.05), radius: 9, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(language.text("Interface mode"))
    }
}
