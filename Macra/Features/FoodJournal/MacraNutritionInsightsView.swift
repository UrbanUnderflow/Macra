import SwiftUI

struct MacraNutritionInsightsRootView: View {
    @StateObject var viewModel: MacraFoodJournalViewModel

    init(viewModel: MacraFoodJournalViewModel = MacraFoodJournalViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        MacraNutritionInsightsView(viewModel: viewModel)
    }
}

struct MacraNutritionInsightsView: View {
    @ObservedObject var viewModel: MacraFoodJournalViewModel

    private var report: MacraNutritionInsightsReport {
        MacraNutritionInsightsReport(
            today: viewModel.selectedDate,
            store: viewModel.store
        )
    }

    var body: some View {
        ZStack {
            MacraFoodJournalTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    scorecardSection(report: report)
                    weeklyTrendSection(report: report)
                    habitsSection(report: report)
                    patternInsightsSection(report: report)
                    predictionsSection(report: report)
                    coachingSection(report: report)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Macra")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
                .tracking(1.8)
            Text("Nutrition insights")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [MacraFoodJournalTheme.text, MacraFoodJournalTheme.accent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text("AI analysis of your meals, habits, and trends.")
                .font(.subheadline)
                .foregroundColor(MacraFoodJournalTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scorecardSection(report: MacraNutritionInsightsReport) -> some View {
        FoodJournalSection(title: "Today's scorecard", subtitle: "How today is shaping up") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(report.todayScore)")
                            .font(.system(size: 56, weight: .black, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [MacraFoodJournalTheme.accent, MacraFoodJournalTheme.accent2],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Text("out of 100 · \(report.todayScoreLabel)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(MacraFoodJournalTheme.textSoft)
                    }
                    Spacer()
                    FoodJournalMacroRing(
                        calories: report.today.totalCalories,
                        target: report.today.macroTarget?.calories,
                        accent: MacraFoodJournalTheme.accent
                    )
                    .frame(width: 110, height: 110)
                }

                VStack(spacing: 10) {
                    adherenceRow(title: "Calories", percent: report.calorieAdherencePercent, tint: MacraFoodJournalTheme.accent)
                    adherenceRow(title: "Protein", percent: report.proteinAdherencePercent, tint: MacraFoodJournalTheme.accent2)
                    adherenceRow(title: "Carbs", percent: report.carbAdherencePercent, tint: MacraFoodJournalTheme.accent3)
                    adherenceRow(title: "Fat", percent: report.fatAdherencePercent, tint: MacraFoodJournalTheme.textSoft)
                }

                HStack(spacing: 12) {
                    winOrGapTile(title: "Biggest win", body: report.biggestWin, icon: "checkmark.seal.fill", tint: MacraFoodJournalTheme.accent)
                    winOrGapTile(title: "Biggest gap", body: report.biggestGap, icon: "exclamationmark.triangle.fill", tint: MacraFoodJournalTheme.accent3)
                }
            }
            .padding(20)
            .background(foodJournalCardBackground)
        }
    }

    private func weeklyTrendSection(report: MacraNutritionInsightsReport) -> some View {
        FoodJournalSection(title: "Weekly trend", subtitle: "Last 7 days at a glance") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    weeklyStat(label: "Avg calories", value: report.weekAverageCaloriesLabel, tint: MacraFoodJournalTheme.accent)
                    weeklyStat(label: "Days logged", value: "\(report.weekLoggedDays) / 7", tint: MacraFoodJournalTheme.accent2)
                    weeklyStat(label: "Streak", value: "\(report.loggingStreak)d", tint: MacraFoodJournalTheme.accent3)
                }

                weeklyBarChart(days: report.weekDays)

                VStack(spacing: 8) {
                    trendRow(title: "Protein avg", value: report.weekAverageProteinLabel, trend: report.proteinTrend)
                    trendRow(title: "Carbs avg", value: report.weekAverageCarbsLabel, trend: report.carbTrend)
                    trendRow(title: "Fat avg", value: report.weekAverageFatLabel, trend: report.fatTrend)
                }
            }
            .padding(20)
            .background(foodJournalCardBackground)
        }
    }

