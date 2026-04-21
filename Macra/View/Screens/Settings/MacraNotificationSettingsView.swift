import SwiftUI

/// Post-onboarding settings surface for Macra push + email preferences.
/// Mirrors the onboarding step's toggles, plus exposes the email opt-outs
/// that weren't shown inline during onboarding (tips series, inactivity
/// winback). Saves to Firestore and re-syncs local notifications on change.
struct MacraNotificationSettingsView: View {
    @ObservedObject var appCoordinator: AppCoordinator

    @State private var push: MacraNotificationPreferences = .default
    @State private var email: MacraEmailPreferences = .default
    @State private var isLoading = true
    @State private var didSyncInitial = false

    private let accent = Color.primaryGreen

    var body: some View {
        ZStack {
            Color.primaryPurple.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.secondaryWhite)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            pushSection
                            emailSection
                            footer
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .onAppear(perform: loadPreferences)
    }

    private var header: some View {
        HStack {
            Button(action: { appCoordinator.closeModals() }) {
                IconImage(.sfSymbol(.close, color: .gray))
            }
            Spacer()
            Text("Notifications")
                .font(.headline.weight(.semibold))
                .foregroundColor(.secondaryWhite)
            Spacer()
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var pushSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PUSH NOTIFICATIONS")

            toggleRow(
                title: "Remind me for every meal",
                subtitle: "A nudge for Meal 1, 2, 3, and 4.",
                icon: "fork.knife",
                isOn: Binding(
                    get: { push.mealReminders },
                    set: { newValue in push.mealReminders = newValue; persistPush() }
                )
            )

            toggleRow(
                title: "Morning: remember to log food",
                subtitle: "An 8 AM nudge to start the day logging.",
                icon: "sunrise.fill",
                isOn: Binding(
                    get: { push.morningLogReminder },
                    set: { newValue in push.morningLogReminder = newValue; persistPush() }
                )
            )

            toggleRow(
                title: "End of day: check in on eating",
                subtitle: "An 8 PM reflection with Nora on how today went.",
                icon: "moon.stars.fill",
                isOn: Binding(
                    get: { push.endOfDayCheckin },
                    set: { newValue in push.endOfDayCheckin = newValue; persistPush() }
                )
            )
        }
    }

    private var emailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("EMAIL")

            toggleRow(
                title: "Nora tips series",
                subtitle: "Short tips on getting the most out of Macra, days 2 / 4 / 7.",
                icon: "envelope.fill",
                isOn: Binding(
                    get: { email.tipsSeries },
                    set: { newValue in email.tipsSeries = newValue; persistEmail() }
                )
            )

            toggleRow(
                title: "Check-in if I stop logging",
                subtitle: "A gentle winback email at 3, 7, and 14 days without a log.",
                icon: "clock.arrow.circlepath",
                isOn: Binding(
                    get: { email.inactivityWinback },
                    set: { newValue in email.inactivityWinback = newValue; persistEmail() }
                )
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondaryWhite.opacity(0.5))
            Text("iOS also lets you manage push notifications in Settings → Macra.")
                .font(.system(size: 12))
                .foregroundColor(.secondaryWhite.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundColor(accent)
            .padding(.top, 8)
    }

    private func toggleRow(title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isOn.wrappedValue ? accent.opacity(0.18) : Color.secondaryWhite.opacity(0.08))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isOn.wrappedValue ? accent : .secondaryWhite.opacity(0.55))
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondaryWhite)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.secondaryWhite.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(accent)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondaryWhite.opacity(isOn.wrappedValue ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isOn.wrappedValue ? accent.opacity(0.55) : Color.secondaryWhite.opacity(0.1),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Persistence

    private func loadPreferences() {
        UserService.sharedInstance.loadMacraPreferences { loadedPush, loadedEmail in
            self.push = loadedPush
            self.email = loadedEmail
            self.isLoading = false
            self.didSyncInitial = true
        }
    }

    private func persistPush() {
        guard didSyncInitial else { return }
        let current = push
        UserService.sharedInstance.saveMacraNotificationPreferences(current)
        syncOrRequestAuthorization(for: current)
    }

    private func persistEmail() {
        guard didSyncInitial else { return }
        UserService.sharedInstance.saveMacraEmailPreferences(email)
    }

    private func syncOrRequestAuthorization(for preferences: MacraNotificationPreferences) {
        guard preferences.hasAnyEnabled else {
            NotificationService.sharedInstance.syncScheduledNotifications(with: preferences)
            return
        }

        Task {
            let status = await NotificationService.sharedInstance.authorizationStatus()
            if status == .notDetermined {
                _ = await NotificationService.sharedInstance.requestAuthorization()
            }
            await MainActor.run {
                NotificationService.sharedInstance.syncScheduledNotifications(with: preferences)
            }
        }
    }
}
