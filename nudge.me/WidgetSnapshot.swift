import Foundation

// Compiled into both targets so the app and widget use the same payload and rules.
struct SharedWidgetReminder: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let dueAt: Date?
    let isCompleted: Bool
}

struct WidgetSnapshot: Sendable {
    let reminders: [SharedWidgetReminder]
    let todayCount: Int
    let overdueCount: Int
    let isAvailable: Bool
    let completionFailed: Bool
    var openCount: Int { reminders.count }

    init(reminders: [SharedWidgetReminder], at date: Date, calendar: Calendar = .current,
         isAvailable: Bool = true, completionFailed: Bool = false) {
        self.reminders = reminders.filter { !$0.isCompleted }.sorted {
            let left = $0.dueAt ?? .distantFuture
            let right = $1.dueAt ?? .distantFuture
            if left != right { return left < right }
            return $0.id.uuidString < $1.id.uuidString
        }
        todayCount = self.reminders.filter { reminder in
            reminder.dueAt.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        }.count
        overdueCount = self.reminders.filter { ($0.dueAt ?? .distantFuture) < date }.count
        self.isAvailable = isAvailable
        self.completionFailed = completionFailed
    }

    // Entries change at due times and local midnight, including 23/25-hour DST days.
    static func timelineDates(for reminders: [SharedWidgetReminder], from now: Date,
                              calendar: Calendar = .current) -> [Date] {
        let horizon = now.addingTimeInterval(6 * 60 * 60)
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? horizon
        let dueDates = reminders.filter { !$0.isCompleted }.compactMap(\.dueAt)
            .map { $0.addingTimeInterval(1) }
            .filter { $0 > now && $0 <= horizon }
        return [now] + Array(Set(dueDates + (midnight <= horizon ? [midnight] : []))).sorted().prefix(48)
    }
}

enum WidgetSharedStore {
    static let appGroupID = "group.com.m2.nudge"
    static let kind = "NudgeWidget"
    static let remindersKey = "widgetReminders"
    static let completionErrorKey = "widgetCompletionFailed"
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static func read(at date: Date, defaults: UserDefaults? = Self.defaults) -> WidgetSnapshot {
        guard let defaults, let data = defaults.data(forKey: remindersKey),
              let reminders = try? JSONDecoder().decode([SharedWidgetReminder].self, from: data) else {
            return WidgetSnapshot(reminders: [], at: date, isAvailable: false)
        }
        return WidgetSnapshot(reminders: reminders, at: date,
                              completionFailed: defaults.bool(forKey: completionErrorKey))
    }
}
