import Foundation
import SwiftData

@MainActor final class AppSettings { var calendarSyncEnabled = false }
@MainActor final class NotificationsManager {
    static let shared = NotificationsManager()
    var removed: [UUID] = []
    func removeNotifications(for reminder: ReminderItem) { removed.append(reminder.id) }
}
@MainActor final class WidgetDataProvider {
    static let shared = WidgetDataProvider()
    var published: [UUID] = []
    func syncReminders(from context: ModelContext) {
        published = (try? context.fetch(FetchDescriptor<ReminderItem>(predicate: #Predicate { $0.statusRaw == "open" })).map(\.id)) ?? []
    }
}
@MainActor final class CalendarSync {
    static let shared = CalendarSync()
    func removeFromCalendar(reminder: ReminderItem) async {}
}
@MainActor final class MorningBriefingManager {
    static let shared = MorningBriefingManager()
    func scheduleIfNeeded(settings: AppSettings, modelContext: ModelContext) async {}
}
