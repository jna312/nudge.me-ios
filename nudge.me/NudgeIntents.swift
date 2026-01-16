import AppIntents
import SwiftData
import SwiftUI

// MARK: - Add Reminder Intent

struct AddNudgeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Nudge"
    static var description = IntentDescription("Create a new reminder in Nudge")
    
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Reminder")
    var reminderTitle: String
    
    @Parameter(title: "Time")
    var dueDate: Date
    
    static var parameterSummary: some ParameterSummary {
        Summary("Remind me to \(\.$reminderTitle) at \(\.$dueDate)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        let container = try ModelContainer(for: ReminderItem.self, configurations: config)
        let context = ModelContext(container)
        
        let reminder = ReminderItem(
            title: reminderTitle,
            dueAt: dueDate,
            alertAt: dueDate
        )
        
        context.insert(reminder)
        try context.save()
        
        // Schedule notification
        await NotificationsManager.shared.schedule(reminder: reminder)
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        let timeStr = formatter.string(from: dueDate)
        
        return .result(dialog: IntentDialog(stringLiteral: "Got it! I'll remind you to \(reminderTitle) at \(timeStr)"))
    }
}

// MARK: - Date Option Enum

enum NudgeDateOption: String, AppEnum {
    case today
    case tomorrow
    case thisWeek
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Date"
    }
    
    static var caseDisplayRepresentations: [NudgeDateOption: DisplayRepresentation] {
        [
            .today: "Today",
            .tomorrow: "Tomorrow",
            .thisWeek: "This Week"
        ]
    }
    
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            let start = calendar.startOfDay(for: tomorrow)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .thisWeek:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 7, to: start)!
            return (start, end)
        }
    }
    
    var displayName: String {
        switch self {
        case .today: return "today"
        case .tomorrow: return "tomorrow"
        case .thisWeek: return "this week"
        }
    }
}

// MARK: - List Reminders Intent

struct ListNudgesForDateIntent: AppIntent {
    static var title: LocalizedStringResource = "List My Nudges"
    static var description = IntentDescription("Show your reminders for a specific day")
    
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "When")
    var dateOption: NudgeDateOption
    
    static var parameterSummary: some ParameterSummary {
        Summary("List my nudges for \(\.$dateOption)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        let container = try ModelContainer(for: ReminderItem.self, configurations: config)
        let context = ModelContext(container)
        
        let range = dateOption.dateRange
        
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" },
            sortBy: [SortDescriptor(\.dueAt)]
        )
        
        let allReminders = try context.fetch(descriptor)
        
        // Filter to reminders in the date range
        let reminders = allReminders.filter { reminder in
            guard let dueAt = reminder.dueAt else { return false }
            return dueAt >= range.start && dueAt < range.end
        }
        
        let dayStr = dateOption.displayName
        
        if reminders.isEmpty {
            return .result(dialog: IntentDialog(stringLiteral: "You have no nudges for \(dayStr)."))
        }
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        if reminders.count == 1 {
            let reminder = reminders[0]
            let timeStr = reminder.dueAt.map { timeFormatter.string(from: $0) } ?? ""
            return .result(dialog: IntentDialog(stringLiteral: "You have 1 nudge for \(dayStr): \(reminder.title) at \(timeStr)."))
        }
        
        var list = "You have \(reminders.count) nudges for \(dayStr): "
        for (index, reminder) in reminders.enumerated() {
            let timeStr = reminder.dueAt.map { timeFormatter.string(from: $0) } ?? ""
            if index == reminders.count - 1 {
                list += "and \(reminder.title) at \(timeStr)."
            } else {
                list += "\(reminder.title) at \(timeStr), "
            }
        }
        
        return .result(dialog: IntentDialog(stringLiteral: list))
    }
}

// MARK: - Complete Reminder Intent

struct CompleteNudgeIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete a Nudge"
    static var description = IntentDescription("Mark a reminder as done")
    
    @Parameter(title: "Reminder")
    var reminderTitle: String
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        let container = try ModelContainer(for: ReminderItem.self, configurations: config)
        let context = ModelContext(container)
        
        let searchTerm = reminderTitle.lowercased()
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" }
        )
        
        let reminders = try context.fetch(descriptor)
        
        if let match = reminders.first(where: { $0.title.lowercased().contains(searchTerm) }) {
            match.status = .completed
            match.completedAt = .now
            try context.save()
            
            // Cancel notification
            let notificationID = "\(match.id.uuidString)-alert"
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
            
            return .result(dialog: IntentDialog(stringLiteral: "Done! Marked \(match.title) as complete."))
        }
        
        return .result(dialog: IntentDialog(stringLiteral: "I couldn't find a reminder matching \(reminderTitle)"))
    }
}

// MARK: - App Shortcuts Provider

struct NudgeShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddNudgeIntent(),
            phrases: [
                "\(.applicationName) me"
            ],
            shortTitle: "Nudge Me",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ListNudgesForDateIntent(),
            phrases: [
                "List my \(.applicationName)s",
                "Show my \(.applicationName)s",
                "What are my \(.applicationName)s"
            ],
            shortTitle: "List Nudges",
            systemImageName: "list.bullet"
        )
    }
}
