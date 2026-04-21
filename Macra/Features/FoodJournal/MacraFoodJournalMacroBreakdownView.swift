import SwiftUI

enum MacraFoodJournalMacroType: String, CaseIterable, Hashable, Identifiable {
    case protein = "Protein"
    case carbs = "Carbs"
    case fat = "Fat"
    case calories = "Calories"

    var id: String { rawValue }

    var unit: String {
        switch self {
        case .calories: return "cal"
        default: return "g"
        }
    }

    var tint: Color {
        switch self {
        case .protein: return MacraFoodJournalTheme.accent
        case .carbs: return MacraFoodJournalTheme.accent2
        case .fat: return MacraFoodJournalTheme.accent3
        case .calories: return MacraFoodJournalTheme.accent
        }
    }

    func value(in meal: MacraFoodJournalMeal) -> Int {
        switch self {
        case .protein: return meal.protein
        case .carbs: return meal.carbs
        case .fat: return meal.fat
        case .calories: return meal.calories
        }
    }

    func value(in supplement: LoggedSupplement) -> Int {
        switch self {
        case .protein: return supplement.protein
        case .carbs: return supplement.carbs
        case .fat: return supplement.fat
        case .calories: return supplement.calories
        }
    }

    func target(in macroTarget: MacraFoodJournalMacroTarget?) -> Int? {
        guard let macroTarget else { return nil }
        switch self {
        case .protein: return macroTarget.protein
        case .carbs: return macroTarget.carbs
        case .fat: return macroTarget.fat
        case .calories: return macroTarget.calories
        }
    }
}

struct MacraFoodJournalMacroBreakdownView: View {
    @Environment(\.dismiss) private var dismiss

    let meals: [MacraFoodJournalMeal]
    let supplements: [LoggedSupplement]
    let macroType: MacraFoodJournalMacroType
    let selectedDate: Date
    let macroTarget: MacraFoodJournalMacroTarget?

    init(
        meals: [MacraFoodJournalMeal],
        supplements: [LoggedSupplement] = [],
        macroType: MacraFoodJournalMacroType,
        selectedDate: Date,
        macroTarget: MacraFoodJournalMacroTarget?
    ) {
        self.meals = meals
        self.supplements = supplements
        self.macroType = macroType
        self.selectedDate = selectedDate
        self.macroTarget = macroTarget
    }

    private var mealBreakdown: [(meal: MacraFoodJournalMeal, amount: Int, time: String)] {
        meals.compactMap { meal in
            let amount = macroType.value(in: meal)
            guard amount > 0 else { return nil }
            return (meal, amount, meal.displayTime)
        }
        .sorted { $0.amount > $1.amount }
    }

    private var supplementBreakdown: [(supplement: LoggedSupplement, amount: Int, time: String)] {
        supplements.compactMap { supp in
            let amount = macroType.value(in: supp)
            guard amount > 0 else { return nil }
            let time = supp.createdAt.formatted(date: .omitted, time: .shortened)
            return (supp, amount, time)
        }
        .sorted { $0.amount > $1.amount }
    }

    private var mealTotal: Int {
        meals.reduce(0) { $0 + macroType.value(in: $1) }
    }

    private var supplementTotal: Int {
        supplements.reduce(0) { $0 + macroType.value(in: $1) }
    }

    private var totalValue: Int { mealTotal + supplementTotal }

    private var target: Int? { macroType.target(in: macroTarget) }

