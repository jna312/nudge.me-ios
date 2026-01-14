import Foundation
import SwiftData

@MainActor
enum ReminderActions {
    static func markDone(reminderID: UUID) async {
        guard let container = ErrorLogger.attempt("Creating model container") {
            try ModelContainer(for: ReminderItem.self)
        } else { return }
        
        let context = ModelContext(container)
        let d = FetchDescriptor<ReminderItem>(predicate: #Predicate { $0.id == reminderID })
        
        guard let item = ErrorLogger.attempt("Fetching reminder for markDone") {
            try context.fetch(d).first
        } else { return }

        item.status = .completed
        item.completedAt = .now
        context.saveWithLogging(context: "Marking reminder done")
    }

    static func snooze(reminderID: UUID, minutes: Int) async {
        guard let container = ErrorLogger.attempt("Creating model container") {
            try ModelContainer(for: ReminderItem.self)
        } else { return }
        
        let context = ModelContext(container)
        let d = FetchDescriptor<ReminderItem>(predicate: #Predicate { $0.id == reminderID })
        
        guard let item = ErrorLogger.attempt("Fetching reminder for snooze") {
            try context.fetch(d).first
        } else { return }
        
        guard item.status == .open else { return }

        let newDue = Date().addingTimeInterval(TimeInterval(minutes * 60))
        item.dueAt = newDue
        item.alertAt = newDue

        context.saveWithLogging(context: "Snoozing reminder")
        
        await NotificationsManager.shared.schedule(reminder: item)
    }

    static func markAllOpenDoneForToday() async {
        guard let container = ErrorLogger.attempt("Creating model container") {
            try ModelContainer(for: ReminderItem.self)
        } else { return }
        
        let context = ModelContext(container)

        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

        let desc = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { item in
                item.statusRaw == "open" &&
                item.createdAt >= start && item.createdAt < end
            }
        )

        let items = ErrorLogger.attempt("Fetching today's reminders") {
            try context.fetch(desc)
        } ?? []
        
        for item in items {
            item.status = .completed
            item.completedAt = .now
        }
        
        context.saveWithLogging(context: "Marking all open done for today")
    }
}
