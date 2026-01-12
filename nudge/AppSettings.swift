import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    @AppStorage("didCompleteOnboarding") var didCompleteOnboarding: Bool = false

    // Times stored as minutes-from-midnight
    @AppStorage("dailyCloseoutMinutes") var dailyCloseoutMinutes: Int = 21 * 60        // 9:00 PM
    @AppStorage("defaultDateOnlyMinutes") var defaultDateOnlyMinutes: Int = 18 * 60     // 6:00 PM

    @AppStorage("writingStyle") var writingStyle: String = "sentence" // sentence | title | caps
    
    @AppStorage("notificationSound") var notificationSound: String = "default"
    @AppStorage("notificationVolume") var notificationVolume: Double = 0.8
}

enum NotificationSoundOption: String, CaseIterable, Identifiable {
    case `default` = "default"
    case triTone = "tri-tone"
    case chime = "chime"
    case pulse = "pulse"
    case synth = "synth"
    case silent = "silent"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .triTone: return "Tri-Tone"
        case .chime: return "Chime"
        case .pulse: return "Pulse"
        case .synth: return "Synth"
        case .silent: return "Silent"
        }
    }
}

