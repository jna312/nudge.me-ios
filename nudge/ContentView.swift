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

            // Debug (optional)
            let s = await UNUserNotificationCenter.current().notificationSettings()
            print("🔔 authStatus =", s.authorizationStatus.rawValue)
            print("🔔 alertSetting =", s.alertSetting.rawValue)
            print("🔔 soundSetting =", s.soundSetting.rawValue)
        }
    }
}
