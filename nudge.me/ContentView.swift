import SwiftUI
import SwiftData
import UserNotifications

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @EnvironmentObject var settings: AppSettings
    @Binding var isSettingsOpen: Bool
    @Binding var autoStartMic: Bool
    @ObservedObject var flow: CaptureFlow
    @ObservedObject var transcriber: SpeechTranscriber
    var onShowReminders: () -> Void
    @Query(filter: #Predicate<ReminderItem> { $0.statusRaw == "open" }, sort: \ReminderItem.dueAt)
    private var reminders: [ReminderItem]

    @State private var showTextEntry = false
    @State private var showQuickAdd = false
    @State private var editingReminder: ReminderItem?
    @State private var savedReminder: ReminderItem?
    @State private var isCapturing = false
    @State private var isHolding = false
    @State private var isFinishing = false
    @State private var isStarting = false
    @State private var isVisible = false
    @FocusState private var isEditingDraft: Bool
    @State private var captureGeneration = UUID()
    @State private var captureTask: Task<Void, Never>?
    @State private var captureTimeout: Task<Void, Never>?
    @State private var notice: String?
    @State private var alertStatus = ""
    @State private var chosenPeriod = ""

    private var isBusy: Bool { isStarting || isFinishing }
    private var isFollowingUp: Bool { flow.step != .idle }
    private var upNext: ReminderItem? {
        reminders.first { ($0.dueAt ?? .distantPast) > .now }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let savedReminder, !isCapturing, !isFollowingUp {
                        savedContent(savedReminder)
                    } else if isFollowingUp && !isCapturing {
                        followUpContent
                    } else {
                        captureContent
                            .frame(minHeight: transcriber.lastError == nil && notice == nil
                                ? max(0, geometry.size.height - 28) : 0)
                    }

                    if let message = transcriber.lastError ?? notice {
                        NudgeCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label(message, systemImage: "exclamationmark.circle")
                                    .font(.subheadline)
                                HStack {
                                    Button("Type instead") { showTextEntry = true }
                                    Spacer()
                                    Button("Settings") {
                                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                        .accessibilityIdentifier("capture.notice")
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NudgeDesign.background.ignoresSafeArea())
        // Reserve real layout space: content never sits behind the thumb-zone controls.
        .safeAreaInset(edge: .top, spacing: 0) { captureHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) { captureDock }
        .toolbar(.hidden, for: .navigationBar)
        .tint(NudgeDesign.accent)
        .sheet(isPresented: $showTextEntry) {
            CaptureTextEntry(initialText: transcriber.lastError == nil ? "" : transcriber.transcript,
                isFollowUp: isFollowingUp, onSubmit: { text in
                    showTextEntry = false
                    submit(text)
                }, onManualEntry: {
                    showTextEntry = false
                    // Present after the first sheet finishes dismissing.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        guard isVisible else { return }
                        showQuickAdd = true
                    }
                })
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView(settings: settings, modelContext: modelContext,
                calendarSyncEnabled: settings.calendarSyncEnabled, onDismiss: {}, onSave: { reminder in
                    flow.reset()
                    showReceipt(reminder)
                })
        }
        .sheet(item: $editingReminder, onDismiss: {
            if let reminder = savedReminder { refreshAlertStatus(reminder) }
        }) { reminder in
            EditReminderView(reminder: reminder, calendarSyncEnabled: settings.calendarSyncEnabled)
        }
        .onAppear {
            isVisible = true
            NotificationsManager.shared.registerCategories()
            NotificationsManager.shared.onNotificationWillPresent = {
                guard isVisible else { return }
                cancelCapture()
            }
            if autoStartMic { consumeAutoStart() }
        }
        .onDisappear {
            isVisible = false
            cancelCapture()
            savedReminder = nil
            NotificationsManager.shared.onNotificationWillPresent = nil
        }
        .onChange(of: autoStartMic) { _, start in if start && isVisible { consumeAutoStart() } }
        .onChange(of: isSettingsOpen) { _, open in if open { cancelCapture() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { cancelCapture() } }
        .onChange(of: flow.lastSavedReminder) { _, reminder in
            if let reminder { showReceipt(reminder) }
        }
        .onChange(of: flow.ambiguousTime) { _, _ in chosenPeriod = "" }
        .onChange(of: transcriber.isRecording) { _, recording in
            // A final result or audio interruption can end recording without a touch.
            if !recording && isCapturing && !isFinishing { finishRecording() }
        }
    }

    private var captureHeader: some View {
        HStack {
            Text("nudge.me").font(.headline)
            Spacer()
            Button {
                if isFollowingUp {
                    cancelCapture(); flow.reset(); transcriber.reset(); savedReminder = nil
                } else {
                    isSettingsOpen = true
                }
            } label: {
                Image(systemName: isFollowingUp ? "xmark" : "slider.horizontal.3")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
                    .background(NudgeDesign.surface, in: Circle())
            }
            .foregroundStyle(.primary)
            .accessibilityLabel(isFollowingUp ? "Cancel reminder" : "Capture settings")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(NudgeDesign.background.ignoresSafeArea(edges: .top))
    }

    private var captureContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isCapturing || isFinishing || !transcriber.transcript.isEmpty {
                Text(isFinishing ? "Processing…" : "Listening…")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(transcriber.transcript.isEmpty ? "…" : transcriber.transcript)
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 24)
                Text("What’s the reminder?")
                    .font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 24)
                if let reminder = upNext {
                    Button { editingReminder = reminder } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reminder.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                if let due = reminder.dueAt {
                                    Text("\(NudgeDesign.dayLabel(due)) · \(formatTimeShort(due))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edit your next reminder")
                }
            }
        }
    }

    private var microphone: some View {
        CaptureMicButton(isRecording: isCapturing, isBusy: isFinishing,
            onTap: {
                if isCapturing { finishRecording() } else { startRecording(holding: false) }
            }, onHoldStart: {
                if isCapturing { isHolding = true } else { startRecording(holding: true) }
            }, onHoldEnd: {
                if isHolding { finishRecording() }
            })
    }

    private var captureDock: some View {
        VStack(spacing: 2) {
            if let time = flow.ambiguousTime, !isCapturing, !isBusy {
                HStack(spacing: 18) {
                    microphone.scaleEffect(0.72).frame(width: 96, height: 100)
                    Button("Save") {
                        submit("\(time) \(chosenPeriod)")
                    }
                    .buttonStyle(NudgePrimaryButtonStyle())
                    .disabled(chosenPeriod.isEmpty)
                    .opacity(chosenPeriod.isEmpty ? 0.5 : 1)
                }
                .padding(.horizontal, 20)
            } else {
                microphone
                Text(isStarting ? "Getting ready…" : isFinishing ? "Finishing…" : isCapturing
                    ? (isHolding ? "Release to finish" : "Tap to finish")
                    : "Tap or hold")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button {
                cancelCapture()
                showTextEntry = true
            } label: {
                Label("Type", systemImage: "keyboard")
                    .font(.subheadline).frame(minHeight: 44)
            }
            .accessibilityLabel(isFollowingUp ? "Type your answer" : "Type a reminder")
            .foregroundStyle(.secondary)
            .disabled(isFinishing)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(NudgeDesign.background.ignoresSafeArea(edges: .bottom))
    }

    private var followUpContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(flow.ambiguousTime == nil ? flow.prompt : String(localized: "AM or PM?"))
                .font(.headline)
            NudgeCard {
                VStack(alignment: .leading, spacing: 16) {
                    if let title = flow.draftTitle {
                        TextField("Reminder title", text: Binding(get: { flow.draftTitle ?? title }, set: flow.updateDraftTitle))
                            .font(.headline)
                            .accessibilityIdentifier("capture.draftTitle")
                            .focused($isEditingDraft)
                            .submitLabel(.done)
                            .onSubmit { isEditingDraft = false }
                    }
                    if let day = flow.draftDate {
                        Divider()
                        Label(NudgeDesign.exactDate(day), systemImage: "calendar")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let time = flow.ambiguousTime {
                        Divider()
                        ViewThatFits(in: .horizontal) {
                            HStack { periodChoices(time) }
                            VStack(alignment: .leading) { periodChoices(time) }
                        }
                    }
                    if let early = flow.pendingEarlyAlertMinutes {
                        Divider()
                        Label("\(formatMinutes(early)) before", systemImage: "bell")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if flow.ambiguousTime == nil {
                switch flow.step {
                case .confirmDuplicate, .confirmEdit, .confirmCancel:
                    HStack {
                        Button("Cancel") { submit("no") }.buttonStyle(.bordered).controlSize(.large)
                        Button("Confirm") { submit("yes") }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                case .calendarConflict:
                    Button("Save anyway") { submit("save anyway") }.buttonStyle(NudgePrimaryButtonStyle())
                    Button("Choose another time") { submit("change time") }.frame(minHeight: 44)
                default:
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder private func periodChoices(_ time: String) -> some View {
        Label(chosenPeriod.isEmpty ? time : "\(time) \(chosenPeriod)", systemImage: "clock")
        Spacer(minLength: 8)
        HStack(spacing: 8) {
            ForEach(["AM", "PM"], id: \.self) { period in
                Button(period) { isEditingDraft = false; chosenPeriod = period }
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 48, minHeight: 44)
                    .background(chosenPeriod == period ? NudgeDesign.softAccent : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityAddTraits(chosenPeriod == period ? .isSelected : [])
            }
        }
    }

    private func savedContent(_ reminder: ReminderItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.headline).foregroundStyle(NudgeDesign.accent)
            NudgeCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text(reminder.title).font(.headline)
                    if let due = reminder.dueAt {
                        Text("\(NudgeDesign.exactDate(due)) at \(formatTimeShort(due))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Label(alertStatus, systemImage: "bell")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let early = reminder.earlyAlertAt, reminder.alertAt != nil {
                        Text("Early warning: \(early.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Edit") { editingReminder = reminder }.frame(minHeight: 44)
                        Spacer()
                        Button("Undo", role: .destructive) { undo(reminder) }.frame(minHeight: 44)
                            .accessibilityLabel("Undo reminder")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            Button("View reminders", action: onShowReminders)
                .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func consumeAutoStart() {
        autoStartMic = false
        startRecording(holding: false)
    }

    private func startRecording(holding: Bool) {
        guard !isCapturing, !isBusy, !isSettingsOpen, isVisible else { return }
        savedReminder = nil; notice = nil; isHolding = holding; isStarting = true
        let generation = UUID()
        captureGeneration = generation
        captureTask = Task { @MainActor in
            let permitted = await transcriber.requestPermissions()
            guard captureGeneration == generation else { return }
            guard !Task.isCancelled, isVisible else { isStarting = false; return }
            isStarting = false
            guard permitted else { isHolding = false; return }
            do {
                try transcriber.start()
                isCapturing = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                captureTimeout = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled, captureGeneration == generation else { return }
                    finishRecording()
                }
            } catch {
                transcriber.lastError = error.localizedDescription
                isCapturing = false; isHolding = false
            }
        }
    }

    private func finishRecording() {
        if isStarting { cancelCapture(); return }
        guard isCapturing, !isFinishing else { return }
        isFinishing = true; isCapturing = false; isHolding = false
        captureTimeout?.cancel()
        let generation = UUID()
        captureGeneration = generation
        captureTask = Task { @MainActor in
            defer { if captureGeneration == generation { isFinishing = false } }
            do {
                let text = try await transcriber.finish()
                guard !Task.isCancelled, isVisible, captureGeneration == generation else { return }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    notice = String(localized: "I didn’t hear anything. Try again or type a reminder.")
                    return
                }
                await flow.handleTranscript(text, settings: settings, modelContext: modelContext)
                transcriber.transcript = ""
            } catch is CancellationError {
                // Leaving the screen cancels capture without submitting a partial reminder.
            } catch {
                if captureGeneration == generation { transcriber.lastError = error.localizedDescription }
            }
        }
    }

    private func submit(_ text: String) {
        guard !isBusy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        savedReminder = nil; notice = nil; transcriber.reset(); isFinishing = true
        isEditingDraft = false
        let generation = UUID()
        captureGeneration = generation
        captureTask = Task { @MainActor in
            await flow.handleTranscript(text, settings: settings, modelContext: modelContext)
            if captureGeneration == generation { isFinishing = false }
        }
    }

    private func cancelCapture() {
        captureGeneration = UUID()
        captureTask?.cancel(); captureTimeout?.cancel()
        isCapturing = false; isHolding = false; isStarting = false; isFinishing = false
        transcriber.stop()
    }

    private func showReceipt(_ reminder: ReminderItem) {
        savedReminder = reminder
        transcriber.transcript = ""
        notice = nil
        refreshAlertStatus(reminder)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func refreshAlertStatus(_ reminder: ReminderItem) {
        alertStatus = String(localized: "Checking alert…")
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let permission = await center.notificationSettings()
            let requests = await center.pendingNotificationRequests()
            guard savedReminder?.id == reminder.id else { return }
            if reminder.alertAt == nil {
                alertStatus = String(localized: "No alert")
            } else if permission.authorizationStatus == .denied || permission.authorizationStatus == .notDetermined {
                alertStatus = String(localized: "Notifications off in Settings")
            } else if requests.contains(where: { $0.identifier == "\(reminder.id.uuidString)-alert" }) {
                alertStatus = String(localized: "Alert scheduled")
            } else {
                alertStatus = String(localized: "Alert not scheduled")
            }
        }
    }

    private func undo(_ reminder: ReminderItem) {
        Task { @MainActor in
            NotificationsManager.shared.removeNotifications(for: reminder)
            if settings.calendarSyncEnabled { await CalendarSync.shared.removeFromCalendar(reminder: reminder) }
            modelContext.delete(reminder)
            do {
                try modelContext.save()
                WidgetDataProvider.shared.syncReminders(from: modelContext)
                await MorningBriefingManager.shared.scheduleIfNeeded(settings: settings, modelContext: modelContext)
                savedReminder = nil; flow.lastSavedReminder = nil; flow.reset()
                notice = nil
            } catch {
                modelContext.rollback()
                notice = String(localized: "Couldn’t undo the reminder. Please try again.")
            }
        }
    }
}

private struct CaptureTextEntry: View {
    @Environment(\.dismiss) private var dismiss
    @State var initialText: String
    let isFollowUp: Bool
    let onSubmit: (String) -> Void
    let onManualEntry: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(isFollowUp ? "Your answer" : "Remind me to…", text: $initialText, axis: .vertical)
                        .lineLimit(2...6).focused($focused)
                        .padding(16).background(NudgeDesign.surface, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("capture.typedReminder")
                    if !isFollowUp {
                        Button("Choose date & time", action: onManualEntry)
                            .font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NudgeDesign.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(isFollowUp ? "Continue" : "Add reminder") { onSubmit(initialText) }
                    .buttonStyle(NudgePrimaryButtonStyle())
                    .disabled(initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(initialText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                    .background(NudgeDesign.background)
            }
            .navigationTitle(isFollowUp ? "Reply" : "New reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { focused = true }
        }
        .tint(NudgeDesign.accent)
    }
}
