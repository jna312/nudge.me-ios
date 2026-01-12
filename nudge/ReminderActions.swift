import Foundation
import SwiftData

@MainActor
enum ReminderActions {
    static func markDone(reminderID: UUID) async {
        guard let container = try? ModelContainer(for: ReminderItem.self) else { return }
        let context = ModelContext(container)

        let d = FetchDescriptor<ReminderItem>(predicate: #Predicate { $0.id == reminderID })
        guard let item = try? context.fetch(d).first else { return }

        item.status = .completed
        item.completedAt = .now
        try? context.save()
    }

    static func snooze(reminderID: UUID, minutes: Int) async {
        guard let container = try? ModelContainer(for: ReminderItem.self) else { return }
        let context = ModelContext(container)

        let d = FetchDescriptor<ReminderItem>(predicate: #Predicate { $0.id == reminderID })
        guard let item = try? context.fetch(d).first else { return }
        guard item.status == .open else { return }

        let newDue = Date().addingTimeInterval(TimeInterval(minutes * 60))
        item.dueAt = newDue
        item.alertAt = newDue

        try? context.save()
        
        await NotificationsManager.shared.schedule(reminder: item)
    }

    static func markAllOpenDoneForToday() async {
        guard let container = try? ModelContainer(for: ReminderItem.self) else { return }
        let context = ModelContext(container)

        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!

        let desc = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { item in
                item.statusRaw == "open" &&
                item.createdAt >= start && item.createdAt < end
            }
        )

        let items = (try? context.fetch(desc)) ?? []
        for item in items {
            item.status = .completed
            item.completedAt = .now
        }
        try? context.save()
    }
}
