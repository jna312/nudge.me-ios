import AppIntents
import SwiftData
import SwiftUI

// MARK: - Add Reminder Intent

struct AddNudgeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a Nudge"
    static var description = IntentDescription("Create a new reminder in Nudge")
    
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "What to remember")
    var reminderTitle: String
    
    @Parameter(title: "When", description: "When should I remind you?")
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
        
        return .result(dialog: "Got it! I'll remind you to \(reminderTitle) at \(timeStr)")
    }
}

// MARK: - List Reminders Intent

struct ListNudgesIntent: AppIntent {
    static var title: LocalizedStringResource = "List My Nudges"
    static var description = IntentDescription("Show your upcoming reminders")
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        let container = try ModelContainer(for: ReminderItem.self, configurations: config)
        let context = ModelContext(container)
        
        var descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" },
            sortBy: [SortDescriptor(\.dueAt)]
        )
        descriptor.fetchLimit = 5
        
        let reminders = try context.fetch(descriptor)
        
        if reminders.isEmpty {
            return .result(dialog: "You have no upcoming reminders. Enjoy your free time!")
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        
        var list = "Here are your upcoming nudges:\n"
        for reminder in reminders {
            let timeStr = reminder.dueAt.map { formatter.string(from: $0) } ?? "No time set"
            list += "• \(reminder.title) - \(timeStr)\n"
        }
        
        return .result(dialog: "\(list)")
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
            
            return .result(dialog: "Done! Marked \"\(match.title)\" as complete.")
        }
        
        return .result(dialog: "I couldn't find a reminder matching \"\(reminderTitle)\"")
    }
}

// MARK: - Quick Add Intent (in 1 hour)

struct QuickNudgeIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Nudge"
    static var description = IntentDescription("Add a reminder for 1 hour from now")
    
    @Parameter(title: "What to remember")
    var reminderTitle: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Remind me to \(\.$reminderTitle) in 1 hour")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let config = ModelConfiguration(cloudKitDatabase: .automatic)
        let container = try ModelContainer(for: ReminderItem.self, configurations: config)
        let context = ModelContext(container)
        
        let dueDate = Date().addingTimeInterval(3600) // 1 hour
        
        let reminder = ReminderItem(
            title: reminderTitle,
            dueAt: dueDate,
            alertAt: dueDate
        )
        
        context.insert(reminder)
        try context.save()
        
        await NotificationsManager.shared.schedule(reminder: reminder)
        
        return .result(dialog: "Got it! I'll remind you to \(reminderTitle) in 1 hour.")
    }
}

// MARK: - App Shortcuts Provider

struct NudgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddNudgeIntent(),
            phrases: [
                "Add a nudge in \(.applicationName)",
                "Create a reminder in \(.applicationName)",
                "Remind me in \(.applicationName)",
                "New nudge in \(.applicationName)"
            ],
            shortTitle: "Add Nudge",
            systemImageName: "plus.circle"
        )
        
        AppShortcut(
            intent: ListNudgesIntent(),
            phrases: [
                "Show my nudges in \(.applicationName)",
                "List reminders in \(.applicationName)",
                "What are my nudges in \(.applicationName)"
            ],
            shortTitle: "List Nudges",
            systemImageName: "list.bullet"
        )
        
        AppShortcut(
            intent: QuickNudgeIntent(),
            phrases: [
                "Quick nudge in \(.applicationName)",
                "Remind me in an hour in \(.applicationName)"
            ],
            shortTitle: "Quick Nudge",
            systemImageName: "clock"
        )
    }
}
