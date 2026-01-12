import SwiftUI
import SwiftData
import UserNotifications

struct RemindersView: View {
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

    private var groupedReminders: [(String, [ReminderItem])] {
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

        var result: [(String, [ReminderItem])] = []
        if !overdue.isEmpty { result.append(("Overdue", overdue)) }
        if !today.isEmpty { result.append(("Today", today)) }
        if !tomorrow.isEmpty { result.append(("Tomorrow", tomorrow)) }
        if !thisWeek.isEmpty { result.append(("This Week", thisWeek)) }
        if !later.isEmpty { result.append(("Later", later)) }
        if !noDue.isEmpty { result.append(("No Date", noDue)) }

        return result
    }

    var body: some View {
        Group {
            if openReminders.isEmpty && completedReminders.isEmpty {
                ContentUnavailableView(
                    "No Reminders",
                    systemImage: "checkmark.circle",
                    description: Text("You're all caught up!")
                )
            } else {
                List {
                    // Open reminders grouped by date
                    ForEach(groupedReminders, id: \.0) { section, items in
                        Section(section) {
                            ForEach(items) { reminder in
                                ReminderRow(reminder: reminder)
                            }
                        }
                    }
                    
                    // Completed reminders (collapsible)
                    if !completedReminders.isEmpty {
                        Section {
                            DisclosureGroup(isExpanded: $isCompletedExpanded) {
                                ForEach(completedReminders) { reminder in
                                    CompletedReminderRow(reminder: reminder)
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
    }
}

struct ReminderRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var reminder: ReminderItem
    
    var isOverdue: Bool {
        guard let due = reminder.dueAt else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                markComplete()
            } label: {
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(isOverdue ? .red : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.body)
                    .foregroundStyle(isOverdue ? .primary : .primary)

                if let due = reminder.dueAt {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(formatDueDate(due))
                            .font(.caption)
                    }
                    .foregroundStyle(isOverdue ? .red : .secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func markComplete() {
        withAnimation {
            reminder.status = .completed
            reminder.completedAt = .now
            
            // Cancel any pending notification
            let notificationID = "\(reminder.id.uuidString)-alert"
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
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
    let reminder: ReminderItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

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
