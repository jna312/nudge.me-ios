import WidgetKit
import SwiftUI

struct NudgeWidgetEntry: TimelineEntry {
    let date: Date
    let reminders: [WidgetReminder]
}

struct WidgetReminder: Identifiable {
    let id: UUID
    let title: String
    let dueAt: Date
}

struct NudgeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NudgeWidgetEntry {
        NudgeWidgetEntry(date: Date(), reminders: [
            WidgetReminder(id: UUID(), title: "Sample reminder", dueAt: Date().addingTimeInterval(3600))
        ])
    }
    
    func getSnapshot(in context: Context, completion: @escaping (NudgeWidgetEntry) -> Void) {
        completion(NudgeWidgetEntry(date: Date(), reminders: loadReminders()))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<NudgeWidgetEntry>) -> Void) {
        let entry = NudgeWidgetEntry(date: Date(), reminders: loadReminders())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
    
    private func loadReminders() -> [WidgetReminder] {
        guard let defaults = UserDefaults(suiteName: "group.com.m2.nudge"),
              let data = defaults.data(forKey: "widgetReminders"),
              let decoded = try? JSONDecoder().decode([SharedReminder].self, from: data) else {
            return []
        }
        let now = Date()
        let endOfDay = Calendar.current.startOfDay(for: now).addingTimeInterval(86400)
        return decoded
            .filter { !$0.isCompleted && $0.dueAt >= now && $0.dueAt < endOfDay }
            .sorted { $0.dueAt < $1.dueAt }
            .prefix(5)
            .map { WidgetReminder(id: $0.id, title: $0.title, dueAt: $0.dueAt) }
    }
}

struct SharedReminder: Codable {
    let id: UUID
    let title: String
    let dueAt: Date
    let isCompleted: Bool
}

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

struct SmallWidgetView: View {
    let entry: NudgeWidgetEntry
    
    var body: some View {
        Link(destination: URL(string: "nudgeme://voice")!) {
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

struct MediumWidgetView: View {
    let entry: NudgeWidgetEntry
    
    var body: some View {
        HStack(spacing: 16) {
            Link(destination: URL(string: "nudgeme://voice")!) {
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
            VStack(alignment: .leading, spacing: 6) {
                if entry.reminders.isEmpty {
                    Text("No reminders today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(entry.reminders.prefix(3)) { reminder in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(formatTime(reminder.dueAt))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

struct LargeWidgetView: View {
    let entry: NudgeWidgetEntry
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("nudge.me")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Link(destination: URL(string: "nudgeme://voice")!) {
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
                        HStack(spacing: 12) {
                            Image(systemName: "circle")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(formatTime(reminder.dueAt))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: date)
    }
}

struct NudgeWidget: Widget {
    let kind: String = "NudgeWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NudgeTimelineProvider()) { entry in
            NudgeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("nudge.me")
        .description("Quick access to add reminders.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
