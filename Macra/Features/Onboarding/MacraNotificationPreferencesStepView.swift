import SwiftUI

/// Onboarding step: "How do you want Nora to hold you accountable on eating?"
/// Offers three independent toggles (meal reminders, morning log reminder,
/// end-of-day check-in). Tapping Continue requests notification permission
/// if any toggle is enabled — if denied, the prefs still save so the user
/// can flip them back on from Settings later.
struct NotificationPreferencesStepView: View {
    @ObservedObject var coordinator: MacraOnboardingCoordinator
    @State private var preferences: MacraNotificationPreferences = .default
    @State private var isRequesting = false

    private let accent = Color(hex: "E0FE10")

    var body: some View {
        OnboardingScaffold(
            title: "Choose how Nora holds you to this.",
            subtitle: "This is your first commitment before unlocking Macra: decide when you want the plan to pull you back on track.",
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            ctaTitle: "Continue to unlock",
            isLoading: isRequesting,
            onBack: coordinator.back,
            onForward: confirmAndAdvance
        ) {
            VStack(spacing: 12) {
                commitmentCard

                toggleCard(
                    title: "I will log every meal",
                    subtitle: "Nora can nudge Meal 1, 2, 3, and 4 so the plan stays visible.",
                    icon: "fork.knife",
                    isOn: $preferences.mealReminders
                )

                toggleCard(
                    title: "I will start the day on track",
                    subtitle: "An 8 AM nudge to make the first food decision intentional.",
                    icon: "sunrise.fill",
                    isOn: $preferences.morningLogReminder
                )

                toggleCard(
                    title: "I will check in before the day ends",
                    subtitle: "An 8 PM reflection with Nora so one day can teach the next.",
                    icon: "moon.stars.fill",
                    isOn: $preferences.endOfDayCheckin
                )

                optOutHint
            }
        }
        .onAppear {
            preferences = coordinator.answers.notificationPreferences
        }
        .onChange(of: preferences) { newValue in
            coordinator.answers.notificationPreferences = newValue
        }
    }

    private var commitmentCard: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 40, height: 40)
                .background(accent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("I am doing this.")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Pick one or more moments where Future You wants Nora to step in before old habits do.")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.32), lineWidth: 1)
        )
    }

    private func toggleCard(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isOn.wrappedValue ? accent.opacity(0.18) : Color.white.opacity(0.05))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isOn.wrappedValue ? accent : Color.white.opacity(0.55))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(accent)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(isOn.wrappedValue ? 0.1 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isOn.wrappedValue ? accent.opacity(0.55) : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
    }

    private var optOutHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.5))
            Text("You can leave reminders off and enable them later in Settings.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func confirmAndAdvance() {
        coordinator.answers.notificationPreferences = preferences

        guard preferences.hasAnyEnabled, !coordinator.isDemoMode else {
            coordinator.persistNotificationPreferences()
            coordinator.finishNotificationPreferencesAndAdvance()
            return
        }

        isRequesting = true
        Task {
            _ = await NotificationService.sharedInstance.requestAuthorization()
            await MainActor.run {
                coordinator.persistNotificationPreferences()
                isRequesting = false
                coordinator.finishNotificationPreferencesAndAdvance()
            }
        }
    }
}
