import RevenueCat
import SwiftUI

struct WelcomeStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator
    @ObservedObject private var noraVoice = MacraNoraVoiceService.shared
    private let accent = Color(hex: "E0FE10")
    private let narrationKey = "macra_onboarding_welcome"

    private var isNoraGuided: Bool {
        coordinator.onboardingExperienceVariant == .noraGuided
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 22) {
                Spacer()

                VStack(spacing: 18) {
                    TalkingNoraOrb(
                        size: 68,
                        isSpeaking: isNoraSpeakingHere,
                        voiceLevel: noraVoice.voiceLevel
                    )

                    Text("NORA NUTRITION AI")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(accent)

                    Text(isNoraGuided ? "Let's build the plan you'll actually use." : "Get your calories,\nmacros, meal plan,\nand goal date.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(isNoraGuided ? "I'll ask a few quick questions, then turn them into calories, macros, meals, and a goal date." : "Answer a few questions. Macra builds the numbers, then Nora helps you follow them day by day.")
                        .font(.system(size: 15))
                        .foregroundColor(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 10) {
                        welcomePromiseRow(icon: "target", title: "Daily calorie and macro target")
                        welcomePromiseRow(icon: "calendar", title: "Projected date to reach your goal")
                        welcomePromiseRow(icon: "fork.knife", title: "Meal ideas that fit your numbers")
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 6)
                }
                .padding(.horizontal, 20)

                Spacer()

                MacraPrimaryButton(
                    title: isNoraGuided ? "Start with my goal" : "Build my plan",
                    accent: accent,
                    isLoading: false,
                    action: coordinator.advance
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var isNoraSpeakingHere: Bool {
        noraVoice.isEnabled &&
            noraVoice.isNarrating &&
            noraVoice.activeNarrationKey == narrationKey
    }

    private func welcomePromiseRow(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(accent.opacity(0.14)))
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
            Spacer(minLength: 0)
        }
    }
}

struct PrimaryFocusStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "What do you want Macra to help with first?",
            subtitle: "Nora will use this as the lens for your targets, meals, and reminders.",
            noraPrompt: coordinator.noraPrompt(for: .primaryFocus),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            VStack(spacing: 10) {
                ForEach(MacraPrimaryFocus.allCases) { focus in
                    OnboardingChoiceCard(
                        title: focus.title,
                        subtitle: focus.subtitle,
                        value: focus,
                        selection: $coordinator.answers.primaryFocus
                    )
                }
            }
        }
    }
}

struct MeetNoraStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    private let accent = Color(hex: "E0FE10")

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        avatarCard
                        capabilityList
                        reassurance
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }

                MacraPrimaryButton(
                    title: "Let's meet Nora",
                    accent: accent,
                    isLoading: false,
                    action: coordinator.advance
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private var topBar: some View {
        HStack {
            if coordinator.canGoBack {
                Button(action: coordinator.back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.78))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEET NORA")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(accent)

            Text("Your AI nutrition coach.")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("Nora lives inside Macra. She'll tune your macros, build meal plans you actually want to eat, and answer questions about your day as you go.")
                .font(.system(size: 15, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var avatarCard: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: "3B82F6").opacity(0.22), Color(hex: "8B5CF6").opacity(0.18), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 46)
            .frame(height: 180)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    NoraOrb(size: 56, isActive: true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nora")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Sports nutrition · real-time")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .tracking(0.8)
                            .foregroundColor(accent)
                    }
                    Spacer()
                }

                Text("\u{201C}Hey — I'll walk through a few questions, then build your first plan. You can ask me anything about your day whenever.\u{201D}")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.white.opacity(0.06), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 14)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var capabilityList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT NORA DOES")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundColor(Color(hex: "8B5CF6"))

            capabilityRow(
                icon: "target",
                title: "Dials in your macros",
                subtitle: "From body + goal to a daily calorie + P/C/F target.",
                accent: accent
            )
            capabilityRow(
                icon: "fork.knife",
                title: "Builds meal plans",
                subtitle: "Simple lists that hit your numbers — no breakfast/lunch/dinner boxes.",
                accent: Color(hex: "3B82F6")
            )
            capabilityRow(
                icon: "bubble.left.and.bubble.right.fill",
                title: "Answers real questions",
                subtitle: "Ask \u{201C}how's my protein today?\u{201D} or \u{201C}what am I missing?\u{201D} — any time.",
                accent: Color(hex: "8B5CF6")
            )
        }
    }

    private func capabilityRow(icon: String, title: String, subtitle: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 38, height: 38)
                Circle().strokeBorder(accent.opacity(0.34), lineWidth: 1).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var reassurance: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            Text("Your data stays yours. Nora only uses it to coach you.")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }
}

