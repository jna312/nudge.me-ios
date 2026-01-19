import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    // MARK: - Keys
    private enum Keys {
        static let didCompleteOnboarding = "didCompleteOnboarding"
        static let dailyCloseoutMinutes = "dailyCloseoutMinutes"
        static let morningBriefingEnabled = "morningBriefingEnabled"
        static let morningBriefingMinutes = "morningBriefingMinutes"
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
    
    @Published var morningBriefingEnabled: Bool = false {
        didSet { UserDefaults.standard.set(morningBriefingEnabled, forKey: Keys.morningBriefingEnabled) }
    }
    
    @Published var morningBriefingMinutes: Int = 8 * 60 { // 8:00 AM
        didSet { UserDefaults.standard.set(morningBriefingMinutes, forKey: Keys.morningBriefingMinutes) }
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
        if userDefaults.object(forKey: Keys.morningBriefingEnabled) != nil {
            self.morningBriefingEnabled = userDefaults.bool(forKey: Keys.morningBriefingEnabled)
        }
        if userDefaults.object(forKey: Keys.morningBriefingMinutes) != nil {
            self.morningBriefingMinutes = userDefaults.integer(forKey: Keys.morningBriefingMinutes)
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

