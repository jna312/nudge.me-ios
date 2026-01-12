import Foundation
import SwiftData
import Combine

enum CaptureStep: Equatable {
    case idle                     // ready to listen
    case gotTask(title: String)   // heard a task but no time yet
    case gotWhen(title: String, dueAt: Date) // have task + due time
}

@MainActor
final class CaptureFlow: ObservableObject {
    @Published var prompt: String = "What do you want me to remind you about?"
    @Published var lastHeard: String = ""
    @Published var step: CaptureStep = .idle
    @Published var lastSavedReminder: ReminderItem?

    private let parser = ReminderParser()
    
    func reset() {
        step = .idle
        prompt = "What do you want me to remind you about?"
        lastHeard = ""
    }

    /// Call this AFTER the user hits Stop (i.e., you have a final transcript).
    func handleTranscript(
        _ transcript: String,
        settings: AppSettings,
        modelContext: ModelContext
    ) async {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lastHeard = t

        switch step {

        case .idle:
            // Try to parse task + time in one shot (e.g. "Call dentist tomorrow at 3pm")
            let result = parser.parse(t)

            switch result {
            case .complete(let draft):
                // If we got both task AND time, save immediately with alert
                if let due = draft.dueAt {
                    await saveReminder(
                        title: draft.title,
                        dueAt: due,
                        wantsAlert: true,
                        settings: settings,
                        modelContext: modelContext
                    )
                } else {
                    // Only got task, need time
                    step = .gotTask(title: draft.title)
                    prompt = "When? (e.g. \"tomorrow at 3 PM\" or \"in 30 minutes\")"
                }

            case .needsWhen(let title, _):
                step = .gotTask(title: title)
                prompt = "When? (e.g. \"tomorrow at 3 PM\" or \"in 30 minutes\")"
            }

        case .gotTask(let title):
            // User is providing the time separately
            guard let due = parseDueDate(from: t) else {
                prompt = "I need a specific time. Try: \"at 3 PM\" or \"in 2 hours\""
                return
            }
            // Save immediately with alert
            await saveReminder(
                title: title,
                dueAt: due,
                wantsAlert: true,
                settings: settings,
                modelContext: modelContext
            )

        case .gotWhen:
            reset()
        }
    }

    // MARK: - Save

    private func saveReminder(
        title: String,
        dueAt: Date,
        wantsAlert: Bool,
        settings: AppSettings,
        modelContext: ModelContext
    ) async {
        let styledTitle = applyWritingStyle(title, style: settings.writingStyle)

        let alertAt: Date? = wantsAlert ? dueAt : nil

        let item = ReminderItem(
            title: styledTitle,
            dueAt: dueAt,
            alertAt: alertAt
        )

        modelContext.insert(item)
        lastSavedReminder = item
        try? modelContext.save()

        // Schedule alert notification
        await NotificationsManager.shared.schedule(reminder: item)

        // Schedule daily closeout if reminders exist today
        await DailyCloseoutManager.shared.scheduleIfNeeded(settings: settings, modelContext: modelContext)

        // Ready for next reminder
        reset()
        prompt = "Saved! What's next?"
    }

    // MARK: - Simple parsing helpers

    private func parseDueDate(from s: String) -> Date? {
        let lower = normalizeNumberWords(s)
        let now = Date()
        var base = now

        // Relative: "in X minutes/hours"
        do {
            let pattern = #"(?:in)\s+(\d+)\s*(minute|minutes|hour|hours)"#
            let re = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(lower.startIndex..., in: lower)
            if let m = re.firstMatch(in: lower, range: range),
               let nRange = Range(m.range(at: 1), in: lower),
               let uRange = Range(m.range(at: 2), in: lower),
               let n = Int(lower[nRange]) {

                let unit = String(lower[uRange])
                let seconds: TimeInterval
                switch unit {
                case "minute", "minutes": seconds = TimeInterval(n * 60)
                case "hour", "hours":     seconds = TimeInterval(n * 3600)
                default:                  seconds = TimeInterval(n * 60)
                }
                return now.addingTimeInterval(seconds)
            }
        } catch { /* ignore */ }

        if lower.contains("tomorrow") {
            base = Calendar.current.date(byAdding: .day, value: 1, to: base) ?? base
        }

        // Time words
        if lower.contains("morning") {
            return setTime(on: base, hour: 9, minute: 0)
        }
        if lower.contains("afternoon") {
            return setTime(on: base, hour: 15, minute: 0)
        }
        if lower.contains("evening") || lower.contains("tonight") {
            return setTime(on: base, hour: 19, minute: 0)
        }

        // "at 7", "at 7 pm", "at 7:30 am"
        let pattern = #"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(lower.startIndex..., in: lower)

        if let m = re?.firstMatch(in: lower, range: range),
           let hrR = Range(m.range(at: 1), in: lower) {
            let hourRaw = Int(lower[hrR]) ?? 9
            var minute = 0
            if let minRange = Range(m.range(at: 2), in: lower) {
                minute = Int(lower[minRange]) ?? 0
            }
            var hour = hourRaw
            if let ampmRange = Range(m.range(at: 3), in: lower) {
                let ampm = lower[ampmRange]
                if ampm == "pm", hour < 12 { hour += 12 }
                if ampm == "am", hour == 12 { hour = 0 }
            }
            return setTime(on: base, hour: hour, minute: minute)
        }

        // No time found
        return nil
    }

    private func setTime(on date: Date, hour: Int, minute: Int) -> Date? {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)
    }

    private func normalizeNumberWords(_ text: String) -> String {
        let map: [String: String] = [
            "one":"1","two":"2","three":"3","four":"4","five":"5","six":"6",
            "seven":"7","eight":"8","nine":"9","ten":"10","eleven":"11","twelve":"12"
        ]
        var t = text.lowercased()
        for (word, digit) in map {
            t = t.replacingOccurrences(of: "\\b\(word)\\b", with: digit, options: .regularExpression)
        }
        return t
    }
    
    private func applyWritingStyle(_ s: String, style: String) -> String {
        switch style {
        case "caps": return s.uppercased()
        case "title": return s.capitalized
        default:
            guard let first = s.first else { return s }
            return String(first).uppercased() + s.dropFirst()
        }
    }
}
