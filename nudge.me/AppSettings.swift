import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    // MARK: - Keys
    private enum Keys {
        static let didCompleteOnboarding = "didCompleteOnboarding"
        static let dailyCloseoutMinutes = "dailyCloseoutMinutes"
        static let writingStyle = "writingStyle"
        static let calendarSyncEnabled = "calendarSyncEnabled"
        static let defaultEarlyAlertMinutes = "defaultEarlyAlertMinutes"
    }

    // MARK: - Published settings
    @Published var didCompleteOnboarding: Bool = false {
        didSet { UserDefaults.standard.set(didCompleteOnboarding, forKey: Keys.didCompleteOnboarding) }
    }

    // Times stored as minutes-from-midnight
    @Published var dailyCloseoutMinutes: Int = 21 * 60 { // 9:00 PM
        didSet { UserDefaults.standard.set(dailyCloseoutMinutes, forKey: Keys.dailyCloseoutMinutes) }
    }

    // sentence | title | caps
    @Published var writingStyle: String = "sentence" {
        didSet { UserDefaults.standard.set(writingStyle, forKey: Keys.writingStyle) }
    }

    // Calendar sync
    @Published var calendarSyncEnabled: Bool = false {
        didSet { UserDefaults.standard.set(calendarSyncEnabled, forKey: Keys.calendarSyncEnabled) }
    }

    // Default early alert (minutes before due time, 0 = none)
    @Published var defaultEarlyAlertMinutes: Int = 0 {
        didSet { UserDefaults.standard.set(defaultEarlyAlertMinutes, forKey: Keys.defaultEarlyAlertMinutes) }
    }

    // MARK: - Init
    init(userDefaults: UserDefaults = .standard) {
        if userDefaults.object(forKey: Keys.didCompleteOnboarding) != nil {
            self.didCompleteOnboarding = userDefaults.bool(forKey: Keys.didCompleteOnboarding)
        }
        if userDefaults.object(forKey: Keys.dailyCloseoutMinutes) != nil {
            self.dailyCloseoutMinutes = userDefaults.integer(forKey: Keys.dailyCloseoutMinutes)
        }
        if let style = userDefaults.string(forKey: Keys.writingStyle) {
            self.writingStyle = style
        }
        if userDefaults.object(forKey: Keys.calendarSyncEnabled) != nil {
            self.calendarSyncEnabled = userDefaults.bool(forKey: Keys.calendarSyncEnabled)
        }
        if userDefaults.object(forKey: Keys.defaultEarlyAlertMinutes) != nil {
            self.defaultEarlyAlertMinutes = userDefaults.integer(forKey: Keys.defaultEarlyAlertMinutes)
        }
    }
}

