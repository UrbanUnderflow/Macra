import Foundation
import UIKit
import UserNotifications

/// Schedules Macra's on-device reminders and mirrors user preferences to
/// `UNUserNotificationCenter`. Every scheduled notification uses a stable
/// identifier so repeat sync calls replace (not duplicate) prior schedules.
///
/// The admin-side source of truth for these is
/// `QuickLifts-Web/src/pages/admin/notificationSequences.tsx` (Macra scope).
final class NotificationService {
    static let sharedInstance = NotificationService()

    private let center = UNUserNotificationCenter.current()

    // MARK: - Identifiers

    private enum Identifier {
        static let morningLog = "macra.morningLogReminder"
        static let endOfDayCheckin = "macra.endOfDayCheckin"
        static let trialEnding = "macra.trialEndingReminder"
        static func mealReminder(index: Int) -> String { "macra.mealReminder.\(index)" }
        static let allMealReminderIndices = 0..<8
    }

    // MARK: - Permission

    /// Requests alert + badge + sound authorization. Returns the granted state so
    /// callers can react (persist a user-visible disabled state, show a settings
    /// deep link, etc.).
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await registerForRemoteNotificationsIfAuthorized()
            }
            return granted
        } catch {
            print("NotificationService: authorization request failed — \(error.localizedDescription)")
            return false
        }
    }

    /// Reads current system authorization without prompting.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Registers with APNs only after the user has granted notification access.
    /// Firebase Messaging then mints a Macra app token in `MacraAppDelegate`.
    func registerForRemoteNotificationsIfAuthorized() async {
        let status = await authorizationStatus()
        guard Self.canRegisterForRemoteNotifications(status) else { return }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - Sync

    /// Replaces Macra's scheduled notifications to match the given preferences.
    /// Safe to call repeatedly — any previously scheduled Macra identifier is
    /// removed before new ones are installed.
    func syncScheduledNotifications(with preferences: MacraNotificationPreferences) {
        removeAllMacraNotifications()

        guard preferences.hasAnyEnabled else { return }

        Task {
            await registerForRemoteNotificationsIfAuthorized()
        }

        if preferences.morningLogReminder {
            scheduleDailyRepeating(
                identifier: Identifier.morningLog,
                at: preferences.morningReminderTime,
                title: "Log your first meal",
                body: "Open Macra so Nora can show you how much protein, carbs, and fat are left for the day.",
                dataType: "macra_morning_log_reminder"
            )
        }

        if preferences.endOfDayCheckin {
            scheduleDailyRepeating(
                identifier: Identifier.endOfDayCheckin,
                at: preferences.endOfDayReminderTime,
                title: "End-of-day check-in",
                body: "Tell Nora how today's eating went — she'll flag what to adjust tomorrow.",
                dataType: "macra_end_of_day_checkin"
            )
        }

        if preferences.mealReminders {
            for (index, time) in preferences.mealReminderTimes.enumerated() {
                let label = "Meal \(index + 1)"
                scheduleDailyRepeating(
                    identifier: Identifier.mealReminder(index: index),
                    at: time,
                    title: "\(label) time",
                    body: "Log \(label) so Nora can show you how much protein, carbs, and fat are left for the day.",
                    dataType: "macra_meal_reminder",
                    extraInfo: ["mealIndex": "\(index + 1)"]
                )
            }
        }
    }

    /// Removes every Macra-owned scheduled notification. Useful when the user
    /// disables everything, or when we want to re-sync cleanly.
    func removeAllMacraNotifications() {
        var identifiers: [String] = [
            Identifier.morningLog,
            Identifier.endOfDayCheckin,
        ]
        for index in Identifier.allMealReminderIndices {
            identifiers.append(Identifier.mealReminder(index: index))
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func scheduleTrialEndingReminder(trialDays: Int, leadDays: Int) {
        center.removePendingNotificationRequests(withIdentifiers: [Identifier.trialEnding])

        let normalizedTrialDays = max(trialDays, 1)
        let normalizedLeadDays = max(1, min(leadDays, max(normalizedTrialDays - 1, 1)))
        let daysUntilReminder = max(normalizedTrialDays - normalizedLeadDays, 1)
        guard let reminderDate = Calendar.current.date(byAdding: .day, value: daysUntilReminder, to: Date()) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Your Macra trial ends soon"
        content.body = normalizedLeadDays == 1
            ? "Your trial renews tomorrow. Review or cancel in Apple Subscriptions before the yearly plan starts."
            : "Your trial renews in \(normalizedLeadDays) days. Review or cancel in Apple Subscriptions before the yearly plan starts."
        content.sound = .default
        content.userInfo = [
            "type": "macra_trial_ending_reminder",
            "leadDays": "\(normalizedLeadDays)",
            "trialDays": "\(normalizedTrialDays)"
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Identifier.trialEnding, content: content, trigger: trigger)

        Task { [weak self] in
            guard let self else { return }

            let status = await self.authorizationStatus()
            if status == .notDetermined {
                _ = await self.requestAuthorization()
            } else {
                await self.registerForRemoteNotificationsIfAuthorized()
            }

            self.center.add(request) { error in
                if let error = error {
                    print("NotificationService: failed to schedule \(Identifier.trialEnding) — \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Private helpers

    private func scheduleDailyRepeating(
        identifier: String,
        at time: TimeOfDay,
        title: String,
        body: String,
        dataType: String,
        extraInfo: [String: String] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var userInfo: [AnyHashable: Any] = ["type": dataType]
        for (key, value) in extraInfo {
            userInfo[key] = value
        }
        content.userInfo = userInfo

        var components = DateComponents()
        components.hour = time.hour
        components.minute = time.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                print("NotificationService: failed to schedule \(identifier) — \(error.localizedDescription)")
            }
        }
    }

    private static func canRegisterForRemoteNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}
