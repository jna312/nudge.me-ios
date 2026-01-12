import Foundation
import Combine
import UserNotifications
import AudioToolbox
import AVFoundation

final class NotificationsManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()

    let reminderCategoryIdentifier = "REMINDER_CATEGORY"
    let closeoutCategoryIdentifier = "CLOSEOUT_CATEGORY"
    
    // Callback to pause/resume speech recognizer
    var onNotificationWillPresent: (() -> Void)?
    var onNotificationSoundComplete: (() -> Void)?
    
    // Published property to trigger navigation to Reminders tab
    @Published var shouldNavigateToReminders = false
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        print("🔔 Notification arriving in foreground...")
        
        // Notify to pause speech recognizer
        await MainActor.run {
            onNotificationWillPresent?()
        }
        
        // Resume mic after sound plays (default sound is ~1 second)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.onNotificationSoundComplete?()
        }
        
        // Let iOS play the default sound
        return [.banner, .badge, .list, .sound]
    }
    
    func requestPermission() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        print("🔔 Notifications permission granted =", granted)
    }

    func registerCategories() {
        let done = UNNotificationAction(identifier: "REMINDER_DONE", title: "Done", options: [])
        let snooze10 = UNNotificationAction(identifier: "REMINDER_SNOOZE_10", title: "Snooze 10m", options: [])

        let reminderCategory = UNNotificationCategory(
            identifier: reminderCategoryIdentifier,
            actions: [done, snooze10],
            intentIdentifiers: [],
            options: []
        )

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

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let actionID = response.actionIdentifier
        let categoryID = response.notification.request.content.categoryIdentifier
        
        print("🔔 Action tapped:", actionID, "Category:", categoryID)
        
        // Handle closeout notification tap (either the notification itself or the Open button)
        if categoryID == closeoutCategoryIdentifier {
            if actionID == UNNotificationDefaultActionIdentifier || actionID == "CLOSEOUT_OPEN_APP" {
                // User tapped on the notification or the "Open" button
                await MainActor.run {
                    shouldNavigateToReminders = true
                }
            }
        }
        
        // Handle reminder notification tap
        if categoryID == reminderCategoryIdentifier {
            if actionID == UNNotificationDefaultActionIdentifier {
                // User tapped on a reminder notification - go to reminders
                await MainActor.run {
                    shouldNavigateToReminders = true
                }
            }
        }
    }
    
    func schedule(reminder: ReminderItem) async {
        let center = UNUserNotificationCenter.current()
        let notificationID = "\(reminder.id.uuidString)-alert"

        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        guard let alertAt = reminder.alertAt else { return }

        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = reminder.title
        content.sound = .default
        content.userInfo = ["reminderID": reminder.id.uuidString]
        content.categoryIdentifier = reminderCategoryIdentifier
        
        // Ensure delivery even in Focus modes
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alertAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let req = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        try? await center.add(req)
        
        print("🔔 Scheduled notification for '\(reminder.title)' at \(alertAt)")
    }
}

