import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var settings: AppSettings
    @Binding var isSettingsOpen: Bool

    @StateObject private var flow = CaptureFlow()
    @StateObject private var transcriber = SpeechTranscriber()
    
    @State private var wasRecordingBeforeSettings = false
    @State private var wasRecordingBeforeNotification = false
    @State private var showQuickAdd = false

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

            HStack(spacing: 16) {
                Button(transcriber.isRecording ? "Stop" : "Speak") {
                    if transcriber.isRecording {
                        transcriber.stop()
                        let finalText = transcriber.transcript

                        Task {
                            await flow.handleTranscript(finalText, settings: settings, modelContext: modelContext)
                            transcriber.transcript = ""

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
                
                Button {
                    if transcriber.isRecording {
                        transcriber.stop()
                    }
                    showQuickAdd = true
                } label: {
                    Image(systemName: "keyboard")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .disabled(isSettingsOpen)
            }
        }
        .padding()
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView(settings: settings, modelContext: modelContext) {
                if !isSettingsOpen && wasRecordingBeforeSettings {
                    try? transcriber.start()
                }
            }
        }
        .task {
            await transcriber.requestPermissions()
            await NotificationsManager.shared.requestPermission()
            NotificationsManager.shared.registerCategories()
            
            // Set up notification sound callbacks
            NotificationsManager.shared.onNotificationWillPresent = { [weak transcriber] in
                guard let transcriber = transcriber else { return }
                wasRecordingBeforeNotification = transcriber.isRecording
                if transcriber.isRecording {
                    transcriber.stop()
                    print("🎤 Paused transcriber for notification sound")
                }
            }
            
            NotificationsManager.shared.onNotificationSoundComplete = { [weak transcriber] in
                guard let transcriber = transcriber else { return }
                if wasRecordingBeforeNotification && !isSettingsOpen {
                    try? transcriber.start()
                    print("🎤 Resumed transcriber after notification")
                }
            }
            
            if !transcriber.isRecording && !isSettingsOpen {
                try? transcriber.start()
                _ = await UNUserNotificationCenter.current().notificationSettings()
            }
        }
        .onChange(of: isSettingsOpen) { _, isOpen in
            if isOpen {
                wasRecordingBeforeSettings = transcriber.isRecording
                if transcriber.isRecording {
                    transcriber.stop()
                }
            } else {
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

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    let settings: AppSettings
    let modelContext: ModelContext
    var onDismiss: () -> Void
    
    @State private var title = ""
    @State private var dueDate = Date().addingTimeInterval(3600)
    @State private var hasAlert = true
    @FocusState private var isTitleFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section("What do you need to remember?") {
                    TextField("Reminder title", text: $title)
                        .focused($isTitleFocused)
                }
                
                Section("When") {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            QuickTimeButton(label: "30 min", date: Date().addingTimeInterval(1800), selection: $dueDate)
                            QuickTimeButton(label: "1 hour", date: Date().addingTimeInterval(3600), selection: $dueDate)
                            QuickTimeButton(label: "3 hours", date: Date().addingTimeInterval(10800), selection: $dueDate)
                            QuickTimeButton(label: "Tomorrow 9 AM", date: tomorrowAt9AM(), selection: $dueDate)
                            QuickTimeButton(label: "Tomorrow 6 PM", date: tomorrowAt6PM(), selection: $dueDate)
                        }
                    }
                }
                
                Section {
                    Toggle("Alert at due time", isOn: $hasAlert)
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addReminder()
                        dismiss()
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                isTitleFocused = true
            }
        }
    }
    
    private func addReminder() {
        let styledTitle = applyWritingStyle(title, style: settings.writingStyle)
        
        let item = ReminderItem(
            title: styledTitle,
            dueAt: dueDate,
            alertAt: hasAlert ? dueDate : nil
        )
        
        modelContext.insert(item)
        
        if hasAlert {
            Task {
                await NotificationsManager.shared.schedule(reminder: item)
            }
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func applyWritingStyle(_ s: String, style: String) -> String {
        switch style {
        case "caps": return s.uppercased()
        case "title": return s.capitalized
        default:
            guard let first = s.first else { return s }
            return String(first).uppercased() + s.dropFirst()
        }
    }
    
    private func tomorrowAt9AM() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
    }
    
    private func tomorrowAt6PM() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow)!
    }
}

struct QuickTimeButton: View {
    let label: String
    let date: Date
    @Binding var selection: Date
    
    var body: some View {
        Button(label) {
            selection = date
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }
        .buttonStyle(.bordered)
        .tint(Calendar.current.isDate(selection, equalTo: date, toGranularity: .minute) ? .blue : .secondary)
    }
}
