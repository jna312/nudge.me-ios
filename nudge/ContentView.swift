import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var settings: AppSettings
    @Binding var isSettingsOpen: Bool

    @StateObject private var flow = CaptureFlow()
    @StateObject private var transcriber = SpeechTranscriber()
    
    // Track if we were recording before settings opened
    @State private var wasRecordingBeforeSettings = false

    var body: some View {
        VStack(spacing: 24) {
            Text(flow.prompt)
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(transcriber.transcript.isEmpty ? "…" : transcriber.transcript)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(transcriber.isRecording ? "Stop" : "Speak") {
                if transcriber.isRecording {
                    transcriber.stop()
                    let finalText = transcriber.transcript

                    Task {
                        await flow.handleTranscript(finalText, settings: settings, modelContext: modelContext)
                        transcriber.transcript = ""

                        // Give UI a breath, then listen again (only if settings not open)
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        if !isSettingsOpen {
                            try? transcriber.start()
                        }
                    }
                } else {
                    try? transcriber.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSettingsOpen)
        }
        .padding()
        .task {
            await transcriber.requestPermissions()
            await NotificationsManager.shared.requestPermission()
            NotificationsManager.shared.registerCategories()
            
            if !transcriber.isRecording && !isSettingsOpen {
                try? transcriber.start()
                
                // Debug (optional)
                _ = await UNUserNotificationCenter.current().notificationSettings()
            }
        }
        .onChange(of: isSettingsOpen) { _, isOpen in
            if isOpen {
                // Settings opened - pause recording
                wasRecordingBeforeSettings = transcriber.isRecording
                if transcriber.isRecording {
                    transcriber.stop()
                }
            } else {
                // Settings closed - resume recording if we were recording before
                if wasRecordingBeforeSettings {
                    try? transcriber.start()
                }
            }
        }
        .onDisappear {
            if transcriber.isRecording { transcriber.stop() }
        }
    }
}
