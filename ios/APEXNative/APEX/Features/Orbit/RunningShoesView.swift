import SwiftUI

struct RunningShoesView: View {
    @Environment(AppSession.self) private var session
    @State private var editing: OrbitShoe?
    @State private var showEditor = false
    @State private var language = LanguageState.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PRIVATE SHOE ROTATION")
                            .font(APEXFont.mono(9))
                            .foregroundStyle(APEXColor.cyan)
                        Text("Running shoes")
                            .font(APEXFont.display(31))
                    }
                    Spacer()
                    Button {
                        editing = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(APEXColor.cyan)
                }

                if activeShoes.isEmpty {
                    GlassCard(radius: 29, padding: 20) {
                        VStack(spacing: 10) {
                            Image(systemName: "shoe.2")
                                .font(.system(size: 38))
                                .foregroundStyle(APEXColor.cyan)
                            Text("Add the pair you run in")
                                .font(APEXFont.display(21))
                            Text("Orbit tracks factual use and notes. It does not declare a shoe unsafe from a generic distance threshold.")
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .multilineTextAlignment(.center)
                        }
                    }
                }

                ForEach(activeShoes) { shoe in
                    GlassCard(radius: 28, padding: 18) {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Image(systemName: "shoe.2.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(APEXColor.cyan.gradient, in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(shoe.name)
                                        .font(APEXFont.display(20))
                                    Text(shoe.brand.isEmpty ? language.text("Brand not specified") : shoe.brand)
                                        .font(APEXFont.body(10, weight: .medium))
                                        .foregroundStyle(APEXColor.secondaryInk)
                                }
                                Spacer()
                                Text(language.format("%.1f km", distance(for: shoe) / 1_000))
                                    .font(APEXFont.mono(10))
                            }
                            if shoe.preferredSurfaces.isEmpty == false {
                                Text(shoe.preferredSurfaces.map { language.text($0.capitalized) }.joined(separator: " · "))
                                    .font(APEXFont.mono(8))
                                    .foregroundStyle(APEXColor.cyan)
                            }
                            if shoe.notes.isEmpty == false {
                                Text(shoe.notes)
                                    .font(APEXFont.body(11, weight: .medium))
                                    .foregroundStyle(APEXColor.secondaryInk)
                            }
                            HStack {
                                Button("Edit") {
                                    editing = shoe
                                    showEditor = true
                                }
                                .buttonStyle(.bordered)
                                Button("Archive") { Task { await session.archiveOrbitShoe(shoe) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                if archivedShoes.isEmpty == false {
                    DisclosureGroup("Archived pairs") {
                        ForEach(archivedShoes) { shoe in
                            HStack {
                                Text(shoe.name).font(APEXFont.body(11, weight: .semibold))
                                Spacer()
                                Text(language.format("%.1f km", distance(for: shoe) / 1_000)).font(APEXFont.mono(8))
                            }
                            .padding(10)
                        }
                    }
                    .font(APEXFont.body(12, weight: .bold))
                    .padding(17)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .navigationTitle("Shoes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            ShoeEditorView(shoe: editing)
                .environment(session)
        }
    }

    private var activeShoes: [OrbitShoe] { session.data.orbitShoes.filter { $0.archived == false } }
    private var archivedShoes: [OrbitShoe] { session.data.orbitShoes.filter(\.archived) }

    private func distance(for shoe: OrbitShoe) -> Double {
        session.data.orbitRuns.filter { $0.shoeID == shoe.id && $0.status == "completed" }
            .reduce(0) { $0 + ($1.metrics["distance_m"]?.numberValue ?? 0) }
    }
}

private struct ShoeEditorView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let shoe: OrbitShoe?

    @State private var name = ""
    @State private var brand = ""
    @State private var firstUseDate = Date()
    @State private var surfaces = Set<String>()
    @State private var notes = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Pair") {
                    TextField("Name", text: $name)
                    TextField("Brand", text: $brand)
                    DatePicker("First used", selection: $firstUseDate, displayedComponents: .date)
                }
                Section("Preferred surfaces") {
                    ForEach(["road", "path", "trail", "mixed"], id: \.self) { surface in
                        Toggle(language.text(surface.capitalized), isOn: Binding(
                            get: { surfaces.contains(surface) },
                            set: { selected in
                                if selected { surfaces.insert(surface) }
                                else { surfaces.remove(surface) }
                            }
                        ))
                    }
                }
                Section("Private wear or comfort note") {
                    TextField("Optional note", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Text("Mileage is shown factually. APEX does not label shoes unsafe from distance alone.")
                        .font(APEXFont.body(10, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
            }
            .navigationTitle(language.text(shoe == nil ? "Add shoes" : "Edit shoes"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
            .onAppear {
                guard let shoe else { return }
                name = shoe.name
                brand = shoe.brand
                firstUseDate = ISO8601DateFormatter.apexDateOnly.date(from: shoe.firstUseDate) ?? .now
                surfaces = Set(shoe.preferredSurfaces)
                notes = shoe.notes
            }
        }
    }

    @MainActor
    private func save() async {
        saving = true
        await session.saveOrbitShoe(
            id: shoe?.id,
            name: name,
            brand: brand,
            firstUseDate: firstUseDate,
            surfaces: surfaces.sorted(),
            notes: notes,
            archived: shoe?.archived ?? false
        )
        saving = false
        dismiss()
    }
}
