import Foundation

enum ParseResult {
    case complete(ReminderDraft)
    case needsWhen(title: String, raw: String)
}

final class ReminderParser {
    func parse(_ text: String) -> ParseResult {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .needsWhen(title: "", raw: text) }

        let due = parseDueDate(cleaned)
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

    private func parseDueDate(_ s: String) -> Date? {
        let lower = normalizeNumberWords(s)
        let now = Date()
        var baseDate = now
        var hasDay = false

        // Relative: "in 30 minutes" / "in 2 hours" / "in 1 day"
        do {
            let pattern = #"(?:in)\s+(\d+)\s*(minute|minutes|hour|hours|day|days)"#
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
                case "day", "days":       seconds = TimeInterval(n * 86400)
                default:                  seconds = TimeInterval(n * 60)
                }
                return now.addingTimeInterval(seconds)
            }
        } catch { /* ignore */ }

        // Day keywords
        if lower.contains("tomorrow") {
            baseDate = Calendar.current.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
            hasDay = true
        } else if lower.contains("today") {
            baseDate = now
            hasDay = true
        } else if let nextWeekday = parseNextWeekday(from: lower) {
            baseDate = nextWeekday
            hasDay = true
        }

        // Time-of-day words: morning/afternoon/evening
        if lower.contains("morning") {
            return setTime(on: baseDate, hour: 9, minute: 0)
        }
        if lower.contains("afternoon") {
            return setTime(on: baseDate, hour: 15, minute: 0)
        }
        if lower.contains("evening") || lower.contains("tonight") {
            return setTime(on: baseDate, hour: 19, minute: 0)
        }

        // "at 7", "at 7 pm", "at 7:30 am"
        do {
            let pattern = #"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
            let re = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(lower.startIndex..., in: lower)

            if let m = re.firstMatch(in: lower, range: range),
               let hrR = Range(m.range(at: 1), in: lower) {

                let hourRaw = Int(lower[hrR]) ?? 9
                var minute = 0
                if let minR = Range(m.range(at: 2), in: lower) { minute = Int(lower[minR]) ?? 0 }

                var hour = hourRaw
                if let ampmR = Range(m.range(at: 3), in: lower) {
                    let ampm = lower[ampmR]
                    if ampm == "pm", hour < 12 { hour += 12 }
                    if ampm == "am", hour == 12 { hour = 0 }
                }

                // If they said "at 3" with no day and that time already passed today -> tomorrow
                if !hasDay {
                    if let candidateToday = setTime(on: now, hour: hour, minute: minute), candidateToday <= now {
                        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
                        return setTime(on: tomorrow, hour: hour, minute: minute)
                    }
                    return setTime(on: now, hour: hour, minute: minute)
                }

                return setTime(on: baseDate, hour: hour, minute: minute)
            }
        } catch { /* ignore */ }

        // If they gave a day word but no time -> return nil (require time)
        // User must specify a time
        return nil
    }
    
    private func parseNextWeekday(from lower: String) -> Date? {
        // supports: "next monday", "next tuesday", etc.
        guard lower.contains("next") else { return nil }
        let weekdays: [(String, Int)] = [
            ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
            ("thursday", 5), ("friday", 6), ("saturday", 7)
        ]
        guard let match = weekdays.first(where: { lower.contains($0.0) }) else { return nil }

        let cal = Calendar.current
        let now = Date()
        let todayWeekday = cal.component(.weekday, from: now)
        var delta = match.1 - todayWeekday
        if delta <= 0 { delta += 7 }
        return cal.date(byAdding: .day, value: delta, to: now)
    }

    private func containsWeekday(_ lower: String) -> Bool {
        return ["sunday","monday","tuesday","wednesday","thursday","friday","saturday"].contains { lower.contains($0) }
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

    private func stripSchedulingPhrases(from s: String) -> String {
        var t = s
        let patterns = [
            #"(?i)\btomorrow\b"#,
            #"(?i)\btoday\b"#,
            #"(?i)\btonight\b"#,
            #"(?i)\bmorning\b"#,
            #"(?i)\bafternoon\b"#,
            #"(?i)\bevening\b"#,
            #"(?i)\bnext\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            #"(?i)\bin\s+\d+\s*(minute|minutes|hour|hours|day|days)\b"#,
            #"(?i)\bat\s+\d{1,2}(?::\d{2})?\s*(am|pm)?"#
        ]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
