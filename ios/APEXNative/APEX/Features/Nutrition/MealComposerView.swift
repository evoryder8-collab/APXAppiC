import SwiftUI

struct MealComposerRequest: Identifiable, Hashable {
    let id = UUID()
    let date: Date
    let mealSlot: String
    let displayName: String
    let existingMeal: LoggedMeal?
    let suggestedFinishedAt: Date?

    static func create(
        date: Date,
        slot: String,
        name: String? = nil,
        finishedAt: Date? = nil
    ) -> MealComposerRequest {
        MealComposerRequest(
            date: date,
            mealSlot: slot,
            displayName: name ?? slot.replacingOccurrences(of: "_", with: " ").capitalized,
            existingMeal: nil,
            suggestedFinishedAt: finishedAt
        )
    }

    static func edit(_ meal: LoggedMeal) -> MealComposerRequest {
        MealComposerRequest(
            date: ISO8601DateFormatter.apexDateOnly.date(from: meal.localDate) ?? .now,
            mealSlot: meal.mealSlot,
            displayName: meal.displayName,
            existingMeal: meal,
            suggestedFinishedAt: nil
        )
    }
}

private enum MealComposerDensity: String, CaseIterable {
    case compact
    case expanded
}

struct MealComposerView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared

    let request: MealComposerRequest

    @State private var draft: MealComposerDraft
    @State private var density: MealComposerDensity = .compact
    @State private var selectionMode = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var showFoodPicker = false
    @State private var showPresetCreator = false
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var hydrated = false
    @State private var guideOpen = false
    @State private var guideEditing = false
    @State private var guideDraft: [String] = []
    @State private var guideQuery: MealProtocolGuide.Query?

    /* Food Memory scores history against the block and clock this meal sits in,
       so a 07:00 breakfast start is not ranked by a 22:00 one. */
    private var memoryBlockID: String? {
        request.existingMeal.flatMap(MealMemory.markedBlock)
    }

    private var memoryTargetTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: draft.finishedAt)
    }

    init(request: MealComposerRequest) {
        self.request = request
        let finished = request.existingMeal.flatMap { Self.parseTimestamp($0.loggedAt) }
            ?? request.suggestedFinishedAt
            ?? Self.defaultFinishedAt(on: request.date, slot: request.mealSlot)
        _draft = State(initialValue: MealComposerDraft(
            id: request.existingMeal?.id ?? UUID(),
            localDate: request.date.apexDateKey,
            mealSlot: request.mealSlot,
            displayName: request.displayName,
            finishedAt: finished,
            sourcePresetID: request.existingMeal?.sourcePresetID,
            sourcePlannedMealID: request.existingMeal?.sourcePlannedMealID,
            replaceMealID: request.existingMeal?.id,
            loggedAs: request.existingMeal?.loggedAs ?? "actual",
            items: []
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                /* Not lazy: the guide and discovery cards are taller than the
                   sheet, and a lazy stack stops materialising what follows
                   them. The same trap the nutrition and training pages hit. */
                VStack(spacing: 18) {
                    mealSummary
                    guideCard
                    discoveryCard
                    presetsCard
                    itemsHeader

                    if draft.items.isEmpty {
                        ContentUnavailableView(
                            "This meal is empty",
                            systemImage: "fork.knife.circle",
                            description: Text("Search Food Memory, scan a barcode, or apply a saved preset.")
                        )
                        .padding(.vertical, 38)
                    } else {
                        ForEach(Array(draft.items.enumerated()), id: \.element.id) { index, item in
                            MealComposerItemCard(
                                item: itemBinding(for: item.id),
                                food: food(for: item),
                                density: density,
                                selecting: selectionMode,
                                selected: selectedItemIDs.contains(item.id),
                                favourite: isFavourite(item),
                                canMoveUp: index > 0,
                                canMoveDown: index < draft.items.count - 1,
                                onToggleSelection: { toggleSelection(item.id) },
                                onToggleFavourite: { toggleFavourite(item) },
                                onMoveUp: { move(item.id, by: -1) },
                                onMoveDown: { move(item.id, by: 1) },
                                onDelete: { remove(item.id) }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 112)
            }
            .background(APEXBackground())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("ACTUAL INTAKE · \(draft.mealSlot.uppercased())")
                            .font(APEXFont.mono(9))
                            .tracking(1.4)
                            .foregroundStyle(APEXColor.secondaryInk)
                        Text("Build this meal")
                            .font(APEXFont.display(18))
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                        .font(APEXFont.body(14, weight: .bold))
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
            .sheet(item: $guideQuery) { query in
                MealFoodPicker(
                    date: request.date,
                    initialQuery: query.search,
                    slot: draft.mealSlot,
                    blockID: memoryBlockID,
                    targetTime: memoryTargetTime,
                    excludeMealID: draft.replaceMealID
                ) { food, amount, unit in
                    add(food, amount: amount, unit: unit)
                }
                .environment(session)
            }
            .sheet(isPresented: $showFoodPicker) {
                MealFoodPicker(
                    date: request.date,
                    slot: draft.mealSlot,
                    blockID: memoryBlockID,
                    targetTime: memoryTargetTime,
                    excludeMealID: draft.replaceMealID
                ) { food, amount, unit in
                    add(food, amount: amount, unit: unit)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPresetCreator) {
                PresetCreationSheet(
                    mealSlot: draft.mealSlot,
                    items: selectedItems.isEmpty ? draft.items : selectedItems
                ) {
                    selectionMode = false
                    selectedItemIDs.removeAll()
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .alert("Could not save meal", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(language.text(errorMessage ?? "Please try again."))
            }
            .confirmationDialog("Discard unsaved changes?", isPresented: $showDeleteConfirmation) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .task { hydrateExistingMeal() }
        }
    }

    private var mealSummary: some View {
        GlassCard(radius: 30, padding: 20) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Meal name")
                            .font(APEXFont.body(12, weight: .bold))
                            .foregroundStyle(APEXColor.secondaryInk)
                        TextField("Meal name", text: $draft.displayName)
                            .font(APEXFont.display(26))
                            .textInputAutocapitalization(.words)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("MEAL FINISHED AT")
                            .font(APEXFont.mono(8))
                            .foregroundStyle(APEXColor.amberDeep)
                        DatePicker("", selection: $draft.finishedAt, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .font(APEXFont.mono(18))
                    }
                    .padding(13)
                    .background(APEXColor.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(draft.totals.kcal.rounded()))")
                        .font(APEXFont.display(38))
                        .contentTransition(.numericText())
                    Text("kcal")
                        .font(APEXFont.body(14, weight: .bold))
                        .foregroundStyle(APEXColor.secondaryInk)
                    Spacer()
                    if !guideLines.isEmpty {
                        Button {
                            withAnimation(.snappy(duration: 0.26)) { guideOpen.toggle() }
                        } label: {
                            Text("\(language.text("Predefined list")) \(guideOpen ? "−" : "+")")
                                .font(APEXFont.body(13, weight: .bold))
                                .foregroundStyle(APEXColor.amberDeep)
                                .padding(.horizontal, 13)
                                .frame(height: 38)
                                .background(APEXColor.amber.opacity(0.14), in: Capsule())
                                .overlay(Capsule().stroke(APEXColor.amber.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("meal-guide-toggle")
                    }
                }

                HStack(spacing: 9) {
                    macroCard("Protein", value: draft.totals.proteinG, target: mealTargets.protein)
                    macroCard("Carbs", value: draft.totals.carbsG, target: mealTargets.carbs)
                    macroCard("Fat", value: draft.totals.fatG, target: mealTargets.fat)
                }
            }
        }
    }

    // MARK: - Predefined list

    private var guidePersona: String { session.data.profile?.persona.rawValue ?? "constantine" }
    private var guideGoal: String { session.data.profile?.goal.rawValue ?? "recomp" }

    private var guideLines: [String] {
        MealProtocolGuide.lines(
            persona: guidePersona,
            slot: draft.mealSlot,
            goal: guideGoal,
            language: language.language.rawValue,
            overrides: session.data.settings?.addons["meal_protocol_overrides"]?.objectValue
        )
    }

    /*
     * The list a person can eat from, shop from, or rewrite. Tapping a line
     * opens the search already pointed at that food and amount; Configure turns
     * the same rows into fields, so the list becomes theirs.
     */
    @ViewBuilder
    private var guideCard: some View {
        if guideOpen, !guideLines.isEmpty {
            GlassCard(radius: 27, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("YOUR MEAL GUIDE")
                                .font(APEXFont.mono(10, weight: .bold))
                                .tracking(1.3)
                                .foregroundStyle(APEXColor.amberDeep)
                            Text(language.text("Adjusted for the current goal. Package labels remain the nutrition source."))
                                .font(APEXFont.body(12, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 6)
                        Button {
                            if guideEditing {
                                guideEditing = false
                            } else {
                                guideDraft = guideLines
                                guideEditing = true
                            }
                        } label: {
                            Text(language.text(guideEditing ? "Done editing" : "Configure"))
                                .font(APEXFont.body(11, weight: .bold))
                                .foregroundStyle(APEXColor.ink)
                                .padding(.horizontal, 11)
                                .frame(height: 32)
                                .background(.white.opacity(0.78), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("meal-guide-configure")
                    }

                    if guideEditing {
                        ForEach(Array(guideDraft.indices), id: \.self) { index in
                            HStack(spacing: 10) {
                                indexBadge(index + 1)
                                TextField(
                                    language.text("Write anything you like"),
                                    text: Binding(
                                        get: { index < guideDraft.count ? guideDraft[index] : "" },
                                        set: { if index < guideDraft.count { guideDraft[index] = $0 } }
                                    )
                                )
                                .font(APEXFont.body(14, weight: .bold))
                                Button {
                                    guideDraft.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(APEXColor.danger)
                                        .frame(width: 30, height: 30)
                                        .background(APEXColor.danger.opacity(0.1), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
                        }

                        HStack(spacing: 10) {
                            Button {
                                guideDraft.append("")
                            } label: {
                                Text(language.text("+ Item"))
                                    .font(APEXFont.body(13, weight: .bold))
                                    .foregroundStyle(APEXColor.ink)
                                    .padding(.horizontal, 15)
                                    .frame(height: 44)
                                    .background(.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("meal-guide-add-item")

                            Button {
                                saveGuide()
                            } label: {
                                Text(language.text("Save configuration"))
                                    .font(APEXFont.body(13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(APEXColor.amber.gradient, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("meal-guide-save")
                        }
                    } else {
                        ForEach(Array(guideLines.enumerated()), id: \.offset) { index, line in
                            HStack(spacing: 10) {
                                indexBadge(index + 1)
                                Text(line)
                                    .font(APEXFont.body(14, weight: .bold))
                                    .foregroundStyle(APEXColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 6)
                                Button {
                                    guideQuery = MealProtocolGuide.Query(line: line)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(APEXColor.amberDeep)
                                        .frame(width: 34, height: 34)
                                        .background(Circle().stroke(APEXColor.amber.opacity(0.55), lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .background(.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func indexBadge(_ number: Int) -> some View {
        Text("\(number)")
            .font(APEXFont.mono(10, weight: .bold))
            .foregroundStyle(APEXColor.amberDeep)
            .frame(width: 26, height: 26)
            .background(APEXColor.amber.opacity(0.2), in: Circle())
    }

    private func saveGuide() {
        let cleaned = guideDraft
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let key = MealProtocolGuide.overrideKey(
            persona: guidePersona,
            slot: draft.mealSlot,
            goal: guideGoal,
            language: language.language.rawValue
        )
        guideEditing = false
        Task { await session.saveMealProtocolOverride(key: key, lines: cleaned) }
    }

    private var discoveryCard: some View {
        GlassCard(radius: 27, padding: 16) {
            Button { showFoodPicker = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(APEXColor.amberDeep)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Search foods, aliases or brands")
                            .font(APEXFont.body(15, weight: .bold))
                            .foregroundStyle(APEXColor.ink)
                        Text("Food Memory, recent foods and barcode scan")
                            .font(APEXFont.body(11, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 54)
                        .background(APEXColor.amber.gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var presetsCard: some View {
        let presets = session.data.mealPresets
            .filter { !$0.archived && ($0.mealSlot == draft.mealSlot || $0.mealSlot == "any") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if presets.isEmpty == false {
            GlassCard(radius: 27, padding: 16) {
                VStack(alignment: .leading, spacing: 11) {
                    Text("FAST STARTS")
                        .font(APEXFont.mono(10))
                        .tracking(1.3)
                        .foregroundStyle(APEXColor.secondaryInk)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(presets) { preset in
                                Button { apply(preset) } label: {
                                    Label(preset.name, systemImage: "sparkles")
                                        .font(APEXFont.body(12, weight: .bold))
                                        .foregroundStyle(APEXColor.ink)
                                        .padding(.horizontal, 14)
                                        .frame(height: 42)
                                        .background(.white.opacity(0.72), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete preset", role: .destructive) {
                                        Task { await session.deleteMealPreset(preset) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var itemsHeader: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("IN THIS MEAL")
                        .font(APEXFont.mono(10))
                        .tracking(1.5)
                        .foregroundStyle(APEXColor.amberDeep)
                    Text(language.format("%d foods", draft.items.count))
                        .font(APEXFont.display(20))
                }
                Spacer()
                if !selectionMode {
                    Button("Select") { selectionMode = true }
                        .buttonStyle(.bordered)
                        .disabled(draft.items.isEmpty)
                }
            }

            /* A count and two buttons beside a title overflow a phone's width,
               and a clipped view is no longer readable or reachable. Selection
               gets its own line. */
            if selectionMode {
                HStack(spacing: 10) {
                    Text(language.format("%d selected", selectedItemIDs.count))
                        .font(APEXFont.body(13, weight: .bold))
                        .foregroundStyle(APEXColor.amberDeep)
                        .fixedSize()
                    Spacer(minLength: 6)
                    Button("Cancel") {
                        selectionMode = false
                        selectedItemIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    Button("Create preset") {
                        guard selectedItemIDs.isEmpty == false else { return }
                        showPresetCreator = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(APEXColor.amber)
                }
            }

            Picker("Food display", selection: $density) {
                Text("Compact").tag(MealComposerDensity.compact)
                Text("Expanded").tag(MealComposerDensity.expanded)
            }
            .pickerStyle(.segmented)
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            Button {
                Task { await save() }
            } label: {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text(language.format("Save changes & close · %d kcal", Int(draft.totals.kcal.rounded())))
                }
            }
            .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amber))
            .disabled(isSaving || draft.items.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var selectedItems: [MealComposerItem] {
        draft.items.filter { selectedItemIDs.contains($0.id) }
    }

    private var mealTargets: (protein: Double, carbs: Double, fat: Double) {
        guard let profile = session.profile else { return (0, 0, 0) }
        let logs = session.data.activityLogs.filter { $0.date == request.date.apexDateKey }
        let targets = EnergyEngine.targets(profile: profile, logs: logs, catalog: session.data.activityTypes)
        let share: Double
        switch draft.mealSlot {
        case "breakfast": share = 0.25
        case "lunch", "dinner": share = 0.30
        case "post_workout", "post-workout": share = 0.15
        default: share = 0.10
        }
        return (Double(targets.proteinG) * share, Double(targets.carbsG) * share, Double(targets.fatG) * share)
    }

    private func macroCard(_ title: String, value: Double, target: Double) -> some View {
        let over = target > 0 && value > target * 1.15
        return VStack(alignment: .leading, spacing: 6) {
            Text(language.text(title))
                .font(APEXFont.body(10, weight: .bold))
                .foregroundStyle(APEXColor.secondaryInk)
            Text(language.format("%.0f / %.0f g", value, target))
                .font(APEXFont.mono(10))
                .foregroundStyle(over ? APEXColor.danger : APEXColor.ink)
            ProgressView(value: min(value / max(target, 1), 1))
                .tint(over ? APEXColor.danger : APEXColor.amber)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((over ? APEXColor.danger : APEXColor.amber).opacity(0.06), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func itemBinding(for id: UUID) -> Binding<MealComposerItem> {
        Binding(
            get: { draft.items.first(where: { $0.id == id }) ?? draft.items[0] },
            set: { updated in
                guard let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
                draft.items[index] = updated
            }
        )
    }

    private func food(for item: MealComposerItem) -> Food? {
        guard let foodID = item.foodID else { return nil }
        return session.data.foods.first { UUID(uuidString: $0.id) == foodID }
    }

    private func isFavourite(_ item: MealComposerItem) -> Bool {
        guard let foodID = item.foodID else { return false }
        return session.data.foodPreferences.first { $0.foodID == foodID }?.favourite == true
    }

    private func toggleFavourite(_ item: MealComposerItem) {
        guard let food = food(for: item) else { return }
        Task { await session.setFoodFavourite(food, favourite: !isFavourite(item)) }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedItemIDs.contains(id) { selectedItemIDs.remove(id) }
        else { selectedItemIDs.insert(id) }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let source = draft.items.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard draft.items.indices.contains(destination) else { return }
        withAnimation(.snappy) { draft.items.swapAt(source, destination) }
    }

    private func remove(_ id: UUID) {
        withAnimation(.snappy) { draft.items.removeAll { $0.id == id } }
        selectedItemIDs.remove(id)
    }

    private func add(_ food: Food, amount: Double, unit: String) {
        var item = MealComposerItem(food: food, quantity: amount, unit: unit)
        if item.equivalentAmount <= 0 {
            item = MealComposerItem(
                food: food,
                quantity: unit == "g" || unit == "ml" ? max(amount, 100) : 1,
                unit: food.nutritionBasis == "per_100ml" ? "ml" : "g"
            )
        }
        withAnimation(.snappy) { draft.items.append(item) }
    }

    private func apply(_ preset: MealPreset) {
        let foodMap = Dictionary(uniqueKeysWithValues: session.data.foods.compactMap { food -> (UUID, Food)? in
            guard let id = UUID(uuidString: food.id) else { return nil }
            return (id, food)
        })
        let items = session.data.mealPresetItems
            .filter { $0.presetID == preset.id }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { row -> MealComposerItem? in
                guard let food = foodMap[row.foodID] else { return nil }
                return MealComposerItem(food: food, preset: row)
            }
        guard items.isEmpty == false else { return }
        withAnimation(.snappy) {
            draft.items = items
            draft.displayName = preset.name
            draft.sourcePresetID = preset.id
        }
    }

    private func hydrateExistingMeal() {
        guard !hydrated else { return }
        hydrated = true
        guard let meal = request.existingMeal else { return }
        draft.items = session.data.loggedFoodEntries
            .filter { $0.mealID == meal.id }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(MealComposerItem.init(entry:))
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.saveStructuredMeal(draft)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func close() {
        if draft.items.isEmpty { dismiss() }
        else { showDeleteConfirmation = true }
    }

    private static func defaultFinishedAt(on date: Date, slot: String) -> Date {
        let hour: Int
        switch slot {
        case "breakfast": hour = 7
        case "lunch": hour = 13
        case "snack": hour = 16
        case "dinner": hour = 19
        case "post_workout", "post-workout": hour = 21
        default: hour = Calendar.current.component(.hour, from: .now)
        }
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct MealComposerItemCard: View {
    @State private var language = LanguageState.shared
    @Binding var item: MealComposerItem
    let food: Food?
    let density: MealComposerDensity
    let selecting: Bool
    let selected: Bool
    let favourite: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggleSelection: () -> Void
    let onToggleFavourite: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    private var availableUnits: [String] {
        var units = [food?.nutritionBasis == "per_100ml" ? "ml" : "g"]
        if food?.servingGramsOrML != nil { units.append("serving") }
        if food?.pieceGramsOrML != nil { units.append("piece") }
        if !units.contains(item.unit) { units.append(item.unit) }
        return units
    }

    var body: some View {
        GlassCard(radius: density == .compact ? 18 : 25, padding: density == .compact ? 9 : 17) {
            VStack(alignment: .leading, spacing: density == .compact ? 0 : 15) {
                if density == .compact {
                    /* One line, like the web: identity on the left, amount,
                       unit, reorder and remove inline on the right. The old
                       layout wrapped these onto a second row and made every
                       food twice as tall as it needs to be. */
                    HStack(spacing: 7) {
                        if selecting {
                            Button(action: onToggleSelection) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundStyle(selected ? APEXColor.amber : APEXColor.secondaryInk.opacity(0.35))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("meal-item-select-\(item.name)")
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.personalLabel.isEmpty ? item.name : item.personalLabel)
                                .font(APEXFont.display(15))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(language.format(
                                "%d kcal · P %.1f · C %.1f · F %.1f",
                                Int(item.nutrients.kcal.rounded()), item.nutrients.proteinG,
                                item.nutrients.carbsG, item.nutrients.fatG
                            ))
                            .font(APEXFont.mono(8))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        TextField("Amount", value: Binding(
                            get: { item.quantity },
                            set: { item.setQuantity($0, food: food) }
                        ), format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .font(APEXFont.mono(16))
                            .multilineTextAlignment(.center)
                            .frame(width: 52)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                        Picker("Unit", selection: Binding(
                            get: { item.unit },
                            set: { item.setUnit($0, food: food) }
                        )) {
                            ForEach(availableUnits, id: \.self) { unit in
                                Text(language.text(unit)).tag(unit)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .font(APEXFont.body(12, weight: .bold))
                        .frame(width: 54)
                        .padding(.vertical, 1)
                        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(spacing: 1) {
                            Button(action: onMoveUp) { Image(systemName: "arrow.up") }.disabled(!canMoveUp)
                            Button(action: onMoveDown) { Image(systemName: "arrow.down") }.disabled(!canMoveDown)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .buttonStyle(.plain)

                        Button(role: .destructive, action: onDelete) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 28, height: 34)
                                .background(APEXColor.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if density == .expanded {
                HStack(spacing: 11) {
                    if selecting {
                        Button(action: onToggleSelection) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(selected ? APEXColor.amber : APEXColor.secondaryInk.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("meal-item-select-\(item.name)")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.personalLabel.isEmpty ? item.name : item.personalLabel)
                            .font(APEXFont.display(density == .compact ? 16 : 21))
                            .lineLimit(1)
                        if density == .expanded, let brand = item.brand, !brand.isEmpty {
                            Text(brand)
                                .font(APEXFont.body(11, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        Text(language.format(
                            "%d kcal · P %.1f · C %.1f · F %.1f",
                            Int(item.nutrients.kcal.rounded()), item.nutrients.proteinG,
                            item.nutrients.carbsG, item.nutrients.fatG
                        ))
                        .font(APEXFont.mono(9))
                        .foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer(minLength: 3)
                    if !selecting {
                        Button(action: onToggleFavourite) {
                            Image(systemName: favourite ? "star.fill" : "star")
                                .foregroundStyle(favourite ? APEXColor.amber : APEXColor.secondaryInk)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Amount", value: Binding(
                        get: { item.quantity },
                        set: { item.setQuantity($0, food: food) }
                    ), format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .font(APEXFont.mono(density == .compact ? 18 : 22))
                        .multilineTextAlignment(.center)
                        .frame(minWidth: 65)
                        .padding(.vertical, 11)
                        .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Picker("Unit", selection: Binding(
                        get: { item.unit },
                        set: { item.setUnit($0, food: food) }
                    )) {
                        ForEach(availableUnits, id: \.self) { unit in
                            Text(language.text(unit)).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(APEXFont.body(13, weight: .bold))
                    .frame(minWidth: 65)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(spacing: 2) {
                        Button(action: onMoveUp) { Image(systemName: "arrow.up") }.disabled(!canMoveUp)
                        Button(action: onMoveDown) { Image(systemName: "arrow.down") }.disabled(!canMoveDown)
                    }
                    .font(.system(size: 12, weight: .bold))
                    .buttonStyle(.plain)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 39, height: 43)
                            .background(APEXColor.danger.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                } // end expanded two-row layout

                if density == .expanded {
                    Divider()
                    HStack(spacing: 12) {
                        Toggle("Adaptive", isOn: $item.adjustable)
                        Toggle("Lock", isOn: $item.locked)
                    }
                    .toggleStyle(.switch)
                    .font(APEXFont.body(11, weight: .semibold))

                    Picker("Adjustment role", selection: $item.adjustmentRole) {
                        Text("Fixed").tag("none")
                        Text("Carbohydrate first").tag("carb")
                        Text("Protein last").tag("protein")
                        Text("Fat").tag("fat")
                    }
                    .pickerStyle(.menu)

                    TextField("Personal label", text: $item.personalLabel)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

private struct MealFoodPicker: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var language = LanguageState.shared
    let date: Date
    /// Opens already searching, when a guide line said what to look for.
    var initialQuery: String = ""
    /* Food Memory ranks against the meal being built, not the whole day. */
    var slot: String = "lunch"
    var blockID: String?
    var targetTime: String?
    var excludeMealID: UUID?
    let onAdd: (Food, Double, String) -> Void

    @State private var query = ""
    @State private var remoteResults: [Food] = []
    @State private var isSearching = false
    @State private var showScanner = false
    @State private var message: String?
    /* Food whose amount is being configured, and per-food burst counters
       that drive the quick-add confirmation animation. */
    @State private var configuring: Food?
    @State private var burstCounts: [String: Int] = [:]

    private var memoryMode: MealMemory.Mode {
        MealMemory.normalizeMode(session.data.settings?.addons["meal_memory_mode"])
    }

    /* Repeatable starts for this slot, ranked out of logged history: recency,
       same weekday, matching block, time of day and how often it repeats. */
    private var history: MealMemory.Recommendations {
        MealMemory.rank(
            context: MealMemory.Context(
                date: APEXDateMath.key(from: date),
                slot: slot,
                mode: memoryMode,
                blockID: blockID,
                targetTime: targetTime,
                excludeMealID: excludeMealID
            ),
            meals: session.data.loggedMeals,
            entries: session.data.loggedFoodEntries,
            foods: session.data.foods,
            presets: session.data.mealPresets,
            foodLimit: 12
        )
    }

    private func displayedFoods(_ history: MealMemory.Recommendations) -> [Food] {
        let prefs = Dictionary(uniqueKeysWithValues: session.data.foodPreferences.map { ($0.foodID.uuidString.lowercased(), $0) })
        func visible(_ foods: [Food]) -> [Food] {
            foods.filter { prefs[$0.id.lowercased()]?.hidden != true }
        }
        if remoteResults.isEmpty == false { return visible(remoteResults) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return visible(session.data.foods.filter {
                $0.name.localizedCaseInsensitiveContains(trimmed)
                    || ($0.brand?.localizedCaseInsensitiveContains(trimmed) ?? false)
            })
        }
        let ranked = visible(history.foods)
        /* Weekly memory means "what I eat on this weekday", so a populated
           history is not diluted by generally-used foods. */
        let backfill = memoryMode == .weekly && ranked.isEmpty == false
            ? []
            : visible(session.data.foods).filter { food in
                let preference = prefs[food.id.lowercased()]
                return preference?.favourite == true || (preference?.usageCount ?? 0) > 0
            }.sorted { lhs, rhs in
                let left = prefs[lhs.id.lowercased()]
                let right = prefs[rhs.id.lowercased()]
                if (left?.favourite ?? false) != (right?.favourite ?? false) { return left?.favourite == true }
                if (left?.usageCount ?? 0) != (right?.usageCount ?? 0) { return (left?.usageCount ?? 0) > (right?.usageCount ?? 0) }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        var seen: Set<String> = []
        let memory = (ranked + backfill).filter { seen.insert($0.id.lowercased()).inserted }
        /* A brand-new account has no history to rank, so the catalogue stays
           browsable instead of showing an empty list before the first search. */
        if memory.isEmpty {
            return visible(session.data.foods)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return memory
    }

    var body: some View {
        /* Rank once per render; every row reads the same remembered amounts. */
        let history = self.history
        let remembered: [String: MealMemory.Selection] = Dictionary(
            history.selections.map { ($0.foodID.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { showScanner = true } label: {
                            Label("Scan barcode", systemImage: "barcode.viewfinder")
                                .font(APEXFont.body(14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .foregroundStyle(.white)
                                .background(APEXColor.amber.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if isSearching { ProgressView("Searching APEX Food Memory").padding(.vertical, 18) }
                    if let message {
                        Text(language.text(message))
                            .font(APEXFont.body(12, weight: .medium))
                            .foregroundStyle(APEXColor.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(APEXColor.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }

                    ForEach(displayedFoods(history)) { food in
                        HStack(spacing: 12) {
                            /* Tapping the food opens the amount configurator,
                               matching the web composer. Only + quick-adds. */
                            Button { configuring = food } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(food.name)
                                        .font(APEXFont.body(15, weight: .bold))
                                        .foregroundStyle(APEXColor.ink)
                                        .lineLimit(1)
                                    Text(foodSubtitle(food, remembered: remembered[food.id.lowercased()]))
                                        .font(APEXFont.body(10, weight: .medium))
                                        .foregroundStyle(APEXColor.secondaryInk)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("food-row-\(food.id)")
                            .accessibilityHint(language.text("Configure amount"))

                            Button { quickAdd(food, remembered: remembered[food.id.lowercased()]) } label: {
                                ZStack {
                                    Image(systemName: "plus")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(APEXColor.amberDeep)
                                        .frame(width: 48, height: 48)
                                        .background(APEXColor.amber.opacity(0.1), in: Circle())
                                        .quickAddKick(trigger: burstCounts[food.id] ?? 0)
                                    QuickAddBurst(trigger: burstCounts[food.id] ?? 0)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("food-quick-add-\(food.id)")
                            .accessibilityLabel(language.format("Quick add %@", food.name))
                        }
                        .padding(14)
                        .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                    }
                }
                .padding(16)
            }
            .background(APEXBackground())
            .navigationTitle("Food Memory")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search foods, aliases or brands")
            .onSubmit(of: .search) { Task { await search() } }
            .onChange(of: query) { _, value in if value.isEmpty { remoteResults = []; message = nil } }
            .onAppear { if query.isEmpty { query = initialQuery } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await search() } } label: { Image(systemName: "magnifyingglass") }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                BarcodeScannerView(date: date) { food, amount, unit in
                    onAdd(food, amount, unit)
                    showScanner = false
                }
            }
            .apexPopover(item: $configuring) { food in
                FoodAmountSheet(
                    food: food,
                    preference: preference(for: food),
                    remembered: remembered[food.id.lowercased()],
                    onClose: { configuring = nil }
                ) { amount, unit in
                    onAdd(food, amount, unit)
                }
            }
        }
    }

    private func preference(for food: Food) -> FoodPreference? {
        UUID(uuidString: food.id).flatMap { id in
            session.data.foodPreferences.first { $0.foodID == id }
        }
    }

    /* + adds the remembered portion straight away. The default now comes
       from the same beginFoodSelection rules the web uses, so the quantity
       shown in the configurator and the quantity + adds are the same. */
    private func quickAdd(_ food: Food, remembered: MealMemory.Selection?) {
        let start = FoodPortionMath.defaultSelection(food, preference: preference(for: food), remembered: remembered)
        onAdd(food, start.quantity, start.unit.rawValue)
        burstCounts[food.id, default: 0] += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /* The row states the amount the + button will actually log: the grams this
       food was last confirmed at, not an abstract per-100 figure. */
    private func foodSubtitle(_ food: Food, remembered: MealMemory.Selection?) -> String {
        let preference = preference(for: food)
        let start = FoodPortionMath.defaultSelection(food, preference: preference, remembered: remembered)
        let usedBefore = (preference?.usageCount ?? 0) > 0
            && preference?.usualAmount != nil
            && preference?.usualUnit != nil
        let saved = remembered != nil || usedBefore
        let lead = language.text(saved ? "Last used" : "Suggested portion")
        var parts = [lead + " · " + describeAmount(food, start.quantity, start.unit)]
        if let portion = FoodPortionMath.portion(food, quantity: start.quantity, unit: start.unit) {
            parts.append(language.format("%d kcal", Int(portion.kcal.rounded())))
        }
        if let brand = food.brand, !brand.isEmpty { parts.append(brand) }
        return parts.joined(separator: " · ")
    }

    private func describeAmount(_ food: Food, _ quantity: Double, _ unit: FoodUnitKind) -> String {
        let rounded = (quantity * 10).rounded() / 10
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        switch unit {
        case .serving, .piece:
            let equivalent = FoodPortionMath.equivalentAmount(food, quantity: quantity, unit: unit)
            let basis = food.nutritionBasis == "per_100ml" ? "ml" : "g"
            let label = language.text(unit == .piece ? "piece" : "serving")
            guard let equivalent else { return "\(number) × \(label)" }
            return "\(number) × \(label) · \(Int(equivalent.rounded())) \(basis)"
        default:
            return "\(number) \(unit.rawValue)"
        }
    }

    @MainActor
    private func search() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 2 else { return }
        isSearching = true
        message = nil
        defer { isSearching = false }
        do {
            remoteResults = try await session.searchFoods(query: value)
            if remoteResults.isEmpty { message = "No reliable nutrition match was returned." }
        } catch {
            remoteResults = []
            message = "Online search is unavailable. Your saved Food Memory remains usable."
        }
    }
}

private struct PresetCreationSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let mealSlot: String
    let items: [MealComposerItem]
    let onSaved: () -> Void

    @State private var title = ""
    @State private var subtitle = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Keep this combination")
                    .font(APEXFont.display(24))
                TextField("Preset title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(APEXFont.display(18))
                TextField("Subtitle (optional)", text: $subtitle)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView().tint(.white) }
                    else { Text("Save preset") }
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.amber))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                Text("Presets are reusable food groups. Add several presets to one meal without renaming the meal itself.")
                    .font(APEXFont.body(12, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                Spacer()
            }
            .padding(20)
            .background(APEXBackground())
            .navigationTitle("Create preset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Could not save preset", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "Please try again.") }
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await session.saveMealPreset(name: title, mealSlot: mealSlot, items: items, subtitle: subtitle)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
