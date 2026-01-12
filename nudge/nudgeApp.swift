import SwiftData
import SwiftUI

@main
struct NudgeApp: App {
    @StateObject private var settings = AppSettings()
    
    init() {
        // Initialize NotificationsManager early so delegate is set for foreground notifications
        _ = NotificationsManager.shared
    }

    var body: some Scene {
        WindowGroup {
            if settings.didCompleteOnboarding {
                RootView(settings: settings)
            } else {
                OnboardingView(settings: settings)
            }
        }
        .modelContainer(for: ReminderItem.self)
    }
}

