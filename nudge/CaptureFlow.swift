import Foundation
import SwiftData
import Combine

enum CaptureStep: Equatable {
    case idle                     // ready to listen
    case gotTask(title: String)   // heard a task but no time yet
    case gotWhen(title: String, dueAt: Date) // have task + due time
    case askAlert(title: String, dueAt: Date)
}

@MainActor
final class CaptureFlow: ObservableObject {
    @Published var prompt: String = "What do you want me to remind you about?"
    @Published var lastHeard: String = ""
    @Published var step: CaptureStep = .idle

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
            let result = parser.parse(t, defaultDateOnlyMinutes: settings.defaultDateOnlyMinutes)

            switch result {
            case .complete(let draft):
                // If we got a due date/time, jump straight to alert question
                if let due = draft.dueAt {
                    step = .askAlert(title: draft.title, dueAt: due)
                    prompt = "Do you want an alert at \(formatTime(due))? Say yes or no."
                } else {
                    step = .gotTask(title: draft.title)
                    prompt = "When should I remind you? (Try: "tomorrow at 3 PM")"
                }

            case .needsWhen(let title, _):
                step = .gotTask(title: title)
                prompt = "When should I remind you? (Try: "tomorrow at 3 PM")"
            }

        case .gotTask(let title):
            // For now, only accept very simple "tomorrow at 3pm / at 7pm" patterns.
            guard let due = parseDueDate(from: t, defaultDateOnlyMinutes: settings.defaultDateOnlyMinutes) else {
                prompt = "Sorry — I didn't catch the time. Try: "tomorrow at 3 PM""
                return
            }
            step = .askAlert(title: title, dueAt: due)
            prompt = "Do you want an alert at \(formatTime(due))? Say yes or no."

        case .askAlert(let title, let dueAt):
            guard let wantsAlert = parseYesNo(t) else {
                prompt = "Please say yes or no."
                return
            }
            await saveReminder(
                title: title,
                dueAt: dueAt,
                wantsAlert: wantsAlert,
                settings: settings,
                modelContext: modelContext
            )

        case .gotWhen:
            // not used yet
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
        try? modelContext.save()

        // Schedule alert notification
        await NotificationsManager.shared.schedule(reminder: item)

        // Schedule daily closeout if reminders exist today
        await DailyCloseoutManager.shared.scheduleIfNeeded(settings: settings, modelContext: modelContext)

        // Ready for next reminder
        reset()
        prompt = "Saved. What else do you want me to remind you about?"
    }

    // MARK: - Simple parsing helpers (we’ll replace with ReminderParser next)

    private func parseYesNo(_ s: String) -> Bool? {
        let x = s.lowercased()
        if x.contains("yes") || x == "yeah" || x == "yep" || x == "sure" { return true }
        if x.contains("no") || x == "nope" || x == "nah" { return false }
        return nil
    }

    private func parseDueDate(from s: String, defaultDateOnlyMinutes: Int) -> Date? {
        let lower = normalizeNumberWords(s)
        var base = Date()

        if lower.contains("tomorrow") {
            base = Calendar.current.date(byAdding: .day, value: 1, to: base) ?? base
        }

        // “at 7”, “at 7 pm”, “at 7:30 am”
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

        // if “tomorrow” but no time, use default
        if lower.contains("tomorrow") {
            let h = defaultDateOnlyMinutes / 60
            let m = defaultDateOnlyMinutes % 60
            return setTime(on: base, hour: h, minute: m)
        }

        return nil
    }

    private func setTime(on date: Date, hour: Int, minute: Int) -> Date? {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
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

