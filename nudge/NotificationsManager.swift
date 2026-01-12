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
    
    // Current sound setting (set by ContentView)
    var currentSoundSetting: String = "default"
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        print("🔔 Notification arriving in foreground...")
        
        // Get sound setting from notification userInfo
        let soundSetting = notification.request.content.userInfo["soundSetting"] as? String ?? currentSoundSetting
        
        // Notify to pause speech recognizer and play sound manually
        await MainActor.run {
            onNotificationWillPresent?()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.playNotificationSound(soundSetting: soundSetting)
            }
        }
        
        return [.banner, .badge, .list] // Remove .sound since we play manually in foreground
    }
    
    @MainActor
    private func playNotificationSound(soundSetting: String) {
        let soundOption = NotificationSoundOption.from(soundSetting)
        
        guard soundOption != .silent else {
            print("🔔 Sound is set to silent, skipping")
            onNotificationSoundComplete?()
            return
        }
        
        print("🔔 Playing sound: \(soundOption.displayName) (duration: \(soundOption.duration)s)")
        
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("🔔 Audio session error: \(error)")
        }
        
        AudioServicesPlayAlertSound(SystemSoundID(soundOption.systemSoundID))
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        
        let delay = soundOption.duration + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            print("🔔 Sound complete, resuming mic")
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
        content.userInfo = [
            "reminderID": reminder.id.uuidString,
            "soundSetting": soundSetting
        ]
        content.categoryIdentifier = reminderCategoryIdentifier
        
        // Set notification sound based on setting
        let soundOption = NotificationSoundOption.from(soundSetting)
        if soundOption == .silent {
            content.sound = nil
        } else if let soundFileName = soundOption.notificationSoundFile,
                  Bundle.main.url(forResource: soundFileName, withExtension: nil) != nil {
            // Use bundled sound file if available
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundFileName))
        } else {
            // Fall back to default system sound
            content.sound = .default
        }
        
        // For important reminders, use interruptionLevel to ensure delivery
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alertAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let req = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        try? await center.add(req)
        
        print("🔔 Scheduled notification for '\(reminder.title)' at \(alertAt) with sound: \(soundOption.displayName)")
    }
}
