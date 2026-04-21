import SwiftUI

struct MealSelectionView: View {
    let availableMeals: [Meal]
    let planName: String
    var onAddSelected: ([Meal]) -> Void
    var onCancel: () -> Void

    @State private var searchText = ""
    @State private var selectedMealIDs: Set<String> = []

    private var filteredMeals: [Meal] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return availableMeals
        }

        let query = searchText.lowercased()
        return availableMeals.filter { meal in
            meal.name.lowercased().contains(query) ||
            meal.caption.lowercased().contains(query) ||
            meal.ingredients.joined(separator: " ").lowercased().contains(query) ||
            meal.categories.contains(where: { $0.displayName.lowercased().contains(query) || $0.rawValue.lowercased().contains(query) })
        }
    }

    private var selectedMeals: [Meal] {
        availableMeals.filter { selectedMealIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.secondaryCharcoal.ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Text("Add meals to plan")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondaryWhite)

                        Text(planName)
                            .font(.subheadline)
                            .foregroundColor(.secondaryWhite.opacity(0.68))
                    }
                    .padding(.top, 8)

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondaryWhite.opacity(0.6))
                        TextField("Search meal history", text: $searchText)
                            .foregroundColor(.secondaryWhite)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.secondaryWhite.opacity(0.06))
                    )

                    HStack {
                        MealPlanningStatusPill(text: "\(selectedMealIDs.count) selected", tint: .primaryGreen)
                        Spacer()
                        Button("Select all") {
                            selectedMealIDs = Set(filteredMeals.map(\.id))
                        }
                        .font(.subheadline)
                        .foregroundColor(.primaryGreen)
                    }

                    if filteredMeals.isEmpty {
                        MealPlanningEmptyState(
                            title: "No meals found",
                            message: searchText.isEmpty ? "Log a few meals first, then come back to seed this plan." : "Try a different search term.",
                            systemImage: "magnifyingglass"
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredMeals) { meal in
                                    MealSelectionRow(
                                        meal: meal,
                                        isSelected: selectedMealIDs.contains(meal.id)
                                    ) {
                                        toggleSelection(meal)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    HStack(spacing: 10) {
                        MealPlanningSecondaryButton(title: "Cancel", systemImage: "xmark") {
                            onCancel()
                        }

                        MealPlanningPrimaryButton(title: "Add selected", systemImage: "plus") {
                            onAddSelected(selectedMeals)
                        }
                        .disabled(selectedMeals.isEmpty)
                        .opacity(selectedMeals.isEmpty ? 0.55 : 1)
                    }
                }
                .padding(16)
            }
            .navigationBarHidden(true)
        }
    }

    private func toggleSelection(_ meal: Meal) {
        if selectedMealIDs.contains(meal.id) {
            selectedMealIDs.remove(meal.id)
        } else {
            selectedMealIDs.insert(meal.id)
        }
    }
}

struct MealSelectionRow: View {
    let meal: Meal
    let isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                MealPlanningMealThumbnail(meal: meal, size: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(meal.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondaryWhite)
                        .lineLimit(1)

                    Text(meal.macroLine)
                        .font(.subheadline)
                        .foregroundColor(.secondaryWhite.opacity(0.68))
                        .lineLimit(1)

                    Text(meal.categories.map { $0.displayName }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundColor(.secondaryWhite.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? .primaryGreen : .secondaryWhite.opacity(0.4))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.primaryGreen.opacity(0.12) : Color.secondaryWhite.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isSelected ? Color.primaryGreen.opacity(0.24) : Color.secondaryWhite.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
