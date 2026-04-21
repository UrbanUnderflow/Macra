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
            title: "How should Nora hold you accountable?",
            subtitle: "Pick any combination of reminders — you can change these any time.",
            progress: coordinator.progress,
            canGoBack: coordinator.canGoBack,
            canGoForward: coordinator.canGoForward,
            ctaTitle: "Continue",
            isLoading: isRequesting,
            onBack: coordinator.back,
            onForward: confirmAndAdvance
        ) {
            VStack(spacing: 12) {
                toggleCard(
                    title: "Remind me for every meal",
                    subtitle: "A nudge for Meal 1, 2, 3, and 4 so you never forget to log.",
                    icon: "fork.knife",
                    isOn: $preferences.mealReminders
                )

                toggleCard(
                    title: "Morning: remember to log food",
                    subtitle: "An 8 AM nudge to start the day on the right foot.",
                    icon: "sunrise.fill",
                    isOn: $preferences.morningLogReminder
                )

                toggleCard(
                    title: "End of day: check in on eating",
                    subtitle: "An 8 PM reflection with Nora on how today went.",
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
            Text("Leave everything off if you'd rather not be notified. You can enable later in Settings.")
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private func confirmAndAdvance() {
        coordinator.answers.notificationPreferences = preferences

        guard preferences.hasAnyEnabled else {
            coordinator.persistNotificationPreferencesAndNotifyWelcome()
            coordinator.advance()
            return
        }

        isRequesting = true
        Task {
            _ = await NotificationService.sharedInstance.requestAuthorization()
            await MainActor.run {
                coordinator.persistNotificationPreferencesAndNotifyWelcome()
                isRequesting = false
                coordinator.advance()
            }
        }
    }
}
