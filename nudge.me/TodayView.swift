import SwiftUI
import SwiftData

struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var settings: AppSettings
    @Binding var selectedReminderID: UUID?
    var onCapture: () -> Void
    @Query(filter: #Predicate<ReminderItem> { $0.statusRaw == "open" }, sort: \ReminderItem.dueAt)
    private var openReminders: [ReminderItem]
    @Query(filter: #Predicate<ReminderItem> { $0.statusRaw == "completed" }, sort: \ReminderItem.completedAt, order: .reverse)
    private var completedReminders: [ReminderItem]
    @State private var isCompletedExpanded = false
    @State private var editingReminder: ReminderItem?
    @State private var showSettings = false

    private struct ReminderSection: Identifiable {
        var id: String { title }
        let title: String
        let items: [ReminderItem]
    }

    private func groupedReminders(at now: Date) -> [ReminderSection] {
        let calendar = Calendar.current
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let grouped = Dictionary(grouping: openReminders) { reminder -> String in
            guard let due = reminder.dueAt else { return "No date" }
            if due < now { return "Overdue" }
            if calendar.isDateInToday(due) { return "Today" }
            if calendar.isDateInTomorrow(due) { return "Tomorrow" }
            return due < nextWeek ? "This week" : "Later"
        }
        return ["Overdue", "Today", "Tomorrow", "This week", "Later", "No date"].compactMap { title in
            grouped[title].map { ReminderSection(title: title, items: $0) }
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            List {
                if openReminders.isEmpty {
                    Label("No reminders", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8).listRowBackground(NudgeDesign.surface)
                }

                ForEach(groupedReminders(at: timeline.date)) { section in
                    Section {
                        ForEach(section.items) { reminder in
                            ReminderRow(reminder: reminder, calendarSyncEnabled: settings.calendarSyncEnabled,
                                onEdit: { editingReminder = reminder })
                                .listRowBackground(NudgeDesign.surface)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button { snooze(reminder, minutes: 10) } label: {
                                        Label("10 min", systemImage: "clock.arrow.circlepath")
                                    }.tint(NudgeDesign.accent)
                                    Button { snooze(reminder, minutes: 60) } label: {
                                        Label("1 hour", systemImage: "clock")
                                    }.tint(.indigo)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(reminder) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(section.title).font(.caption.weight(.semibold)).tracking(1)
                    }
                }
                if !completedReminders.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $isCompletedExpanded) {
                            ForEach(completedReminders) { reminder in
                                CompletedReminderRow(reminder: reminder, calendarSyncEnabled: settings.calendarSyncEnabled)
                                    .swipeActions {
                                        Button(role: .destructive) { delete(reminder) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                        } label: {
                            HStack {
                                Text("Completed").font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(completedReminders.count)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(NudgeDesign.surface)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(NudgeDesign.background)
        }
        .navigationTitle("Reminders")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: onCapture) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add reminder")
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Reminder settings")
            }
        }
        .sheet(item: $editingReminder) { reminder in
            EditReminderView(reminder: reminder, calendarSyncEnabled: settings.calendarSyncEnabled)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView(settings: settings).navigationTitle("Settings") }
        }
        .onAppear { openSelectedReminder() }
        .onChange(of: selectedReminderID) { _, _ in openSelectedReminder() }
        .tint(NudgeDesign.accent)
    }

    private func openSelectedReminder() {
        guard let id = selectedReminderID,
              let reminder = openReminders.first(where: { $0.id == id }) else { return }
        editingReminder = reminder
        selectedReminderID = nil
    }

    private func delete(_ reminder: ReminderItem) {
        NotificationsManager.shared.removeNotifications(for: reminder)
        Task { @MainActor in
            if settings.calendarSyncEnabled { await CalendarSync.shared.removeFromCalendar(reminder: reminder) }
            modelContext.delete(reminder)
            modelContext.saveWithLogging(context: "Deleting reminder")
            WidgetDataProvider.shared.syncReminders(from: modelContext)
        }
    }

    private func snooze(_ reminder: ReminderItem, minutes: Int) {
        reminder.dueAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        reminder.alertAt = reminder.dueAt
        modelContext.saveWithLogging(context: "Snoozing reminder")
        WidgetDataProvider.shared.syncReminders(from: modelContext)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await NotificationsManager.shared.schedule(reminder: reminder)
            if settings.calendarSyncEnabled { await CalendarSync.shared.syncToCalendar(reminder: reminder) }
        }
    }
}
struct ReminderRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var reminder: ReminderItem
    let calendarSyncEnabled: Bool
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: markComplete) {
                Image(systemName: "circle").font(.title2)
                    .foregroundStyle(NudgeDesign.accent).frame(width: 44, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(reminder.title)")
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(reminder.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if let due = reminder.dueAt {
                        Label(formatDueDate(due), systemImage: due < .now ? "exclamationmark.circle" : "clock")
                            .font(.subheadline)
                            .foregroundStyle(due < .now ? Color.red : Color.secondary)
                    }
                    if let early = reminder.earlyAlertMinutes, reminder.alertAt != nil {
                        Text("\(formatMinutes(early)) warning").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit reminder")
        }
        .padding(.vertical, 8)
    }
    private func markComplete() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            reminder.status = .completed
            reminder.completedAt = .now
            NotificationsManager.shared.removeNotifications(for: reminder)
        }
        modelContext.saveWithLogging(context: "Updating reminder completion")
        WidgetDataProvider.shared.syncReminders(from: modelContext)
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
    @Environment(\.modelContext) private var modelContext
    @Bindable var reminder: ReminderItem
    let calendarSyncEnabled: Bool
    var body: some View {
        HStack(spacing: 12) {
            Button {
                markIncomplete()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(NudgeDesign.accent)
                    .frame(width: 44, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reopen \(reminder.title)")
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
        modelContext.saveWithLogging(context: "Updating reminder completion")
        WidgetDataProvider.shared.syncReminders(from: modelContext)
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
