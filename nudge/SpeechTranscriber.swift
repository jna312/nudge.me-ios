import SwiftUI
import Combine
import Speech
import AVFoundation

final class SpeechTranscriber: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording = false

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.current.identifier))
    private let recognitionLocale = Locale.current
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestPermissions() async {
        // Request microphone permission
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            #if os(iOS)
            if #available(iOS 17.0, tvOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            #else
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
            #endif
        }

        // Request speech recognition authorization
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func start() throws {
        // Reset any stuck state first
        reset()
        
        transcript = ""
        isRecording = true

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        guard let request, let recognizer = recognizer else {
            isRecording = false
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            
            if error != nil {
                return
            }
            
            guard let result else { return }
            Task { @MainActor in
                self.transcript = result.bestTranscription.formattedString
            }
        }
    }
    
    /// Reset the transcriber to a clean state (call if it gets stuck)
    func reset() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func stop() {
        isRecording = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        
        // Deactivate audio session to allow other audio (like system sounds) to play
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