struct SexStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "What's your biological sex?",
            subtitle: "This is used to calculate your metabolic rate.",
            noraPrompt: coordinator.noraPrompt(for: .sex),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            VStack(spacing: 12) {
                ForEach(BiologicalSex.allCases) { sex in
                    OnboardingChoiceCard(
                        title: sex.title,
                        subtitle: nil,
                        value: sex,
                        selection: $coordinator.answers.sex
                    )
                }
            }
        }
    }
}

struct AgeStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator
    @State private var date: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()

    var body: some View {
        OnboardingScaffold(
            title: "When were you born?",
            subtitle: "Age affects your daily calorie needs.",
            noraPrompt: coordinator.noraPrompt(for: .age),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxWidth: .infinity)
                .onChange(of: date) { newValue in
                    coordinator.answers.birthdate = newValue
                }
                .onAppear {
                    if let existing = coordinator.answers.birthdate {
                        date = existing
                    } else {
                        coordinator.answers.birthdate = date
                    }
                }
        }
    }
}

struct HeightStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator
    @State private var feet: Int = 5
    @State private var inches: Int = 10

    private var heightCm: Double {
        Double(feet * 12 + inches) * 2.54
    }

    var body: some View {
        OnboardingScaffold(
            title: "How tall are you?",
            subtitle: nil,
            noraPrompt: coordinator.noraPrompt(for: .height),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    VStack {
                        Text("FEET")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.55))
                        Picker("", selection: $feet) {
                            ForEach(3...7, id: \.self) { Text("\($0)").foregroundColor(.white).tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100, height: 160)
                    }
                    VStack {
                        Text("INCHES")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.55))
                        Picker("", selection: $inches) {
                            ForEach(0...11, id: \.self) { Text("\($0)").foregroundColor(.white).tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 100, height: 160)
                    }
                }
                .frame(maxWidth: .infinity)

                Text("\(Int(heightCm.rounded())) cm")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.55))
            }
            .onChange(of: feet) { _ in coordinator.answers.heightCm = heightCm }
            .onChange(of: inches) { _ in coordinator.answers.heightCm = heightCm }
            .onAppear {
                if let existing = coordinator.answers.heightCm {
                    let totalInches = Int((existing / 2.54).rounded())
                    feet = max(3, min(7, totalInches / 12))
                    inches = max(0, min(11, totalInches % 12))
                } else {
                    coordinator.answers.heightCm = heightCm
                }
            }
        }
    }
}

struct WeightStepView: View {
    enum Kind: Equatable {
        case current
        case goal

        var title: String {
            switch self {
            case .current: return "What's your current weight?"
            case .goal: return "What's your goal weight?"
            }
        }
    }

    @ObservedObject var coordinator: MacraOnboardingCoordinator
    let kind: Kind
    @State private var pounds: Double = 170

    var body: some View {
        OnboardingScaffold(
            title: kind.title,
            subtitle: nil,
            noraPrompt: coordinator.noraPrompt(for: kind == .current ? .currentWeight : .goalWeight),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            VStack(spacing: 16) {
                Text("\(Int(pounds.rounded())) lbs")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)

                Slider(value: $pounds, in: 70...400, step: 1)
                    .tint(Color.primaryGreen)

                Text(String(format: "%.1f kg", pounds / 2.20462))
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
            }
            .onChange(of: pounds) { newValue in
                let kg = newValue / 2.20462
                switch kind {
                case .current: coordinator.answers.currentWeightKg = kg
                case .goal: coordinator.answers.goalWeightKg = kg
                }
            }
            .onAppear {
                let existingKg: Double?
                switch kind {
                case .current: existingKg = coordinator.answers.currentWeightKg
                case .goal: existingKg = coordinator.answers.goalWeightKg
                }

                if let kg = existingKg {
                    pounds = kg * 2.20462
                } else {
                    let kg = pounds / 2.20462
                    switch kind {
                    case .current: coordinator.answers.currentWeightKg = kg
                    case .goal: coordinator.answers.goalWeightKg = kg
                    }
                }
            }
        }
    }
}

