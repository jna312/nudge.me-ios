import SwiftData

@MainActor
enum NudgePersistence {
    // Keep the existing configuration and store location. Background widget actions
    // use this same app-owned container instead of opening a second store.
    static let shared: ModelContainer = {
        do {
            return try ModelContainer(for: ReminderItem.self,
                                      configurations: ModelConfiguration(cloudKitDatabase: .automatic))
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}
