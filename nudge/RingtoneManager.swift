import Foundation
import Combine
import AVFoundation
import UserNotifications
import AudioToolbox

/// Manages ringtone selection and playback for reminders
final class RingtoneManager: ObservableObject {
    static let shared = RingtoneManager()
    
    /// Ringtone categories for organized display
    enum RingtoneCategory: String, CaseIterable {
        case system = "System"
        case alertTones = "Alert Tones"
        case classic = "Classic"
        case appSounds = "App Sounds"
    }
    
    /// Available ringtones - all with bundled .caf files for lock screen support
    struct Ringtone: Identifiable, Equatable {
        let id: String
        let displayName: String
        let category: RingtoneCategory
        let systemSoundID: SystemSoundID?
        let cafFileName: String?
        
        var rawValue: String { id }
        
        /// Returns the notification sound for this ringtone
        var notificationSound: UNNotificationSound {
            // If we have a bundled .caf file, use it
            if let cafName = cafFileName,
               Bundle.main.url(forResource: cafName.replacingOccurrences(of: ".caf", with: ""), withExtension: "caf") != nil {
                return UNNotificationSound(named: UNNotificationSoundName(cafName))
            }
            // Otherwise use system default
            return .default
        }
    }
    
    // MARK: - All Available Ringtones (all with bundled .caf files)
    
    static let allRingtones: [Ringtone] = [
        // System
        Ringtone(id: "default", displayName: "Default (System)", category: .system, systemSoundID: nil, cafFileName: nil),
        
        // Alert Tones (iOS-style sounds) - all with bundled .caf files
        Ringtone(id: "tritone", displayName: "Tri-tone", category: .alertTones, systemSoundID: 1007, cafFileName: "tritone.caf"),
        Ringtone(id: "aurora", displayName: "Aurora", category: .alertTones, systemSoundID: 1320, cafFileName: "aurora.caf"),
        Ringtone(id: "bamboo", displayName: "Bamboo", category: .alertTones, systemSoundID: 1321, cafFileName: "bamboo.caf"),
        Ringtone(id: "bloom", displayName: "Bloom", category: .alertTones, systemSoundID: 1322, cafFileName: "bloom.caf"),
        Ringtone(id: "calypso", displayName: "Calypso", category: .alertTones, systemSoundID: 1323, cafFileName: "calypso.caf"),
        Ringtone(id: "choo_choo", displayName: "Choo Choo", category: .alertTones, systemSoundID: 1324, cafFileName: "choo_choo.caf"),
        Ringtone(id: "descent", displayName: "Descent", category: .alertTones, systemSoundID: 1325, cafFileName: "descent.caf"),
        Ringtone(id: "fanfare", displayName: "Fanfare", category: .alertTones, systemSoundID: 1326, cafFileName: "fanfare.caf"),
        Ringtone(id: "ladder", displayName: "Ladder", category: .alertTones, systemSoundID: 1327, cafFileName: "ladder.caf"),
        Ringtone(id: "minuet", displayName: "Minuet", category: .alertTones, systemSoundID: 1328, cafFileName: "minuet.caf"),
        Ringtone(id: "news_flash", displayName: "News Flash", category: .alertTones, systemSoundID: 1329, cafFileName: "news_flash.caf"),
        Ringtone(id: "noir", displayName: "Noir", category: .alertTones, systemSoundID: 1330, cafFileName: "noir.caf"),
        Ringtone(id: "sherwood_forest", displayName: "Sherwood Forest", category: .alertTones, systemSoundID: 1331, cafFileName: "sherwood_forest.caf"),
        Ringtone(id: "spell", displayName: "Spell", category: .alertTones, systemSoundID: 1332, cafFileName: "spell.caf"),
        Ringtone(id: "suspense", displayName: "Suspense", category: .alertTones, systemSoundID: 1333, cafFileName: "suspense.caf"),
        Ringtone(id: "telegraph", displayName: "Telegraph", category: .alertTones, systemSoundID: 1334, cafFileName: "telegraph.caf"),
        Ringtone(id: "tiptoes", displayName: "Tiptoes", category: .alertTones, systemSoundID: 1335, cafFileName: "tiptoes.caf"),
        Ringtone(id: "typewriters", displayName: "Typewriters", category: .alertTones, systemSoundID: 1336, cafFileName: "typewriters.caf"),
        Ringtone(id: "update", displayName: "Update", category: .alertTones, systemSoundID: 1337, cafFileName: "update.caf"),
        
        // Classic sounds - all with bundled .caf files
        Ringtone(id: "glass", displayName: "Glass", category: .classic, systemSoundID: 1013, cafFileName: "glass.caf"),
        Ringtone(id: "horn", displayName: "Horn", category: .classic, systemSoundID: 1033, cafFileName: "horn.caf"),
        Ringtone(id: "bell_classic", displayName: "Bell (Classic)", category: .classic, systemSoundID: 1016, cafFileName: "bell_classic.caf"),
        Ringtone(id: "electronic", displayName: "Electronic", category: .classic, systemSoundID: 1014, cafFileName: "electronic.caf"),
        Ringtone(id: "anticipate", displayName: "Anticipate", category: .classic, systemSoundID: 1020, cafFileName: "anticipate.caf"),
        Ringtone(id: "arpeggio", displayName: "Arpeggio", category: .classic, systemSoundID: 1034, cafFileName: "arpeggio.caf"),
        Ringtone(id: "complete", displayName: "Complete", category: .classic, systemSoundID: 1025, cafFileName: "complete.caf"),
        Ringtone(id: "hello", displayName: "Hello", category: .classic, systemSoundID: 1026, cafFileName: "hello.caf"),
        Ringtone(id: "input", displayName: "Input", category: .classic, systemSoundID: 1027, cafFileName: "input.caf"),
        Ringtone(id: "keys", displayName: "Keys", category: .classic, systemSoundID: 1028, cafFileName: "keys.caf"),
        Ringtone(id: "note", displayName: "Note", category: .classic, systemSoundID: 1029, cafFileName: "note.caf"),
        Ringtone(id: "popcorn", displayName: "Popcorn", category: .classic, systemSoundID: 1030, cafFileName: "popcorn.caf"),
        Ringtone(id: "synth", displayName: "Synth", category: .classic, systemSoundID: 1031, cafFileName: "synth.caf"),
        Ringtone(id: "tweet", displayName: "Tweet", category: .classic, systemSoundID: 1032, cafFileName: "tweet.caf"),
        
        // App bundled sounds (original custom sounds)
        Ringtone(id: "standard", displayName: "Standard", category: .appSounds, systemSoundID: 1007, cafFileName: "standard.caf"),
        Ringtone(id: "gentle", displayName: "Gentle", category: .appSounds, systemSoundID: 1013, cafFileName: "gentle.caf"),
        Ringtone(id: "urgent", displayName: "Urgent", category: .appSounds, systemSoundID: 1005, cafFileName: "urgent.caf"),
        Ringtone(id: "chime", displayName: "Chime", category: .appSounds, systemSoundID: 1025, cafFileName: "chime.caf"),
        Ringtone(id: "bell", displayName: "Bell", category: .appSounds, systemSoundID: 1016, cafFileName: "bell.caf"),
        Ringtone(id: "marimba", displayName: "Marimba", category: .appSounds, systemSoundID: 1030, cafFileName: "marimba.caf"),
        Ringtone(id: "pulse", displayName: "Pulse", category: .appSounds, systemSoundID: 1020, cafFileName: "pulse.caf"),
        Ringtone(id: "alert", displayName: "Alert", category: .appSounds, systemSoundID: 1006, cafFileName: "alert.caf"),
    ]
    
