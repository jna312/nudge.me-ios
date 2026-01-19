import Foundation
import Combine
import UserNotifications

final class NotificationsManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()

    let reminderCategoryIdentifier = "REMINDER_CATEGORY"
    let closeoutCategoryIdentifier = "CLOSEOUT_CATEGORY"
    
    // Custom alarm sound (15 seconds)
    private let alarmSound = UNNotificationSound(named: UNNotificationSoundName("reminder_alarm.caf"))
    private let alarmDuration: TimeInterval = 15.0
    
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
        
        // Notify to pause speech recognizer
        await MainActor.run {
            onNotificationWillPresent?()
        }
        
        // Check if this is an early alert (shorter sound) or main reminder (15s alarm)
        let isEarlyAlert = notification.request.content.userInfo["isEarlyAlert"] as? Bool ?? false
        let soundDuration = isEarlyAlert ? 1.5 : alarmDuration + 0.5
        
        // Resume mic after sound plays
        DispatchQueue.main.asyncAfter(deadline: .now() + soundDuration) {
            self.onNotificationSoundComplete?()
        }
        
        // Let iOS play the sound
        return [.banner, .badge, .list, .sound]
    }
    
    func requestPermission() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            ErrorLogger.log(error, context: "Requesting notification permission")
        }
    }

    func registerCategories() {
        let done = UNNotificationAction(identifier: "REMINDER_DONE", title: String(localized: "Done"), options: [])
        let snooze5 = UNNotificationAction(identifier: "REMINDER_SNOOZE_5", title: String(localized: "Snooze 5m"), options: [])
        let snooze15 = UNNotificationAction(identifier: "REMINDER_SNOOZE_15", title: String(localized: "Snooze 15m"), options: [])
        let snooze30 = UNNotificationAction(identifier: "REMINDER_SNOOZE_30", title: String(localized: "Snooze 30m"), options: [])

        let reminderCategory = UNNotificationCategory(
            identifier: reminderCategoryIdentifier,
            actions: [done, snooze5, snooze15, snooze30],
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
        
        
        // Handle closeout notification tap (either the notification itself or the Open button)
        if categoryID == closeoutCategoryIdentifier {
            if actionID == UNNotificationDefaultActionIdentifier || actionID == "CLOSEOUT_OPEN_APP" {
                await MainActor.run {
                    shouldNavigateToReminders = true
                }
            }
        }
        
        // Handle reminder notification tap
        if categoryID == reminderCategoryIdentifier {
            if actionID == UNNotificationDefaultActionIdentifier {
                await MainActor.run {
                    shouldNavigateToReminders = true
                }
                return
            }

            guard let idString = response.notification.request.content.userInfo["reminderID"] as? String,
                  let reminderID = UUID(uuidString: idString) else { return }

            switch actionID {
            case "REMINDER_DONE":
                await ReminderActions.markDone(reminderID: reminderID)
                await MorningBriefingManager.shared.scheduleUsingStoredSettings()
            case "REMINDER_SNOOZE_5":
                await ReminderActions.snooze(reminderID: reminderID, minutes: 5)
                await MorningBriefingManager.shared.scheduleUsingStoredSettings()
            case "REMINDER_SNOOZE_15":
                await ReminderActions.snooze(reminderID: reminderID, minutes: 15)
                await MorningBriefingManager.shared.scheduleUsingStoredSettings()
            case "REMINDER_SNOOZE_30":
                await ReminderActions.snooze(reminderID: reminderID, minutes: 30)
                await MorningBriefingManager.shared.scheduleUsingStoredSettings()
            default:
                break
            }
        }
    }
    
    /// Schedule a reminder notification
    func schedule(reminder: ReminderItem) async {
        let center = UNUserNotificationCenter.current()
        let mainNotificationID = "\(reminder.id.uuidString)-alert"
        let earlyNotificationID = "\(reminder.id.uuidString)-early-alert"

        // Remove any existing notifications for this reminder
        center.removePendingNotificationRequests(withIdentifiers: [mainNotificationID, earlyNotificationID])

        guard let alertAt = reminder.alertAt else { return }

        // Schedule main alert at due time
        let mainContent = UNMutableNotificationContent()
        mainContent.title = "Reminder"
        mainContent.body = reminder.title
        mainContent.sound = alarmSound  // 15-second classic alarm
        mainContent.userInfo = ["reminderID": reminder.id.uuidString]
        mainContent.categoryIdentifier = reminderCategoryIdentifier
        
        if #available(iOS 15.0, *) {
            mainContent.interruptionLevel = .timeSensitive
        }

        let mainComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: alertAt)
        let mainTrigger = UNCalendarNotificationTrigger(dateMatching: mainComps, repeats: false)
        let mainReq = UNNotificationRequest(identifier: mainNotificationID, content: mainContent, trigger: mainTrigger)
        do {
            try await center.add(mainReq)
        } catch {
            ErrorLogger.log(error, context: "Scheduling main notification for '\(reminder.title)'")
        }
        
        
        // Schedule early alert if configured
        if let earlyAlertAt = reminder.earlyAlertAt, earlyAlertAt > Date() {
            let earlyContent = UNMutableNotificationContent()
            earlyContent.title = "⏰ \(formatMinutes(reminder.earlyAlertMinutes ?? 15)) \(String(localized: "warning"))"
            earlyContent.body = "\(reminder.title) \(String(localized: "at")) \(formatTimeShort(alertAt))"
            earlyContent.sound = .default
            earlyContent.userInfo = ["reminderID": reminder.id.uuidString, "isEarlyAlert": true]
            earlyContent.categoryIdentifier = reminderCategoryIdentifier
            
            if #available(iOS 15.0, *) {
                earlyContent.interruptionLevel = .timeSensitive
            }
            
            let earlyComps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: earlyAlertAt)
            let earlyTrigger = UNCalendarNotificationTrigger(dateMatching: earlyComps, repeats: false)
            let earlyReq = UNNotificationRequest(identifier: earlyNotificationID, content: earlyContent, trigger: earlyTrigger)
            do {
                try await center.add(earlyReq)
            } catch {
                ErrorLogger.log(error, context: "Scheduling early alert for '\(reminder.title)'")
            }
        }
    }
    
}

extension NotificationsManager {
    func removeNotifications(for reminder: ReminderItem) {
        let mainID = "\(reminder.id.uuidString)-alert"
        let earlyID = "\(reminder.id.uuidString)-early-alert"
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [mainID, earlyID])
    }
}
