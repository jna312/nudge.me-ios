import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var settings: AppSettings
    @Binding var isSettingsOpen: Bool
    @Binding var autoStartMic: Bool

    @StateObject private var flow = CaptureFlow()
    @StateObject private var transcriber = SpeechTranscriber()
    @StateObject private var wakeWordDetector = WakeWordDetector()
    @ObservedObject private var tipsManager = TipsManager.shared
    
    @State private var isHoldingMic = false
    @State private var showQuickAdd = false
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
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
            
            // Pre-prepare haptic for instant response
            hapticGenerator.prepare()
            
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
        .onChange(of: autoStartMic) { _, shouldStart in
            if shouldStart {
                autoStartMic = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startAutoListening()
                }
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
                
                // Sync to widget
                WidgetDataProvider.shared.syncReminders(from: modelContext)
                
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
            if needsFollowUp && !isHoldingMic && !isSettingsOpen {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    startAutoListening()
                }
            }
        }
        .onChange(of: transcriber.transcript) { _, newValue in
            if isAutoListening && !newValue.isEmpty {
                resetSilenceTimer()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // App became active - ensure audio system is ready
                transcriber.warmUp()
                hapticGenerator.prepare()
                if settings.wakeWordEnabled && !isHoldingMic && !isSettingsOpen {
                    wakeWordDetector.startListening()
                }
            } else if newPhase == .background {
                // App going to background - clean up
                if isHoldingMic {
                    stopRecording()
                }
                wakeWordDetector.stopListening()
                silenceTimer?.invalidate()
                silenceTimer = nil
            }
        }
    }
    
    private func handleWakeWordTriggered() {
        guard !isHoldingMic && !isSettingsOpen else { return }
        
        // Auto-start recording after wake word
        wakeWordTriggered = true
        isAutoListening = true  // Enable silence detection after speech starts
        startRecording()
        
        // Don't start silence timer yet - wait until user starts speaking
        
        // Safety timeout after 60 seconds (in case user forgets)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if isHoldingMic && wakeWordTriggered && transcriber.transcript.isEmpty {
                stopRecording()
                wakeWordTriggered = false
                flow.prompt = String(localized: "Mic timed out. Tap to try again.")
            }
        }
    }
    
    private func startRecording() {
        // Immediate haptic feedback - generator already prepared
        hapticGenerator.impactOccurred()
        
        // Immediately update UI state
        isHoldingMic = true
        transcriber.transcript = ""
        
        withAnimation {
            showUndoBanner = false
        }
        
        // Stop wake word detection while recording
        wakeWordDetector.stopListening()
        
        do {
            try transcriber.start()
        } catch {
            // Failed to start - reset state
            isHoldingMic = false
            transcriber.reset()
            
            // Resume wake word if enabled
            if settings.wakeWordEnabled {
                wakeWordDetector.startListening()
            }
            
            // Haptic feedback for error
            let errorGenerator = UINotificationFeedbackGenerator()
            errorGenerator.notificationOccurred(.error)
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
        guard !isHoldingMic && !isSettingsOpen else {
            return
        }
        
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
            // Don't start silence timer yet - wait until user starts speaking
        } catch {
            // Failed to start - reset state
            isHoldingMic = false
            isAutoListening = false
            transcriber.reset()
            
            if settings.wakeWordEnabled {
                wakeWordDetector.startListening()
            }
        }
        
        // Safety timeout after 60 seconds (in case user forgets)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if self.isAutoListening && self.transcriber.transcript.isEmpty {
                self.stopRecording()
                self.flow.prompt = String(localized: "Mic timed out. Tap to try again.")
            }
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        
        // Only use silence detection after user has started speaking
        let hasSpoken = !transcriber.transcript.isEmpty
        guard hasSpoken else { return }  // Don't timeout before speech
        
        // After speech detected, wait for 2 seconds of silence to auto-stop
        let silenceTimeout: TimeInterval = 2.0
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { _ in
            DispatchQueue.main.async {
                if self.isAutoListening {
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
        flow.prompt = String(localized: "Undone. Try again?")
    }
}
