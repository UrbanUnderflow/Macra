import SwiftUI

/// Read-only meal detail sheet shown when the user taps a row in
/// `BuddyDayView`. Hero image up top, macro tiles, collapsible
/// ingredients, then the shared `MealSocialView` so likes/comments
/// stay in sync with the owner's own meal-log detail surface.
struct BuddyMealDetailView: View {
    let meal: Meal
    let ownerUid: String
    let ownerDisplayName: String

    @Environment(\.dismiss) private var dismiss
    @State private var isIngredientsExpanded: Bool = false

    private let blue = Color(hex: "3B82F6")
    private let lime = Color(hex: "E0FE10")
    private let amber = Color(hex: "F59E0B")
    private let accent = Color(hex: "8B5CF6")

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: meal.createdAt)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: meal.createdAt)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "0A0B0F"), Color(hex: "111318")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        heroImage
                        titleBlock
                        macroTotalsCard
                        ingredientsSection
                        MealSocialView(
                            ownerUid: ownerUid,
                            mealId: meal.id,
                            accentColor: lime
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .principal) {
                    Text(ownerDisplayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroImage: some View {
        if !meal.image.isEmpty, let url = URL(string: meal.image) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    heroFallback
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
        } else {
            heroFallback
        }
    }

    private var heroFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "fork.knife")
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(.white.opacity(0.40))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meal.name.isEmpty ? "Meal" : meal.name)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(dateString) · \(timeString)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    // MARK: - Macro tiles

    private var macroTotalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(meal.calories.formatted())")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .monospacedDigit()
                Text("kcal")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
            }

            HStack(spacing: 10) {
                macroTile(label: "P", icon: "bolt.fill", value: meal.protein, tint: blue)
                macroTile(label: "C", icon: "leaf.fill", value: meal.carbs, tint: lime)
                macroTile(label: "F", icon: "drop.fill", value: meal.fat, tint: amber)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [accent.opacity(0.40), lime.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private func macroTile(label: String, icon: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(tint)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundColor(tint.opacity(0.92))
            }
            Text("\(value)g")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.20), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.50), tint.opacity(0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Ingredients (collapsible)

    @ViewBuilder
    private var ingredientsSection: some View {
        if !meal.ingredients.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        isIngredientsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .bold))
                        Text("INGREDIENTS")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                        Spacer()
                        Text("\(meal.ingredients.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(isIngredientsExpanded ? 180 : 0))
                    }
                    .foregroundColor(.white.opacity(0.75))
                }
                .buttonStyle(.plain)

                if isIngredientsExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(meal.ingredients, id: \.self) { ingredient in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(lime.opacity(0.85))
                                    .frame(width: 4, height: 4)
                                Text(ingredient)
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.78))
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
    }
}
