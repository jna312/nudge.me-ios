import Foundation
import UserNotifications
import AudioToolbox
import AVFoundation

final class NotificationsManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()

    let reminderCategoryIdentifier = "REMINDER_CATEGORY"
    let closeoutCategoryIdentifier = "CLOSEOUT_CATEGORY"
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Play sound on main thread since we're in async context
        await MainActor.run {
            playNotificationSound()
        }
        
        return [.banner, .sound, .badge, .list]
    }
    
    /// Play notification sound manually - works even when microphone is active
    @MainActor
    private func playNotificationSound() {
        print("🔔 Playing foreground notification sound...")
        
        // Configure audio session to allow playback even while recording
        do {
            let session = AVAudioSession.sharedInstance()
            // Use playAndRecord with duckOthers to lower other audio and play our sound
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers, .allowBluetooth])
            try session.setActive(true, options: [])
            print("🔔 Audio session configured for playAndRecord")
        } catch {
            print("🔔 Audio session error: \(error)")
        }
        
        // Play alert sound (with vibration on supported devices)
        AudioServicesPlayAlertSound(SystemSoundID(1007))
        
        // Also trigger vibration as backup feedback
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        print("🔔 Sound triggered")
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
        print("🔔 Action tapped:", response.actionIdentifier)
    }
    
    func schedule(reminder: ReminderItem, soundSetting: String = "default") async {
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

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alertAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let req = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        try? await center.add(req)
        
        print("🔔 Scheduled notification for '\(reminder.title)' at \(alertAt)")
    }
}