struct ActivityLevelStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "How active are you?",
            subtitle: "On an average week, outside of any planned workouts.",
            noraPrompt: coordinator.noraPrompt(for: .activityLevel),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            VStack(spacing: 10) {
                ForEach(ActivityLevel.allCases) { level in
                    OnboardingChoiceCard(
                        title: level.title,
                        subtitle: level.subtitle,
                        value: level,
                        selection: $coordinator.answers.activityLevel
                    )
                }
            }
        }
    }
}

struct PaceStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "How fast do you want to get there?",
            subtitle: "Your calorie target adjusts to match. You can change this later.",
            noraPrompt: coordinator.noraPrompt(for: .pace),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            VStack(spacing: 10) {
                ForEach(GoalPace.allCases) { pace in
                    OnboardingChoiceCard(
                        title: pace.title,
                        subtitle: pace.subtitle,
                        value: pace,
                        selection: $coordinator.answers.pace
                    )
                }
            }
        }
    }
}

struct SportSelectionStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator
    @StateObject private var configService = MacraSportConfigService.shared

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var selectedSport: MacraSportConfig? {
        guard let id = coordinator.answers.sport else { return nil }
        return configService.sports.first(where: { $0.id == id })
    }

    var body: some View {
        OnboardingScaffold(
            title: "What sport do you play?",
            subtitle: "We'll tune Nora to your sport's training, fueling, and game-day demands.",
            noraPrompt: coordinator.noraPrompt(for: .sportSelection),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            VStack(alignment: .leading, spacing: 18) {
                if configService.isLoading && configService.sports.isEmpty {
                    HStack {
                        ProgressView().tint(Color.primaryGreen)
                        Text("Loading sports…").foregroundColor(Color.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                } else if let error = configService.loadError, configService.sports.isEmpty {
                    VStack(spacing: 8) {
                        Text("Couldn't load sports")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        Button("Retry") { configService.load() }
                            .foregroundColor(Color.primaryGreen)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(configService.sports) { sport in
                            SportTile(
                                sport: sport,
                                isSelected: coordinator.answers.sport == sport.id,
                                onTap: {
                                    coordinator.answers.sport = sport.id
                                    coordinator.answers.sportName = sport.name
                                    if !sport.positions.contains(coordinator.answers.sportPosition ?? "") {
                                        coordinator.answers.sportPosition = nil
                                    }
                                }
                            )
                        }
                    }
                }

                if let sport = selectedSport, !sport.positions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Position")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundColor(Color.white.opacity(0.55))
                        FlexibleChipGroup(
                            options: sport.positions,
                            selection: $coordinator.answers.sportPosition
                        )
                        Text("Optional — pick one if you have a primary position.")
                            .font(.system(size: 12))
                            .foregroundColor(Color.white.opacity(0.45))
                    }
                    .padding(.top, 4)
                }
            }
            .onAppear { configService.loadIfNeeded() }
        }
    }
}

private struct SportTile: View {
    let sport: MacraSportConfig
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(sport.emoji).font(.system(size: 28))
                Text(sport.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.primaryGreen.opacity(0.8) : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FlexibleChipGroup: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button(action: { selection = (selection == option) ? nil : option }) {
                    Text(option)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(selection == option ? Color.secondaryCharcoal : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selection == option ? Color.primaryGreen : Color.white.opacity(0.06))
                        )
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(selection == option ? 0 : 0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct DietaryPreferenceStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "Any dietary preferences?",
            subtitle: "We'll tailor meal suggestions to match.",
            noraPrompt: coordinator.noraPrompt(for: .dietaryPreference),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            VStack(spacing: 10) {
                ForEach(DietaryPreference.allCases) { pref in
                    OnboardingChoiceCard(
                        title: pref.title,
                        subtitle: nil,
                        value: pref,
                        selection: $coordinator.answers.dietaryPreference
                    )
                }
            }
        }
    }
}

