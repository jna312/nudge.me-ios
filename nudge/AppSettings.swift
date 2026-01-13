import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    @AppStorage("didCompleteOnboarding") var didCompleteOnboarding: Bool = false

    // Times stored as minutes-from-midnight
    @AppStorage("dailyCloseoutMinutes") var dailyCloseoutMinutes: Int = 21 * 60        // 9:00 PM

    @AppStorage("writingStyle") var writingStyle: String = "sentence" // sentence | title | caps
    
    // Wake word detection
    @AppStorage("wakeWordEnabled") var wakeWordEnabled: Bool = false
    
    // Calendar sync
    @AppStorage("calendarSyncEnabled") var calendarSyncEnabled: Bool = false
    
    // Calendar sync frequency in minutes (15, 30, 60)
    @AppStorage("calendarSyncFrequency") var calendarSyncFrequency: Int = 30
    
    // Security
    
    // Default early alert (minutes before due time, 0 = none)
    @AppStorage("defaultEarlyAlertMinutes") var defaultEarlyAlertMinutes: Int = 0
}
