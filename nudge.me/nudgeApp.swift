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
        
        // CloudKit sync enabled
        do {
            let config = ModelConfiguration(cloudKitDatabase: .automatic)
            modelContainer = try ModelContainer(for: ReminderItem.self, configurations: config)
            print("✓ SwiftData initialized successfully with CloudKit")
        } catch {
            print("SwiftData/CloudKit error: \(error)")
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