struct BiggestStruggleStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "What's held you back before?",
            subtitle: "We'll design your daily coaching around this.",
            noraPrompt: coordinator.noraPrompt(for: .biggestStruggle),
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            onBack: coordinator.back,
            onForward: coordinator.advance
        ) {
            VStack(spacing: 10) {
                ForEach(BiggestStruggle.allCases) { struggle in
                    OnboardingChoiceCard(
                        title: struggle.title,
                        subtitle: struggle.subtitle,
                        value: struggle,
                        selection: $coordinator.answers.biggestStruggle
                    )
                }
            }
        }
    }
}

struct GeneratingPlanStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator
    @ObservedObject private var noraVoice = MacraNoraVoiceService.shared
    @State private var progress: Double = 0
    @State private var messageIndex: Int = 0
    @State private var isAnimationFinished = false
    @State private var didScheduleAdvance = false

    private let messages = [
        "Analyzing your profile...",
        "Calculating your metabolic rate...",
        "Building your macro targets...",
        "Projecting your goal date..."
    ]

    private let totalDuration: Double = 4.0
    private let narrationKey = "macra_onboarding_generating_plan"

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 24) {
                Spacer(minLength: 68)

                TalkingNoraOrb(
                    size: 104,
                    isSpeaking: isNoraSpeakingHere,
                    voiceLevel: noraVoice.voiceLevel
                )

                VStack(spacing: 8) {
                    Text("Analyzing your answers...")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(messages[messageIndex])
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                        .id(messageIndex)
                }

                VStack(spacing: 16) {
                    GeneratingPlanProgressRow(
                        title: "Profile",
                        progress: profileProgress,
                        accent: Color.primaryGreen
                    )
                    GeneratingPlanProgressRow(
                        title: "Goals",
                        progress: goalsProgress,
                        accent: Color(hex: "8DB7FF")
                    )
                    GeneratingPlanProgressRow(
                        title: "Personalization",
                        progress: personalizationProgress,
                        accent: Color(hex: "FFB454")
                    )
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.24)))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.top, 2)

                Spacer(minLength: 76)
            }
            .padding(.horizontal, 28)
        }
        .onAppear { runAnimation() }
        .onChange(of: noraVoice.lastCompletedNarrationKey) { completedKey in
            guard completedKey == narrationKey else { return }
            scheduleAdvanceWhenReady()
        }
        .onChange(of: noraVoice.isEnabled) { isEnabled in
            guard !isEnabled else { return }
            scheduleAdvanceWhenReady()
        }
    }

    private var isNoraSpeakingHere: Bool {
        noraVoice.isEnabled &&
            noraVoice.isNarrating &&
            noraVoice.activeNarrationKey == narrationKey
    }

    private var profileProgress: Double {
        clamped(progress / 0.34)
    }

    private var goalsProgress: Double {
        clamped((progress - 0.18) / 0.42)
    }

    private var personalizationProgress: Double {
        clamped((progress - 0.52) / 0.48)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func runAnimation() {
        guard !isAnimationFinished, !didScheduleAdvance else { return }
        progress = 0
        messageIndex = 0

        let stepCount = messages.count
        for i in 1..<stepCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration * Double(i) / Double(stepCount)) {
                guard coordinator.currentStep == .generatingPlan else { return }
                withAnimation { messageIndex = i }
            }
        }

        withAnimation(.linear(duration: totalDuration)) {
            progress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            guard coordinator.currentStep == .generatingPlan else { return }
            isAnimationFinished = true
            scheduleAdvanceWhenReady()
        }
    }

    private func scheduleAdvanceWhenReady() {
        guard isAnimationFinished, !didScheduleAdvance else { return }
        guard coordinator.currentStep == .generatingPlan else { return }

        if noraVoice.isEnabled,
           noraVoice.lastCompletedNarrationKey != narrationKey,
           noraVoice.isNarrating,
           noraVoice.activeNarrationKey == narrationKey {
            return
        }

        didScheduleAdvance = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard coordinator.currentStep == .generatingPlan else { return }
            coordinator.advance()
        }
    }
}

