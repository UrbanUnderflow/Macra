import SwiftUI

/// Daily "Full Nutrition Breakdown" card shown under the Today hero macros.
/// Starts collapsed — users tap the header to expand and see micronutrients,
/// vitamins, and minerals. Port of the FWP Food Tracker detailed-nutrition
/// section (`MealDetailsView.swift`), re-skinned for Macra's blue theme and
/// driven by `MacraFoodJournalDaySummary` daily totals rather than a single
/// meal.
struct MacraFoodJournalNutritionBreakdownCard: View {
    let summary: MacraFoodJournalDaySummary

    @State private var isExpanded: Bool = false

    private var hasAccurateData: Bool { summary.hasAnyIngredientDetailedNutrition }

    private var sortedVitamins: [(String, Int)] {
        summary.totalVitamins
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
    }

    private var sortedMinerals: [(String, Int)] {
        summary.totalMinerals
            .filter { $0.value > 0 }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton

            if isExpanded {
                if summary.hasDetailedNutrition {
                    expandedContent
                        .padding(.top, 16)
                } else {
                    emptyState
                        .padding(.top, 16)
                }
            }
        }
        .padding(20)
        .background(foodJournalCardBackground)
    }

    // MARK: - Header

    private var headerButton: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(MacraFoodJournalTheme.accent2.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(MacraFoodJournalTheme.accent2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Full nutrition breakdown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundColor(MacraFoodJournalTheme.textMuted)
                }

                Spacer()

                qualityBadge

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Full nutrition breakdown, \(isExpanded ? "expanded" : "collapsed")")
    }

    private var headerSubtitle: String {
        if summary.hasDetailedNutrition {
            var parts: [String] = []
            if summary.totalFiber > 0 { parts.append("\(summary.totalFiber)g fiber") }
            if summary.totalSodium > 0 { parts.append("\(summary.totalSodium)mg sodium") }
            let vitaminCount = sortedVitamins.count
            let mineralCount = sortedMinerals.count
            if vitaminCount + mineralCount > 0 {
                parts.append("\(vitaminCount + mineralCount) vitamins & minerals")
            }
            if parts.isEmpty { return "Tap to see micronutrients" }
            return parts.prefix(2).joined(separator: " · ")
        }
        return "Log a meal with ingredients to unlock micros"
    }

    private var qualityBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: hasAccurateData ? "checkmark.seal.fill" : "info.circle")
                .font(.caption2.weight(.semibold))
            Text(hasAccurateData ? "Accurate" : "Estimated")
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(hasAccurateData ? MacraFoodJournalTheme.accent : MacraFoodJournalTheme.textMuted)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((hasAccurateData ? MacraFoodJournalTheme.accent : MacraFoodJournalTheme.textMuted).opacity(0.12))
        )
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            microGrid
            if !sortedVitamins.isEmpty {
                vitaminsSection
            }
            if !sortedMinerals.isEmpty {
                mineralsSection
            }
        }
    }

    private var microGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            if summary.totalSugars > 0 {
                MacraNutritionStatTile(
                    title: "Sugars",
                    value: summary.totalSugars,
                    unit: "g",
                    color: .purple,
                    hasAccurateData: hasAccurateData
                )
            }
            if summary.totalFiber > 0 {
                MacraNutritionStatTile(
                    title: "Fiber",
                    value: summary.totalFiber,
                    unit: "g",
                    color: MacraFoodJournalTheme.accent,
                    hasAccurateData: hasAccurateData
                )
            }
            if summary.totalSodium > 0 {
                MacraNutritionStatTile(
                    title: "Sodium",
                    value: summary.totalSodium,
                    unit: "mg",
                    color: .red,
                    hasAccurateData: hasAccurateData
                )
            }
            if summary.totalCholesterol > 0 {
                MacraNutritionStatTile(
                    title: "Cholesterol",
                    value: summary.totalCholesterol,
                    unit: "mg",
                    color: .yellow,
                    hasAccurateData: hasAccurateData
                )
            }
            if summary.totalSaturatedFat > 0 {
                MacraNutritionStatTile(
                    title: "Sat. Fat",
                    value: summary.totalSaturatedFat,
                    unit: "g",
                    color: MacraFoodJournalTheme.accent3,
                    hasAccurateData: hasAccurateData
                )
            }
            if summary.totalUnsaturatedFat > 0 {
                MacraNutritionStatTile(
                    title: "Unsat. Fat",
                    value: summary.totalUnsaturatedFat,
                    unit: "g",
                    color: MacraFoodJournalTheme.accent2,
                    hasAccurateData: hasAccurateData
                )
            }
        }
    }

    private var vitaminsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Vitamins")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 8) {
                ForEach(sortedVitamins, id: \.0) { name, amount in
                    MacraVitaminMineralTile(
                        name: name,
                        amount: amount,
                        unit: MacraFoodJournalNutrientUnits.forVitamin(name),
                        color: MacraFoodJournalTheme.accent
                    )
                }
            }
        }
    }

    private var mineralsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Minerals")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 8) {
                ForEach(sortedMinerals, id: \.0) { name, amount in
                    MacraVitaminMineralTile(
                        name: name,
                        amount: amount,
                        unit: MacraFoodJournalNutrientUnits.forMineral(name),
                        color: MacraFoodJournalTheme.accent2
                    )
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(MacraFoodJournalTheme.textSoft)
            .tracking(1)
            .textCase(.uppercase)
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundColor(MacraFoodJournalTheme.accent2)
            Text("No micronutrient data for today yet. Scan a meal or add ingredients with amounts to unlock sodium, vitamins, and minerals.")
                .font(.caption)
                .foregroundColor(MacraFoodJournalTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Tile components

struct MacraNutritionStatTile: View {
    let title: String
    let value: Int
    let unit: String
    let color: Color
    let hasAccurateData: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(MacraFoodJournalTheme.textSoft)
                Spacer()
                Image(systemName: hasAccurateData ? "checkmark.circle.fill" : "info.circle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(hasAccurateData ? MacraFoodJournalTheme.accent : MacraFoodJournalTheme.textMuted)
            }

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(color)
                Text(unit)
                    .font(.caption2)
                    .foregroundColor(MacraFoodJournalTheme.textMuted)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(hasAccurateData ? 0.14 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(color.opacity(hasAccurateData ? 0.32 : 0.20), lineWidth: hasAccurateData ? 1 : 0.5)
                )
        )
    }
}

