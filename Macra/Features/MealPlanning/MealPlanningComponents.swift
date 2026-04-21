import SwiftUI

struct MealPlanningCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.secondaryCharcoal.opacity(0.95),
                        Color.black.opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.secondaryWhite.opacity(0.08), lineWidth: 1)
            )
    }
}

struct MealPlanningSectionHeader: View {
    var title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondaryWhite)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondaryWhite.opacity(0.65))
                }
            }

            Spacer(minLength: 12)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primaryGreen)
                }
            }
        }
    }
}

struct MealMetricChip: View {
    var label: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(tint)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondaryWhite.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

struct MealPlanningPrimaryButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondaryCharcoal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primaryGreen)
                )
        }
    }
}

struct MealPlanningSecondaryButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondaryWhite)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.secondaryWhite.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.secondaryWhite.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

struct MealPlanningEmptyState: View {
    var title: String
    var message: String
    var systemImage: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.primaryGreen)
                .frame(width: 76, height: 76)
                .background(Circle().fill(Color.primaryGreen.opacity(0.12)))

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondaryWhite)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondaryWhite.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                MealPlanningPrimaryButton(title: actionTitle, systemImage: "plus") {
                    action()
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(MealPlanningCardBackground())
    }
}

struct MealPlanningMealThumbnail: View {
    let meal: Meal
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            if let url = URL(string: meal.image), !meal.image.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.primaryBlue.opacity(0.75), Color.primaryGreen.opacity(0.7)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(initials)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.secondaryWhite)
        }
    }

    private var initials: String {
        let pieces = meal.name.split(separator: " ")
        if let first = pieces.first {
            if pieces.count > 1, let second = pieces.dropFirst().first {
                return "\(first.prefix(1))\(second.prefix(1))".uppercased()
            }
            return String(first.prefix(2)).uppercased()
        }
        return "M"
    }
}

struct MealPlanningStatusPill: View {
    var text: String
    var tint: Color = .primaryGreen

    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                    )
            )
    }
}
