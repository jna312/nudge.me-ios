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
        
        // Test: Local only (no CloudKit) to verify SwiftData works
        do {
            let config = ModelConfiguration(cloudKitDatabase: .none)
            modelContainer = try ModelContainer(for: ReminderItem.self, configurations: config)
            print("✓ SwiftData initialized successfully (local mode)")
        } catch {
            print("SwiftData error: \(error)")
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