struct MacraVitaminMineralTile: View {
    let name: String
    let amount: Int
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(amount)\(unit)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .tracking(-0.1)

            Text(name)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(MacraFoodJournalTheme.textMuted)
                .tracking(0.2)
                .textCase(.uppercase)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(color.opacity(0.22), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Unit lookup
// Ported from the FWP helpers `getVitaminUnit` / `getMineralUnit` so daily
// totals render with the same unit labeling users saw on FWP.

enum MacraFoodJournalNutrientUnits {
    static func forVitamin(_ vitamin: String) -> String {
        let v = vitamin.lowercased()
        switch v {
        case let s where s.contains("vitamin a") || s.contains("retinol"): return "mcg"
        case let s where s.contains("vitamin b1") || s.contains("thiamine"): return "mg"
        case let s where s.contains("vitamin b2") || s.contains("riboflavin"): return "mg"
        case let s where s.contains("vitamin b3") || s.contains("niacin"): return "mg"
        case let s where s.contains("vitamin b5") || s.contains("pantothenic"): return "mg"
        case let s where s.contains("vitamin b6") || s.contains("pyridoxine"): return "mg"
        case let s where s.contains("vitamin b7") || s.contains("biotin"): return "mcg"
        case let s where s.contains("vitamin b9") || s.contains("folate") || s.contains("folic"): return "mcg"
        case let s where s.contains("vitamin b12") || s.contains("cobalamin"): return "mcg"
        case let s where s.contains("vitamin c") || s.contains("ascorbic"): return "mg"
        case let s where s.contains("vitamin d"): return "mcg"
        case let s where s.contains("vitamin e") || s.contains("tocopherol"): return "mg"
        case let s where s.contains("vitamin k"): return "mcg"
        case let s where s.contains("choline"): return "mg"
        default: return "mg"
        }
    }

    static func forMineral(_ mineral: String) -> String {
        let m = mineral.lowercased()
        switch m {
        case let s where s.contains("calcium"): return "mg"
        case let s where s.contains("iron"): return "mg"
        case let s where s.contains("magnesium"): return "mg"
        case let s where s.contains("phosphorus"): return "mg"
        case let s where s.contains("potassium"): return "mg"
        case let s where s.contains("sodium"): return "mg"
        case let s where s.contains("zinc"): return "mg"
        case let s where s.contains("copper"): return "mg"
        case let s where s.contains("manganese"): return "mg"
        case let s where s.contains("selenium"): return "mcg"
        case let s where s.contains("chromium"): return "mcg"
        case let s where s.contains("molybdenum"): return "mcg"
        case let s where s.contains("iodine"): return "mcg"
        case let s where s.contains("fluoride"): return "mg"
        default: return "mg"
        }
    }
}
