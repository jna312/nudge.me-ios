import SwiftData
import SwiftUI

@main
struct NudgeApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var biometricAuth = BiometricAuth.shared
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        _ = NotificationsManager.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !settings.didCompleteOnboarding {
                    OnboardingView(settings: settings)
                } else if settings.biometricLockEnabled && !biometricAuth.isUnlocked {
                    LockScreenView()
                } else {
                    RootView(settings: settings)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background && settings.biometricLockEnabled {
                    biometricAuth.lock()
                }
            }
        }
        .modelContainer(for: ReminderItem.self)
    }
}