private struct GeneratingPlanProgressRow: View {
    let title: String
    let progress: Double
    let accent: Color

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    private var percent: Int {
        Int((clampedProgress * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                Text("\(percent)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.68))
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [accent, Color.primaryGreen],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * clampedProgress))
                }
            }
            .frame(height: 8)
        }
    }
}

struct PredictionStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    private var prediction: MacraOnboardingPrediction? {
        MacraOnboardingPrediction.compute(from: coordinator.answers)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(alignment: .leading, spacing: 20) {
                Text("YOUR PLAN")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(Color.primaryGreen)
                    .padding(.top, 60)

                if let prediction = prediction {
                    predictionContent(prediction: prediction)
                } else {
                    Text("We couldn't calculate your plan. Go back and check your answers.")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                MacraPrimaryButton(
                    title: coordinator.isFinishing ? "Saving..." : "See my plan",
                    accent: Color.primaryGreen,
                    isLoading: coordinator.isFinishing,
                    action: coordinator.completeQuestionnaire
                )
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func predictionContent(prediction: MacraOnboardingPrediction) -> some View {
        let lbs = prediction.targetWeightKg * 2.20462
        let dateStr = Self.dateFormatter.string(from: prediction.estimatedGoalDate)

        Text("You'll reach \(Int(lbs.rounded())) lbs by \(dateStr).")
            .font(.system(size: 32, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .fixedSize(horizontal: false, vertical: true)

        VStack(spacing: 12) {
            planCard(
                label: "Daily calorie target",
                value: "\(prediction.dailyCalorieTarget) kcal"
            )
            planCard(
                label: "Estimated maintenance",
                value: "\(prediction.tdee) kcal"
            )
            if abs(prediction.weeklyWeightChangeKg) > 0.01 {
                planCard(
                    label: "Weekly pace",
                    value: String(format: "%.1f lb/wk", abs(prediction.weeklyWeightChangeKg) * 2.20462)
                )
            }
        }
        .padding(.top, 12)
    }

    private func planCard(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 14))
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct PlanReadyStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private var prediction: MacraOnboardingPrediction? {
        MacraOnboardingPrediction.compute(from: coordinator.answers)
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                PaywallTopBar(
                    canGoBack: coordinator.canGoBack,
                    onBack: coordinator.back
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("YOUR PLAN IS READY")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(Color.primaryGreen)

                        if let prediction = prediction {
                            let lbs = prediction.targetWeightKg * 2.20462
                            let dateStr = Self.dateFormatter.string(from: prediction.estimatedGoalDate)
                            Text("Reach \(Int(lbs.rounded())) lbs by \(dateStr)")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Your personalized plan")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }

                        macroPlanCard

                        coachingFocusCard

                        mealPlanSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }

                MacraPrimaryButton(
                    title: "Continue to unlock",
                    accent: Color.primaryGreen,
                    isLoading: false,
                    action: coordinator.advance
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .opacity(coordinator.canGoForward ? 1 : 0.4)
                .disabled(!coordinator.canGoForward)
            }
        }
        .onAppear {
            coordinator.loadPlanMacros()
            coordinator.loadSuggestedMealPlan()
        }
        .onChange(of: coordinator.planMacros) { _ in
            coordinator.loadSuggestedMealPlan()
        }
    }

    @ViewBuilder
    private var mealPlanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR MEAL PLAN")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundColor(Color.primaryGreen)
                Spacer()
                if coordinator.suggestedMealPlan != nil {
                    Button {
                        coordinator.loadSuggestedMealPlan(forceRegenerate: true)
                    } label: {
                        Text("Regenerate")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }

            if let plan = coordinator.suggestedMealPlan {
                VStack(spacing: 10) {
                    ForEach(Array(plan.meals.enumerated()), id: \.offset) { index, meal in
                        mealCard(index: index, meal: meal)
                    }
                    if let notes = displayablePlanNotes(from: plan.notes) {
                        Text(notes)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
            } else if coordinator.isLoadingMealPlan {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color.primaryGreen)
                        Text("Nora is building your meal plan...")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    Text("You can keep going while this finishes.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if let error = coordinator.mealPlanError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "FF8A80"))
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        coordinator.loadSuggestedMealPlan(forceRegenerate: true)
                    } label: {
                        Text("Try again")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.primaryGreen)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func displayablePlanNotes(from notes: String?) -> String? {
        guard let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return nil
        }

        let lowercased = notes.lowercased()
        let looksInternal = lowercased.contains("demo") ||
            lowercased.contains("meal-plan service") ||
            lowercased.contains("ad-friendly")

        guard !looksInternal else {
            return nil
        }

        return notes
    }

    @ViewBuilder
    private var coachingFocusCard: some View {
        if let struggle = coordinator.answers.biggestStruggle {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.primaryGreen)
                    Text(struggle.coachingFocusTitle.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(Color.primaryGreen)
                }

                Text(struggle.coachingFocusBody)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.primaryGreen.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.primaryGreen.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private func mealCard(index: Int, meal: MacraSuggestedMeal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Meal \(index + 1)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text("\(meal.totalCalories) kcal")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(meal.items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.95))
                            Text(item.quantity)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.55))
                        }
                        Spacer()
                        Text("\(item.calories)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
            }

            HStack(spacing: 10) {
                macroChip(label: "P", grams: meal.totalProtein, color: Color.primaryBlue)
                macroChip(label: "C", grams: meal.totalCarbs, color: Color.primaryGreen)
                macroChip(label: "F", grams: meal.totalFat, color: Color(hex: "FFB454"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func macroChip(label: String, grams: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text("\(grams)g")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.1)))
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private var macroPlanCard: some View {
        let macros = displayedMacros
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("DAILY TARGETS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundColor(Color.primaryGreen)
                Spacer()
            }

            if let macros {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(macros.calories)")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("kcal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                HStack(spacing: 10) {
                    macroPill(label: "Protein", grams: macros.protein, accent: Color.primaryBlue)
                    macroPill(label: "Carbs", grams: macros.carbs, accent: Color.primaryGreen)
                    macroPill(label: "Fat", grams: macros.fat, accent: Color(hex: "FFB454"))
                }
            } else if coordinator.isLoadingPlanMacros {
                Text("Generating your plan…")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.vertical, 8)
            } else {
                Text("Your daily targets will appear once your plan is generated.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.vertical, 8)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func macroPill(label: String, grams: Int, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundColor(accent)
            Text("\(grams)g")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(accent.opacity(0.08)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accent.opacity(0.22), lineWidth: 1)
        )
    }

    private var displayedMacros: MacroRecommendation? {
        if let prediction = prediction {
            let userId = UserService.sharedInstance.user?.id ?? ""
            return prediction.toMacroRecommendation(userId: userId)
        }
        return coordinator.planMacros
    }
}

struct FeaturesStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    private let features: [(String, String)] = [
        ("camera.viewfinder", "AI food photo logging"),
        ("target", "Personalized macro targets"),
        ("calendar", "Projected goal date tracking"),
        ("qrcode.viewfinder", "Label scanner with ingredient analysis"),
        ("list.bullet.rectangle", "Meal planning that moves into your journal"),
        ("sparkles", "Daily nutrition coaching"),
        // Cross-product entitlement: one Macra subscription unlocks
        // Fit With Pulse Pro (live challenges, AI workouts, club coaching).
        // Same flag flips both ways — see Pulse's WorkoutReadyView copy.
        ("dumbbell", "Includes Fit With Pulse Pro — AI workouts, live challenges, clubs")
    ]

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                PaywallTopBar(
                    canGoBack: coordinator.canGoBack,
                    onBack: coordinator.back
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("WHAT YOU UNLOCK")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(Color.primaryGreen)

                        Text("Everything you need to hit your number.")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 12) {
                            ForEach(features, id: \.1) { feature in
                                HStack(spacing: 14) {
                                    Image(systemName: feature.0)
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.primaryGreen)
                                        .frame(width: 32, height: 32)
                                        .background(Color.primaryGreen.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))

                                    Text(feature.1)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white.opacity(0.92))

                                    Spacer()
                                }
                            }
                        }
                        .padding(.top, 8)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Built around your real logs, targets, and meal history.")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("No sample meals or filler plans are added to your account.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.68))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }

                MacraPrimaryButton(
                    title: "Continue",
                    accent: Color.primaryGreen,
                    isLoading: false,
                    action: coordinator.advance
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}