    private var formattedDate: String {
        selectedDate.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            header
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            Divider().background(Color.white.opacity(0.08))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if mealBreakdown.isEmpty && supplementBreakdown.isEmpty {
                        emptyState
                            .padding(.top, 48)
                            .frame(maxWidth: .infinity)
                    } else {
                        if !mealBreakdown.isEmpty {
                            contributionsHeader
                                .padding(.horizontal, 20)
                                .padding(.top, 18)

                            ForEach(Array(mealBreakdown.enumerated()), id: \.element.meal.id) { index, item in
                                mealRow(index: index, meal: item.meal, amount: item.amount, time: item.time)
                                    .padding(.horizontal, 20)
                            }
                        }

                        if !supplementBreakdown.isEmpty {
                            supplementContributionsHeader
                                .padding(.horizontal, 20)
                                .padding(.top, mealBreakdown.isEmpty ? 18 : 22)

                            ForEach(Array(supplementBreakdown.enumerated()), id: \.element.supplement.id) { index, item in
                                supplementRow(index: index, supplement: item.supplement, amount: item.amount, time: item.time)
                                    .padding(.horizontal, 20)
                            }
                        }

                        summaryCard
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .background(MacraFoodJournalTheme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(macroType.tint.opacity(0.18))
                    .frame(width: 52, height: 52)
                Text(macroType.unit)
                    .font(.headline.weight(.bold))
                    .foregroundColor(macroType.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(macroType.rawValue) by meal")
                    .font(.headline)
                    .foregroundColor(MacraFoodJournalTheme.text)
                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalValue)")
                    .font(.title2.weight(.bold))
                    .foregroundColor(macroType.tint)
                if let target {
                    Text("of \(target)\(macroType.unit)")
                        .font(.caption)
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                } else {
                    Text("total \(macroType.unit)")
                        .font(.caption)
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                }
            }
        }
    }

    private var contributionsHeader: some View {
        HStack {
            Text("Meal contributions")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textSoft)
            Spacer()
            Text("\(mealBreakdown.count) of \(meals.count)")
                .font(.caption)
                .foregroundColor(MacraFoodJournalTheme.textMuted)
        }
    }

    private var supplementContributionsHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "pills.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(.purple)
            Text("Supplement contributions")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.textSoft)
            Spacer()
            Text("+\(supplementTotal)\(macroType.unit)")
                .font(.caption.weight(.bold))
                .foregroundColor(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.purple.opacity(0.14)))
        }
    }

    private func mealRow(index: Int, meal: MacraFoodJournalMeal, amount: Int, time: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(macroType.tint.opacity(0.15))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().strokeBorder(macroType.tint.opacity(0.35), lineWidth: 1)
                    )
                Text("\(index + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(macroType.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name.isEmpty ? "Untitled meal" : meal.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.text)
                    .lineLimit(2)
                Text("Logged at \(time)")
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(amount)\(macroType.unit)")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(macroType.tint)
                if totalValue > 0 {
                    let pct = Int((Double(amount) / Double(totalValue)) * 100)
                    Text("\(pct)%")
                        .font(.caption)
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(MacraFoodJournalTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(macroType.tint.opacity(0.22), lineWidth: 1)
                )
        )
    }

    private func supplementRow(index: Int, supplement: LoggedSupplement, amount: Int, time: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle().strokeBorder(Color.purple.opacity(0.35), lineWidth: 1)
                    )
                Image(systemName: supplement.formIcon)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(supplement.name.isEmpty ? "Supplement" : supplement.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.text)
                    .lineLimit(2)
                Text("Taken at \(time) • \(supplement.dosageDescription)")
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(amount)\(macroType.unit)")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.purple)
                if totalValue > 0 {
                    let pct = Int((Double(amount) / Double(totalValue)) * 100)
                    Text("\(pct)%")
                        .font(.caption)
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.purple.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.purple.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(macroType.tint)
                Text("Daily summary")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(macroType.tint)
                Spacer()
            }
            Text(summaryText)
                .font(.caption)
                .foregroundColor(MacraFoodJournalTheme.textSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(macroType.tint.opacity(0.10))
        )
    }

    private var summaryText: String {
        let sourceCount = mealBreakdown.count + supplementBreakdown.count
        let sourceLabel: String
        if supplementBreakdown.isEmpty {
            sourceLabel = mealBreakdown.count == 1 ? "meal" : "meals"
        } else {
            sourceLabel = sourceCount == 1 ? "source" : "sources"
        }
        let base = "You consumed \(totalValue)\(macroType.unit) of \(macroType.rawValue.lowercased()) across \(sourceCount) \(sourceLabel) on \(formattedDate)."
        guard let target, target > 0 else { return base }
        let pct = Int((Double(totalValue) / Double(target)) * 100)
        return base + " That's \(pct)% of your \(target)\(macroType.unit) target."
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 44))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
            Text("No meals with \(macroType.rawValue.lowercased())")
                .font(.headline)
                .foregroundColor(MacraFoodJournalTheme.textSoft)
            Text("None of your meals for this day contain significant \(macroType.rawValue.lowercased()).")
                .font(.subheadline)
                .foregroundColor(MacraFoodJournalTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
