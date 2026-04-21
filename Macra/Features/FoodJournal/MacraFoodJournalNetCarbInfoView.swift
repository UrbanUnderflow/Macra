import SwiftUI

struct MacraFoodJournalNetCarbInfoView: View {
    let meals: [MacraFoodJournalMeal]
    let selectedDate: Date

    private var mealsWithAdjustment: [MacraFoodJournalMeal] {
        meals.filter { $0.hasNetCarbAdjustment }
    }

    private var totalCarbs: Int { meals.reduce(0) { $0 + $1.carbs } }
    private var totalFiber: Int { meals.reduce(0) { $0 + ($1.fiber ?? 0) } }
    private var totalSugarAlcohols: Int { meals.reduce(0) { $0 + ($1.sugarAlcohols ?? 0) } }
    private var totalNetCarbs: Int { max(0, totalCarbs - totalFiber - totalSugarAlcohols) }

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

            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    formulaCard
                    totalsCard
                    if !mealsWithAdjustment.isEmpty {
                        adjustmentsSection
                    }
                    disclaimer
                }
                .padding(20)
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
                    .fill(MacraFoodJournalTheme.accent2.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "leaf.fill")
                    .font(.headline.weight(.bold))
                    .foregroundColor(MacraFoodJournalTheme.accent2)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Net carbs")
                    .font(.headline)
                    .foregroundColor(MacraFoodJournalTheme.text)
                Text(formattedDate)
                    .font(.subheadline)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalNetCarbs)g")
                    .font(.title2.weight(.bold))
                    .foregroundColor(MacraFoodJournalTheme.accent2)
                Text("net")
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
        }
        .padding(.horizontal, 20)
    }

    private var formulaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How it's calculated")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(MacraFoodJournalTheme.text)

            HStack(spacing: 6) {
                pill(text: "Total carbs", tint: MacraFoodJournalTheme.accent2)
                Text("−").font(.headline).foregroundColor(MacraFoodJournalTheme.textMuted)
                pill(text: "Fiber", tint: MacraFoodJournalTheme.accent)
                Text("−").font(.headline).foregroundColor(MacraFoodJournalTheme.textMuted)
                pill(text: "Sugar alcohols", tint: MacraFoodJournalTheme.accent3)
            }
            Text("Net carbs = max(0, carbs − fiber − sugar alcohols). Fiber passes through largely undigested, and sugar alcohols (erythritol, xylitol, allulose, monk fruit blends) are mostly unabsorbed — so they don't spike blood sugar the way regular carbs do.")
                .font(.caption)
                .foregroundColor(MacraFoodJournalTheme.textSoft)
                .lineSpacing(3)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(MacraFoodJournalTheme.panel)
        )
    }

    private var totalsCard: some View {
        VStack(spacing: 12) {
            totalRow(label: "Total carbs", value: totalCarbs, tint: MacraFoodJournalTheme.accent2)
            totalRow(label: "Fiber", value: totalFiber, tint: MacraFoodJournalTheme.accent, isSubtraction: true)
            totalRow(label: "Sugar alcohols", value: totalSugarAlcohols, tint: MacraFoodJournalTheme.accent3, isSubtraction: true)
            Divider().background(Color.white.opacity(0.12))
            totalRow(label: "Net carbs", value: totalNetCarbs, tint: MacraFoodJournalTheme.accent2, isResult: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(MacraFoodJournalTheme.panel)
        )
    }

    private var adjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Meals with adjustments")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.textSoft)
                Spacer()
                Text("\(mealsWithAdjustment.count)")
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }

            ForEach(mealsWithAdjustment) { meal in
                mealRow(meal)
            }
        }
    }

    private func mealRow(_ meal: MacraFoodJournalMeal) -> some View {
        let fiber = meal.fiber ?? 0
        let alcohols = meal.sugarAlcohols ?? 0
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name.isEmpty ? "Untitled meal" : meal.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(MacraFoodJournalTheme.text)
                    .lineLimit(2)
                Text("\(meal.carbs)g carbs • \(fiber)g fiber • \(alcohols)g sugar alcohols")
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(meal.netCarbs)g")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(MacraFoodJournalTheme.accent2)
                Text("net")
                    .font(.caption)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(MacraFoodJournalTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(MacraFoodJournalTheme.accent2.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var disclaimer: some View {
        Text("Sugar alcohols like allulose and erythritol are absorbed at very low rates. Maltitol absorbs more and behaves closer to a regular carb — if you track strictly, halve it instead of subtracting the full amount.")
            .font(.caption2)
            .foregroundColor(MacraFoodJournalTheme.textMuted)
            .lineSpacing(3)
            .padding(.top, 4)
    }

    private func pill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint.opacity(0.15)))
    }

    private func totalRow(label: String, value: Int, tint: Color, isSubtraction: Bool = false, isResult: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(isResult ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundColor(isResult ? MacraFoodJournalTheme.text : MacraFoodJournalTheme.textSoft)
            Spacer()
            Text("\(isSubtraction ? "−" : "")\(value)g")
                .font(isResult ? .headline.weight(.bold) : .subheadline.weight(.semibold))
                .foregroundColor(tint)
        }
    }
}
