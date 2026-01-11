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

        // Remove existing
        center.removePendingNotificationRequests(withIdentifiers: [
            "\(reminder.id.uuidString)-a1",
            "\(reminder.id.uuidString)-a2",
            "\(reminder.id.uuidString)-a1-wd-2",
            "\(reminder.id.uuidString)-a1-wd-3",
            "\(reminder.id.uuidString)-a1-wd-4",
            "\(reminder.id.uuidString)-a1-wd-5",
            "\(reminder.id.uuidString)-a1-wd-6",
            "\(reminder.id.uuidString)-a2-wd-2",
            "\(reminder.id.uuidString)-a2-wd-3",
            "\(reminder.id.uuidString)-a2-wd-4",
            "\(reminder.id.uuidString)-a2-wd-5",
            "\(reminder.id.uuidString)-a2-wd-6"
        ])

        let userInfo: [AnyHashable: Any] = ["reminderID": reminder.id.uuidString]

        func scheduleSingle(id: String, fireAt: Date, subtitle: String?) async {
            let trigger = makeTrigger(for: fireAt, repeatRule: reminder.repeatRule)
            let req = makeRequestWithTrigger(
                id: id,
                title: reminder.title,
                subtitle: subtitle,
                userInfo: userInfo,
                trigger: trigger
            )
            try? await center.add(req)
        }

        func scheduleWeekdays(baseID: String, fireAt: Date, subtitle: String?) async {
            // Monday=2 ... Friday=6 in Calendar weekday
            let weekdays = [2, 3, 4, 5, 6]
            let cal = Calendar.current
            let hm = cal.dateComponents([.hour, .minute], from: fireAt)

            for wd in weekdays {
                var comps = DateComponents()
                comps.weekday = wd
                comps.hour = hm.hour
                comps.minute = hm.minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let id = "\(baseID)-wd-\(wd)"

                let req = makeRequestWithTrigger(
                    id: id,
                    title: reminder.title,
                    subtitle: subtitle,
                    userInfo: userInfo,
                    trigger: trigger
                )
                try? await center.add(req)
            }
        }

        if let a1 = reminder.alert1At {
            if reminder.repeatRule == .weekdays {
                await scheduleWeekdays(baseID: "\(reminder.id.uuidString)-a1", fireAt: a1, subtitle: nil)
            } else {
                await scheduleSingle(id: "\(reminder.id.uuidString)-a1", fireAt: a1, subtitle: nil)
            }
        }

        if let a2 = reminder.alert2At {
            if reminder.repeatRule == .weekdays {
                await scheduleWeekdays(baseID: "\(reminder.id.uuidString)-a2", fireAt: a2, subtitle: "Second reminder")
            } else {
                await scheduleSingle(id: "\(reminder.id.uuidString)-a2", fireAt: a2, subtitle: "Second reminder")
            }
        }
    }

    private func makeTrigger(for fireAt: Date, repeatRule: ReminderItem.RepeatRule) -> UNNotificationTrigger {
        let cal = Calendar.current

        switch repeatRule {
        case .none:
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        case .daily:
            let comps = cal.dateComponents([.hour, .minute], from: fireAt)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        case .weekly:
            let comps = cal.dateComponents([.weekday, .hour, .minute], from: fireAt)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        case .weekdays:
            // We handle weekdays by scheduling 5 separate repeating requests (Mon–Fri)
            // so this function won’t be used for weekdays.
            let comps = cal.dateComponents([.hour, .minute], from: fireAt)
            return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        }
    }

    private func makeRequestWithTrigger(
        id: String,
        title: String,
        subtitle: String?,
        userInfo: [AnyHashable: Any],
        trigger: UNNotificationTrigger
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.sound = .default
        content.userInfo = userInfo
        content.categoryIdentifier = reminderCategoryIdentifier

        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

}

