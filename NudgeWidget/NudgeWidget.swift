import WidgetKit
import SwiftUI
import AppIntents

private let voiceURL = URL(string: "nudgeme://voice")!
private let remindersURL = URL(string: "nudgeme://reminders")!

struct NudgeWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct NudgeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NudgeWidgetEntry { Self.preview }

    func getSnapshot(in context: Context, completion: @escaping (NudgeWidgetEntry) -> Void) {
        let now = Date()
        completion(context.isPreview ? Self.preview : NudgeWidgetEntry(date: now, snapshot: WidgetSharedStore.read(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NudgeWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSharedStore.read(at: now)
        let entries = WidgetSnapshot.timelineDates(for: snapshot.reminders, from: now).map { date in
            NudgeWidgetEntry(date: date, snapshot: WidgetSnapshot(reminders: snapshot.reminders, at: date,
                isAvailable: snapshot.isAvailable, completionFailed: snapshot.completionFailed))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }

    static var preview: NudgeWidgetEntry {
        let now = Date()
        let reminders = ["Call Maya", "Pick up groceries", "Water the plants"].enumerated().map { offset, title in
            SharedWidgetReminder(id: UUID(), title: title, dueAt: now.addingTimeInterval(Double(offset + 1) * 3600), isCompleted: false)
        }
        return NudgeWidgetEntry(date: now, snapshot: WidgetSnapshot(reminders: reminders, at: now))
    }
}

struct NudgeWidgetEntryView: View {
    let entry: NudgeWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            switch family {
            case .systemSmall: small
            case .systemMedium: medium
            default: large
            }
        }
        .tint(NudgeDesign.accent)
        .containerBackground(for: .widget) { NudgeDesign.background }
        .widgetURL(family == .systemSmall && entry.snapshot.isAvailable ? voiceURL : remindersURL)
    }

    private var small: some View {
        VStack(spacing: 8) {
            Text("nudge.me").font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            WidgetMic(size: 62)
            Spacer(minLength: 0)
            if !entry.snapshot.isAvailable {
                Text("Open nudge.me").font(.caption)
            } else if entry.snapshot.overdueCount > 0 {
                Text("\(entry.snapshot.overdueCount) overdue")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            } else {
                Text("\(entry.snapshot.openCount) open").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Create reminder. \(entry.snapshot.openCount) open, \(entry.snapshot.overdueCount) overdue.")
        .accessibilityHint("Opens the microphone in nudge.me")
    }

    private var medium: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                heading
                if entry.snapshot.reminders.isEmpty {
                    emptyState.frame(maxHeight: .infinity)
                } else {
                    reminderRows(limit: typeSize.isAccessibilitySize ? 1 : 2)
                    if entry.snapshot.completionFailed { completionError }
                }
            }
            Spacer(minLength: 0)
            Link(destination: voiceURL) {
                VStack(spacing: 6) {
                    WidgetMic(size: 56)
                    Text("Speak").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Create reminder by voice")
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                heading
                Spacer(minLength: 8)
                Link(destination: voiceURL) { WidgetMic(size: 40).frame(width: 44, height: 44) }
                    .accessibilityLabel("Create reminder by voice")
            }
            if entry.snapshot.reminders.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let limit = typeSize.isAccessibilitySize ? 3 : 5
                reminderRows(limit: limit)
                Spacer(minLength: 0)
                if entry.snapshot.completionFailed {
                    completionError
                } else if entry.snapshot.openCount > limit {
                    Link("\(entry.snapshot.openCount - limit) more", destination: remindersURL)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var heading: some View {
        Link(destination: remindersURL) {
            HStack(spacing: 6) {
                Text("Reminders").font(.subheadline.weight(.semibold))
                if entry.snapshot.isAvailable {
                    Text("\(entry.snapshot.openCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NudgeDesign.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(NudgeDesign.softAccent, in: Capsule())
                        .widgetAccentable()
                        .invalidatableContent()
                }
            }
            .lineLimit(1)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("\(entry.snapshot.openCount) open reminders")
    }

    private var emptyState: some View {
        Link(destination: remindersURL) {
            Label(entry.snapshot.isAvailable ? "No reminders" : "Open nudge.me",
                  systemImage: entry.snapshot.isAvailable ? "checkmark.circle" : "arrow.up.forward.app")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var completionError: some View {
        Link("Couldn’t complete. Open app.", destination: remindersURL)
            .font(.caption).foregroundStyle(.secondary)
    }

    private func reminderRows(limit: Int) -> some View {
        VStack(spacing: 2) {
            ForEach(entry.snapshot.reminders.prefix(limit)) { reminder in
                WidgetReminderRow(reminder: reminder, date: entry.date)
            }
        }
    }
}

private struct WidgetReminderRow: View {
    let reminder: SharedWidgetReminder
    let date: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var overdue: Bool { (reminder.dueAt ?? .distantFuture) < date }
    private var detail: String {
        guard let due = reminder.dueAt else { return String(localized: "No date") }
        let calendar = Calendar.current
        let time = due.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(due, inSameDayAs: date) {
            return overdue ? String(localized: "Overdue") + " · " + time : time
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date), calendar.isDate(due, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow") + " · " + time
        }
        let day = due.formatted(.dateTime.month(.abbreviated).day())
        return (overdue ? String(localized: "Overdue") + " · " : "") + day + " · " + time
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(intent: CompleteWidgetReminderIntent(id: reminder.id)) {
                Image(systemName: "circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(NudgeDesign.accent)
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .widgetAccentable()
            .accessibilityLabel("Complete \(reminder.title)")
            Link(destination: URL(string: "nudgeme://reminder/\(reminder.id.uuidString)")!) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(detail).font(.caption2)
                        .foregroundStyle(overdue && renderingMode == .fullColor ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityLabel("\(reminder.title), \(detail)")
            .accessibilityHint("Edit reminder")
        }
        .invalidatableContent()
    }
}

private struct WidgetMic: View {
    let size: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        ZStack {
            if renderingMode == .fullColor {
                Circle().fill(RadialGradient(colors: [Color(red: 0.72, green: 0.80, blue: 1),
                    Color(red: 0.40, green: 0.46, blue: 0.94), Color(red: 0.20, green: 0.27, blue: 0.65)],
                    center: .init(x: 0.27, y: 0.17), startRadius: 0, endRadius: size))
            } else {
                Circle().fill(.primary.opacity(0.15))
            }
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(renderingMode == .fullColor ? Color.white : Color.primary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct NudgeWidget: Widget {
    let kind = WidgetSharedStore.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NudgeTimelineProvider()) { entry in
            NudgeWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("nudge.me")
        .description("Speak a reminder. See what’s due. Mark it done.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) { NudgeWidget() } timeline: { NudgeTimelineProvider.preview }
#Preview(as: .systemMedium) { NudgeWidget() } timeline: { NudgeTimelineProvider.preview }
#Preview(as: .systemLarge) { NudgeWidget() } timeline: { NudgeTimelineProvider.preview }
