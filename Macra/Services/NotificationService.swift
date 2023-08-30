import Foundation
import UserNotifications

class NotificationService {
    static let sharedInstance = NotificationService()

    func scheduleDailyNotification() {
        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Notification"
        content.body = "Notification"
        content.sound = UNNotificationSound.default

        // Calculate the trigger time (2 hours before the task expires)
//        let calendar = Calendar.current
//        guard let expirationDate = getActivityExpirationFromUserDefaults() else {
//            print("Error: Couldn't get activity expiration date from UserDefaults")
//            return
//        }
//        let triggerDate = calendar.date(byAdding: .hour, value: -2, to: expirationDate)!
//        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
//
//        // Create a trigger
//        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
//
//        // Create a notification request
//        let request = UNNotificationRequest(identifier: "dailyActivityReminder", content: content, trigger: trigger)
//
//        // Schedule the notification
//        UNUserNotificationCenter.current().add(request) { error in
//            if let error = error {
//                print("Error scheduling daily notification: \(error.localizedDescription)")
//            } else {
//                print("Daily notification scheduled successfully")
//            }
//        }
    }
}
