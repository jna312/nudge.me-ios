import SwiftUI

struct ContentView: View {
    @StateObject private var transcriber = SpeechTranscriber()

    var body: some View {
        VStack(spacing: 24) {
            Text("Speak something")
                .font(.title2)

            Text(transcriber.transcript.isEmpty ? "…" : transcriber.transcript)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(transcriber.isRecording ? "Stop" : "Speak") {
                if transcriber.isRecording {
                    transcriber.stop()
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
            await NotificationsManager.shared.scheduleTestIn30Seconds()
        }
    }
}
