import SwiftUI

struct OnboardingScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    let progress: Double
    let canGoBack: Bool
    let canGoForward: Bool
    let ctaTitle: String
    let isLoading: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        progress: Double,
        canGoBack: Bool,
        canGoForward: Bool,
        ctaTitle: String = "Continue",
        isLoading: Bool = false,
        onBack: @escaping () -> Void,
        onForward: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.ctaTitle = ctaTitle
        self.isLoading = isLoading
        self.onBack = onBack
        self.onForward = onForward
        self.content = content()
    }

    var body: some View {
        ZStack {
            MacraChromaticBackground()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if canGoBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                    } else {
                        Color.clear.frame(width: 40, height: 40)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(Color.primaryGreen)
                                .frame(width: max(8, geo.size.width * progress))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 32)

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.system(size: 15))
                                .foregroundColor(Color.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        content
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }

                MacraPrimaryButton(
                    title: ctaTitle,
                    accent: Color.primaryGreen,
                    isLoading: isLoading,
                    action: onForward
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .opacity(canGoForward ? 1 : 0.4)
                .disabled(!canGoForward || isLoading)
            }
        }
    }
}

struct OnboardingChoiceCard<Value: Hashable>: View {
    let title: String
    let subtitle: String?
    let value: Value
    @Binding var selection: Value?

    var isSelected: Bool { selection == value }

    var body: some View {
        Button(action: { selection = value }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? Color.primaryGreen : Color.white.opacity(0.3))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.primaryGreen.opacity(0.7) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct PaywallTopBar: View {
    let canGoBack: Bool
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack {
            if canGoBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

struct TierCard: View {
    let title: String
    let perPeriodPrice: String
    let billingNote: String
    let badge: String?
    let emphasized: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(0.8)
                            .foregroundColor(Color.secondaryCharcoal)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primaryGreen)
                            .clipShape(Capsule())
                    }
                }

                Text(perPeriodPrice)
                    .font(.system(size: emphasized ? 28 : 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text(billingNote)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.12 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.primaryGreen : Color.white.opacity(0.08),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