    private func habitsSection(report: MacraNutritionInsightsReport) -> some View {
        FoodJournalSection(title: "Habits", subtitle: "Patterns detected in your logs") {
            VStack(spacing: 12) {
                if report.habits.isEmpty {
                    MacraFoodJournalEmptyState(
                        title: "Not enough data yet",
                        message: "Log a few more meals and we can surface your patterns."
                    )
                } else {
                    ForEach(report.habits) { habit in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: habit.icon)
                                .foregroundColor(MacraFoodJournalTheme.accent)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle().fill(MacraFoodJournalTheme.accent.opacity(0.16))
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(habit.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                Text(habit.detail)
                                    .font(.caption)
                                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(foodJournalCardBackground)
                    }
                }
            }
        }
    }

    private func patternInsightsSection(report: MacraNutritionInsightsReport) -> some View {
        FoodJournalSection(title: "Insights", subtitle: "Auto-generated from your week") {
            VStack(spacing: 12) {
                if report.patternInsights.isEmpty {
                    MacraFoodJournalEmptyState(
                        title: "Nothing to flag",
                        message: "You're staying consistent — keep going."
                    )
                } else {
                    ForEach(report.patternInsights) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: insight.icon)
                                .foregroundColor(insight.tint)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(insight.tint.opacity(0.16)))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(insight.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                Text(insight.body)
                                    .font(.caption)
                                    .foregroundColor(MacraFoodJournalTheme.textSoft)
                                    .lineSpacing(3)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(foodJournalCardBackground)
                    }
                }
            }
        }
    }

    private func predictionsSection(report: MacraNutritionInsightsReport) -> some View {
        FoodJournalSection(title: "Predictions", subtitle: "Where today and the week are trending") {
            VStack(spacing: 12) {
                ForEach(report.predictions) { prediction in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: prediction.icon)
                            .foregroundColor(MacraFoodJournalTheme.accent2)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(MacraFoodJournalTheme.accent2.opacity(0.16)))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(prediction.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text(prediction.body)
                                .font(.caption)
                                .foregroundColor(MacraFoodJournalTheme.textSoft)
                                .lineSpacing(3)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(foodJournalCardBackground)
                }
            }
        }
    }

    private func coachingSection(report: MacraNutritionInsightsReport) -> some View {
        FoodJournalSection(title: "AI coaching", subtitle: "Saved feedback from your journal") {
            VStack(spacing: 12) {
                if report.coachingInsights.isEmpty {
                    MacraFoodJournalEmptyState(
                        title: "No coaching notes yet",
                        message: "As you log meals, saved AI feedback will appear here."
                    )
                } else {
                    ForEach(report.coachingInsights) { insight in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: insight.icon)
                                    .foregroundColor(MacraFoodJournalTheme.accent)
                                Text(insight.title)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()
                                Text(insight.timestamp.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                            }
                            Text(insight.response)
                                .font(.subheadline)
                                .foregroundColor(MacraFoodJournalTheme.textSoft)
                                .lineSpacing(4)
                        }
                        .padding(14)
                        .background(foodJournalCardBackground)
                    }
                }
            }
        }
    }

    private func adherenceRow(title: String, percent: Int?, tint: Color) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
                .frame(width: 64, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * CGFloat(min(1.0, Double(percent ?? 0) / 100.0)))
                }
            }
            .frame(height: 8)
            Text(percent.map { "\($0)%" } ?? "—")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func winOrGapTile(title: String, body: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
            Text(body)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(foodJournalCardBackground)
    }

    private func weeklyStat(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
            Text(value)
                .font(.headline)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.14))
        )
    }

    private func trendRow(title: String, value: String, trend: MacraNutritionInsightsReport.Trend) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
            Image(systemName: trend.iconName)
                .foregroundColor(trend.tint)
        }
    }

    private func weeklyBarChart(days: [MacraNutritionInsightsReport.DayPoint]) -> some View {
        let maxCalories = max(days.map(\.calories).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(days) { day in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(day.isToday ? MacraFoodJournalTheme.accent : MacraFoodJournalTheme.accent.opacity(0.35))
                        .frame(height: max(6, CGFloat(day.calories) / CGFloat(maxCalories) * 88))
                    Text(day.weekdayLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(day.isToday ? MacraFoodJournalTheme.accent : MacraFoodJournalTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 118)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

struct MacraNutritionInsightsReport {
    struct DayPoint: Identifiable {
        let id: String
        let date: Date
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let mealCount: Int
        let isToday: Bool

        var weekdayLabel: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEEE"
            return formatter.string(from: date)
        }
    }

    struct Habit: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let icon: String
    }

    struct PatternInsight: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let icon: String
        let tint: Color
    }

    struct Prediction: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let icon: String
    }

    enum Trend {
        case up
        case down
        case flat

        var iconName: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .flat: return "arrow.right"
            }
        }

        var tint: Color {
            switch self {
            case .up: return MacraFoodJournalTheme.accent
            case .down: return MacraFoodJournalTheme.accent3
            case .flat: return MacraFoodJournalTheme.textMuted
            }
        }
    }

    let today: MacraFoodJournalDaySummary
    let weekDays: [DayPoint]
    let weekMeals: [MacraFoodJournalMeal]
    let coachingInsights: [MacraFoodJournalDailyInsight]

    init(today date: Date, store: MacraFoodJournalStore) {
        let calendar = Calendar.current
        self.today = store.daySummary(for: date)

        let startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: date)) ?? date
        var points: [DayPoint] = []
        var meals: [MacraFoodJournalMeal] = []
        for offset in 0..<7 {
            guard let current = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let dayMeals = store.meals(on: current)
            meals.append(contentsOf: dayMeals)
            points.append(
                DayPoint(
                    id: current.macraFoodJournalDayKey,
                    date: current,
                    calories: dayMeals.reduce(0) { $0 + $1.calories },
                    protein: dayMeals.reduce(0) { $0 + $1.protein },
                    carbs: dayMeals.reduce(0) { $0 + $1.carbs },
                    fat: dayMeals.reduce(0) { $0 + $1.fat },
                    mealCount: dayMeals.count,
                    isToday: calendar.isDate(current, inSameDayAs: date)
                )
            )
        }
        self.weekDays = points
        self.weekMeals = meals
        self.coachingInsights = today.insights
    }

    // MARK: - Scorecard

    var todayScore: Int {
        let metrics = [calorieAdherenceScore, proteinAdherenceScore, carbAdherenceScore, fatAdherenceScore]
            .compactMap { $0 }
        guard !metrics.isEmpty else {
            return today.mealCount > 0 ? 55 : 0
        }
        let average = metrics.reduce(0, +) / metrics.count
        return max(0, min(100, average))
    }

    var todayScoreLabel: String {
        switch todayScore {
        case 85...: return "On track"
        case 70..<85: return "Solid"
        case 50..<70: return "Room to tighten"
        case 1..<50: return "Needs attention"
        default: return "No data yet"
        }
    }

    var calorieAdherencePercent: Int? { percent(actual: today.totalCalories, target: today.macroTarget?.calories) }
    var proteinAdherencePercent: Int? { percent(actual: today.totalProtein, target: today.macroTarget?.protein) }
    var carbAdherencePercent: Int? { percent(actual: today.totalCarbs, target: today.macroTarget?.carbs) }
    var fatAdherencePercent: Int? { percent(actual: today.totalFat, target: today.macroTarget?.fat) }

    private var calorieAdherenceScore: Int? { adherenceScore(percent: calorieAdherencePercent) }
    private var proteinAdherenceScore: Int? { adherenceScore(percent: proteinAdherencePercent) }
    private var carbAdherenceScore: Int? { adherenceScore(percent: carbAdherencePercent) }
    private var fatAdherenceScore: Int? { adherenceScore(percent: fatAdherencePercent) }

    var biggestWin: String {
        if today.mealCount == 0 {
            return "Log your first meal to start the day."
        }
        if let target = today.macroTarget {
            if today.totalProtein >= target.protein {
                return "Protein is at or above target."
            }
            if Double(today.totalCalories) >= Double(target.calories) * 0.8 &&
               Double(today.totalCalories) <= Double(target.calories) * 1.05 {
                return "Calories are dialed in."
            }
        }
        if today.mealCount >= 3 {
            return "\(today.mealCount) meals already logged today."
        }
        return "You're logging — that's half the battle."
    }

    var biggestGap: String {
        guard let target = today.macroTarget else {
            return "Set macro targets to unlock gap detection."
        }
        let proteinRatio = Double(today.totalProtein) / Double(max(target.protein, 1))
        let carbRatio = Double(today.totalCarbs) / Double(max(target.carbs, 1))
        let fatRatio = Double(today.totalFat) / Double(max(target.fat, 1))
        let calorieRatio = Double(today.totalCalories) / Double(max(target.calories, 1))

        let entries: [(String, Double, Int, Int)] = [
            ("protein", proteinRatio, today.totalProtein, target.protein),
            ("carbs", carbRatio, today.totalCarbs, target.carbs),
            ("fat", fatRatio, today.totalFat, target.fat)
        ]

        if calorieRatio > 1.1 {
            return "Calories running \(Int((calorieRatio - 1) * 100))% over target."
        }

        if let worst = entries.min(by: { $0.1 < $1.1 }), worst.1 < 0.7 {
            let remaining = max(0, worst.3 - worst.2)
            return "\(remaining)g \(worst.0) short of target."
        }
        return "No big gaps right now."
    }

    // MARK: - Weekly trend

    var weekAverageCaloriesLabel: String {
        let logged = weekDays.filter { $0.calories > 0 }
        guard !logged.isEmpty else { return "—" }
        let avg = logged.map(\.calories).reduce(0, +) / logged.count
        return "\(avg)"
    }

    var weekAverageProteinLabel: String { average(weekDays.map(\.protein)) }
    var weekAverageCarbsLabel: String { average(weekDays.map(\.carbs)) }
    var weekAverageFatLabel: String { average(weekDays.map(\.fat)) }

    var weekLoggedDays: Int { weekDays.filter { $0.mealCount > 0 }.count }

    var loggingStreak: Int {
        var streak = 0
        for day in weekDays.reversed() {
            if day.mealCount > 0 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    var proteinTrend: Trend { trend(for: weekDays.map(\.protein)) }
    var carbTrend: Trend { trend(for: weekDays.map(\.carbs)) }
    var fatTrend: Trend { trend(for: weekDays.map(\.fat)) }

    // MARK: - Habits

    var habits: [Habit] {
        var items: [Habit] = []

        let loggedDays = weekDays.filter { $0.mealCount > 0 }
        guard !loggedDays.isEmpty else { return items }

        let avgMeals = Double(loggedDays.map(\.mealCount).reduce(0, +)) / Double(loggedDays.count)
        items.append(
            Habit(
                title: "Typical day: \(formatted(avgMeals)) meals",
                detail: "Average across the \(loggedDays.count) days you logged this week.",
                icon: "fork.knife"
            )
        )

        let allMeals = weekMeals
        if !allMeals.isEmpty {
            let counts = Dictionary(grouping: allMeals, by: { $0.name.lowercased() })
                .mapValues(\.count)
                .sorted { $0.value > $1.value }
            if let top = counts.first, top.value >= 2 {
                items.append(
                    Habit(
                        title: "Repeat favorite: \(top.key.capitalized)",
                        detail: "Logged \(top.value)× this week.",
                        icon: "star.fill"
                    )
                )
            }
        }

        let methodCounts = Dictionary(grouping: allMeals, by: { $0.entryMethod })
            .mapValues(\.count)
        if let topMethod = methodCounts.max(by: { $0.value < $1.value }) {
            items.append(
                Habit(
                    title: "Preferred entry: \(topMethod.key.habitLabel)",
                    detail: "\(topMethod.value) of \(allMeals.count) meals this week.",
                    icon: topMethod.key.habitIcon
                )
            )
        }

        let hourComponents = allMeals.map { Calendar.current.component(.hour, from: $0.createdAt) }
        if !hourComponents.isEmpty {
            let earliest = hourComponents.min() ?? 0
            let latest = hourComponents.max() ?? 0
            items.append(
                Habit(
                    title: "Eating window: \(formatHour(earliest))–\(formatHour(latest))",
                    detail: "First meal to last meal across the week.",
                    icon: "clock.fill"
                )
            )
        }

        return items
    }

    // MARK: - Pattern insights

    var patternInsights: [PatternInsight] {
        var items: [PatternInsight] = []
        let logged = weekDays.filter { $0.mealCount > 0 }
        guard !logged.isEmpty else { return items }

        let stdDev = standardDeviation(logged.map { Double($0.calories) })
        if stdDev > 500 {
            items.append(
                PatternInsight(
                    title: "Calorie variance is high",
                    body: "Daily calories swing by ±\(Int(stdDev)) kcal. Evening out the big days could help steady progress.",
                    icon: "waveform.path",
                    tint: MacraFoodJournalTheme.accent3
                )
            )
        } else if stdDev < 200 && logged.count >= 3 {
            items.append(
                PatternInsight(
                    title: "Very consistent calories",
                    body: "Your intake stays within ±\(Int(stdDev)) kcal most days.",
                    icon: "equal.circle.fill",
                    tint: MacraFoodJournalTheme.accent
                )
            )
        }

        if let target = today.macroTarget {
            let proteinAvg = logged.map(\.protein).reduce(0, +) / max(logged.count, 1)
            if proteinAvg < Int(Double(target.protein) * 0.8) {
                items.append(
                    PatternInsight(
                        title: "Protein trailing",
                        body: "Weekly average of \(proteinAvg)g is below your \(target.protein)g target.",
                        icon: "flame.fill",
                        tint: MacraFoodJournalTheme.accent3
                    )
                )
            }

            let carbAvg = logged.map(\.carbs).reduce(0, +) / max(logged.count, 1)
            if carbAvg > Int(Double(target.carbs) * 1.2) {
                items.append(
                    PatternInsight(
                        title: "Carbs above target",
                        body: "Averaging \(carbAvg)g carbs vs \(target.carbs)g target — worth checking late-day snacks.",
                        icon: "leaf.fill",
                        tint: MacraFoodJournalTheme.accent2
                    )
                )
            }
        }

        let weekendDays = logged.filter {
            let weekday = Calendar.current.component(.weekday, from: $0.date)
            return weekday == 1 || weekday == 7
        }
        let weekdayDays = logged.filter {
            let weekday = Calendar.current.component(.weekday, from: $0.date)
            return !(weekday == 1 || weekday == 7)
        }
        if !weekendDays.isEmpty && !weekdayDays.isEmpty {
            let weekendAvg = weekendDays.map(\.calories).reduce(0, +) / weekendDays.count
            let weekdayAvg = weekdayDays.map(\.calories).reduce(0, +) / weekdayDays.count
            let diff = weekendAvg - weekdayAvg
            if abs(diff) > 350 {
                let direction = diff > 0 ? "higher" : "lower"
                items.append(
                    PatternInsight(
                        title: "Weekend effect",
                        body: "Weekend calories run ~\(abs(diff)) kcal \(direction) than weekdays.",
                        icon: "calendar.badge.exclamationmark",
                        tint: MacraFoodJournalTheme.accent2
                    )
                )
            }
        }

        if loggingStreak >= 5 {
            items.append(
                PatternInsight(
                    title: "\(loggingStreak)-day streak",
                    body: "Consistent logging is the highest-leverage habit for hitting targets.",
                    icon: "flame.fill",
                    tint: MacraFoodJournalTheme.accent
                )
            )
        }

        return items
    }

    // MARK: - Predictions

    var predictions: [Prediction] {
        var items: [Prediction] = []

        let logged = weekDays.filter { $0.calories > 0 }
        if !logged.isEmpty {
            let avg = logged.map(\.calories).reduce(0, +) / logged.count
            let projected = avg * 7
            items.append(
                Prediction(
                    title: "Projected weekly intake",
                    body: "At your current pace you'll hit ~\(projected) kcal across the week.",
                    icon: "chart.line.uptrend.xyaxis"
                )
            )
        }

        if let target = today.macroTarget {
            let remaining = max(0, target.calories - today.totalCalories)
            items.append(
                Prediction(
                    title: "Remaining today",
                    body: "\(remaining) kcal left to stay inside your \(target.calories) kcal target.",
                    icon: "gauge.with.dots.needle.33percent"
                )
            )

            let proteinRemaining = max(0, target.protein - today.totalProtein)
            if proteinRemaining > 0 {
                items.append(
                    Prediction(
                        title: "Protein to go",
                        body: "\(proteinRemaining)g protein to hit \(target.protein)g — roughly \(proteinRemaining / 25 + 1) more Meal-sized servings.",
                        icon: "bolt.fill"
                    )
                )
            }
        }

        if loggingStreak >= 3 {
            items.append(
                Prediction(
                    title: "Streak projection",
                    body: "Log tomorrow to push your streak to \(loggingStreak + 1) days.",
                    icon: "flame"
                )
            )
        }

        if items.isEmpty {
            items.append(
                Prediction(
                    title: "Log a few meals",
                    body: "Predictions unlock once we have at least a day or two of data.",
                    icon: "sparkles"
                )
            )
        }

        return items
    }

    // MARK: - Helpers

    private func percent(actual: Int, target: Int?) -> Int? {
        guard let target, target > 0 else { return nil }
        return Int((Double(actual) / Double(target)) * 100)
    }

    private func adherenceScore(percent: Int?) -> Int? {
        guard let percent else { return nil }
        let distance = abs(100 - percent)
        return max(0, min(100, 100 - distance))
    }

    private func average(_ values: [Int]) -> String {
        let nonZero = values.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return "—" }
        let avg = nonZero.reduce(0, +) / nonZero.count
        return "\(avg)g"
    }

    private func trend(for values: [Int]) -> Trend {
        guard values.count >= 4 else { return .flat }
        let firstHalf = Array(values.prefix(values.count / 2))
        let secondHalf = Array(values.suffix(values.count / 2))
        let firstAvg = firstHalf.reduce(0, +) / max(firstHalf.count, 1)
        let secondAvg = secondHalf.reduce(0, +) / max(secondHalf.count, 1)
        let delta = secondAvg - firstAvg
        if abs(delta) < max(8, firstAvg / 20) { return .flat }
        return delta > 0 ? .up : .down
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        return variance.squareRoot()
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private func formatHour(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = hour
        let date = Calendar.current.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }
}

private extension MacraFoodJournalEntryMethod {
    var habitLabel: String {
        switch self {
        case .photo: return "Photo scans"
        case .text: return "Text entry"
        case .voice: return "Voice notes"
        case .history: return "Repeat meals"
        case .label: return "Label scans"
        case .quickLog: return "Quick logs"
        case .manual: return "Manual entry"
        }
    }

    var habitIcon: String {
        switch self {
        case .photo: return "camera.fill"
        case .text: return "text.alignleft"
        case .voice: return "mic.fill"
        case .history: return "clock.arrow.circlepath"
        case .label: return "barcode.viewfinder"
        case .quickLog: return "bolt.fill"
        case .manual: return "square.and.pencil"
        }
    }
}
