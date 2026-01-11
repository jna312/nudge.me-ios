import SwiftData
import SwiftUI

@main
struct NudgeApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            if settings.didCompleteOnboarding {
                RootView(settings: settings)
            } else {
                OnboardingView(settings: settings)
            }
        }
    .modelContainer(for: ReminderItem.self) // ✅ REQUIRED
    }
}

