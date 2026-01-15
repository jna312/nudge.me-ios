import Foundation
import SwiftData
import UserNotifications

@MainActor
final class DailyCloseoutManager {
    static let shared = DailyCloseoutManager()
    private let closeoutRequestID = "DAILY_CLOSEOUT"

    func scheduleIfNeeded(settings: AppSettings, modelContext: ModelContext) async {
        // Only schedule if at least 1 reminder was created today.
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

        let desc = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { item in
                item.createdAt >= start && item.createdAt < end
            }
        )

        let count = ErrorLogger.attempt("Counting today's reminders") {
            try modelContext.fetchCount(desc)
        } ?? 0
        
        let center = UNUserNotificationCenter.current()

        if count == 0 {
            center.removePendingNotificationRequests(withIdentifiers: [closeoutRequestID])
            return
        }

        // Schedule at user's chosen time today (or tomorrow if already passed).
        let minutes = settings.dailyCloseoutMinutes
        let hour = minutes / 60
        let minute = minutes % 60

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour
        comps.minute = minute

        guard let fireDate = Calendar.current.date(from: comps) else { return }
        let actualFireDate = fireDate > Date()
            ? fireDate
            : Calendar.current.date(byAdding: .day, value: 1, to: fireDate)!

        center.removePendingNotificationRequests(withIdentifiers: [closeoutRequestID])

        let content = UNMutableNotificationContent()
        content.title = "Daily closeout"
        content.body = "Want to close out today's reminders?"
        content.sound = .default
        content.categoryIdentifier = NotificationsManager.shared.closeoutCategoryIdentifier

        let triggerComps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: actualFireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)

        let req = UNNotificationRequest(identifier: closeoutRequestID, content: content, trigger: trigger)
        do {
            try await center.add(req)
        } catch {
            ErrorLogger.log(error, context: "Scheduling daily closeout notification")
        }
    }
}
