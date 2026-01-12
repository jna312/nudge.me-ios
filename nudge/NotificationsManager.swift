import Foundation
import UserNotifications
import AudioToolbox
import AVFoundation

final class NotificationsManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()

    let reminderCategoryIdentifier = "REMINDER_CATEGORY"
    let closeoutCategoryIdentifier = "CLOSEOUT_CATEGORY"
    
    // Callback to pause/resume speech recognizer
    var onNotificationWillPresent: (() -> Void)?
    var onNotificationSoundComplete: (() -> Void)?
    
    private var audioPlayer: AVAudioPlayer?
    
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
            
            // Small delay to let audio session release, then play sound
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.playNotificationSound()
            }
        }
        
        return [.banner, .badge, .list] // Remove .sound since we play manually
    }
    
    @MainActor
    private func playNotificationSound() {
        print("🔔 Attempting to play sound...")
        
        do {
            // Configure for playback
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("🔔 Audio session set to playback")
            
            // Play system alert sound
            AudioServicesPlayAlertSound(SystemSoundID(1007))
            
            // Also vibrate
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            
            print("🔔 Sound command sent")
            
            // Resume speech after sound completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.onNotificationSoundComplete?()
            }
        } catch {
            print("🔔 Audio error: \(error)")
            self.onNotificationSoundComplete?()
        }
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
