import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Entry

struct NudgeWidgetEntry: TimelineEntry {
    let date: Date
    let reminders: [WidgetReminder]
}

struct WidgetReminder: Identifiable {
    let id: UUID
    let title: String
    let dueAt: Date
    let isCompleted: Bool
}

// MARK: - Timeline Provider

struct NudgeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NudgeWidgetEntry {
        NudgeWidgetEntry(
            date: Date(),
            reminders: [
                WidgetReminder(id: UUID(), title: "Walk the dog", dueAt: Date().addingTimeInterval(3600), isCompleted: false),
                WidgetReminder(id: UUID(), title: "Call mom", dueAt: Date().addingTimeInterval(7200), isCompleted: false),
                WidgetReminder(id: UUID(), title: "Buy groceries", dueAt: Date().addingTimeInterval(10800), isCompleted: false)
            ]
        )
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NudgeWidgetEntry) -> Void) {
        let entry = NudgeWidgetEntry(
            date: Date(),
            reminders: loadReminders()
        )
        completion(entry)
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NudgeWidgetEntry>) -> Void) {
        let currentDate = Date()
        let reminders = loadReminders()
        
        let entry = NudgeWidgetEntry(date: currentDate, reminders: reminders)
        
        // Update every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate) ?? currentDate.addingTimeInterval(900)
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        
        completion(timeline)
    }
    
    private func loadReminders() -> [WidgetReminder] {
        // Load from App Group shared UserDefaults
        guard let sharedDefaults = UserDefaults(suiteName: "group.com.nudge.app") else {
            return []
        }
        
        guard let data = sharedDefaults.data(forKey: "widgetReminders"),
              let decoded = try? JSONDecoder().decode([SharedReminder].self, from: data) else {
            return []
        }
        
        let now = Date()
        let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        
        return decoded
            .filter { !$0.isCompleted && $0.dueAt >= now && $0.dueAt < endOfDay }
            .sorted { $0.dueAt < $1.dueAt }
            .prefix(5)
            .map { WidgetReminder(id: $0.id, title: $0.title, dueAt: $0.dueAt, isCompleted: $0.isCompleted) }
    }
}

// Shared reminder struct for encoding/decoding
struct SharedReminder: Codable {
    let id: UUID
    let title: String
    let dueAt: Date
    let isCompleted: Bool
}

// MARK: - Widget Views

struct NudgeWidgetEntryView: View {
    var entry: NudgeTimelineProvider.Entry
    @Environment(\.widgetFamily) var family
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget (Tap to Speak only)

struct SmallWidgetView: View {
    let entry: NudgeWidgetEntry
    
    var body: some View {
        Link(destination: URL(string: "nudge://voice")!) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                }
                
                Text("Tap to speak")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                if !entry.reminders.isEmpty {
                    Text("\(entry.reminders.count) today")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: - Medium Widget (Tap to Speak + 3 Reminders)

struct MediumWidgetView: View {
    let entry: NudgeWidgetEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side: Mic button
            Link(destination: URL(string: "nudge://voice")!) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
                    
                    Text("Tap to speak")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .frame(width: 80)
            }
            
            Divider()
            
            // Right side: Reminders list
            VStack(alignment: .leading, spacing: 6) {
                if entry.reminders.isEmpty {
                    Text("No reminders today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(entry.reminders.prefix(3)) { reminder in
                        Link(destination: URL(string: "nudge://reminder/\(reminder.id.uuidString)")!) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reminder.title)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)
                                    
                                    Text(formatTime(reminder.dueAt))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    if entry.reminders.count > 3 {
                        Text("+\(entry.reminders.count - 3) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Large Widget (Tap to Speak + 5 Reminders)

struct LargeWidgetView: View {
    let entry: NudgeWidgetEntry
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with mic button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nudge")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text(formattedDate())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Link(destination: URL(string: "nudge://voice")!) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                }
            }
            
            Divider()
            
            // Reminders list
            if entry.reminders.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("All done for today!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                VStack(spacing: 8) {
                    ForEach(entry.reminders.prefix(5)) { reminder in
                        ReminderRowView(reminder: reminder)
                    }
                    
                    if entry.reminders.count > 5 {
                        Link(destination: URL(string: "nudge://reminders")!) {
                            Text("View all \(entry.reminders.count) reminders")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer(minLength: 0)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
}

struct ReminderRowView: View {
    let reminder: WidgetReminder
    
    var body: some View {
        Link(destination: URL(string: "nudge://reminder/\(reminder.id.uuidString)")!) {
            HStack(spacing: 12) {
                Image(systemName: "circle")
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    Text(formatTime(reminder.dueAt))
                        .font(.caption2)
                        .foregroundColor(isPastDue(reminder.dueAt) ? .red : .secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func isPastDue(_ date: Date) -> Bool {
        date < Date()
    }
}

// MARK: - Widget Configuration

struct NudgeWidget: Widget {
    let kind: String = "NudgeWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NudgeTimelineProvider()) { entry in
            NudgeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Nudge")
        .description("Quick access to add reminders and see today's tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    NudgeWidget()
} timeline: {
    NudgeWidgetEntry(date: Date(), reminders: [])
    NudgeWidgetEntry(date: Date(), reminders: [
        WidgetReminder(id: UUID(), title: "Walk the dog", dueAt: Date().addingTimeInterval(3600), isCompleted: false)
    ])
}

#Preview(as: .systemMedium) {
    NudgeWidget()
} timeline: {
    NudgeWidgetEntry(date: Date(), reminders: [
        WidgetReminder(id: UUID(), title: "Walk the dog", dueAt: Date().addingTimeInterval(3600), isCompleted: false),
        WidgetReminder(id: UUID(), title: "Call mom", dueAt: Date().addingTimeInterval(7200), isCompleted: false),
        WidgetReminder(id: UUID(), title: "Buy groceries", dueAt: Date().addingTimeInterval(10800), isCompleted: false)
    ])
}
