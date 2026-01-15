import SwiftUI
import SwiftData
import UserNotifications
struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedReminderID: UUID?
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
    @ObservedObject private var tipsManager = TipsManager.shared
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
                                                snoozeReminder(reminder, minutes: 30)
                                            } label: {
                                                Label("30 min", systemImage: "clock.arrow.circlepath")
                                            }
                                            .tint(.yellow)
                                            Button {
                                                snoozeReminder(reminder, minutes: 60)
                                            } label: {
                                                Label("1 hour", systemImage: "clock")
                                            }
                                            .tint(.blue)
                                            Button {
                                                snoozeReminder(reminder, minutes: 1440) // 24 hours
                                            } label: {
                                                Label("1 day", systemImage: "calendar")
                                            }
                                            .tint(.purple)
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
            // Show swipe actions tip when there are reminders
            if !openReminders.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if tipsManager.currentTip == nil {
                        tipsManager.showTipIfNeeded(.swipeActions)
                    }
                }
            }
        }
        .onChange(of: selectedReminderID) { _, newID in
            if let id = newID,
               let reminder = openReminders.first(where: { $0.id == id }) {
                editingReminder = reminder
                selectedReminderID = nil
            }
        }
        .overlay {
            // Tip overlay
            if let tip = tipsManager.currentTip {
                TipOverlay(tip: tip) {
                    tipsManager.dismissTip(tip.id)
                }
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
        
            
            // Sync to widget
            WidgetDataProvider.shared.syncReminders(from: modelContext)
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
        
        // Sync to widget
        WidgetDataProvider.shared.syncReminders(from: modelContext)
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
