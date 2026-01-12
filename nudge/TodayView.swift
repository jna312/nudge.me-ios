import SwiftUI
import SwiftData
import UserNotifications

struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var settings: AppSettings
    
    @Query(
        filter: #Predicate<ReminderItem> { $0.statusRaw == "open" },
        sort: \ReminderItem.dueAt
    ) private var openReminders: [ReminderItem]
    
    @Query(
        filter: #Predicate<ReminderItem> { $0.statusRaw == "completed" },
        sort: \ReminderItem.completedAt,
        order: .reverse
    ) private var completedReminders: [ReminderItem]
    
    @State private var isCompletedExpanded = false
    @State private var editingReminder: ReminderItem?
    @State private var showSettings = false
    
    private let emptyStateMessages = [
        ("No Reminders", "checkmark.circle", "You're all caught up!"),
        ("All Clear", "sparkles", "Nothing to do. Enjoy the moment!"),
        ("Free Time", "sun.max", "Your schedule is wide open."),
        ("Well Done", "hand.thumbsup", "You've completed everything!"),
        ("Peace of Mind", "leaf", "No pending tasks. Relax.")
    ]
    
    @State private var emptyState: (title: String, image: String, description: String)? = nil
    
    @ViewBuilder
    private var emptyStateView: some View {
        let state = emptyState ?? (emptyStateMessages.first ?? ("No Reminders", "checkmark.circle", "You're all caught up!"))
        ContentUnavailableView(
            state.title,
            systemImage: state.image,
            description: Text(state.description)
        )
    }
    
    private struct ReminderSection: Identifiable {
        let id = UUID()
        let title: String
        let items: [ReminderItem]
    }
    
    private var groupedReminders: [ReminderSection] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let startOfNextWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday)!

        var overdue: [ReminderItem] = []
        var today: [ReminderItem] = []
        var tomorrow: [ReminderItem] = []
        var thisWeek: [ReminderItem] = []
        var later: [ReminderItem] = []
        var noDue: [ReminderItem] = []

        for reminder in openReminders {
            guard let due = reminder.dueAt else {
                noDue.append(reminder)
                continue
            }

            if due < startOfToday {
                overdue.append(reminder)
            } else if due < startOfTomorrow {
                today.append(reminder)
            } else if due < calendar.date(byAdding: .day, value: 2, to: startOfToday)! {
                tomorrow.append(reminder)
            } else if due < startOfNextWeek {
                thisWeek.append(reminder)
            } else {
                later.append(reminder)
            }
        }

        var sections: [ReminderSection] = []
        if !overdue.isEmpty { sections.append(ReminderSection(title: "Overdue", items: overdue)) }
        if !today.isEmpty { sections.append(ReminderSection(title: "Today", items: today)) }
        if !tomorrow.isEmpty { sections.append(ReminderSection(title: "Tomorrow", items: tomorrow)) }
        if !thisWeek.isEmpty { sections.append(ReminderSection(title: "This Week", items: thisWeek)) }
        if !later.isEmpty { sections.append(ReminderSection(title: "Later", items: later)) }
        if !noDue.isEmpty { sections.append(ReminderSection(title: "No Date", items: noDue)) }
        return sections
    }

    var body: some View {
        NavigationStack {
            Group {
                if openReminders.isEmpty && completedReminders.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(groupedReminders) { section in
                            Section(section.title) {
                                ForEach(section.items) { reminder in
                                    ReminderRow(reminder: reminder, calendarSyncEnabled: settings.calendarSyncEnabled)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            editingReminder = reminder
                                        }
                                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                            Button {
                                                snoozeReminder(reminder, minutes: 10)
                                            } label: {
                                                Label("10 min", systemImage: "clock.arrow.circlepath")
                                            }
                                            .tint(.orange)
                                            
                                            Button {
                                                snoozeReminder(reminder, minutes: 60)
                                            } label: {
                                                Label("1 hour", systemImage: "clock")
                                            }
                                            .tint(.blue)
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            Button(role: .destructive) {
                                                deleteReminder(reminder)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                        
                        if !completedReminders.isEmpty {
                            Section {
                                DisclosureGroup(isExpanded: $isCompletedExpanded) {
                                    ForEach(completedReminders) { reminder in
                                        CompletedReminderRow(reminder: reminder, calendarSyncEnabled: settings.calendarSyncEnabled)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button(role: .destructive) {
                                                    deleteReminder(reminder)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                    }
                                } label: {
                                    HStack {
                                        Text("Completed")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text("\(completedReminders.count)")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(item: $editingReminder) { reminder in
            EditReminderView(reminder: reminder, calendarSyncEnabled: settings.calendarSyncEnabled)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(settings: settings)
            }
        }
        .onAppear {
            if emptyState == nil {
                let pick = emptyStateMessages[Int.random(in: 0..<emptyStateMessages.count)]
                emptyState = (title: pick.0, image: pick.1, description: pick.2)
            }
        }
    }
    
    private func deleteReminder(_ reminder: ReminderItem) {
        if settings.calendarSyncEnabled {
            Task {
                await CalendarSync.shared.removeFromCalendar(reminder: reminder)
            }
        }
        
        withAnimation {
            let notificationID = "\(reminder.id.uuidString)-alert"
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
            modelContext.delete(reminder)
        }
    }
    
    private func snoozeReminder(_ reminder: ReminderItem, minutes: Int) {
        let newDue = Date().addingTimeInterval(TimeInterval(minutes * 60))
        reminder.dueAt = newDue
        reminder.alertAt = newDue
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        Task {
            await NotificationsManager.shared.schedule(reminder: reminder)
            
            if settings.calendarSyncEnabled {
                await CalendarSync.shared.syncToCalendar(reminder: reminder)
            }
        }
    }
}

struct ReminderRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var reminder: ReminderItem
    let calendarSyncEnabled: Bool
    
    private var urgencyColor: Color {
        guard let due = reminder.dueAt else { return .secondary }
        let calendar = Calendar.current
        let now = Date()
        
        if due < calendar.startOfDay(for: now) {
            return .red
        } else if calendar.isDateInToday(due) {
            return .orange
        } else if calendar.isDateInTomorrow(due) {
            return .blue
        } else {
            return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                markComplete()
            } label: {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(urgencyColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body)

                if let due = reminder.dueAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(formatDueDate(due))
                            .font(.caption)
                    }
                    .foregroundStyle(urgencyColor)
                }
            }
            
            Spacer()
            
            Circle()
                .fill(urgencyColor)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }
    
    private func markComplete() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            reminder.status = .completed
            reminder.completedAt = .now
            
            let notificationID = "\(reminder.id.uuidString)-alert"
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        }
        
        if calendarSyncEnabled {
            Task {
                await CalendarSync.shared.removeFromCalendar(reminder: reminder)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let successGenerator = UINotificationFeedbackGenerator()
            successGenerator.notificationOccurred(.success)
        }
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today at \(formatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Tomorrow at \(formatter.string(from: date))"
        } else if date < now {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
            return formatter.string(from: date)
        }
    }
}

struct CompletedReminderRow: View {
    @Bindable var reminder: ReminderItem
    let calendarSyncEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                markIncomplete()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body)
                    .strikethrough()
                    .foregroundStyle(.secondary)

                if let completedAt = reminder.completedAt {
                    Text("Completed \(formatCompletedDate(completedAt))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func markIncomplete() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        withAnimation {
            reminder.status = .open
            reminder.completedAt = nil
            
            if let alertAt = reminder.alertAt, alertAt > Date() {
                Task {
                    await NotificationsManager.shared.schedule(reminder: reminder)
                }
            }
        }
        
        if calendarSyncEnabled {
            Task {
                await CalendarSync.shared.syncToCalendar(reminder: reminder)
            }
        }
    }
    
    private func formatCompletedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "today at \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "yesterday at \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

struct EditReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var reminder: ReminderItem
    let calendarSyncEnabled: Bool
    
    @State private var title: String = ""
    @State private var dueDate: Date = Date()
    @State private var hasAlert: Bool = true
    @State private var earlyAlertMinutes: Int = 0  // 0 = none
    
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
                    
                    if earlyAlertMinutes > 0 {
                        HStack {
                            Image(systemName: "bell.badge")
                                .foregroundStyle(.orange)
                            Text("You'll get a heads up \(formatEarlyAlert(earlyAlertMinutes)) before")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section {
                    Button("Snooze 1 Hour") {
                        dueDate = Date().addingTimeInterval(3600)
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                    }
                    
                    Button("Snooze to Tomorrow 9 AM") {
                        let calendar = Calendar.current
                        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
                        dueDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
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
    
    private func formatEarlyAlert(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
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
