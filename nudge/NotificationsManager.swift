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
        let id = reminder.id.uuidString
        let center = UNUserNotificationCenter.current()
        
        let identifiers = ["REM_\(id)_A1", "REM_\(id)_A2"]
        
        if reminder.alert1At == nil && reminder.alert2At == nil {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            return
        }
        
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = reminder.title
        content.sound = .default
        content.categoryIdentifier = reminderCategoryIdentifier
        
        if let alert1 = reminder.alert1At {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert1)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "REM_\(id)_A1", content: content, trigger: trigger)
            try? await center.add(req)
        }
        
        if let alert2 = reminder.alert2At {
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert2)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "REM_\(id)_A2", content: content, trigger: trigger)
            try? await center.add(req)
        }
        
        let pending = await center.pendingNotificationRequests()
        print("🔔 Pending requests after scheduling reminder:", pending.map { $0.identifier })
    }
}
