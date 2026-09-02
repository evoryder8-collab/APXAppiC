import SwiftUI

struct FoodDataAcknowledgementsView: View {
    static let sourceURL = URL(string: "https://doi.org/10.11583/DTU.32312844")!
    static let licenceURL = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
    static let disclaimerURL = URL(string: "https://fcdb.fooddata.dk/disclaimer")!

    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(language.text("Food data acknowledgements"), systemImage: "checkmark.seal.fill")
                        .font(APEXFont.display(29))
                        .foregroundStyle(APEXColor.ink)

                    Text(language.text("See where APEX food data comes from and how it is adapted."))
                        .font(APEXFont.body(14))
                        .foregroundStyle(APEXColor.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    GlassCard(radius: 25, padding: 18) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(language.text("APEX uses adapted data from:"))
                                .font(APEXFont.body(16, weight: .bold))

                            Text(language.text("Marija Langwagen, Jette Jakobsen and Anders Poulsen: The Danish Food Composition Database, version 6.1, May 2026, National Food Institute, Technical University of Denmark."))
                                .font(APEXFont.body(13))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            acknowledgementLink(
                                Text(language.text("Source dataset")),
                                systemImage: "doc.text",
                                destination: Self.sourceURL,
                                identifier: "food-data-source-link"
                            )
                            acknowledgementLink(
                                Text(verbatim: "CC BY 4.0"),
                                systemImage: "person.crop.circle.badge.checkmark",
                                destination: Self.licenceURL,
                                identifier: "food-data-licence-link"
                            )
                            acknowledgementLink(
                                Text(language.text("DTU disclaimer")),
                                systemImage: "shield.lefthalf.filled",
                                destination: Self.disclaimerURL,
                                identifier: "food-data-disclaimer-link"
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GlassCard(radius: 25, padding: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(language.text("APEX extracted, normalized and mapped selected source records to reviewed APEX food entries. These changes are by APEX; DTU does not endorse APEX."))
                                .font(APEXFont.body(13, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(language.text("DTU does not guarantee that the database is error-free or suitable for a particular purpose. Check the current package label when exact product values matter."))
                                .font(APEXFont.body(12))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(22)
            }
            .background(AuroraField(animated: false).ignoresSafeArea())
            .navigationTitle(language.text("Food data acknowledgements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language.text("Done"), action: dismiss.callAsFunction)
                        .font(APEXFont.body(15, weight: .bold))
                }
            }
        }
    }

    private func acknowledgementLink(
        _ title: Text,
        systemImage: String,
        destination: URL,
        identifier: String
    ) -> some View {
        Link(destination: destination) {
            Label {
                title.font(APEXFont.body(14, weight: .bold))
            } icon: {
                Image(systemName: systemImage)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier(identifier)
    }
}
