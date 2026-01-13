import SwiftData
import SwiftUI

@main
struct NudgeApp: App {
    @StateObject private var settings = AppSettings()
    
    let modelContainer: ModelContainer
    
    init() {
        _ = NotificationsManager.shared
        
        // Configure SwiftData with CloudKit sync
        let schema = Schema([ReminderItem.self])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic // Syncs to user's private iCloud database
        )
        
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if !settings.didCompleteOnboarding {
                OnboardingView(settings: settings)
            } else {
                RootView(settings: settings)
            }
        }
        .modelContainer(modelContainer)
    }
}
