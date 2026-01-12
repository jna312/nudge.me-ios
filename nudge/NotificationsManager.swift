import Foundation
import UserNotifications

final class NotificationsManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()

    let reminderCategoryIdentifier = "REMINDER_CATEGORY"
    let closeoutCategoryIdentifier = "CLOSEOUT_CATEGORY"

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }
    
    func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        print("🔔 Notifications permission granted =", granted)
        UNUserNotificationCenter.current().delegate = self
    }

    func registerCategories() {
        // Reminder actions
        let done = UNNotificationAction(identifier: "REMINDER_DONE", title: "Done", options: [])
        let snooze10 = UNNotificationAction(identifier: "REMINDER_SNOOZE_10", title: "Snooze 10m", options: [])

        let reminderCategory = UNNotificationCategory(
            identifier: reminderCategoryIdentifier,
            actions: [done, snooze10],
            intentIdentifiers: [],
            options: []
        )

        // Closeout actions
        let markAllDone = UNNotificationAction(identifier: "CLOSEOUT_MARK_ALL_DONE", title: "Mark all done", options: [])
        let snoozeAllTomorrow = UNNotificationAction(identifier: "CLOSEOUT_SNOOZE_ALL_TOMORROW", title: "Snooze all to tomorrow", options: [])
        let openApp = UNNotificationAction(identifier: "CLOSEOUT_OPEN_APP", title: "Open", options: [.foreground])

        let closeoutCategory = UNNotificationCategory(
            identifier: closeoutCategoryIdentifier,
            actions: [markAllDone, snoozeAllTomorrow, openApp],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([reminderCategory, closeoutCategory])
    }

    func scheduleTestIn30Seconds() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["TEST_30S"])

        let content = UNMutableNotificationContent()
        content.title = "Nudge TEST"
        content.body = "If you see this, notifications are working."
        content.sound = .default
        content.categoryIdentifier = closeoutCategoryIdentifier

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
        let req = UNNotificationRequest(identifier: "TEST_30S", content: content, trigger: trigger)
        try? await center.add(req)

        let pending = await center.pendingNotificationRequests()
        print("🔔 Pending requests:", pending.map { $0.identifier })
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        // We’ll wire these after DailyCloseoutManager exists
        print("🔔 Action tapped:", response.actionIdentifier)
    }
    
    func schedule(reminder: ReminderItem) async {
        let center = UNUserNotificationCenter.current()
        let notificationID = "\(reminder.id.uuidString)-alert"

        // Remove existing notification for this reminder
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        guard let alertAt = reminder.alertAt else { return }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.sound = .default
        content.userInfo = ["reminderID": reminder.id.uuidString]
        content.categoryIdentifier = reminderCategoryIdentifier

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alertAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let req = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        try? await center.add(req)
    }

}

