import RevenueCat
import SwiftUI

struct WelcomeStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 16) {
                    Text("PULSE NUTRITION")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundColor(Color.primaryGreen)

                    Text("We'll build your plan\nin about 2 minutes.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text("Tell us about your body and goals. Macra will calculate your calorie target and project the date you'll reach your goal weight.")
                        .font(.system(size: 15))
                        .foregroundColor(Color.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }
                .padding(.horizontal, 20)

                Spacer()

                MacraPrimaryButton(
                    title: "Let's start",
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
                colors: [accent.opacity(0.32), Color(hex: "8B5CF6").opacity(0.28), Color(hex: "3B82F6").opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blur(radius: 46)
            .frame(height: 180)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accent, Color(hex: "8B5CF6")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .shadow(color: accent.opacity(0.55), radius: 22, x: 0, y: 8)

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
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [accent.opacity(0.5), accent.opacity(0.16), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: accent.opacity(0.22), radius: 24, x: 0, y: 14)
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
    enum Kind {
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

struct DietaryPreferenceStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator

    var body: some View {
        OnboardingScaffold(
            title: "Any dietary preferences?",
            subtitle: "We'll tailor meal suggestions to match.",
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
    @State private var progress: Double = 0
    @State private var messageIndex: Int = 0

    private let messages = [
        "Analyzing your profile...",
        "Calculating your metabolic rate...",
        "Building your macro targets...",
        "Projecting your goal date..."
    ]

    private let totalDuration: Double = 4.0

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 32) {
                Spacer()

                Text(messages[messageIndex])
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .id(messageIndex)

                VStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(Color.primaryGreen)
                                .frame(width: max(8, geo.size.width * progress))
                        }
                    }
                    .frame(height: 8)
                    .frame(maxWidth: 240)

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 13))
                        .foregroundColor(Color.white.opacity(0.6))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
        }
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        let stepCount = messages.count
        for i in 1..<stepCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration * Double(i) / Double(stepCount)) {
                withAnimation { messageIndex = i }
            }
        }

        withAnimation(.linear(duration: totalDuration)) {
            progress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) {
            coordinator.advance()
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
                    onBack: coordinator.back,
                    onClose: coordinator.dismissPaywall
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

                        mealPlanSection
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
                    if let notes = plan.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
            } else if coordinator.isLoadingMealPlan {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.primaryGreen)
                    Text("Generating your meal plan…")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
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
        ("sparkles", "Daily nutrition coaching")
    ]

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                PaywallTopBar(
                    canGoBack: coordinator.canGoBack,
                    onBack: coordinator.back,
                    onClose: coordinator.dismissPaywall
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

struct CommitTrialStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator
    @ObservedObject private var offering: OfferingViewModel = PurchaseService.sharedInstance.offering
    @State private var betaTapCount = 0

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    private var selectedPlan: SubscriptionPlanOption? {
        coordinator.selectedPlan
    }

    private var isSubscriptionRenewalFlow: Bool {
        coordinator.startingStep == .commitTrial
    }

    private var trialDays: Int? {
        guard !isSubscriptionRenewalFlow else { return nil }
        return selectedPlan?.trialDays
    }

    private var trialEndDate: Date? {
        guard let days = trialDays else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: Date())
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                PaywallTopBar(
                    canGoBack: coordinator.canGoBack,
                    onBack: coordinator.back,
                    onClose: coordinator.dismissPaywall
                )

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(headerEyebrow)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundColor(Color.primaryGreen)

                        Text(headerTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        if !isSubscriptionRenewalFlow {
                            planSummaryCard
                        }

                        tierPickerSection

                        timelineCard

                        priceDisclosureCard

                        if let errorMessage = coordinator.purchaseError {
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "FF8A80"))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }

                VStack(spacing: 14) {
                    MacraPrimaryButton(
                        title: coordinator.isPurchasing ? "Processing..." : ctaTitle,
                        accent: Color.primaryGreen,
                        isLoading: coordinator.isPurchasing,
                        action: coordinator.purchaseAndContinue
                    )
                    .disabled(coordinator.isPurchasing || offering.isLoadingPackages || selectedPlan == nil)

                    HStack(spacing: 16) {
                        Button(action: coordinator.restorePurchasesAndContinue) {
                            Text("Restore Purchases")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.55))
                        }

                        Button(action: { coordinator.appCoordinator.showPrivacyScreenModal() }) {
                            Text("Privacy")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.55))
                        }

                        Button(action: {}) {
                            Text("Terms")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            VStack(spacing: 0) {
                Color.clear
                    .frame(height: 80)
                    .allowsHitTesting(false)
                Color.clear
                    .frame(height: 220)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("[BetaUnlock] header catcher tapped")
                        addToBetaGroup()
                    }
                Spacer()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            print("[BetaUnlock] CommitTrialStepView appeared — renewal=\(isSubscriptionRenewalFlow), tap the top 260pt area 5x quickly to unlock beta")
            if !isSubscriptionRenewalFlow {
                coordinator.loadPlanMacros()
            }
            coordinator.ensureOfferingsLoaded()
        }
    }

    @ViewBuilder
    private var planSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR PLAN")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(Color.primaryGreen)

            if let macros = coordinator.planMacros {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(macros.calories)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("kcal daily")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }

                HStack(spacing: 8) {
                    planSummaryChip(label: "P", value: "\(macros.protein)g", color: Color.primaryBlue)
                    planSummaryChip(label: "C", value: "\(macros.carbs)g", color: Color.primaryGreen)
                    planSummaryChip(label: "F", value: "\(macros.fat)g", color: Color(hex: "FFB454"))
                }
            }

            if let plan = coordinator.suggestedMealPlan, !plan.meals.isEmpty {
                Divider().background(Color.white.opacity(0.08))
                HStack(spacing: 10) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.primaryGreen)
                    Text("\(plan.meals.count) meals planned")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.primaryGreen.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.primaryGreen.opacity(0.25), lineWidth: 1)
        )
    }

    private func planSummaryChip(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.1)))
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder
    private var tierPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE YOUR PLAN")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.3)
                .foregroundColor(Color.primaryGreen)

            if offering.isLoadingPackages {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.primaryGreen)
                    Text("Loading plans...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if let packageLoadError = offering.packageLoadError, offering.planOptions.isEmpty {
                planStatusCard(message: packageLoadError)
            } else if offering.planOptions.isEmpty {
                planStatusCard(message: "No subscription plans are available right now.")
            } else {
                ForEach(Array(offering.planOptions.enumerated()), id: \.element.id) { index, plan in
                    TierCard(
                        title: plan.displayTitle,
                        perPeriodPrice: plan.perPeriodDisplay,
                        billingNote: plan.billingNote,
                        badge: tierSavingsBadge(for: plan),
                        emphasized: index == 0,
                        isSelected: coordinator.selectedPlan?.id == plan.id,
                        onTap: { coordinator.selectPlan(plan) }
                    )
                }
            }
        }
    }

    private func planStatusCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: { coordinator.ensureOfferingsLoaded(force: true) }) {
                Text("Retry loading plans")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.primaryGreen)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func tierSavingsBadge(for plan: SubscriptionPlanOption) -> String? {
        guard plan.periodKind == .year,
              let monthly = offering.planOptions.first(where: { $0.periodKind == .month }) else { return nil }
        let yearlyPrice = NSDecimalNumber(decimal: plan.price).doubleValue
        let monthlyPrice = NSDecimalNumber(decimal: monthly.price).doubleValue
        let annualizedMonthly = monthlyPrice * 12
        guard annualizedMonthly > 0, yearlyPrice < annualizedMonthly else { return nil }
        let pct = Int(((annualizedMonthly - yearlyPrice) / annualizedMonthly * 100).rounded())
        return pct > 0 ? "SAVE \(pct)%" : nil
    }

    private var headerEyebrow: String {
        if isSubscriptionRenewalFlow { return "SUBSCRIPTION REQUIRED" }
        return trialDays != nil ? "START YOUR FREE TRIAL" : "CONFIRM YOUR PLAN"
    }

    private var headerTitle: String {
        if isSubscriptionRenewalFlow { return "Renew Macra Pro." }
        if let days = trialDays {
            return "\(days) days free, then you decide."
        }
        guard let plan = selectedPlan else { return "Unlock Macra Pro." }
        switch plan.periodKind {
        case .year: return "Unlock Macra Pro for a year."
        case .month: return "Unlock Macra Pro."
        case .week: return "Unlock Macra Pro for the week."
        default: return "Unlock Macra Pro."
        }
    }

    private var ctaTitle: String {
        if trialDays != nil { return "Start free trial" }
        guard let plan = selectedPlan else { return "Continue" }
        let price = plan.priceLabel
        switch plan.periodKind {
        case .year: return "Subscribe \(price)/yr"
        case .month: return "Subscribe \(price)/mo"
        case .week: return "Subscribe \(price)/wk"
        default: return "Continue"
        }
    }

    @ViewBuilder
    private var timelineCard: some View {
        if let days = trialDays, let endDate = trialEndDate {
            VStack(alignment: .leading, spacing: 14) {
                timelineRow(
                    dot: Color.primaryGreen,
                    title: "Today",
                    body: "Full access to Macra Pro. No charge."
                )
                timelineRow(
                    dot: Color.white.opacity(0.4),
                    title: "Day \(max(1, days - 2))",
                    body: "We'll send a reminder 2 days before your trial ends."
                )
                timelineRow(
                    dot: Color.white.opacity(0.4),
                    title: Self.fullDateFormatter.string(from: endDate),
                    body: billingAfterTrialCopy
                )
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func timelineRow(dot: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(dot)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(body)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var billingAfterTrialCopy: String {
        guard let plan = selectedPlan else { return "Your plan begins billing." }
        switch plan.periodKind {
        case .year: return "\(plan.priceLabel) charged annually. Your trial ends."
        case .month: return "\(plan.priceLabel) charged monthly. Your trial ends."
        case .week: return "\(plan.priceLabel) charged weekly. Your trial ends."
        default: return "Your trial ends."
        }
    }

    private var priceDisclosureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if trialDays != nil {
                Text("Cancel anytime in Settings → [your name] → Subscriptions. You won't be charged if you cancel before the trial ends.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Auto-renews at the price shown until canceled. Cancel anytime in Settings → [your name] → Subscriptions.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let plan = selectedPlan {
                HStack {
                    Text("Plan")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 12))
                    Spacer()
                    Text(plan.priceLabel)
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.04)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func triggerBetaUnlock() {
        print("[BetaUnlock] triggerBetaUnlock — activating beta bypass")
        betaTapCount = 0
        performBetaUnlock()
    }

    private func addToBetaGroup() {
        betaTapCount += 1
        print("[BetaUnlock] addToBetaGroup invoked — count=\(betaTapCount)/5")

        guard betaTapCount == 5 else { return }
        betaTapCount = 0
        print("[BetaUnlock] 5 taps reached — activating beta bypass")
        performBetaUnlock()
    }

    private func performBetaUnlock() {

        coordinator.appCoordinator.showToast(viewModel: ToastViewModel(
            message: "Welcome to the Macra beta.",
            backgroundColor: .secondaryCharcoal,
            textColor: .secondaryWhite
        ))

        guard let user = UserService.sharedInstance.user else {
            print("[BetaUnlock] no cached user in UserService — dismissing paywall without Firestore write")
            coordinator.dismissPaywall()
            return
        }

        UserService.sharedInstance.grantLocalMacraBetaAccess()
        print("[BetaUnlock] Local Macra beta access enabled for \(user.email) without mutating shared subscription fields")

        PurchaseService.sharedInstance.checkSubscriptionStatus(forceRefresh: true) { result in
            print("[BetaUnlock] PurchaseService.checkSubscriptionStatus result: \(result)")
        }
        coordinator.dismissPaywall()
        print("[BetaUnlock] coordinator.dismissPaywall() called")
    }
}
