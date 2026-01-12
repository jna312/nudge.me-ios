import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var settings: AppSettings
    @Binding var isSettingsOpen: Bool

    @StateObject private var flow = CaptureFlow()
    @StateObject private var transcriber = SpeechTranscriber()
    
    @State private var isHoldingMic = false
    @State private var showQuickAdd = false
    @State private var lastSavedReminder: ReminderItem?
    @State private var showUndoBanner = false

    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Prompt text
                Text(flow.prompt)
                    .font(.title2)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                // Transcript display
                if !transcriber.transcript.isEmpty || isHoldingMic {
                    Text(transcriber.transcript.isEmpty ? "Listening..." : transcriber.transcript)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Hold-to-record mic button
                VStack(spacing: 12) {
                    ZStack {
                        // Pulsing background when recording
                        if isHoldingMic {
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                .frame(width: 120, height: 120)
                                .scaleEffect(isHoldingMic ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isHoldingMic)
                        }
                        
                        // Main mic button
                        Circle()
                            .fill(isHoldingMic ? Color.red : Color.accentColor)
                            .frame(width: 88, height: 88)
                            .shadow(color: isHoldingMic ? .red.opacity(0.4) : .accentColor.opacity(0.3), radius: 8, y: 4)
                            .overlay {
                                Image(systemName: isHoldingMic ? "waveform" : "mic.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.white)
                                    .symbolEffect(.variableColor.iterative, isActive: isHoldingMic)
                            }
                            .scaleEffect(isHoldingMic ? 1.1 : 1.0)
                            .animation(.spring(response: 0.3), value: isHoldingMic)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !isHoldingMic && !isSettingsOpen {
                                    startRecording()
                                }
                            }
                            .onEnded { _ in
                                if isHoldingMic {
                                    stopRecording()
                                }
                            }
                    )
                    .disabled(isSettingsOpen)
                    .opacity(isSettingsOpen ? 0.5 : 1.0)
                    
                    Text(isHoldingMic ? "Release to save" : "Hold to speak")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Keyboard button
                Button {
                    showQuickAdd = true
                } label: {
                    Label("Type instead", systemImage: "keyboard")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(isSettingsOpen)
                .padding(.bottom, 32)
            }
            
            // Undo banner overlay
            if showUndoBanner, let reminder = lastSavedReminder {
                VStack {
                    Spacer()
                    
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        
                        Text("Saved: \(reminder.title)")
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button("Undo") {
                            undoLastReminder()
                        }
                        .fontWeight(.semibold)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                    .padding(.horizontal)
                    .padding(.bottom, 120) // Above the mic button
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.3), value: showUndoBanner)
            }
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView(settings: settings, modelContext: modelContext) {}
        }
        .task {
            await transcriber.requestPermissions()
            await NotificationsManager.shared.requestPermission()
            NotificationsManager.shared.registerCategories()
            NotificationsManager.shared.currentSoundSetting = settings.notificationSound
            
            // Set up notification sound callbacks
            NotificationsManager.shared.onNotificationWillPresent = { [weak transcriber] in
                guard let transcriber = transcriber else { return }
                if transcriber.isRecording {
                    transcriber.stop()
                    isHoldingMic = false
                }
            }
            
            NotificationsManager.shared.onNotificationSoundComplete = {
                // Don't auto-resume - user controls mic now
            }
        }
        .onChange(of: settings.notificationSound) { _, newSound in
            NotificationsManager.shared.currentSoundSetting = newSound
        }
        .onChange(of: isSettingsOpen) { _, isOpen in
            if isOpen && isHoldingMic {
                transcriber.stop()
                isHoldingMic = false
            }
        }
        .onChange(of: flow.lastSavedReminder) { _, newReminder in
            if let reminder = newReminder {
                lastSavedReminder = reminder
                withAnimation {
                    showUndoBanner = true
                }
                
                // Auto-hide after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        if lastSavedReminder?.id == reminder.id {
                            showUndoBanner = false
                        }
                    }
                }
            }
        }
    }
    
    private func startRecording() {
        // Hide undo banner when starting new recording
        withAnimation {
            showUndoBanner = false
        }
        
        isHoldingMic = true
        transcriber.transcript = ""
        try? transcriber.start()
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    private func stopRecording() {
        isHoldingMic = false
        transcriber.stop()
        
        let finalText = transcriber.transcript
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            transcriber.transcript = ""
            return
        }
        
        Task {
            await flow.handleTranscript(finalText, settings: settings, modelContext: modelContext)
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            transcriber.transcript = ""
        }
    }
    
    private func undoLastReminder() {
        guard let reminder = lastSavedReminder else { return }
        
        // Cancel notification
        let notificationID = "\(reminder.id.uuidString)-alert"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        
        // Delete reminder
        modelContext.delete(reminder)
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        // Hide banner and reset
        withAnimation {
            showUndoBanner = false
        }
        lastSavedReminder = nil
        flow.prompt = "Undone. Try again?"
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
