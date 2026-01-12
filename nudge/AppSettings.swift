import SwiftUI
import Combine

final class AppSettings: ObservableObject {
    @AppStorage("didCompleteOnboarding") var didCompleteOnboarding: Bool = false

    // Times stored as minutes-from-midnight
    @AppStorage("dailyCloseoutMinutes") var dailyCloseoutMinutes: Int = 21 * 60        // 9:00 PM
    @AppStorage("defaultDateOnlyMinutes") var defaultDateOnlyMinutes: Int = 18 * 60     // 6:00 PM

    @AppStorage("writingStyle") var writingStyle: String = "sentence" // sentence | title | caps
    
    @AppStorage("notificationSound") var notificationSound: String = "default"
}

enum NotificationSoundOption: String, CaseIterable, Identifiable {
    // Standard alerts
    case `default` = "default"
    case triTone = "tri-tone"
    case alert = "alert"
    
    // Classic tones
    case chime = "chime"
    case glass = "glass"
    case horn = "horn"
    case bell = "bell"
    case electronic = "electronic"
    
    // Modern tones
    case anticipate = "anticipate"
    case bloom = "bloom"
    case calypso = "calypso"
    case chooChoo = "choo-choo"
    case descent = "descent"
    case ding = "ding"
    case fanfare = "fanfare"
    case ladder = "ladder"
    case minuet = "minuet"
    case newsFlash = "news-flash"
    case noir = "noir"
    case sherwood = "sherwood"
    case spell = "spell"
    case suspense = "suspense"
    case telegraph = "telegraph"
    case tiptoes = "tiptoes"
    case typewriters = "typewriters"
    case update = "update"
    
    // System sounds
    case tweet = "tweet"
    case popcorn = "popcorn"
    case shake = "shake"
    case jingle = "jingle"
    
    case silent = "silent"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .default: return "Default"
        case .triTone: return "Tri-Tone"
        case .alert: return "Alert"
        case .chime: return "Chime"
        case .glass: return "Glass"
        case .horn: return "Horn"
        case .bell: return "Bell"
        case .electronic: return "Electronic"
        case .anticipate: return "Anticipate"
        case .bloom: return "Bloom"
        case .calypso: return "Calypso"
        case .chooChoo: return "Choo Choo"
        case .descent: return "Descent"
        case .ding: return "Ding"
        case .fanfare: return "Fanfare"
        case .ladder: return "Ladder"
        case .minuet: return "Minuet"
        case .newsFlash: return "News Flash"
        case .noir: return "Noir"
        case .sherwood: return "Sherwood Forest"
        case .spell: return "Spell"
        case .suspense: return "Suspense"
        case .telegraph: return "Telegraph"
        case .tiptoes: return "Tiptoes"
        case .typewriters: return "Typewriters"
        case .update: return "Update"
        case .tweet: return "Tweet"
        case .popcorn: return "Popcorn"
        case .shake: return "Shake"
        case .jingle: return "Jingle"
        case .silent: return "Silent"
        }
    }
    
    /// System Sound ID for AudioServices playback
    var systemSoundID: UInt32 {
        switch self {
        case .default: return 1007
        case .triTone: return 1016
        case .alert: return 1005
        case .chime: return 1008
        case .glass: return 1009
        case .horn: return 1010
        case .bell: return 1011
        case .electronic: return 1012
        case .anticipate: return 1013
        case .bloom: return 1014
        case .calypso: return 1015
        case .chooChoo: return 1023
        case .descent: return 1024
        case .ding: return 1025
        case .fanfare: return 1020
        case .ladder: return 1021
        case .minuet: return 1022
        case .newsFlash: return 1028
        case .noir: return 1029
        case .sherwood: return 1030
        case .spell: return 1031
        case .suspense: return 1032
        case .telegraph: return 1033
        case .tiptoes: return 1034
        case .typewriters: return 1035
        case .update: return 1036
        case .tweet: return 1016
        case .popcorn: return 1026
        case .shake: return 1027
        case .jingle: return 1019
        case .silent: return 0
        }
    }
    
    /// Duration in seconds for each sound (approximate)
    var duration: Double {
        switch self {
        case .default: return 1.0
        case .triTone: return 1.2
        case .alert: return 0.8
        case .chime: return 1.5
        case .glass: return 0.8
        case .horn: return 1.0
        case .bell: return 2.0
        case .electronic: return 1.5
        case .anticipate: return 2.0
        case .bloom: return 2.5
        case .calypso: return 1.5
        case .chooChoo: return 2.0
        case .descent: return 1.5
        case .ding: return 0.5
        case .fanfare: return 3.0
        case .ladder: return 2.0
        case .minuet: return 3.0
        case .newsFlash: return 2.0
        case .noir: return 2.5
        case .sherwood: return 3.0
        case .spell: return 2.0
        case .suspense: return 2.5
        case .telegraph: return 2.0
        case .tiptoes: return 2.0
        case .typewriters: return 2.5
        case .update: return 1.5
        case .tweet: return 1.2
        case .popcorn: return 2.0
        case .shake: return 1.0
        case .jingle: return 2.5
        case .silent: return 0.0
        }
    }
    
    /// Get option from raw string value
    static func from(_ rawValue: String) -> NotificationSoundOption {
        return NotificationSoundOption(rawValue: rawValue) ?? .default
    }
}

extension NotificationSoundOption {
    /// Filename for bundled notification sound (add .caf files to bundle)
    /// When locked, iOS can only play sounds bundled with the app
    var notificationSoundFile: String? {
        switch self {
        case .silent: return nil
        case .default: return nil // Uses system default
        case .triTone: return "tri-tone.caf"
        case .alert: return "alert.caf"
        case .chime: return "chime.caf"
        case .glass: return "glass.caf"
        case .horn: return "horn.caf"
        case .bell: return "bell.caf"
        case .electronic: return "electronic.caf"
        case .anticipate: return "anticipate.caf"
        case .bloom: return "bloom.caf"
        case .calypso: return "calypso.caf"
        case .chooChoo: return "choo-choo.caf"
        case .descent: return "descent.caf"
        case .ding: return "ding.caf"
        case .fanfare: return "fanfare.caf"
        case .ladder: return "ladder.caf"
        case .minuet: return "minuet.caf"
        case .newsFlash: return "news-flash.caf"
        case .noir: return "noir.caf"
        case .sherwood: return "sherwood.caf"
        case .spell: return "spell.caf"
        case .suspense: return "suspense.caf"
        case .telegraph: return "telegraph.caf"
        case .tiptoes: return "tiptoes.caf"
        case .typewriters: return "typewriters.caf"
        case .update: return "update.caf"
        case .tweet: return "tweet.caf"
        case .popcorn: return "popcorn.caf"
        case .shake: return "shake.caf"
        case .jingle: return "jingle.caf"
        }
    }
}
