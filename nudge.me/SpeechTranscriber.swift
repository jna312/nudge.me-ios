import SwiftUI
import Combine
import Speech
import AVFoundation

@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published var lastError: String?

    private var audioEngine: AVAudioEngine?
    private let recognizer = SFSpeechRecognizer(locale: .current)
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sessionID: UUID?
    private var finalTranscript: String?
    private var finishContinuation: CheckedContinuation<String, Error>?
    private var finishTimeout: Task<Void, Never>?

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc nonisolated private func audioInterrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        Task { @MainActor [weak self] in
            self?.lastError = String(localized: "Recording was interrupted. Your words are still here; try again or type them.")
            self?.cancelSession()
        }
    }

    @discardableResult
    func requestPermissions() async -> Bool {
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard microphone else {
            lastError = String(localized: "Microphone access is off. Enable it in Settings, or type your reminder.")
            return false
        }
        guard !Task.isCancelled else { return false }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            lastError = String(localized: "Speech recognition is off. Enable it in Settings, or type your reminder.")
            return false
        }
        lastError = nil
        return true
    }

    func start() throws {
        guard !isRecording, finishContinuation == nil else { throw TranscriberError.busy }
        guard AVAudioApplication.shared.recordPermission == .granted,
              SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriberError.permissionDenied
        }
        guard let recognizer, recognizer.isAvailable else { throw TranscriberError.recognizerUnavailable }
        cancelSession()
        transcript = ""
        lastError = nil
        finalTranscript = nil
        let id = UUID()
        sessionID = id

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
            try audioSession.setActive(true)
            let engine = AVAudioEngine()
            let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.taskHint = .dictation
            let format = engine.inputNode.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw TranscriberError.invalidAudioFormat }
            // Capture this request, never a mutable request belonging to a later recording.
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                recognitionRequest.append(buffer)
            }
            audioEngine = engine
            request = recognitionRequest
            engine.prepare()
            try engine.start()
            isRecording = true
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal == true
                let failure = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == id else { return }
                    if let text { self.transcript = text }
                    if isFinal {
                        self.finalTranscript = text ?? self.transcript
                        self.stopAudio()
                        self.resolveFinish(.success(self.finalTranscript ?? ""))
                    } else if let failure {
                        self.lastError = failure
                        self.stopAudio()
                        self.resolveFinish(.failure(TranscriberError.recognitionFailed(failure)))
                    }
                }
            }
        } catch {
            cancelSession()
            throw error
        }
    }

    /// Ends input, then waits for Apple's final result instead of saving provisional text.
    func finish() async throws -> String {
        if let finalTranscript {
            cancelSession()
            return finalTranscript
        }
        if let lastError { throw TranscriberError.recognitionFailed(lastError) }
        guard sessionID != nil, finishContinuation == nil else { throw TranscriberError.busy }
        let finishingSession = sessionID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                finishContinuation = continuation
                stopAudio()
                request?.endAudio()
                recognitionTask?.finish()
                finishTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled, let self else { return }
                    self.lastError = String(localized: "I couldn’t finish recognizing that. Try again, or edit your words below.")
                    self.resolveFinish(.failure(TranscriberError.finalizationTimedOut))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.sessionID == finishingSession else { return }
                self?.cancelSession()
            }
        }
    }

    func stop() { cancelSession() }

    func reset() {
        cancelSession()
        transcript = ""
        lastError = nil
        finalTranscript = nil
    }

    private func stopAudio() {
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func resolveFinish(_ result: Result<String, Error>) {
        guard let continuation = finishContinuation else { return }
        finishContinuation = nil
        finishTimeout?.cancel()
        finishTimeout = nil
        sessionID = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        continuation.resume(with: result)
    }

    private func cancelSession() {
        sessionID = nil
        stopAudio()
        request?.endAudio()
        recognitionTask?.cancel()
        request = nil
        recognitionTask = nil
        finishTimeout?.cancel()
        finishTimeout = nil
        let continuation = finishContinuation
        finishContinuation = nil
        continuation?.resume(throwing: CancellationError())
    }
}

enum TranscriberError: LocalizedError {
    case busy, permissionDenied, invalidAudioFormat, recognizerUnavailable, finalizationTimedOut
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .busy: return String(localized: "Please wait for the current recording to finish.")
        case .permissionDenied: return String(localized: "Enable microphone and speech recognition in Settings, or type your reminder.")
        case .invalidAudioFormat: return String(localized: "The microphone is unavailable. Check your audio connection and try again.")
        case .recognizerUnavailable: return String(localized: "Speech recognition is unavailable right now. You can type your reminder instead.")
        case .finalizationTimedOut: return String(localized: "Recognition took too long. Try again, or edit your words below.")
        case .recognitionFailed(let message): return message
        }
    }
}
