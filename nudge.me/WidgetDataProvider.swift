import Foundation
import SwiftData
import WidgetKit

/// Syncs reminder data to the widget via App Groups
@MainActor
final class WidgetDataProvider {
    static let shared = WidgetDataProvider()
    
    private let completedKey = "completedFromWidget"
    
    private var sharedDefaults: UserDefaults? {
        WidgetSharedStore.defaults
    }
    
    private init() {}
    
    /// Sync all active reminders to the widget
    func syncReminders(from context: ModelContext) {
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" },
            sortBy: [SortDescriptor(\.dueAt)]
        )
        
        guard let reminders = try? context.fetch(descriptor) else { return }
        
        let sharedReminders = reminders.map { reminder -> SharedWidgetReminder in
            return SharedWidgetReminder(
                id: reminder.id,
                title: reminder.title,
                dueAt: reminder.dueAt,
                isCompleted: reminder.status != .open
            )
        }
        
        if let encoded = try? JSONEncoder().encode(sharedReminders) {
            sharedDefaults?.set(encoded, forKey: WidgetSharedStore.remindersKey)
            sharedDefaults?.removeObject(forKey: WidgetSharedStore.completionErrorKey)
        }
        
        // Trigger widget refresh
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedStore.kind)
    }
    
    /// Check if any reminders were completed from the widget
    func checkForWidgetCompletions(in context: ModelContext) async {
        guard let completedId = sharedDefaults?.string(forKey: completedKey),
              let uuid = UUID(uuidString: completedId) else { return }
        
        // Migrate any legacy pending action without dropping it before a save.
        do {
            try await WidgetReminderActions.complete(id: uuid, context: context)
            sharedDefaults?.removeObject(forKey: completedKey)
        } catch {
            ErrorLogger.log(error, context: "Applying legacy widget completion")
        }
    }
}

