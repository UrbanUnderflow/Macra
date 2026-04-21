import Foundation
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

    // MARK: - Sync

    /// Replaces Macra's scheduled notifications to match the given preferences.
    /// Safe to call repeatedly — any previously scheduled Macra identifier is
    /// removed before new ones are installed.
    func syncScheduledNotifications(with preferences: MacraNotificationPreferences) {
        removeAllMacraNotifications()

        guard preferences.hasAnyEnabled else { return }

        if preferences.morningLogReminder {
            scheduleDailyRepeating(
                identifier: Identifier.morningLog,
                at: preferences.morningReminderTime,
                title: "Log today's food",
                body: "Get ahead of today — log your first meal and stay on track with Nora.",
                dataType: "macra_morning_log_reminder"
            )
        }

        if preferences.endOfDayCheckin {
            scheduleDailyRepeating(
                identifier: Identifier.endOfDayCheckin,
                at: preferences.endOfDayReminderTime,
                title: "How did eating go today?",
                body: "Let's check in with Nora on how you ate today. Quick reflection keeps you consistent.",
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
                    body: "Log \(label) so Nora can keep your macros on point.",
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
}
