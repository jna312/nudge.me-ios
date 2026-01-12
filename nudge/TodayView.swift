import SwiftUI
import SwiftData
import UserNotifications

struct RemindersView: View {
    @Environment(\.modelContext) private var modelContext
    
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
    @State private var showCelebration = false
    
    private let emptyStateMessages = [
        ("No Reminders", "checkmark.circle", "You're all caught up!"),
        ("All Clear", "sparkles", "Nothing to do. Enjoy the moment!"),
        ("Free Time", "sun.max", "Your schedule is wide open."),
        ("Well Done", "hand.thumbsup", "You've completed everything!"),
        ("Peace of Mind", "leaf", "No pending tasks. Relax.")
    ]
    
    private var randomEmptyState: (String, String, String) {
        emptyStateMessages[Int.random(in: 0..<emptyStateMessages.count)]
    }

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
                let state = randomEmptyState
                ContentUnavailableView(
                    state.0,
                    systemImage: state.1,
                    description: Text(state.2)
                )
            } else {
                List {
                    ForEach(groupedReminders, id: \.0) { section, items in
                        Section(section) {
                            ForEach(items) { reminder in
                                ReminderRow(reminder: reminder)
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
                            DisclosureGroup(isExpanded: \$isCompletedExpanded) {
                                ForEach(completedReminders) { reminder in
                                    CompletedReminderRow(reminder: reminder)
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
        .sheet(item: \$editingReminder) { reminder in
            EditReminderView(reminder: reminder)
        }
        .overlay {
            if showCelebration {
                CelebrationView()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation {
                                showCelebration = false
                            }
                        }
                    }
            }
        }
        .onChange(of: openReminders.count) { oldCount, newCount in
            if oldCount > 0 && newCount == 0 && completedReminders.count > 0 {
                withAnimation(.spring()) {
                    showCelebration = true
                }
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        }
    }
    
    private func deleteReminder(_ reminder: ReminderItem) {
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
        }
    }
}

struct ReminderRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var reminder: ReminderItem
    
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
    
    @State private var title: String = ""
    @State private var dueDate: Date = Date()
    @State private var hasAlert: Bool = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder") {
                    TextField("Title", text: \$title)
                }
                
                Section("When") {
                    DatePicker("Due Date", selection: \$dueDate, displayedComponents: [.date, .hourAndMinute])
                }
                
                Section("Alert") {
                    Toggle("Alert at due time", isOn: \$hasAlert)
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
            }
        }
    }
    
    private func saveChanges() {
        reminder.title = title
        reminder.dueAt = dueDate
        reminder.alertAt = hasAlert ? dueDate : nil
        
        Task {
            if hasAlert {
                await NotificationsManager.shared.schedule(reminder: reminder)
            } else {
                let notificationID = "\(reminder.id.uuidString)-alert"
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
            }
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

struct CelebrationView: View {
    @State private var particles: [ConfettiParticle] = []
    
    let emojis = ["🎉", "✨", "⭐️", "🌟", "🎊", "💫"]
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            ForEach(particles) { particle in
                Text(particle.emoji)
                    .font(.system(size: particle.size))
                    .position(particle.position)
                    .opacity(particle.opacity)
            }
            
            VStack(spacing: 16) {
                Text("🎉")
                    .font(.system(size: 60))
                
                Text("All Done!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                Text("You've completed all your reminders!")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .onAppear {
            startConfetti()
        }
    }
    
    private func startConfetti() {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        for i in 0..<30 {
            let particle = ConfettiParticle(
                id: i,
                emoji: emojis.randomElement()!,
                position: CGPoint(
                    x: CGFloat.random(in: 0...screenWidth),
                    y: -50
                ),
                size: CGFloat.random(in: 20...40),
                opacity: 1.0
            )
            particles.append(particle)
            
            withAnimation(.easeIn(duration: Double.random(in: 1.5...2.5)).delay(Double(i) * 0.05)) {
                if let index = particles.firstIndex(where: { \$0.id == i }) {
                    particles[index].position.y = screenHeight + 50
                    particles[index].position.x += CGFloat.random(in: -100...100)
                    particles[index].opacity = 0
                }
            }
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id: Int
    let emoji: String
    var position: CGPoint
    let size: CGFloat
    var opacity: Double
}
