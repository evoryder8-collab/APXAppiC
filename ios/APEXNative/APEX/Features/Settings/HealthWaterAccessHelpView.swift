import SwiftUI

struct HealthWaterAccessHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "heart.circle.fill")
                        .font(.system(size: 46)).foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(language.text("Share water with Apple Health"))
                        .font(APEXFont.display(28))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(language.text("Apple keeps this switch in Health after your first choice. Change it once, then return here."))
                        .font(APEXFont.body(15)).foregroundStyle(APEXColor.secondaryInk)
                    VStack(alignment: .leading, spacing: 18) {
                        step("1", "Open Health and tap your profile picture.")
                        step("2", "Choose Apps and Services, then FITR MAX.")
                        step("3", "Under Allow to Write, turn on Water.")
                    }
                    Button {
                        guard let url = URL(string: "x-apple-health://") else { return }
                        // Open Health itself, without private Settings deep links.
                        // Instructions remain available if Health is not installed.
                        UIApplication.shared.open(url)
                    } label: {
                        Label(language.text("Open Health"), systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.teal))
                    Text(language.text("Your FITR MAX water log stays available either way."))
                        .font(APEXFont.body(12)).foregroundStyle(APEXColor.secondaryInk)
                }
                .padding(24)
            }
            .background(APEXColor.canvas)
            .navigationTitle(language.text("Water sharing"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func step(_ number: String, _ title: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(APEXFont.mono(14, weight: .bold))
                .foregroundStyle(APEXColor.teal)
            Text(language.text(title)).font(APEXFont.body(15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