struct TrialActivationStartStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    private var firstMeal: MacraSuggestedMeal? {
        coordinator.suggestedMealPlan?.meals.first
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.black)
                                .frame(width: 54, height: 54)
                                .background(Color.primaryGreen)
                                .clipShape(Circle())

                            Text("Your plan is active.")
                                .font(.system(size: 32, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("The first win is simple: log one real meal so Nora can compare it to your target and guide the next choice.")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        activationTargetsCard

                        if let firstMeal {
                            firstMealCard(firstMeal)
                        } else {
                            activationStepCard(
                                icon: "camera.viewfinder",
                                title: "Start with the food in front of you",
                                body: "Use a photo or quick entry. A real meal is more useful than another setup screen."
                            )
                        }

                        activationStepCard(
                            icon: "sparkles",
                            title: "Nora reacts to the log",
                            body: "After that first meal, Macra can show what is left for today and where to adjust."
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 32)
                    .padding(.bottom, 36)
                }

                MacraPrimaryButton(
                    title: "Start with one meal",
                    accent: Color.primaryGreen,
                    isLoading: false,
                    action: coordinator.startTrialActivationFirstMeal
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            coordinator.trackTrialActivationScreenViewedIfNeeded()
        }
    }

    @ViewBuilder
    private var activationTargetsCard: some View {
        if let macros = coordinator.planMacros {
            VStack(alignment: .leading, spacing: 14) {
                Text("TODAY'S TARGET")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundColor(Color.primaryGreen)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(macros.calories)")
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("kcal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                HStack(spacing: 10) {
                    macroMetric(label: "Protein", value: "\(macros.protein)g", accent: Color.primaryBlue)
                    macroMetric(label: "Carbs", value: "\(macros.carbs)g", accent: Color.primaryGreen)
                    macroMetric(label: "Fat", value: "\(macros.fat)g", accent: Color(hex: "FFB454"))
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.primaryGreen.opacity(0.18), lineWidth: 1)
            )
        } else {
            activationStepCard(
                icon: "target",
                title: "Your targets are ready",
                body: "Macra will open to the journal so the first meal can start shaping the rest of today."
            )
        }
    }

    private func firstMealCard(_ meal: MacraSuggestedMeal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.primaryGreen.opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    Text("FIRST MEAL TO LOG")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(Color.primaryGreen)
                    Text(meal.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(meal.totalCalories) calories planned")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.62))
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                macroMetric(label: "Protein", value: "\(meal.totalProtein)g", accent: Color.primaryBlue)
                macroMetric(label: "Carbs", value: "\(meal.totalCarbs)g", accent: Color.primaryGreen)
                macroMetric(label: "Fat", value: "\(meal.totalFat)g", accent: Color(hex: "FFB454"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func macroMetric(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.9)
                .foregroundColor(accent)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13).fill(accent.opacity(0.08)))
    }

    private func activationStepCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.primaryGreen)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.primaryGreen.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

struct CommitTrialStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    var body: some View {
        PayWallView(
            viewModel: PayWallViewModel(appCoordinator: coordinator.appCoordinator),
            isDemoMode: coordinator.isDemoMode,
            usesLivePurchasesInDemo: coordinator.usesLivePurchasesInDemo,
            onboardingCoordinator: coordinator,
            existingSubscriptionAccessOverride: coordinator.existingSubscriptionAccessOverride,
            defaultPlanSelectionOverride: coordinator.paywallDefaultPlanSelectionOverride,
            layoutVariantOverride: coordinator.paywallLayoutVariantOverride
        )
    }
}
