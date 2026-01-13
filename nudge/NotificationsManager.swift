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
    
    // AlarmKit manager for iOS 26+
    private let alarmKitManager = AlarmKitManager.shared
    
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
        // Request standard notification permission
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        print("🔔 Notifications permission granted =", granted)
        
        // Also request AlarmKit permission if available
        await requestAlarmKitPermission()
    }
    
    /// Request AlarmKit authorization (iOS 26+)
    func requestAlarmKitPermission() async {
        let granted = await alarmKitManager.requestAuthorization()
        print("⏰ AlarmKit permission: \(granted ? "granted" : "denied or unavailable")")
    }
    
    /// Check if AlarmKit is available and authorized
    var isAlarmKitReady: Bool {
        alarmKitManager.isAlarmKitAvailable && alarmKitManager.isAuthorized
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
    
    /// Schedule a reminder - uses AlarmKit if available and enabled, otherwise standard notifications
    func schedule(reminder: ReminderItem) async {
        let useAlarmMode = UserDefaults.standard.bool(forKey: "useAlarmMode")
        let selectedRingtone = UserDefaults.standard.string(forKey: "selectedRingtone") ?? "standard"
        
        // Try AlarmKit first if enabled and available (iOS 26+)
        if useAlarmMode && isAlarmKitReady {
            let alarmScheduled = await alarmKitManager.scheduleAlarm(for: reminder, soundName: selectedRingtone)
            if alarmScheduled {
                print("⏰ Using AlarmKit for reminder: \(reminder.title)")
                // Also schedule a backup notification (quieter, in case alarm is dismissed)
                await scheduleBackupNotification(reminder: reminder, soundName: selectedRingtone)
                return
            }
        }
        
        // Fall back to standard notification
        await scheduleStandardNotification(reminder: reminder, soundName: selectedRingtone)
    }
    
    /// Schedule a standard notification (for older iOS or when AlarmKit is disabled)
    private func scheduleStandardNotification(reminder: ReminderItem, soundName: String) async {
        let center = UNUserNotificationCenter.current()
        let mainNotificationID = "\(reminder.id.uuidString)-alert"
        let earlyNotificationID = "\(reminder.id.uuidString)-early-alert"

        // Remove any existing notifications for this reminder
        center.removePendingNotificationRequests(withIdentifiers: [mainNotificationID, earlyNotificationID])

        guard let alertAt = reminder.alertAt else { return }

        let notificationSound = getNotificationSound(for: soundName)
        
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
        
        print("🔔 Scheduled standard notification for '\(reminder.title)' at \(alertAt)")
        
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
    
    /// Schedule a quiet backup notification when using AlarmKit
    /// This shows in notification center even after alarm is dismissed
    private func scheduleBackupNotification(reminder: ReminderItem, soundName: String) async {
        guard let alertAt = reminder.alertAt else { return }
        
        let center = UNUserNotificationCenter.current()
        let backupID = "\(reminder.id.uuidString)-backup"
        
        let content = UNMutableNotificationContent()
        content.title = "Reminder"
        content.body = reminder.title
        content.sound = nil  // Silent - alarm handles the sound
        content.userInfo = ["reminderID": reminder.id.uuidString, "isBackup": true]
        content.categoryIdentifier = reminderCategoryIdentifier
        
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alertAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: backupID, content: content, trigger: trigger)
        try? await center.add(req)
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
        // Use system default if selected or if ringtone is empty
        if ringtone == "default" || ringtone.isEmpty {
            print("🔔 Using system default sound")
            return .default
        }
        
        // Check if sound file exists in bundle
        guard let url = Bundle.main.url(forResource: ringtone, withExtension: "caf") else {
            print("🔔 Sound file '\(ringtone).caf' not found in bundle, using default")
            return .default
        }
        
        // Verify file exists at URL
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("🔔 Sound file exists in bundle but not on disk: \(url.path), using default")
            return .default
        }
        
        print("🔔 Using custom sound: \(ringtone).caf")
        return UNNotificationSound(named: UNNotificationSoundName("\(ringtone).caf"))
    }
}

extension NotificationsManager {
    func removeNotifications(for reminder: ReminderItem) {
        let mainID = "\(reminder.id.uuidString)-alert"
        let earlyID = "\(reminder.id.uuidString)-early-alert"
        let backupID = "\(reminder.id.uuidString)-backup"
        
        // Remove standard notifications
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [mainID, earlyID, backupID])
        print("🔔 Removed all notifications for \(reminder.title)")
        
        // Also cancel AlarmKit alarm if applicable
        Task {
            await alarmKitManager.cancelAlarm(for: reminder)
        }
    }
}
