import SwiftUI

struct MarathonInductionView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var answers = OrbitCampaignEngine.emptyAnswers
    @State private var inductionID = UUID()
    @State private var step = 0
    @State private var createdAt = Date().ISO8601Format()
    @State private var loaded = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var language = LanguageState.shared

    private var question: InductionQuestion { questions[min(step, questions.count - 1)] }
    private var progress: Double { Double(step + 1) / Double(questions.count) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("FITNESS-READINESS CHECK")
                            .font(APEXFont.mono(10))
                            .tracking(1.5)
                            .foregroundStyle(APEXColor.cyan)
                        Spacer()
                        Text("\(step + 1) / \(questions.count)")
                            .font(APEXFont.mono(10))
                    }
                    ProgressView(value: progress)
                        .tint(APEXColor.cyan)
                    Text("APEX reuses your age, profile and strength plan. It asks only for missing running context.")
                        .font(APEXFont.body(11, weight: .medium))
                        .foregroundStyle(APEXColor.secondaryInk)
                }

                GlassCard(radius: 34, padding: 22) {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: question.icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(APEXColor.cyan)
                            .frame(width: 56, height: 56)
                            .background(APEXColor.cyan.opacity(0.1), in: Circle())
                        Text(language.text(question.title))
                            .font(APEXFont.display(29))
                        if question.helper.isEmpty == false {
                            Text(language.text(question.helper))
                                .font(APEXFont.body(13, weight: .medium))
                                .foregroundStyle(APEXColor.secondaryInk)
                        }
                        answerControl
                    }
                }

                if let message {
                    Text(language.text(message))
                        .font(APEXFont.body(11, weight: .semibold))
                        .foregroundStyle(APEXColor.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    Button {
                        if step == 0 { dismiss() }
                        else { withAnimation(.snappy) { step -= 1 } }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button { Task { await next() } } label: {
                        if isSaving { ProgressView().tint(.white) }
                        else {
                            Label(language.text(step == questions.count - 1 ? "Complete induction" : "Next"), systemImage: "arrow.right")
                        }
                    }
                    .buttonStyle(APEXPrimaryButtonStyle(color: APEXColor.cyan))
                    .disabled(isSaving || hasAnswer == false)
                }

                Text("This check assigns a training recommendation. It does not provide medical clearance or diagnose a condition.")
                    .font(APEXFont.body(9, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .padding(.bottom, 30)
        }
        .navigationTitle("Marathon induction")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadExisting() }
    }

    @ViewBuilder
    private var answerControl: some View {
        switch question.kind {
        case .text(let prompt):
            TextField(language.text(prompt), text: stringBinding(question.key))
                .textInputAutocapitalization(.words)
                .padding(15)
                .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 19))

        case .date:
            DatePicker(
                "Race date",
                selection: dateBinding(question.key),
                in: Calendar.current.date(byAdding: .day, value: 1, to: .now)!...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(APEXColor.cyan)

        case .single(let choices):
            VStack(spacing: 9) {
                ForEach(choices) { choice in
                    choiceButton(choice, selected: answers[question.key]?.stringValue == choice.value) {
                        answers[question.key] = .string(choice.value)
                    }
                }
            }

        case .multiple(let choices):
            VStack(spacing: 9) {
                ForEach(choices) { choice in
                    let selected = selectedStrings(question.key).contains(choice.value)
                    choiceButton(choice, selected: selected) { toggleString(choice.value, key: question.key) }
                }
            }

        case .symptoms(let choices):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(choices) { choice in
                    Toggle(isOn: boolBinding(choice.value)) {
                        Text(language.text(choice.label))
                            .font(APEXFont.body(13, weight: .semibold))
                    }
                    .tint(APEXColor.amber)
                    .padding(13)
                    .background(.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18))
                }
                Text("Leave every switch off if none applies.")
                    .font(APEXFont.body(10, weight: .medium))
                    .foregroundStyle(APEXColor.secondaryInk)
            }
        }
    }

    private func choiceButton(_ choice: InductionChoice, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? APEXColor.cyan : APEXColor.secondaryInk)
                Text(language.text(choice.label))
                    .font(APEXFont.body(13, weight: .semibold))
                    .foregroundStyle(APEXColor.ink)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(14)
            .background(selected ? APEXColor.cyan.opacity(0.1) : .white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? APEXColor.cyan.opacity(0.75) : .white.opacity(0.85)))
        }
        .buttonStyle(.plain)
    }

    private var hasAnswer: Bool {
        switch question.kind {
        case .text:
            return (answers[question.key]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .date:
            return answers[question.key]?.stringValue?.isEmpty == false
        case .single:
            return answers[question.key]?.stringValue?.isEmpty == false
        case .multiple, .symptoms:
            return true
        }
    }

    private func loadExisting() {
        guard loaded == false else { return }
        loaded = true
        guard let profile = session.profile else { return }
        if let existing = session.data.orbitInductions.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            inductionID = existing.id
            answers.merge(existing.answers) { _, new in new }
            step = min(existing.completed ? 0 : existing.currentStep, questions.count - 1)
            createdAt = existing.createdAt
        }
        let lowerBodyDays = session.data.programDays.filter { ["legs_a", "legs_b"].contains($0.dayType) }.count
        answers["strength_days_per_week"] = .number(Double(lowerBodyDays))
        if answers["race_date"]?.stringValue?.isEmpty != false {
            answers["race_date"] = .string(Calendar.current.date(byAdding: .month, value: 6, to: .now)!.apexDateKey)
        }
        if answers["issue_status"]?.stringValue?.isEmpty != false,
           answers["previous_issue"]?.stringValue == "none" {
            answers["issue_status"] = .string("resolved")
        }
        _ = profile
    }

    @MainActor
    private func next() async {
        guard let profile = session.profile else { return }
        message = nil
        if question.key == "previous_issue", answers[question.key]?.stringValue == "none" {
            answers["issue_status"] = .string("resolved")
        }
        isSaving = true
        let now = Date().ISO8601Format()
        let isLast = step == questions.count - 1
        let assessment = OrbitCampaignEngine.assess(answers)
        let induction = OrbitInduction(
            id: inductionID,
            userID: profile.userID,
            answers: answers,
            currentStep: isLast ? questions.count : step + 1,
            completed: isLast,
            outcome: isLast ? assessment.outcome : nil,
            outcomeReason: isLast ? assessment.reason : "",
            createdAt: createdAt,
            updatedAt: now
        )
        if isLast {
            guard OrbitCampaignEngine.isComplete(answers) else {
                isSaving = false
                message = "Some required context is still missing. Review the earlier answers."
                return
            }
            _ = await session.completeOrbitInduction(induction)
            isSaving = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } else {
            await session.saveOrbitInduction(induction)
            isSaving = false
            withAnimation(.snappy) { step += 1 }
        }
    }

    private func stringBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { answers[key]?.stringValue ?? "" },
            set: { answers[key] = .string($0) }
        )
    }

    private func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { answers[key]?.boolValue ?? false },
            set: { answers[key] = .bool($0) }
        )
    }

    private func dateBinding(_ key: String) -> Binding<Date> {
        Binding(
            get: {
                guard let value = answers[key]?.stringValue,
                      let date = ISO8601DateFormatter.apexDateOnly.date(from: value)
                else { return Calendar.current.date(byAdding: .month, value: 6, to: .now)! }
                return date
            },
            set: { answers[key] = .string($0.apexDateKey) }
        )
    }

    private func selectedStrings(_ key: String) -> Set<String> {
        Set((answers[key]?.arrayValue ?? []).compactMap(\.stringValue))
    }

    private func toggleString(_ value: String, key: String) {
        var selected = selectedStrings(key)
        if selected.contains(value) { selected.remove(value) }
        else { selected.insert(value) }
        answers[key] = .array(selected.sorted().map { .string($0) })
    }
}

