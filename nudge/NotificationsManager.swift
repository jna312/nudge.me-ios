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
        let mainNotificationID = "\(reminder.id.uuidString)-alert"
        let earlyNotificationID = "\(reminder.id.uuidString)-early-alert"

        // Remove any existing notifications for this reminder
        center.removePendingNotificationRequests(withIdentifiers: [mainNotificationID, earlyNotificationID])

        guard let alertAt = reminder.alertAt else { return }

        // Get selected ringtone
        let selectedRingtone = UserDefaults.standard.string(forKey: "selectedRingtone") ?? "standard"
        let notificationSound = getNotificationSound(for: selectedRingtone)
        
        // Schedule main alert at due time
        let mainContent = UNMutableNotificationContent()
        mainContent.title = "Reminder"
        mainContent.body = reminder.title
        mainContent.sound = notificationSound
        mainContent.userInfo = ["reminderID": reminder.id.uuidString]
        mainContent.categoryIdentifier = reminderCategoryIdentifier
        
        if #available(iOS 15.0, *) {
            mainContent.interruptionLevel = .timeSensitive
        }

        let mainComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alertAt)
        let mainTrigger = UNCalendarNotificationTrigger(dateMatching: mainComps, repeats: false)
        let mainReq = UNNotificationRequest(identifier: mainNotificationID, content: mainContent, trigger: mainTrigger)
        try? await center.add(mainReq)
        
        print("🔔 Scheduled main notification for '\(reminder.title)' at \(alertAt)")
        
        // Schedule early alert if configured
        if let earlyAlertAt = reminder.earlyAlertAt, earlyAlertAt > Date() {
            let earlyContent = UNMutableNotificationContent()
            earlyContent.title = "Coming Up"
            earlyContent.body = "\(reminder.title) in \(formatMinutes(reminder.earlyAlertMinutes ?? 15))"
            earlyContent.sound = notificationSound
            earlyContent.userInfo = ["reminderID": reminder.id.uuidString, "isEarlyAlert": true]
            earlyContent.categoryIdentifier = reminderCategoryIdentifier
            
            if #available(iOS 15.0, *) {
                earlyContent.interruptionLevel = .timeSensitive
            }
            
            let earlyComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: earlyAlertAt)
            let earlyTrigger = UNCalendarNotificationTrigger(dateMatching: earlyComps, repeats: false)
            let earlyReq = UNNotificationRequest(identifier: earlyNotificationID, content: earlyContent, trigger: earlyTrigger)
            try? await center.add(earlyReq)
            
            print("🔔 Scheduled early notification for '\(reminder.title)' at \(earlyAlertAt)")
        }
    }
    
    private func formatMinutes(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
    
    /// Get notification sound for the selected ringtone
    private func getNotificationSound(for ringtone: String) -> UNNotificationSound {
        // Sound files are in bundle root
        if let url = Bundle.main.url(forResource: ringtone, withExtension: "caf") {
            print("🔔 Using custom sound: \(ringtone).caf at \(url)")
            return UNNotificationSound(named: UNNotificationSoundName("\(ringtone).caf"))
        }
        print("🔔 Sound file not found for \(ringtone), using default")
        return .default
    }
}

extension NotificationsManager {
    func removeNotifications(for reminder: ReminderItem) {
        let mainID = "\(reminder.id.uuidString)-alert"
        let earlyID = "\(reminder.id.uuidString)-early-alert"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [mainID, earlyID])
        print("🔔 Removed all notifications for \(reminder.title)")
    }
}

