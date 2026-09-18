import SwiftUI
import SwiftData

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    let settings: AppSettings
    let modelContext: ModelContext
    let calendarSyncEnabled: Bool
    var onDismiss: () -> Void
    var onSave: (ReminderItem) -> Void = { _ in }
    
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var title = ""
    @State private var dueDate = Date().addingTimeInterval(Duration.oneHour)
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
                            QuickTimeButton(label: "30 min", date: Date().addingTimeInterval(Duration.thirtyMinutes), selection: $dueDate)
                            QuickTimeButton(label: "1 hour", date: Date().addingTimeInterval(Duration.oneHour), selection: $dueDate)
                            QuickTimeButton(label: "3 hours", date: Date().addingTimeInterval(Duration.threeHours), selection: $dueDate)
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
                        Task { await addReminder() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dueDate <= .now)
                }
            }
            .onAppear {
                isTitleFocused = true
                earlyAlertMinutes = settings.defaultEarlyAlertMinutes
                
            }
            .scrollContentBackground(.hidden)
            .background(NudgeDesign.background)
            .alert("Couldn’t save reminder", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }

        }
        .tint(NudgeDesign.accent)
    }

    private func addReminder() async {
        isSaving = true
        defer { isSaving = false }
        let styledTitle = applyWritingStyle(title, style: settings.writingStyle)
        
        let item = ReminderItem(
            title: styledTitle,
            dueAt: dueDate,
            alertAt: hasAlert ? dueDate : nil,
            earlyAlertMinutes: earlyAlertMinutes > 0 ? earlyAlertMinutes : nil
        )
        
        modelContext.insert(item)
        
        do { try modelContext.save() }
        catch {
            modelContext.delete(item)
            saveError = error.localizedDescription
            return
        }
        if hasAlert {
            await NotificationsManager.shared.requestPermission()
            await NotificationsManager.shared.schedule(reminder: item)
        }
        if calendarSyncEnabled { await CalendarSync.shared.syncToCalendar(reminder: item) }
        WidgetDataProvider.shared.syncReminders(from: modelContext)
        await MorningBriefingManager.shared.scheduleIfNeeded(settings: settings, modelContext: modelContext)
        onSave(item)
        dismiss()
        onDismiss()

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
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
        .tint(Calendar.current.isDate(selection, equalTo: date, toGranularity: .minute) ? NudgeDesign.accent : .secondary)
    }
}
