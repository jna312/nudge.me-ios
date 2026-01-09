import Foundation

enum ParseResult {
    case complete(ReminderDraft)
    case needsWhen(title: String, raw: String)
}

final class ReminderParser {
    func parse(_ text: String, defaultDateOnlyMinutes: Int) -> ParseResult {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .needsWhen(title: "", raw: text) }

        let due = parseDueDate(cleaned, defaultDateOnlyMinutes: defaultDateOnlyMinutes)
        let title = stripSchedulingPhrases(from: cleaned)

        if due == nil {
            return .needsWhen(title: title.isEmpty ? cleaned : title, raw: cleaned)
        }

        return .complete(ReminderDraft(
            rawTranscript: cleaned,
            title: title.isEmpty ? cleaned : title,
            dueAt: due,
            wantsAlert1: true,
            alert2OffsetSeconds: nil
        ))
    }

    private func parseDueDate(_ s: String, defaultDateOnlyMinutes: Int) -> Date? {
        let lower = s.lowercased()
        var base = Date()

        if lower.contains("tomorrow") {
            base = Calendar.current.date(byAdding: .day, value: 1, to: base) ?? base
        }

        let pattern = #"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(lower.startIndex..., in: lower)

        if let m = re?.firstMatch(in: lower, range: range),
           let hrR = Range(m.range(at: 1), in: lower) {
            let hourRaw = Int(lower[hrR]) ?? 9
            var minute = 0
            if let minRange = Range(m.range(at: 2), in: lower) { minute = Int(lower[minRange]) ?? 0 }
            var hour = hourRaw
            if let ampmRange = Range(m.range(at: 3), in: lower) {
                let ampm = lower[ampmRange]
                if ampm == "pm", hour < 12 { hour += 12 }
                if ampm == "am", hour == 12 { hour = 0 }
            }
            return setTime(on: base, hour: hour, minute: minute)
        }

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

    private func stripSchedulingPhrases(from s: String) -> String {
        var t = s
        let patterns = [
            #"(?i)\btomorrow\b"#,
            #"(?i)\bat\s+\d{1,2}(?::\d{2})?\s*(am|pm)?"#
        ]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
