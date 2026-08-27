import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var health = HealthKitManager.shared
    @State private var language = LanguageState.shared
    @State private var entitlements = EntitlementStore.shared
    @State private var showPaywall = false
    @State private var showLogout = false
    @State private var pendingNewbieMode = false
    @State private var confirmRestorePlan = false
    @State private var timeZoneDraft = ""
    @State private var measuredBMRDraft = ""

    private var settings: UserSettings? { session.data.settings }
    private var profile: Profile? { session.profile }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                APEXTopBar(profile: profile)
                pageHeader
                identityCard
                simpleModeCard
                daylineCard
                recoveryCard
                bodyProfileCard
                playerCard
                cameraCard
                addOnCard
                membershipCard
                healthCard
                accountCard
            }
            .padding(18)
            .padding(.bottom, 30)
.dockClearance()
        }
        .navigationTitle(language.text(.settings))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: profile?.userID) {
            timeZoneDraft = addonString("time_zone", default: TimeZone.current.identifier)
            measuredBMRDraft = settings?.addons["custom_bmr"]?.numberValue.map { String(Int($0.rounded())) } ?? ""
        }
        .confirmationDialog(language.text(.logoutWarning), isPresented: $showLogout, titleVisibility: .visible) {
            Button(language.text(.yesLogout), role: .destructive) { Task { await session.signOut() } }
            Button(language.text(.cancel), role: .cancel) {}
        }
    }

    /// What this account is entitled to, in plain words, and a way to see the
    /// available tiers without implying a temporary free-access period.
    private var membershipCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(language.text("Membership"))
                    .font(APEXFont.body(17, weight: .bold))
                Text(membershipStatus)
                    .font(APEXFont.body(13))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                /* A founding account has nothing to buy, so it is not shown a
                   price list it can never need. */
                if entitlements.access != .founding {
                    Button(language.text("See the plans")) { showPaywall = true }
                        .font(APEXFont.body(14, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView { showPaywall = false }
        }
    }

    private var membershipStatus: String {
        switch entitlements.access {
        case .founding:
            language.text("Founding account. Full access, permanently, with nothing to pay.")
        case .beta:
            language.text("Unlocked with a beta code.")
        case .subscribed(let tier):
            language.format("Subscribed to %@.", language.text(tier == .premium ? "Premium" : "Coach"))
        case .locked:
            language.text("Premium access or a beta code is required.")
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(language.text(.settings)).font(APEXFont.display(38))
            Text(language.text("Profile, targets and preferences"))
                .font(APEXFont.body(15, weight: .medium))
                .foregroundStyle(APEXColor.secondaryInk)
            Capsule().fill(APEXColor.violet.gradient).frame(width: 64, height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityCard: some View {
        GlassCard(radius: 31, padding: 21) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top, spacing: 14) {
                    ProfileAvatarPicker()
                    VStack(alignment: .leading, spacing: 5) {
                        Text(language.text("ACTIVE IDENTITY"))
                            .font(APEXFont.mono(10)).tracking(2)
                            .foregroundStyle(APEXColor.secondaryInk)
                        Text(profile?.displayName ?? "APEX")
                            .font(APEXFont.display(26))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Text((profile?.persona.displayName ?? "APEX").uppercased(with: language.language.locale))
                        .font(APEXFont.mono(9)).tracking(1.1).foregroundStyle(APEXColor.violet)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .overlay(Capsule().stroke(APEXColor.violet.opacity(0.3)))
                }
                Text(language.text(profile?.profileNote ?? "Your private performance system."))
                    .font(APEXFont.body(14, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk).lineSpacing(4)
                HStack(spacing: 8) {
                    identityMetric("KCAL", profile?.targetKcal.map(String.init) ?? "—")
                    identityMetric("PROTEIN", profile?.targetProteinG.map { "\($0)g" } ?? "—")
                    identityMetric("FAT", profile?.targetFatG.map { "\($0)g" } ?? "—")
                    identityMetric("CARBS", profile?.targetCarbsG.map { "\($0)g" } ?? "—")
                }
            }
        }
    }

    private var simpleModeCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 17) {
                sectionTitle("Simple Mode", subtitle: "Choose exactly what stays visible on your distraction-free home screen.")
                settingGroup(title: "Interface mode", subtitle: "Clean hides optional guidance. Detailed keeps the extra context visible.", tint: APEXColor.violet) {
                    choiceRow(options: [("Clean", "clean"), ("Detailed", "detailed")], selected: addonString("interface_mode", default: "clean")) {
                        setAddon("interface_mode", .string($0))
                    }
                }
                settingGroup(title: "Weight unit", subtitle: nil, tint: APEXColor.cyan) {
                    choiceRow(options: [("Kilograms (kg)", "kg"), ("Pounds (lb)", "lb")], selected: addonString("weight_unit", default: "kg")) {
                        setAddon("weight_unit", .string($0))
                    }
                }
                VStack(spacing: 0) {
                    simpleToggle("Show APEX Orbit shortcut", key: "simple_show_orbit", default: true)
                    Divider(); simpleToggle("Show Body Index shortcut", key: "simple_show_body_index", default: true)
                    Divider(); simpleToggle("Show guided workout card", key: "simple_show_guided_plan", default: true)
                    Divider(); simpleToggle("Show hydration reminder card", key: "simple_show_hydration_reminder", default: false)
                    Divider(); simpleToggle("Show workout summary card", key: "simple_show_manual_workout", default: false)
                    Divider(); simpleToggle("Show next action card", key: "simple_show_next_action", default: false)
                }
                settingGroup(title: "ADHD mode", subtitle: "Only nutrition, four quick actions and your editable workout stay visible. Everything else is hidden from Simple Mode.", tint: APEXColor.violet) {
                    Toggle("", isOn: addonBinding("adhd_mode", default: false))
                        .labelsHidden().tint(APEXColor.teal)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var daylineCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 17) {
                sectionTitle("Meal Dayline", subtitle: "Control the clock, spacing and Food Memory shared with the web app.")
                settingGroup(title: "Meal dayline timezone", subtitle: "Controls the live clock, meal positions and pre-workout timing analysis.", tint: APEXColor.green) {
                    VStack(spacing: 10) {
                        TextField("Europe/Zurich", text: $timeZoneDraft)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(APEXFont.mono(13)).padding(13)
                            .background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        HStack {
                            Button(language.text("Use device timezone")) {
                                timeZoneDraft = TimeZone.current.identifier
                                setAddon("time_zone", .string(timeZoneDraft))
                            }.buttonStyle(.bordered)
                            Button(language.text("Set timezone")) {
                                let valid = TimeZone(identifier: timeZoneDraft) != nil ? timeZoneDraft : TimeZone.current.identifier
                                timeZoneDraft = valid
                                setAddon("time_zone", .string(valid))
                            }.buttonStyle(.borderedProminent).tint(APEXColor.teal)
                        }
                    }
                }
                settingGroup(title: "Dayline spacing", subtitle: "Choose the vertical space between hours.", tint: APEXColor.cyan) {
                    choiceRow(options: [("Compact", "compact"), ("Medium", "medium"), ("Long", "long")], selected: addonString("meal_dayline_density", default: "medium")) {
                        setAddon("meal_dayline_density", .string($0))
                    }
                }
                settingGroup(
                    title: "Camera & comparison",
                    subtitle: "Choose what appears on exported progress comparisons.",
                    tint: APEXColor.violet
                ) {
                    VStack(alignment: .leading, spacing: 13) {
                        settingToggle(
                            "Allow front camera for food scanning",
                            subtitle: "Off keeps every new scan on the rear camera. Turn this on only when you need a camera switch.",
                            value: addonBool("allow_front_camera_scanning", default: false)
                        ) { setAddon("allow_front_camera_scanning", .bool($0)) }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(language.text("Comparison export stats"))
                                .font(APEXFont.body(12, weight: .bold))
                                .foregroundStyle(APEXColor.ink)
                            choiceRow(
                                options: [("Minimal", "minimal"), ("Detailed", "detailed")],
                                selected: addonString("comparison_export_mode", default: "detailed")
                            ) {
                                setAddon("comparison_export_mode", .string($0))
                            }
                            Text(language.text("Minimal exports show only APEX, Before/After, and each photo's date and time."))
                                .font(APEXFont.body(9))
                                .foregroundStyle(APEXColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                /* Detected from the device, never asked. The override is here
                   for what detection cannot see: someone who moved and kept
                   their old App Store country, or who shops across a border. */
                settingGroup(
                    title: "Food region",
                    subtitle: language.format(
                        "Detected: %@. Sets units, energy display and which products rank first.",
                        language.text(FoodRegion.detected().title)
                    ),
                    tint: APEXColor.violet
                ) {
                    choiceRow(
                        options: FoodRegion.allCases.map { (language.text($0.title), $0.rawValue) },
                        selected: FoodRegion.resolved(settings).rawValue
                    ) {
                        setAddon("food_region", .string($0))
                    }
                }
                settingGroup(title: "Meal-specific food memory", subtitle: "Daily prioritizes recent foods. Weekly prioritizes the same weekday.", tint: APEXColor.amber) {
                    choiceRow(options: [("Daily", "daily"), ("Weekly", "weekly")], selected: addonString("meal_memory_mode", default: "daily")) {
                        setAddon("meal_memory_mode", .string($0))
                    }
                }
                settingGroup(title: "Meal movement step", subtitle: "The meal-finished time snaps to this step and syncs to your account.", tint: APEXColor.cyan) {
                    choiceRow(
                        options: [("5 min", "5"), ("15 min", "15"), ("30 min", "30"), ("1 hour", "60")],
                        selected: String(Int(settings?.addons["meal_timeline_snap_minutes"]?.numberValue ?? 30))
                    ) { setAddon("meal_timeline_snap_minutes", .number(Double($0) ?? 30)) }
                }
                settingToggle("Adapt late post-workout meals to dinner", subtitle: "After 19:00, use your complete dinner foods instead of a snack-only list.", value: addonBool("adaptive_post_workout_dinner", default: true)) {
                    setAddon("adaptive_post_workout_dinner", .bool($0))
                }
                settingGroup(title: "Meal blocks", subtitle: "Choose the meals that define daily completion and their usual times.", tint: APEXColor.amber) {
                    VStack(spacing: 9) {
                        ForEach(mealBlocks, id: \.id) { block in
                            HStack(spacing: 10) {
                                Button { updateMealBlock(block.id, enabled: !block.enabled) } label: {
                                    Image(systemName: block.enabled ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(block.enabled ? APEXColor.amber : APEXColor.secondaryInk)
                                }.buttonStyle(.plain)
                                Text(language.text(block.label)).font(APEXFont.body(13, weight: .bold))
                                Spacer()
                                Button { moveMealBlock(block.id, minutes: -15) } label: { Image(systemName: "minus") }.buttonStyle(.bordered)
                                Text(block.time).font(APEXFont.mono(12)).frame(width: 52)
                                Button { moveMealBlock(block.id, minutes: 15) } label: { Image(systemName: "plus") }.buttonStyle(.bordered)
                            }
                            .padding(11)
                            .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var recoveryCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 17) {
                sectionTitle("Recovery data source", subtitle: "Apple Health sleep, HRV and resting heart rate import automatically. Earlier history keeps its source and is never reinterpreted.")
                choiceRow(options: [("Apple", "apple"), ("Other", "other")], selected: addonString("recovery_data_source", default: "apple")) {
                    setAddon("recovery_data_source", .string($0))
                }
                Text(language.text("Apple Health context is imported automatically. Choose Other to enter a 0 to 100 recovery score from any watch or app that does not publish one to HealthKit."))
                    .font(APEXFont.body(10, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                /* Switching this on shows a generated beginner block instead
                   of the established programme. Nothing is deleted, but it
                   looks exactly like loss, so it asks first. */
                settingToggle("I’m a newbie", subtitle: "Turn on the short induction in Transition and Main Phase.", value: addonBool("newbie_mode", default: false)) { enabled in
                    if enabled {
                        pendingNewbieMode = true
                    } else {
                        Task { await session.restoreOriginalProgramme() }
                    }
                }
                .disabled(session.isBusy)

                if addonBool("newbie_mode", default: false) || hasInduction {
                    Button {
                        confirmRestorePlan = true
                    } label: {
                        Text(language.text("Restore my original programme"))
                            .font(APEXFont.body(14, weight: .bold))
                            .foregroundStyle(APEXColor.green)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(APEXColor.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isBusy)
                }
            }
        }
        .alert(language.text("Turn on starter mode?"), isPresented: $pendingNewbieMode) {
            Button(language.text("Cancel"), role: .cancel) {}
            Button(language.text("Continue")) { setAddon("newbie_mode", .bool(true)) }
        } message: {
            Text(language.text("Starter mode shows a generated beginner block instead of your current programme. Your programme is kept and returns when you switch this off."))
        }
        .alert(language.text("Restore your original programme?"), isPresented: $confirmRestorePlan) {
            Button(language.text("Cancel"), role: .cancel) {}
            Button(language.text("Restore")) {
                Task { await session.restoreOriginalProgramme() }
            }
            .disabled(session.isBusy)
        } message: {
            Text(language.text("This clears the generated starter plan and brings your own programme back into every calendar."))
        }
    }

    private var hasInduction: Bool {
        TrainingInduction.hasRestorableOverlay(in: session.data)
    }

    private var bodyProfileCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 17) {
                sectionTitle("Body profile", subtitle: language.format("Age %d, computed from your birthdate. Never hardcoded.", profile?.age ?? 0))
                profileStepper("Weight", value: profile?.weightKG ?? 0, unit: "kg", step: 0.5) { delta in
                    Task { await session.updateProfile { $0.weightKG = max(25, $0.weightKG + delta) } }
                }
                Divider()
                profileStepper("Body fat", value: profile?.bodyFatPercent ?? 0, unit: "%", step: 0.5) { delta in
                    Task { await session.updateProfile { $0.bodyFatPercent = min(70, max(2, $0.bodyFatPercent + delta)) } }
                }
                Divider()
                profileStepper("Height", value: profile?.heightCM ?? 0, unit: "cm", step: 1) { delta in
                    Task { await session.updateProfile { $0.heightCM = min(240, max(100, $0.heightCM + delta)) } }
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Text(language.text("Measured BMR (optional)")).font(APEXFont.display(17))
                    Text(language.text("Use an exact value from DEXA or indirect calorimetry. Clear it to return to the calculated formula."))
                        .font(APEXFont.body(11, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                    HStack {
                        TextField("1559", text: $measuredBMRDraft)
                            .keyboardType(.numberPad).font(APEXFont.mono(16)).multilineTextAlignment(.trailing)
                            .padding(13).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        Text("kcal").font(APEXFont.mono(11))
                        Button(language.text("Save")) {
                            if let value = Double(measuredBMRDraft), (700...4000).contains(value) { setAddon("custom_bmr", .number(value)) }
                            else { setAddon("custom_bmr", .null) }
                        }.buttonStyle(.borderedProminent).tint(APEXColor.violet)
                    }
                }
                profileTextRow("Birthdate", value: profile?.birthdate ?? "") { next in
                    Task { await session.updateProfile { $0.birthdate = next } }
                }
                profileTextRow("Default training time", value: profile?.trainingTime ?? "19:00") { next in
                    Task { await session.updateProfile { $0.trainingTime = next } }
                }
            }
        }
    }

    private var playerCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 3) {
                sectionTitle("Player", subtitle: nil)
                settingsToggle("Voice announcements", icon: "waveform", value: settings?.voiceOn ?? true) { next in
                    Task { await session.updateSettings { $0.voiceOn = next } }
                }
                Divider()
                settingsToggle("Cadence ticks", icon: "metronome", value: settings?.ticksOn ?? true) { next in
                    Task { await session.updateSettings { $0.ticksOn = next } }
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("Overload Guardian sensitivity")).font(APEXFont.body(14, weight: .bold))
                        Text(language.text("Warn when a jump exceeds this multiple of your typical increment"))
                            .font(APEXFont.body(10, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                    }
                    Spacer()
                    Button { adjustGuardian(-0.1) } label: { Image(systemName: "minus") }.buttonStyle(.bordered)
                    Text((settings?.guardianFactor ?? 1.5).formatted(.number.precision(.fractionLength(1))))
                        .font(APEXFont.mono(16)).frame(width: 42)
                    Button { adjustGuardian(0.1) } label: { Image(systemName: "plus") }.buttonStyle(.borderedProminent).tint(APEXColor.violet)
                }.padding(.vertical, 11)
                Divider()
                settingsToggle("Meal + stack reminders", icon: "bell", value: settings?.notificationsOn ?? false) { next in
                    Task { await session.updateSettings { $0.notificationsOn = next } }
                }
            }
        }
    }

    private var cameraCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 17) {
                sectionTitle("Camera & comparison", subtitle: "Choose what appears on exported progress comparisons.")
                settingGroup(title: "Comparison export stats", subtitle: "Minimal shows only APEX, Before/After, and each photo’s date and time.", tint: APEXColor.violet) {
                    choiceRow(options: [("Minimal", "minimal"), ("Detailed", "detailed")], selected: addonString("comparison_export_mode", default: "detailed")) {
                        setAddon("comparison_export_mode", .string($0))
                    }
                }
            }
        }
    }

    private var addOnCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("Main Phase add-on protocols", subtitle: "Off by default. They appear inside Main Phase sessions when on.").padding(.bottom, 8)
                settingsToggle("Endurance Phase 1", icon: "1.circle", value: addonBool("endurance1", default: false)) { setAddon("endurance1", .bool($0)) }
                Divider(); settingsToggle("Endurance Phase 2", icon: "2.circle", value: addonBool("endurance2", default: false)) { setAddon("endurance2", .bool($0)) }
                Divider(); settingsToggle("Endurance Phase 3", icon: "3.circle", value: addonBool("endurance3", default: false)) { setAddon("endurance3", .bool($0)) }
            }
        }
    }

    private var healthCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 13) {
                    Image(systemName: "heart.text.square.fill").font(.system(size: 31)).foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(language.text("Apple Health import")).font(APEXFont.display(22))
                        Text(language.text("Nutrition, water, weight, VO₂ max, resting heart rate and workouts feed the engine."))
                            .font(APEXFont.body(11, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                    }
                }
                Text(language.text("Anything logged manually in APEX wins over imported values. Imports only add signal and never create decay."))
                    .font(APEXFont.body(11, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                Button {
                    Task { if let snapshot = await health.requestAccessAndImport() { await session.applyHealthSnapshot(snapshot) } }
                } label: {
                    if health.isSyncing { ProgressView().tint(.white) }
                    else { Label(language.text(health.isAuthorized ? "Sync now" : "Connect Apple Health"), systemImage: "heart.fill") }
                }
                .buttonStyle(APEXPrimaryButtonStyle(color: .red))
                if let snapshot = health.lastSnapshot {
                    HStack(spacing: 12) {
                        healthMetric("WATER", snapshot.dietaryWaterL, "L")
                        healthMetric("STEPS", snapshot.steps, "")
                        healthMetric("ACTIVE", snapshot.activeEnergyKcal, "kcal")
                    }
                }
                waterSharingStatus
                if let message = health.message {
                    Text(language.text(message)).font(APEXFont.body(11, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                }
            }
        }
    }

    @ViewBuilder
    private var waterSharingStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: health.waterWriteState == .authorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(health.waterWriteState == .authorized ? APEXColor.teal : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text("Apple Health water sharing"))
                    .font(APEXFont.body(12, weight: .bold))
                Text(language.text(waterSharingExplanation))
                    .font(APEXFont.body(11, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if health.waterWriteState != .authorized {
            Button {
                Task { await health.reconnectWaterAccess() }
            } label: {
                Label(language.text("Reconnect water access"), systemImage: "drop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(APEXColor.teal)
        }
    }

    private var waterSharingExplanation: String {
        switch health.waterWriteState {
        case .authorized:
            return "Connected. APEX, your Watch and other allowed apps share the HealthKit dietary-water ledger."
        case .denied:
            return "Water write access is off. Open Health > profile > Apps and Services > APEX and enable Water."
        case .notDetermined:
            return "Connect to publish APEX drink and food water and import water recorded by your Watch or other apps."
        case .unavailable:
            return "Apple Health water tracking is unavailable on this device."
        }
    }

    private var accountCard: some View {
        GlassCard(radius: 31, padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(language.text("Account")).font(APEXFont.display(22))
                Text(profile?.displayName ?? "APEX").font(APEXFont.body(15, weight: .bold))
                Text(language.text("Your records remain private under Supabase row-level security and are shared only between your authenticated APEX clients."))
                    .font(APEXFont.body(12, weight: .medium)).foregroundStyle(APEXColor.secondaryInk)
                Button(role: .destructive) { showLogout = true } label: {
                    Label(language.text("Log out"), systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(APEXColor.danger)
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(language.text(title)).font(APEXFont.display(24))
            if let subtitle {
                Text(language.text(subtitle)).font(APEXFont.body(12, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk).lineSpacing(3)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingGroup<Content: View>(title: String, subtitle: String?, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text(title)).font(APEXFont.display(17))
            if let subtitle {
                Text(language.text(subtitle)).font(APEXFont.body(11, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk).lineSpacing(3)
            }
            content()
        }
        .padding(15)
        .background(tint.opacity(0.045), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(tint.opacity(0.15)))
    }

    private func choiceRow(options: [(String, String)], selected: String, onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.1) { option in
                Button { onSelect(option.1) } label: {
                    Text(language.text(option.0)).font(APEXFont.body(11, weight: .bold))
                        .foregroundStyle(selected == option.1 ? APEXColor.violet : APEXColor.secondaryInk)
                        .frame(maxWidth: .infinity).frame(minHeight: 45)
                        .background(selected == option.1 ? .white : .clear, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .shadow(color: selected == option.1 ? .black.opacity(0.07) : .clear, radius: 7, y: 3)
                }.buttonStyle(.plain)
            }
        }
        .padding(3).background(APEXColor.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func simpleToggle(_ title: String, key: String, default value: Bool) -> some View {
        settingToggle(title, subtitle: nil, value: addonBool(key, default: value)) { setAddon(key, .bool($0)) }
    }

    private func settingToggle(_ title: String, subtitle: String?, value: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(language.text(title)).font(APEXFont.body(14, weight: .bold))
                if let subtitle {
                    Text(language.text(subtitle)).font(APEXFont.body(10, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk).lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { value }, set: onChange)).labelsHidden().tint(APEXColor.teal)
        }.padding(.vertical, 10)
    }

    private func settingsToggle(_ title: String, icon: String, value: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(APEXColor.violet).frame(width: 34)
            Text(language.text(title)).font(APEXFont.body(14, weight: .semibold))
            Spacer()
            Toggle("", isOn: Binding(get: { value }, set: onChange)).labelsHidden().tint(APEXColor.violet)
        }.frame(minHeight: 56)
    }

    private func identityMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(title).font(APEXFont.mono(8)).foregroundStyle(APEXColor.secondaryInk)
            Text(value).font(APEXFont.mono(13))
        }.frame(maxWidth: .infinity)
    }

    private func profileStepper(_ title: String, value: Double, unit: String, step: Double, adjust: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(language.text(title)).font(APEXFont.display(17)); Spacer()
            Button { adjust(-step) } label: { Image(systemName: "minus") }.buttonStyle(.borderedProminent).tint(APEXColor.violet)
            Text("\(value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 1)))) \(language.text(unit))")
                .font(APEXFont.mono(16)).frame(minWidth: 82)
            Button { adjust(step) } label: { Image(systemName: "plus") }.buttonStyle(.borderedProminent).tint(APEXColor.violet)
        }
    }

    private func profileTextRow(_ title: String, value: String, save: @escaping (String) -> Void) -> some View {
        HStack {
            Text(language.text(title)).font(APEXFont.display(16)); Spacer()
            TextField("", text: Binding(get: { value }, set: save))
                .font(APEXFont.mono(13)).multilineTextAlignment(.trailing).padding(12).frame(maxWidth: 150)
                .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func addonBool(_ key: String, default fallback: Bool) -> Bool { settings?.addons[key]?.boolValue ?? fallback }
    private func addonString(_ key: String, default fallback: String) -> String { settings?.addons[key]?.stringValue ?? fallback }
    private func addonBinding(_ key: String, default fallback: Bool) -> Binding<Bool> {
        Binding(get: { addonBool(key, default: fallback) }, set: { setAddon(key, .bool($0)) })
    }
    private func setAddon(_ key: String, _ value: JSONValue) {
        Task { await session.updateSettings { $0.addons[key] = value } }
    }
    private func adjustGuardian(_ delta: Double) {
        Task { await session.updateSettings { $0.guardianFactor = min(3, max(1, (($0.guardianFactor + delta) * 10).rounded() / 10)) } }
    }

    private var mealBlocks: [NativeMealBlock] {
        let defaults = NativeMealBlock.defaults
        guard let values = settings?.addons["meal_blocks"]?.objectValue?["blocks"]?.arrayValue else { return defaults }
        let supplied = values.compactMap(NativeMealBlock.init(json:))
        return defaults.map { fallback in supplied.first(where: { $0.id == fallback.id }) ?? fallback }
    }
    private func updateMealBlock(_ id: String, enabled: Bool) {
        var blocks = mealBlocks
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        if !enabled, blocks.filter(\.enabled).count == 1 { return }
        blocks[index].enabled = enabled; saveMealBlocks(blocks)
    }
    private func moveMealBlock(_ id: String, minutes delta: Int) {
        var blocks = mealBlocks
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        let pieces = blocks[index].time.split(separator: ":").compactMap { Int($0) }
        let current = (pieces.first ?? 0) * 60 + (pieces.dropFirst().first ?? 0)
        let next = (current + delta + 1440) % 1440
        blocks[index].time = String(format: "%02d:%02d", next / 60, next % 60)
        saveMealBlocks(blocks)
    }
    private func saveMealBlocks(_ blocks: [NativeMealBlock]) {
        var root = settings?.addons["meal_blocks"]?.objectValue ?? [:]
        root["blocks"] = .array(blocks.map(\.json))
        if root["custom_blocks"] == nil { root["custom_blocks"] = .array([]) }
        if root["preset_assignments"] == nil { root["preset_assignments"] = .object([:]) }
        setAddon("meal_blocks", .object(root))
    }
    private func healthMetric(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(language.text(title)).font(APEXFont.mono(8)).foregroundStyle(APEXColor.secondaryInk)
            Text(value.map { language.format("%d %@", Int($0.rounded()), language.text(unit)) } ?? "—").font(APEXFont.display(15))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NativeMealBlock: Hashable {
    let id: String
    let label: String
    var time: String
    var enabled: Bool

    static let defaults: [NativeMealBlock] = [
        .init(id: "breakfast", label: "Breakfast", time: "07:00", enabled: true),
        .init(id: "lunch", label: "Lunch", time: "13:00", enabled: true),
        .init(id: "dinner", label: "Dinner", time: "19:00", enabled: true),
        .init(id: "snack", label: "Snack", time: "16:00", enabled: true),
        .init(id: "post_workout", label: "Post-workout", time: "21:00", enabled: true),
    ]

    init(id: String, label: String, time: String, enabled: Bool) {
        self.id = id; self.label = label; self.time = time; self.enabled = enabled
    }
    init?(json: JSONValue) {
        guard let object = json.objectValue, let id = object["id"]?.stringValue, let time = object["time"]?.stringValue else { return nil }
        self.id = id
        self.label = NativeMealBlock.defaults.first(where: { $0.id == id })?.label ?? id
        self.time = time
        self.enabled = object["enabled"]?.boolValue ?? true
    }
    var json: JSONValue {
        .object(["id": .string(id), "kind": .string(id), "time": .string(time), "enabled": .bool(enabled)])
    }
}
