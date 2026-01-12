import Foundation
import Combine
import AVFoundation
import UserNotifications
import AudioToolbox

/// Manages ringtone selection and playback for reminders
final class RingtoneManager: ObservableObject {
    static let shared = RingtoneManager()
    
    /// Available ringtones - these correspond to .caf files in the bundle
    enum Ringtone: String, CaseIterable, Identifiable {
        case standard = "standard"
        case gentle = "gentle"
        case urgent = "urgent"
        case chime = "chime"
        case bell = "bell"
        case marimba = "marimba"
        case pulse = "pulse"
        case alert = "alert"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .standard: return "Standard"
            case .gentle: return "Gentle"
            case .urgent: return "Urgent"
            case .chime: return "Chime"
            case .bell: return "Bell"
            case .marimba: return "Marimba"
            case .pulse: return "Pulse"
            case .alert: return "Alert"
            }
        }
        
        var fileName: String {
            "\(rawValue).caf"
        }
        
        /// Returns the notification sound for this ringtone
        var notificationSound: UNNotificationSound {
            if Bundle.main.url(forResource: rawValue, withExtension: "caf") != nil {
                return UNNotificationSound(named: UNNotificationSoundName(fileName))
            }
            return .default
        }
    }
    
    private var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    @Published var currentlyPlaying: Ringtone?
    
    private init() {}
    
    /// Preview a ringtone
    func preview(_ ringtone: Ringtone) {
        stop()
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("🔔 Audio session error: \(error)")
        }
        
        if let url = Bundle.main.url(forResource: ringtone.rawValue, withExtension: "caf") {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                isPlaying = true
                currentlyPlaying = ringtone
                
                DispatchQueue.main.asyncAfter(deadline: .now() + (audioPlayer?.duration ?? 3)) {
                    self.stop()
                }
            } catch {
                print("🔔 Could not play ringtone: \(error)")
                playSystemSound(for: ringtone)
            }
        } else {
            playSystemSound(for: ringtone)
        }
    }
    
    private func playSystemSound(for ringtone: Ringtone) {
        let soundID: SystemSoundID
        switch ringtone {
        case .standard: soundID = 1007
        case .gentle: soundID = 1013
        case .urgent: soundID = 1005
        case .chime: soundID = 1025
        case .bell: soundID = 1016
        case .marimba: soundID = 1030
        case .pulse: soundID = 1020
        case .alert: soundID = 1006
        }
        
        AudioServicesPlaySystemSound(soundID)
        isPlaying = true
        currentlyPlaying = ringtone
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.isPlaying = false
            self.currentlyPlaying = nil
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
