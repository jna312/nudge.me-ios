import SwiftData
import SwiftUI

// MARK: - App Delegate for Orientation Lock
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}

@main
struct NudgeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings()
    
    let modelContainer: ModelContainer
    
    init() {
        _ = NotificationsManager.shared
        
        // Configure SwiftData with CloudKit sync
        let schema = Schema([ReminderItem.self])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none // Temporarily disabled - re-enable with .automatic for iCloud sync
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
