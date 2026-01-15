import Foundation
import SwiftData
import WidgetKit

/// Syncs reminder data to the widget via App Groups
final class WidgetDataProvider {
    static let shared = WidgetDataProvider()
    
    private let appGroupID = "group.com.m2.nudge"
    private let remindersKey = "widgetReminders"
    private let completedKey = "completedFromWidget"
    
    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }
    
    private init() {}
    
    /// Sync all active reminders to the widget
    func syncReminders(from context: ModelContext) {
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.completedAt == nil },
            sortBy: [SortDescriptor(\.dueAt)]
        )
        
        guard let reminders = try? context.fetch(descriptor) else { return }
        
        let sharedReminders = reminders.compactMap { reminder -> SharedWidgetReminder? in
            guard let dueAt = reminder.dueAt else { return nil }
            return SharedWidgetReminder(
                id: reminder.id,
                title: reminder.title,
                dueAt: dueAt,
                isCompleted: (reminder.completedAt != nil)
            )
        }
        
        if let encoded = try? JSONEncoder().encode(sharedReminders) {
            sharedDefaults?.set(encoded, forKey: remindersKey)
        }
        
        // Trigger widget refresh
        WidgetCenter.shared.reloadAllTimelines()
    }
    
    /// Check if any reminders were completed from the widget
    func checkForWidgetCompletions(in context: ModelContext) {
        guard let completedId = sharedDefaults?.string(forKey: completedKey),
              let uuid = UUID(uuidString: completedId) else { return }
        
        // Clear the flag
        sharedDefaults?.removeObject(forKey: completedKey)
        
        // Find and complete the reminder in the main app
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.id == uuid }
        )
        
        if let reminders = try? context.fetch(descriptor),
           let reminder = reminders.first {
            reminder.completedAt = Date()
            try? context.save()
            
            // Resync to widget
            syncReminders(from: context)
        }
    }
}

/// Shared struct for encoding reminders (must match widget's SharedReminder)
struct SharedWidgetReminder: Codable {
    let id: UUID
    let title: String
    let dueAt: Date
    let isCompleted: Bool
}

