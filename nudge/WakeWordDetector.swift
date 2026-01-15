import Foundation
import Speech
import AVFoundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class WakeWordDetector: ObservableObject {
    @Published var isListening = false
    @Published var wakeWordDetected = false
    @Published var isEnabled = false
    
    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    private let wakePhrase = "hey nudge me"
    
    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    func startListening() {
        guard isEnabled, !isListening else { return }
        
        // Reset state
        wakeWordDetected = false
        
        do {
            try setupAudioSession()
            try startRecognition()
            isListening = true
        } catch {
        }
    }
    
    func stopListening() {
        isListening = false
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        
        audioEngine = nil
        request = nil
        task = nil
        
        // Deactivate async to prevent blocking
        DispatchQueue.global(qos: .utility).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    
    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
        try session.setActive(true)
    }
    
    private func startRecognition() throws {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else { return }
        
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true // Use on-device for privacy
        
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        guard let recognizer = recognizer else { return }
        
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcript = result.bestTranscription.formattedString.lowercased()
                
                // Check for wake phrase
                if transcript.contains(self.wakePhrase) || 
                   transcript.contains("hey, nudge me") ||
                   transcript.contains("a nudge me") ||
                   transcript.hasSuffix("nudge me") {
                    Task { @MainActor in
                        self.handleWakeWordDetected()
                    }
                }
            }
            
            // If recognition ended, restart it (for continuous listening)
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    if self.isEnabled && self.isListening && !self.wakeWordDetected {
                        self.stopListening()
                        // Small delay before restarting
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self.startListening()
                    }
                }
            }
        }
    }
    
    private func handleWakeWordDetected() {
        guard !wakeWordDetected else { return } // Prevent multiple triggers
        
        wakeWordDetected = true
        stopListening()
        
        // Haptic feedback
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
        
        
        // Post notification for ContentView to handle
        NotificationCenter.default.post(name: .wakeWordDetected, object: nil)
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let wakeWordDetected = Notification.Name("wakeWordDetected")
}
