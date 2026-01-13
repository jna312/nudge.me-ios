import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var settings: AppSettings
    @Binding var isSettingsOpen: Bool

    @StateObject private var flow = CaptureFlow()
    @StateObject private var transcriber = SpeechTranscriber()
    @StateObject private var wakeWordDetector = WakeWordDetector()
    @ObservedObject private var tipsManager = TipsManager.shared
    
    @State private var isHoldingMic = false
    @State private var showQuickAdd = false
    @State private var lastSavedReminder: ReminderItem?
    @State private var showUndoBanner = false
    @State private var wakeWordTriggered = false
    @State private var isAutoListening = false
    @State private var silenceTimer: Timer?

    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Spacer()
                
                // Wake word indicator
                if settings.wakeWordEnabled && wakeWordDetector.isListening {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Listening for \"Hey Nudge\"...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                
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
                            .fill(isHoldingMic ? Color.red : Color.blue)
                            .frame(width: 88, height: 88)
                            .shadow(color: isHoldingMic ? .red.opacity(0.4) : .blue.opacity(0.3), radius: 8, y: 4)
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
                    
                    Text(isHoldingMic ? "Release to save" : (settings.wakeWordEnabled ? "Hold or say \"Hey Nudge\"" : "Hold to speak"))
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
                    .padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.spring(response: 0.3), value: showUndoBanner)
            }
            
            // Tip overlay
            if let tip = tipsManager.currentTip {
                TipOverlay(tip: tip) {
                    tipsManager.dismissTip(tip.id)
                }
            }
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView(settings: settings, modelContext: modelContext, calendarSyncEnabled: settings.calendarSyncEnabled) {}
        }
        .task {
            await transcriber.requestPermissions()
            await NotificationsManager.shared.requestPermission()
            NotificationsManager.shared.registerCategories()
            
            // Set up notification callbacks
            NotificationsManager.shared.onNotificationWillPresent = { [weak transcriber, weak wakeWordDetector] in
                transcriber?.stop()
                wakeWordDetector?.stopListening()
                isHoldingMic = false
            }
            
            NotificationsManager.shared.onNotificationSoundComplete = { [weak wakeWordDetector] in
                // Resume wake word if enabled
                if settings.wakeWordEnabled {
                    wakeWordDetector?.startListening()
                }
            }
            
            // Start wake word detection if enabled
            if settings.wakeWordEnabled {
                wakeWordDetector.isEnabled = true
                wakeWordDetector.startListening()
            }
            
            // Show hold to speak tip on first launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                tipsManager.showTipIfNeeded(.holdToSpeak)
            }
        }
        .onChange(of: settings.wakeWordEnabled) { _, enabled in
            wakeWordDetector.isEnabled = enabled
            if enabled {
                wakeWordDetector.startListening()
            } else {
                wakeWordDetector.stopListening()
            }
        }
        .onChange(of: isSettingsOpen) { _, isOpen in
            if isOpen {
                if isHoldingMic {
                    transcriber.stop()
                    isHoldingMic = false
                }
                wakeWordDetector.stopListening()
            } else {
                if settings.wakeWordEnabled {
                    wakeWordDetector.startListening()
                }
            }
        }
        .onChange(of: flow.lastSavedReminder) { _, newReminder in
            if let reminder = newReminder {
                lastSavedReminder = reminder
                withAnimation {
                    showUndoBanner = true
                }
                
                // Sync to calendar if enabled
                if settings.calendarSyncEnabled {
                    Task {
                        await CalendarSync.shared.syncToCalendar(reminder: reminder)
                    }
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        if lastSavedReminder?.id == reminder.id {
                            showUndoBanner = false
                        }
                    }
                }
                
                // Show tips after first successful reminder
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if tipsManager.currentTip == nil {
                        tipsManager.showTipIfNeeded(.undoBanner)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    if tipsManager.currentTip == nil {
                        tipsManager.showTipIfNeeded(.voiceCommands)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wakeWordDetected)) { _ in
            handleWakeWordTriggered()
        }
        .onChange(of: flow.needsFollowUp) { _, needsFollowUp in
            print("🎤 needsFollowUp changed to: \(needsFollowUp), isHoldingMic: \(isHoldingMic), isSettingsOpen: \(isSettingsOpen)")
            if needsFollowUp && !isHoldingMic && !isSettingsOpen {
                print("🎤 Starting auto-listen in 0.5s...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    print("🎤 Calling startAutoListening()")
                    startAutoListening()
                }
            }
        }
        .onChange(of: transcriber.transcript) { _, newValue in
            if isAutoListening && !newValue.isEmpty {
                resetSilenceTimer()
            }
        }
    }
    
    private func handleWakeWordTriggered() {
        guard !isHoldingMic && !isSettingsOpen else { return }
        
        // Auto-start recording after wake word
        wakeWordTriggered = true
        startRecording()
        
        // Auto-stop after 10 seconds of recording (if user doesn't manually stop)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if isHoldingMic && wakeWordTriggered {
                stopRecording()
                wakeWordTriggered = false
            }
        }
    }
    
    private func startRecording() {
        withAnimation {
            showUndoBanner = false
        }
        
        // Stop wake word detection while recording
        wakeWordDetector.stopListening()
        
        isHoldingMic = true
        transcriber.transcript = ""
        
        do {
            try transcriber.start()
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            // Failed to start - reset state
            print("🎤 Failed to start recording: \(error.localizedDescription)")
            isHoldingMic = false
            transcriber.reset()
            
            // Resume wake word if enabled
            if settings.wakeWordEnabled {
                wakeWordDetector.startListening()
            }
            
            // Haptic feedback for error
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    
    private func stopRecording() {
        isAutoListening = false
        silenceTimer?.invalidate()
        silenceTimer = nil
        isHoldingMic = false
        wakeWordTriggered = false
        transcriber.stop()
        
        let finalText = transcriber.transcript
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        // Resume wake word detection
        if settings.wakeWordEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                wakeWordDetector.startListening()
            }
        }
        
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
    
    // MARK: - Auto-listening for follow-up questions
    
    private func startAutoListening() {
        print("🎤 startAutoListening called, isHoldingMic: \(isHoldingMic), isSettingsOpen: \(isSettingsOpen)")
        guard !isHoldingMic && !isSettingsOpen else {
            print("🎤 startAutoListening guard failed - skipping")
            return
        }
        print("🎤 Auto-listen starting!")
        
        withAnimation {
            showUndoBanner = false
        }
        
        wakeWordDetector.stopListening()
        
        isHoldingMic = true
        isAutoListening = true
        transcriber.transcript = ""
        
        do {
            try transcriber.start()
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            resetSilenceTimer()
        } catch {
            // Failed to start - reset state
            print("🎤 Failed to start auto-listening: \(error.localizedDescription)")
            isHoldingMic = false
            isAutoListening = false
            transcriber.reset()
            
            if settings.wakeWordEnabled {
                wakeWordDetector.startListening()
            }
        }
        
        // Safety timeout after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if self.isAutoListening {
                self.stopRecording()
            }
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        
        // Wait 1.5 seconds of silence before auto-stopping
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            DispatchQueue.main.async {
                if self.isAutoListening && !self.transcriber.transcript.isEmpty {
                    self.stopRecording()
                }
            }
        }
    }

    private func undoLastReminder() {
        guard let reminder = lastSavedReminder else { return }
        
        // Cancel notification
        let notificationID = "\(reminder.id.uuidString)-alert"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        
        // Remove from calendar if sync enabled
        if settings.calendarSyncEnabled {
            Task {
                await CalendarSync.shared.removeFromCalendar(reminder: reminder)
            }
        }
        
        // Delete reminder
        modelContext.delete(reminder)
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
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
    let calendarSyncEnabled: Bool
    var onDismiss: () -> Void
    
    @State private var title = ""
    @State private var dueDate = Date().addingTimeInterval(3600)
    @State private var hasAlert = true
    @State private var earlyAlertMinutes: Int = 0
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
                    
                    if hasAlert {
                        Picker("Early warning", selection: $earlyAlertMinutes) {
                            Text("None").tag(0)
                            Text("5 minutes before").tag(5)
                            Text("15 minutes before").tag(15)
                            Text("30 minutes before").tag(30)
                            Text("1 hour before").tag(60)
                        }
                    }
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
                earlyAlertMinutes = settings.defaultEarlyAlertMinutes
                
                // Show quick time button tip
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    TipsManager.shared.showTipIfNeeded(.quickAdd)
                }
            }
            .overlay {
                if let tip = TipsManager.shared.currentTip {
                    TipOverlay(tip: tip) {
                        TipsManager.shared.dismissTip(tip.id)
                    }
                }
            }
        }
    }
    
    private func addReminder() {
        let styledTitle = applyWritingStyle(title, style: settings.writingStyle)
        
        let item = ReminderItem(
            title: styledTitle,
            dueAt: dueDate,
            alertAt: hasAlert ? dueDate : nil,
            earlyAlertMinutes: earlyAlertMinutes > 0 ? earlyAlertMinutes : nil
        )
        
        modelContext.insert(item)
        
        if hasAlert {
            Task {
                await NotificationsManager.shared.schedule(reminder: item)
            }
        }
        
        // Sync to calendar
        if calendarSyncEnabled {
            Task {
                await CalendarSync.shared.syncToCalendar(reminder: item)
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
