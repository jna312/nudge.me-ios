import Foundation
import SwiftData
import EventKit

@MainActor
enum WidgetReminderActions {
    static func complete(id: UUID, context: ModelContext) async throws {
        let descriptor = FetchDescriptor<ReminderItem>(predicate: #Predicate { $0.id == id })
        guard let reminder = try context.fetch(descriptor).first else {
            // The reminder may have been deleted since the timeline was rendered.
            WidgetDataProvider.shared.syncReminders(from: context)
            return
        }
        if reminder.status != .completed || reminder.completedAt == nil {
            reminder.status = .completed
            reminder.completedAt = .now
            do { try context.save() } catch { context.rollback(); throw error }
        }
        NotificationsManager.shared.removeNotifications(for: reminder)
        WidgetDataProvider.shared.syncReminders(from: context)

        // An action in the background must never prompt for Calendar permission.
        let settings = AppSettings()
        let permission = EKEventStore.authorizationStatus(for: .event)
        if settings.calendarSyncEnabled && permission == .fullAccess {
            await CalendarSync.shared.removeFromCalendar(reminder: reminder)
        }
        await MorningBriefingManager.shared.scheduleIfNeeded(settings: settings, modelContext: context)
    }
}