private enum InductionQuestionKind {
    case text(prompt: String)
    case date
    case single([InductionChoice])
    case multiple([InductionChoice])
    case symptoms([InductionChoice])
}

private struct InductionQuestion {
    let key: String
    let title: String
    let helper: String
    let icon: String
    let kind: InductionQuestionKind
}

private struct InductionChoice: Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

private extension MarathonInductionView {
    var questions: [InductionQuestion] {
        [
            .init(key: "race_name", title: "Which marathon are you preparing for?", helper: "Use the official event name or a working title.", icon: "flag.checkered", kind: .text(prompt: "Marathon name")),
            .init(key: "race_date", title: "When is race day?", helper: "Orbit will reject a timeline that cannot be progressed credibly.", icon: "calendar", kind: .date),
            .init(key: "race_goal", title: "What should this campaign achieve?", helper: "The objective changes intensity, specificity and pacing guidance.", icon: "scope", kind: .single([
                .init(value: "finish", label: "Finish"), .init(value: "finish_comfortably", label: "Finish comfortably"),
                .init(value: "target_time", label: "Reach a target time"), .init(value: "best_realistic", label: "Best realistic performance")
            ])),
            .init(key: "course_profile", title: "What is the course profile?", helper: "Orbit can match route characteristics during specific training.", icon: "mountain.2", kind: .single([
                .init(value: "flat", label: "Mostly flat"), .init(value: "rolling", label: "Rolling"), .init(value: "hilly", label: "Hilly")
            ])),
            .init(key: "course_surface", title: "What surface does the race use?", helper: "Choose the dominant surface.", icon: "road.lanes", kind: .single([
                .init(value: "road", label: "Road"), .init(value: "trail", label: "Trail"), .init(value: "mixed", label: "Mixed")
            ])),
            .init(key: "climate_familiar", title: "Is the expected climate familiar?", helper: "Orbit does not assume race-day weather. This only informs preparation context.", icon: "sun.max", kind: .single([
                .init(value: "yes", label: "Yes"), .init(value: "no", label: "No"), .init(value: "unsure", label: "Not sure")
            ])),
            .init(key: "running_frequency", title: "How often are you running now?", helper: "Use the recent normal week, not your best-ever week.", icon: "figure.run", kind: .single([
                .init(value: "none", label: "I am not currently running"), .init(value: "one", label: "Once per week"),
                .init(value: "two", label: "Twice per week"), .init(value: "three", label: "Three times per week"),
                .init(value: "four", label: "Four times per week"), .init(value: "five_plus", label: "Five or more times per week")
            ])),
            .init(key: "weekly_distance", title: "What is your recent weekly distance?", helper: "A broad range is more useful than false precision.", icon: "ruler", kind: .single([
                .init(value: "under_10", label: "Under 10 km"), .init(value: "10_20", label: "10 to 20 km"),
                .init(value: "20_35", label: "20 to 35 km"), .init(value: "35_50", label: "35 to 50 km"),
                .init(value: "over_50", label: "More than 50 km"), .init(value: "unsure", label: "I am not sure")
            ])),
            .init(key: "longest_run", title: "What is your longest recent run?", helper: "Use the current training period.", icon: "arrow.right.to.line", kind: .single([
                .init(value: "under_5", label: "Under 5 km"), .init(value: "5_10", label: "5 to 10 km"),
                .init(value: "10_15", label: "10 to 15 km"), .init(value: "15_21", label: "15 to 21 km"),
                .init(value: "over_21", label: "More than 21 km"), .init(value: "unsure", label: "I am not sure")
            ])),
            .init(key: "consistency", title: "How consistent has recent training been?", helper: "Consistency matters more than one impressive session.", icon: "calendar.badge.checkmark", kind: .single([
                .init(value: "none", label: "I have not trained consistently"), .init(value: "under_month", label: "Less than one month"),
                .init(value: "one_three_months", label: "One to three months"), .init(value: "three_six_months", label: "Three to six months"),
                .init(value: "over_six_months", label: "More than six months")
            ])),
            .init(key: "race_experience", title: "What races have you completed?", helper: "Choose the longest relevant experience.", icon: "medal", kind: .single([
                .init(value: "none", label: "No organised races"), .init(value: "5k", label: "5K"), .init(value: "10k", label: "10K"),
                .init(value: "half", label: "Half marathon"), .init(value: "marathon", label: "Marathon"), .init(value: "multiple_marathons", label: "Multiple marathons")
            ])),
            .init(key: "marathon_experience", title: "How many marathons have you completed?", helper: "This helps choose the campaign family.", icon: "trophy", kind: .single([
                .init(value: "never", label: "Never"), .init(value: "one", label: "One marathon"),
                .init(value: "two_four", label: "Two to four marathons"), .init(value: "five_plus", label: "Five or more marathons")
            ])),
            .init(key: "structured_plan", title: "Have you followed a structured plan?", helper: "There is no penalty for being new to structured training.", icon: "list.bullet.clipboard", kind: .single([
                .init(value: "never", label: "Never followed one"), .init(value: "inconsistent", label: "Followed one inconsistently"),
                .init(value: "completed_one", label: "Completed one"), .init(value: "completed_several", label: "Completed several")
            ])),
            .init(key: "running_style", title: "Which running style fits you?", helper: "Run-walk can be a deliberate, effective strategy.", icon: "figure.walk.motion", kind: .single([
                .init(value: "continuous", label: "Mostly continuous running"), .init(value: "run_walk", label: "Mostly run-walk"),
                .init(value: "either", label: "Comfortable with either"), .init(value: "unsure", label: "Not sure yet")
            ])),
            .init(key: "available_days", title: "How many running days are realistic?", helper: "Orbit will coordinate these with your existing APEX strength plan.", icon: "calendar.day.timeline.leading", kind: .single([
                .init(value: "three", label: "Three days"), .init(value: "four", label: "Four days"),
                .init(value: "five", label: "Five days"), .init(value: "six", label: "Six days"), .init(value: "variable", label: "Variable schedule")
            ])),
            .init(key: "long_run_day", title: "Which long-run day works best?", helper: "Event and work conflicts can still move it transparently.", icon: "calendar.badge.clock", kind: .single([
                .init(value: "saturday", label: "Saturday"), .init(value: "sunday", label: "Sunday"),
                .init(value: "other", label: "Another fixed day"), .init(value: "variable", label: "Variable")
            ])),
            .init(key: "unavailable_days", title: "Which days are regularly unavailable?", helper: "Select all that apply, or continue with none selected.", icon: "calendar.badge.minus", kind: .multiple([
                .init(value: "1", label: "Monday"), .init(value: "2", label: "Tuesday"), .init(value: "3", label: "Wednesday"),
                .init(value: "4", label: "Thursday"), .init(value: "5", label: "Friday"), .init(value: "6", label: "Saturday"), .init(value: "0", label: "Sunday")
            ])),
            .init(key: "constraints", title: "Which lifestyle constraints recur?", helper: "Select every relevant constraint. APEX calendar events are also considered automatically.", icon: "person.crop.circle.badge.clock", kind: .multiple([
                .init(value: "physical_work", label: "Physically demanding work"), .init(value: "travel", label: "Travel"),
                .init(value: "shift_work", label: "Shift work"), .init(value: "childcare", label: "Childcare"), .init(value: "events", label: "Events")
            ])),
            .init(key: "previous_issue", title: "Have you had a previous issue affecting running?", helper: "An old resolved issue does not automatically block a campaign.", icon: "cross.case", kind: .single([
                .init(value: "none", label: "No significant previous issue"), .init(value: "knee", label: "Knee"),
                .init(value: "hip", label: "Hip"), .init(value: "ankle", label: "Ankle"), .init(value: "foot", label: "Foot"),
                .init(value: "lower_back", label: "Lower back"), .init(value: "other", label: "Another area")
            ])),
            .init(key: "previous_surgery", title: "Any surgery affecting running?", helper: "Orbit asks about timing only. It does not interpret a procedure.", icon: "heart.text.square", kind: .single([
                .init(value: "no", label: "No"), .init(value: "over_three_years", label: "Yes, more than three years ago"),
                .init(value: "one_three_years", label: "Yes, one to three years ago"), .init(value: "six_twelve_months", label: "Yes, six to twelve months ago"),
                .init(value: "under_six_months", label: "Yes, within the last six months"), .init(value: "prefer_not", label: "Prefer not to answer")
            ])),
            .init(key: "issue_status", title: "What is the current status?", helper: "Report what is true now.", icon: "waveform.path.ecg", kind: .single([
                .init(value: "resolved", label: "Fully returned with no current symptoms"),
                .init(value: "noticeable", label: "Occasionally noticeable but does not change movement"),
                .init(value: "changes_movement", label: "Currently causes pain or changes movement"),
                .init(value: "rehabilitating", label: "Currently rehabilitating"),
                .init(value: "restricted", label: "Currently under a professional restriction")
            ])),
            .init(key: "symptoms", title: "Does any current item apply?", helper: "These answers can pause strenuous campaign assignment without blocking general Orbit.", icon: "exclamationmark.shield", kind: .symptoms([
                .init(value: "pain_changes_movement", label: "Pain that changes walking or running"),
                .init(value: "chest_discomfort", label: "Chest discomfort during exertion"),
                .init(value: "fainting", label: "Unexplained fainting or near-fainting"),
                .init(value: "unusual_breathlessness", label: "Unusual breathlessness"),
                .init(value: "recent_illness_or_operation", label: "A recent significant illness or operation"),
                .init(value: "professional_restriction", label: "A professional restriction on strenuous exercise")
            ])),
            .init(key: "medication", title: "Is medication relevant to exercise response?", helper: "APEX does not request names, doses or interpret interactions.", icon: "pills", kind: .single([
                .init(value: "none", label: "No medication relevant to exercise"),
                .init(value: "clinician_knows", label: "Yes, and my prescribing clinician knows about my training"),
                .init(value: "not_discussed", label: "Yes, but I have not discussed marathon training"),
                .init(value: "changes_response", label: "I have been told it changes heart-rate or exercise response"),
                .init(value: "unsure", label: "Unsure or prefer not to answer")
            ]))
        ]
    }
}
