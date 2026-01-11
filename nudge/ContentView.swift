import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var settings: AppSettings

    @StateObject private var flow = CaptureFlow()
    @StateObject private var transcriber = SpeechTranscriber()

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

                        // Give UI a breath, then listen again
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        try? transcriber.start()
                    }
                } else {
                    try? transcriber.start()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .task {
            await transcriber.requestPermissions()
            await NotificationsManager.shared.requestPermission()
            NotificationsManager.shared.registerCategories()
            
            if !transcriber.isRecording {
                try? transcriber.start()
                
                // Debug (optional)
                _ = await UNUserNotificationCenter.current().notificationSettings()
            }
        }
        .onDisappear {
            if transcriber.isRecording { transcriber.stop() }
        }

    }
}
