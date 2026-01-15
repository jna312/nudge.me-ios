import SwiftUI
import Combine
import Speech
import AVFoundation

final class SpeechTranscriber: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording = false
    @Published var lastError: String?

    private var audioEngine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    private let stateQueue = DispatchQueue(label: "com.nudge.transcriber.state")
    private var isStarting = false
    private var isStopping = false
    private var isWarmedUp = false
    private var lastUsedTime: Date?

    init() {
        createFreshRecognizer()
        
        // Listen for app lifecycle to handle long-running sessions
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
    
    @objc private func handleAppDidBecomeActive() {
        // Re-warm audio system when app becomes active (handles long background periods)
        isWarmedUp = false
        warmUp()
        
        // Recreate recognizer if it's been a while (handles stale state)
        if let lastUsed = lastUsedTime, Date().timeIntervalSince(lastUsed) > 300 {
            createFreshRecognizer()
        }
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        if type == .ended {
            // Audio interruption ended - re-warm
            isWarmedUp = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.warmUp()
            }
        }
    }
    
    private func createFreshRecognizer() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: Locale.current.identifier))
    }
    
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
        
        warmUp()
    }
    
    /// Pre-warm audio session for faster start
    func warmUp() {
        guard !isWarmedUp else { return }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                
                DispatchQueue.main.async {
                    self.isWarmedUp = true
                }
            } catch {
                // Will configure on first use
            }
        }
    }
    
    /// Ensure recognizer is available and fresh
    private func ensureRecognizerAvailable() -> Bool {
        // Check if recognizer exists and is available
        if recognizer == nil || recognizer?.isAvailable != true {
            createFreshRecognizer()
        }
        return recognizer?.isAvailable == true
    }

    func start() throws {
        // Prevent concurrent start calls
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
        
        // Track usage time for long-running detection
        lastUsedTime = Date()
        
        // Cleanup any existing state
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        
        DispatchQueue.main.async {
            self.transcript = ""
            self.lastError = nil
        }
        
        // ALWAYS set up audio session first
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw TranscriberError.audioSessionFailed(error)
        }
        
        // Cleanup old engine if exists
        if let engine = audioEngine, isWarmedUp {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning {
                engine.stop()
            }
        }
        
        // Create fresh engine for each recording
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else {
            throw TranscriberError.engineCreationFailed
        }

        // Create recognition request
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else {
            throw TranscriberError.requestCreationFailed
        }
        request.shouldReportPartialResults = true
        
        // Configure audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw TranscriberError.invalidAudioFormat
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        // Start engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw TranscriberError.engineStartFailed(error)
        }
        
        DispatchQueue.main.async {
            self.isRecording = true
        }

        // Ensure recognizer is fresh and available
        guard ensureRecognizerAvailable(), let recognizer = recognizer else {
            stop()
            throw TranscriberError.recognizerUnavailable
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                let nsError = error as NSError
                // Ignore cancellation errors (code 203, 216, 1110)
                if nsError.code != 203 && nsError.code != 216 && nsError.code != 1110 {
                    DispatchQueue.main.async {
                        self.lastError = error.localizedDescription
                    }
                }
                return
            }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.transcript = result.bestTranscription.formattedString
                }
            }
        }
    }
    
    /// Force cleanup - use when state is potentially corrupted
    private func forceCleanup() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        
        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        isWarmedUp = false
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    /// Reset the transcriber to a clean state (call if it gets stuck)
    func reset() {
        stateQueue.sync {
            isStarting = false
            isStopping = false
        }
        
        forceCleanup()
        createFreshRecognizer()
        isWarmedUp = false
        
        DispatchQueue.main.async {
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
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    /// Check if transcriber is in a good state
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
