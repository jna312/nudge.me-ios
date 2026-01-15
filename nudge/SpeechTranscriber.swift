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
    private let audioQueue = DispatchQueue(label: "com.nudge.transcriber.audio", qos: .userInteractive)
    private var isStarting = false
    private var isStopping = false
    private var audioSessionReady = false
    private var prewarmedEngine: AVAudioEngine?

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
    
    @objc private func handleAppDidBecomeActive() {
        audioSessionReady = false
        warmUp()
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        
        if type == .ended {
            audioSessionReady = false
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
    
    /// Pre-warm audio session and engine - call this BEFORE user presses mic
    func warmUp() {
        guard !audioSessionReady else { return }
        
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
                try session.setActive(true)
                
                // Pre-create audio engine
                let engine = AVAudioEngine()
                engine.prepare()
                
                DispatchQueue.main.async {
                    self.prewarmedEngine = engine
                    self.audioSessionReady = true
                }
            } catch {
                // Will set up on demand
            }
        }
    }

    /// Start recording - optimized for instant response
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
        
        // Use pre-warmed engine if available, otherwise create new
        let engine: AVAudioEngine
        if let prewarmed = prewarmedEngine, audioSessionReady {
            engine = prewarmed
            prewarmedEngine = nil
        } else {
            // Fallback: set up audio session (pre-warm failed)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
            try session.setActive(true)  // Fast when duckOthers is used
            engine = AVAudioEngine()
            engine.prepare()  // Pre-prepare to speed up start()
        }
        
        audioEngine = engine

        // Create recognition request
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else {
            throw TranscriberError.requestCreationFailed
        }
        request.shouldReportPartialResults = true
        
        // Configure audio tap
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw TranscriberError.invalidAudioFormat
        }
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        // Start engine (should be fast if pre-warmed)
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        
        isRecording = true

        // Start recognition
        guard let recognizer = recognizer, recognizer.isAvailable else {
            stop()
            throw TranscriberError.recognizerUnavailable
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                let nsError = error as NSError
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
        prewarmedEngine = nil
        audioSessionReady = false
        
        // Deactivate session async to prevent blocking
        audioQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        
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
            if engine.isRunning { engine.stop() }
        }
        audioEngine = nil
        
        // Deactivate session async so music resumes without blocking
        audioQueue.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioSessionReady = false
        }
        
        // Pre-warm for next use
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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
