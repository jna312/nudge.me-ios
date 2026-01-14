import SwiftUI
import SwiftData

struct EditReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var reminder: ReminderItem
    let calendarSyncEnabled: Bool
    
    @State private var title: String = ""
    @State private var dueDate: Date = Date()
    @State private var hasAlert: Bool = true
    @State private var earlyAlertMinutes: Int = 0
    
    private let earlyAlertOptions: [(String, Int)] = [
        ("None", 0),
        ("5 minutes before", 5),
        ("15 minutes before", 15),
        ("30 minutes before", 30),
        ("1 hour before", 60),
        ("2 hours before", 120)
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Title", text: $title)
                }
                
                Section("When") {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Alerts") {
                    Toggle("Alert at due time", isOn: $hasAlert)
                    
                    Picker("Early warning", selection: $earlyAlertMinutes) {
                        ForEach(earlyAlertOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                    
                    Text("Get a \"Coming Up\" notification before your main alert.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section("Quick Snooze") {
                    HStack(spacing: 12) {
                        SnoozeButton(title: "10 min", color: .orange) {
                            dueDate = Date().addingTimeInterval(Duration.tenMinutes)
                        }
                        SnoozeButton(title: "30 min", color: .yellow) {
                            dueDate = Date().addingTimeInterval(Duration.thirtyMinutes)
                        }
                        SnoozeButton(title: "1 hour", color: .blue) {
                            dueDate = Date().addingTimeInterval(Duration.oneHour)
                        }
                        SnoozeButton(title: "1 day", color: .purple) {
                            dueDate = Date().addingTimeInterval(Duration.oneDay)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    
                    Button("Tomorrow at 9 AM") {
                        dueDate = tomorrowAt9AM()
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
                }
            }
            .navigationTitle("Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                title = reminder.title
                dueDate = reminder.dueAt ?? Date()
                hasAlert = reminder.alertAt != nil
                earlyAlertMinutes = reminder.earlyAlertMinutes ?? 0
            }
        }
    }
    
    private func saveChanges() {
        reminder.title = title
        reminder.dueAt = dueDate
        reminder.alertAt = hasAlert ? dueDate : nil
        reminder.earlyAlertMinutes = earlyAlertMinutes > 0 ? earlyAlertMinutes : nil
        
        Task {
            if hasAlert || earlyAlertMinutes > 0 {
                await NotificationsManager.shared.schedule(reminder: reminder)
            } else {
                NotificationsManager.shared.removeNotifications(for: reminder)
            }
            
            if calendarSyncEnabled {
                await CalendarSync.shared.syncToCalendar(reminder: reminder)
            }
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

struct SnoozeButton: View {
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            action()
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateModel {
    let title: String
    let systemImage: String
    let description: String
}

struct EmptyStateView: View {
    let state: EmptyStateModel
    
    var body: some View {
        ContentUnavailableView(
            state.title,
            systemImage: state.systemImage,
            description: Text(state.description)
        )
    }
}