    /// Get ringtones grouped by category
    static var ringtonesByCategory: [(category: RingtoneCategory, ringtones: [Ringtone])] {
        RingtoneCategory.allCases.compactMap { category in
            let tones = allRingtones.filter { $0.category == category }
            return tones.isEmpty ? nil : (category, tones)
        }
    }
    
    /// Find a ringtone by its ID
    static func ringtone(for id: String) -> Ringtone? {
        allRingtones.first { $0.id == id }
    }
    
    private var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var currentlyPlaying: Ringtone?
    
    private init() {}
    
    /// Preview a ringtone
    func preview(_ ringtone: Ringtone) {
        stop()
        
        // Special case for system default
        if ringtone.id == "default" {
            AudioServicesPlaySystemSound(1007)
            isPlaying = true
            currentlyPlaying = ringtone
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.isPlaying = false
                self.currentlyPlaying = nil
            }
            return
        }
        
        // Try to play the bundled .caf file
        if let cafName = ringtone.cafFileName {
            let resourceName = cafName.replacingOccurrences(of: ".caf", with: "")
            if let url = Bundle.main.url(forResource: resourceName, withExtension: "caf") {
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
                    try AVAudioSession.sharedInstance().setActive(true)
                    
                    audioPlayer = try AVAudioPlayer(contentsOf: url)
                    audioPlayer?.prepareToPlay()
                    audioPlayer?.play()
                    isPlaying = true
                    currentlyPlaying = ringtone
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 3)) {
                        self.stop()
                    }
                    return
                } catch {
                    print("🔔 Could not play bundled ringtone: \(error)")
                }
            }
        }
        
        // Fall back to system sound if available
        if let soundID = ringtone.systemSoundID {
            AudioServicesPlaySystemSound(soundID)
            isPlaying = true
            currentlyPlaying = ringtone
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isPlaying = false
                self.currentlyPlaying = nil
            }
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentlyPlaying = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
