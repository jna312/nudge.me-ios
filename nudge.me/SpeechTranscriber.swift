import SwiftUI
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording = false
    @Published var lastError: String?

    // These are touched from the audio tap / recognition callbacks (arbitrary
    // queues) and from the `stateQueue`/`audioQueue` closures below. They are
    // protected by those queues (or by the SFSpeech/AVAudioEngine lifecycle)
    // rather than by the main actor, so we opt them out of actor isolation.
    nonisolated(unsafe) private var audioEngine: AVAudioEngine?
    nonisolated(unsafe) private var recognizer: SFSpeechRecognizer?
    nonisolated(unsafe) private var request: SFSpeechAudioBufferRecognitionRequest?
    nonisolated(unsafe) private var task: SFSpeechRecognitionTask?

    nonisolated private let stateQueue = DispatchQueue(label: "com.nudge.me.transcriber.state")
    nonisolated private let audioQueue = DispatchQueue(label: "com.nudge.me.transcriber.audio", qos: .userInteractive)
    nonisolated(unsafe) private var isStarting = false
    nonisolated(unsafe) private var isStopping = false
    nonisolated(unsafe) private var audioSessionReady = false

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.current.identifier))
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc nonisolated private func handleAppDidBecomeActive() {
        // UIApplication.didBecomeActiveNotification is posted on the main
        // thread, but hop explicitly so main-actor-isolated state (`warmUp`,
        // `audioSessionReady`) is touched on the right executor.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.audioSessionReady = false
            self.warmUp()
        }
    }

    @objc nonisolated private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        if type == .ended {
            DispatchQueue.main.async { [weak self] in
                self?.audioSessionReady = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.warmUp()
            }
        }
    }
    
    func requestPermissions() async {
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            #if os(iOS)
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            #endif
        }

        _ = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        warmUp()
    }
    
    /// Pre-warm audio session ONLY (not engine) - safe to call anytime
    func warmUp() {
        guard !audioSessionReady else { return }

        audioQueue.async { [weak self] in
            guard let self = self else { return }

            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
                try session.setActive(true)

                Task { @MainActor [weak self] in
                    self?.audioSessionReady = true
                }
            } catch {
                // Will set up on demand
            }
        }
    }

    /// Start recording
    func start() throws {
        var shouldReturn = false
        stateQueue.sync {
            if isStarting || isStopping {
                shouldReturn = true
            } else {
                isStarting = true
            }
        }
        if shouldReturn {
            throw TranscriberError.busy
        }
        
        defer {
            stateQueue.sync { isStarting = false }
        }
        
        // Quick cleanup
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        
        transcript = ""
        lastError = nil
        
        // ALWAYS ensure audio session is configured first
        let session = AVAudioSession.sharedInstance()
        if !audioSessionReady {
            do {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
                try session.setActive(true)
                audioSessionReady = true
            } catch {
                throw TranscriberError.audioSessionFailed(error)
            }
        }
        
        // Create fresh engine AFTER audio session is ready
        let engine = AVAudioEngine()
        audioEngine = engine

        // Create recognition request
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else {
            throw TranscriberError.requestCreationFailed
        }
        request.shouldReportPartialResults = true
        
        // Configure audio tap - audio session MUST be active before this
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw TranscriberError.invalidAudioFormat
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        // Start engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw TranscriberError.engineStartFailed(error)
        }
        
        isRecording = true

        // Start recognition
        guard let recognizer = recognizer, recognizer.isAvailable else {
            stop()
            throw TranscriberError.recognizerUnavailable
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error = error {
                let nsError = error as NSError
                if nsError.code != 203 && nsError.code != 216 && nsError.code != 1110 {
                    let message = error.localizedDescription
                    Task { @MainActor [weak self] in
                        self?.lastError = message
                    }
                }
                return
            }

            if let result = result {
                let formatted = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    self?.transcript = formatted
                }
            }
        }
    }
    
    func reset() {
        stateQueue.sync {
            isStarting = false
            isStopping = false
        }
        
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        
        if let engine = audioEngine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        audioSessionReady = false
        
        audioQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isRecording = false
            self.transcript = ""
            self.lastError = nil
        }
    }

    func stop() {
        var shouldReturn = false
        stateQueue.sync {
            if isStopping {
                shouldReturn = true
            } else {
                isStopping = true
            }
        }
        if shouldReturn { return }
        
        defer {
            stateQueue.sync { isStopping = false }
        }
        
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        audioEngine = nil
        
        audioQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.isRecording = false
            self.audioSessionReady = false
        }

        // Pre-warm for next use
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.warmUp()
        }
    }
    
    var isHealthy: Bool {
        if isRecording {
            return audioEngine?.isRunning == true
        }
        return recognizer?.isAvailable == true
    }
}

enum TranscriberError: LocalizedError {
    case busy
    case engineCreationFailed
    case audioSessionFailed(Error)
    case requestCreationFailed
    case invalidAudioFormat
    case engineStartFailed(Error)
    case recognizerUnavailable
    
    var errorDescription: String? {
        switch self {
        case .busy: return "Transcriber is busy"
        case .engineCreationFailed: return "Failed to create audio engine"
        case .audioSessionFailed(let e): return "Audio session error: \(e.localizedDescription)"
        case .requestCreationFailed: return "Failed to create recognition request"
        case .invalidAudioFormat: return "Invalid audio format"
        case .engineStartFailed(let e): return "Engine start error: \(e.localizedDescription)"
        case .recognizerUnavailable: return "Speech recognizer unavailable"
        }
    }
}
