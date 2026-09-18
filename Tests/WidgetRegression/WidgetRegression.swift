import Foundation
import SwiftData

@main struct WidgetRegression {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            precondition(condition(), description)
            checks += 1
            print("PASS \(description)")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        func date(_ value: String) -> Date {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: value)!
        }
        let now = date("2026-09-18T16:00:00Z")
        let old = SharedWidgetReminder(id: UUID(), title: "Overdue", dueAt: now.addingTimeInterval(-86400), isCompleted: false)
        let later = SharedWidgetReminder(id: UUID(), title: "Tomorrow", dueAt: now.addingTimeInterval(86400), isCompleted: false)
        let undated = SharedWidgetReminder(id: UUID(), title: "No date", dueAt: nil, isCompleted: false)
        let done = SharedWidgetReminder(id: UUID(), title: "Completed", dueAt: now, isCompleted: true)
        let today = (1...8).map { SharedWidgetReminder(id: UUID(), title: "Task \($0)", dueAt: now.addingTimeInterval(Double($0) * 600), isCompleted: false) }
        let snapshot = WidgetSnapshot(reminders: [later, done, undated, old] + today.reversed(), at: now, calendar: calendar)
        check(snapshot.openCount == 11, "count includes every open reminder, beyond five")
        check(snapshot.todayCount == 8, "today count is independent of visible row limit")
        check(snapshot.overdueCount == 1, "overdue count includes previous days")
        check(snapshot.reminders.first?.id == old.id, "overdue reminders stay visible first")
        check(snapshot.reminders.last?.id == undated.id, "undated reminders stay available")
        check(snapshot.reminders.contains { $0.id == later.id }, "tomorrow is visible when today's tasks are done")
        check(!snapshot.reminders.contains { $0.id == done.id }, "completed reminders are excluded")
        check(snapshot.reminders[1].id == today[0].id, "upcoming reminders sort by due time")

        let spring = date("2026-03-08T16:00:00Z")
        let nextDay = SharedWidgetReminder(id: UUID(), title: "After spring DST day", dueAt: date("2026-03-09T04:15:00Z"), isCompleted: false)
        check(WidgetSnapshot(reminders: [nextDay], at: spring, calendar: calendar).todayCount == 0, "23-hour day does not include tomorrow")
        let fall = date("2026-11-01T17:00:00Z")
        let late = SharedWidgetReminder(id: UUID(), title: "Late on fall DST day", dueAt: date("2026-11-02T04:30:00Z"), isCompleted: false)
        check(WidgetSnapshot(reminders: [late], at: fall, calendar: calendar).todayCount == 1, "25-hour day includes its final hour")
        let beforeMidnight = date("2026-11-02T03:30:00Z")
        let dates = WidgetSnapshot.timelineDates(for: [late], from: beforeMidnight, calendar: calendar)
        check(dates.contains(date("2026-11-02T05:00:00Z")), "timeline changes at local midnight")
        check(dates.contains(late.dueAt!.addingTimeInterval(1)), "timeline changes when a reminder becomes overdue")
        check(dates.first == beforeMidnight, "timeline begins with current state")
        check(WidgetSnapshot(reminders: [late], at: late.dueAt!.addingTimeInterval(1), calendar: calendar).overdueCount == 1, "future timeline entry updates overdue state")
        let dense = (1...100).map { SharedWidgetReminder(id: UUID(), title: "Dense", dueAt: now.addingTimeInterval(Double($0)), isCompleted: false) }
        check(WidgetSnapshot.timelineDates(for: dense, from: now).count <= 49, "timeline size stays bounded")

        let suite = "nudge-widget-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(!WidgetSharedStore.read(at: now, defaults: defaults).isAvailable, "missing snapshot is not reported as all done")
        defaults.set(Data("broken".utf8), forKey: WidgetSharedStore.remindersKey)
        check(!WidgetSharedStore.read(at: now, defaults: defaults).isAvailable, "corrupt snapshot is not reported as all done")
        defaults.set(try JSONEncoder().encode([SharedWidgetReminder]()), forKey: WidgetSharedStore.remindersKey)
        check(WidgetSharedStore.read(at: now, defaults: defaults).isAvailable, "known empty snapshot is available")
        let legacy = "[{\"id\":\"\(old.id.uuidString)\",\"title\":\"Legacy\",\"dueAt\":12345,\"isCompleted\":false}]"
        defaults.set(Data(legacy.utf8), forKey: WidgetSharedStore.remindersKey)
        check(WidgetSharedStore.read(at: now, defaults: defaults).openCount == 1, "existing widget payload remains readable")
        defaults.set(true, forKey: WidgetSharedStore.completionErrorKey)
        check(WidgetSharedStore.read(at: now, defaults: defaults).completionFailed, "completion failure can be shown without hiding a task")

        let container = try ModelContainer(for: ReminderItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let first = ReminderItem(title: "Same title", dueAt: now, alertAt: now, earlyAlertMinutes: 15)
        let second = ReminderItem(title: "Same title", dueAt: now)
        context.insert(first); context.insert(second); try context.save()
        try await WidgetReminderActions.complete(id: first.id, context: context)
        check(first.status == .completed && first.completedAt != nil, "completion persists both status fields")
        check(second.status == .open, "completion targets ID, never a matching title")
        check(NotificationsManager.shared.removed == [first.id], "completion invokes full notification cleanup for the right reminder")
        check(WidgetDataProvider.shared.published == [second.id], "snapshot is refreshed after saved completion")
        let completionDate = first.completedAt
        try await WidgetReminderActions.complete(id: first.id, context: context)
        check(first.completedAt == completionDate, "repeated completion is idempotent")
        try await WidgetReminderActions.complete(id: UUID(), context: context)
        check(second.status == .open, "stale deleted reminder action leaves other reminders alone")
        let persisted = try ModelContext(container).fetch(FetchDescriptor<ReminderItem>())
        check(persisted.first { $0.id == first.id }?.status == .completed, "a fresh context reads persisted completion")
        print("\(checks) widget regression checks passed")
    }
}
