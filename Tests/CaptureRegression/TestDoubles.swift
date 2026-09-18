import Foundation
import SwiftData

// No external side effects. The runner compiles the production parser and flow.
@MainActor final class AppSettings {
    var writingStyle = "sentence"
    var defaultEarlyAlertMinutes = 0
    var calendarSyncEnabled = false
}
@MainActor final class NotificationsManager {
    static let shared = NotificationsManager()
    var scheduledIDs: [UUID] = []
    func requestPermission() async {}
    func schedule(reminder: ReminderItem) async { scheduledIDs.append(reminder.id) }
}
@MainActor final class CalendarSync {
    static let shared = CalendarSync()
    func syncToCalendar(reminder: ReminderItem) async {}
}
@MainActor final class WidgetDataProvider {
    static let shared = WidgetDataProvider()
    func syncReminders(from context: ModelContext) {}
}
@MainActor final class MorningBriefingManager {
    static let shared = MorningBriefingManager()
    func scheduleIfNeeded(settings: AppSettings, modelContext: ModelContext) async {}
}
@MainActor final class DailyCloseoutManager {
    static let shared = DailyCloseoutManager()
    func scheduleIfNeeded(settings: AppSettings, modelContext: ModelContext) async {}
}
