import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    @AppStorage("didCompleteOnboarding") var didCompleteOnboarding: Bool = false

    // Times stored as minutes-from-midnight
    @AppStorage("dailyCloseoutMinutes") var dailyCloseoutMinutes: Int = 21 * 60        // 9:00 PM
    @AppStorage("defaultDateOnlyMinutes") var defaultDateOnlyMinutes: Int = 18 * 60     // 6:00 PM

    @AppStorage("writingStyle") var writingStyle: String = "sentence" // sentence | title | caps
}

