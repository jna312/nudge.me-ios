import Foundation

enum ParseResult {
    case complete(ReminderDraft)
    case needsWhen(title: String, raw: String)
    case needsTime(title: String, baseDate: Date, periodHint: String?) // Has day but needs specific time
}

final class ReminderParser {
    func parse(_ text: String) -> ParseResult {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .needsWhen(title: "", raw: text) }

        let lower = normalizeNumberWords(cleaned.lowercased())
        let title = stripSchedulingPhrases(from: cleaned)
        let finalTitle = title.isEmpty ? cleaned : title
        
        // Check for early alert phrases like "with a 15 minute warning"
        let earlyAlertMinutes = parseEarlyAlertPhrase(lower)
        
        // Check for relative time first (these are complete)
        if let relativeDate = parseRelativeTime(lower) {
            return .complete(ReminderDraft(
                rawTranscript: cleaned,
                title: finalTitle,
                dueAt: relativeDate,
                wantsAlert1: true,
                earlyAlertMinutes: earlyAlertMinutes
            ))
        }
        
        // Check for explicit time (at X:XX)
        let hasExplicitTime = hasExplicitTimePattern(lower)
        
        // Check for day reference
        let (baseDate, hasDay) = parseDayReference(lower)
        
        // Check for vague time-of-day words
        let periodHint = parseTimePeriod(lower)
        
        if hasExplicitTime {
            // Has explicit time like "at 3 PM"
            if let due = parseExplicitTime(lower, baseDate: baseDate) {
                return .complete(ReminderDraft(
                    rawTranscript: cleaned,
                    title: finalTitle,
                    dueAt: due,
                    wantsAlert1: true,
                    earlyAlertMinutes: earlyAlertMinutes
                ))
            }
        }
        
        if periodHint != nil || hasDay {
            // Has a day or vague period - need specific time
            return .needsTime(title: finalTitle, baseDate: baseDate, periodHint: periodHint)
        }
        
        // No time info at all
        return .needsWhen(title: finalTitle, raw: cleaned)
    }
    
    // MARK: - Early Alert Parsing
    
    private func parseEarlyAlertPhrase(_ lower: String) -> Int? {
        // Match patterns like:
        // "with a 15 minute warning"
        // "with 15 minute warning"
        // "with an early alert"
        // "warn me 30 minutes before"
        // "alert me 1 hour before"
        // "remind me 15 minutes early"
        
        let patterns: [(String, Int?)] = [
            // "with a X minute warning" / "with X minute warning"
            (#"with\s+(?:a\s+)?(\d+)\s*(?:minute|min)\s*(?:warning|alert|heads?\s*up)"#, nil),
            // "with a X hour warning"
            (#"with\s+(?:a\s+)?(\d+)\s*hour\s*(?:warning|alert|heads?\s*up)"#, nil),
            // "warn/alert/remind me X minutes before/early"
            (#"(?:warn|alert|remind)\s+me\s+(\d+)\s*(?:minute|min)s?\s*(?:before|early|earlier)"#, nil),
            // "warn/alert/remind me X hour(s) before/early"
            (#"(?:warn|alert|remind)\s+me\s+(\d+)\s*hours?\s*(?:before|early|earlier)"#, nil),
            // "with an early alert" / "with early warning" (default 15 min)
            (#"with\s+(?:an?\s+)?early\s*(?:alert|warning|heads?\s*up)"#, 15),
        ]
        
        for (pattern, defaultMinutes) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(lower.startIndex..., in: lower)
            
            if let match = re.firstMatch(in: lower, range: range) {
                // If pattern has a capture group (number), extract it
                if match.numberOfRanges > 1, let numRange = Range(match.range(at: 1), in: lower) {
                    let numStr = String(lower[numRange])
                    if let num = Int(numStr) {
                        // Check if it's hours
                        if pattern.contains("hour") {
                            return num * 60  // Convert hours to minutes
                        }
                        return num
                    }
                }
                // No capture group or couldn't parse - use default
                if let defaultMinutes = defaultMinutes {
                    return defaultMinutes
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Relative time ("in X minutes/hours")
    
    private func parseRelativeTime(_ lower: String) -> Date? {
        let pattern = #"(?:in)\s+(\d+)\s*(minute|minutes|hour|hours|day|days)"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        
        guard let m = re.firstMatch(in: lower, range: range),
              let nRange = Range(m.range(at: 1), in: lower),
              let uRange = Range(m.range(at: 2), in: lower),
              let n = Int(lower[nRange]) else { return nil }
        
        let unit = String(lower[uRange])
        let seconds: TimeInterval
        switch unit {
        case "minute", "minutes": seconds = TimeInterval(n * 60)
        case "hour", "hours":     seconds = TimeInterval(n * 3600)
        case "day", "days":       seconds = TimeInterval(n * 86400)
        default:                  seconds = TimeInterval(n * 60)
        }
        return Date().addingTimeInterval(seconds)
    }
    
    // MARK: - Day reference
    
    private func parseDayReference(_ lower: String) -> (Date, Bool) {
        let now = Date()
        var baseDate = now
        var hasDay = false
        
        if lower.contains("tomorrow") {
            baseDate = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            hasDay = true
        } else if lower.contains("today") {
            hasDay = true
        } else if let nextWeekday = parseNextWeekday(from: lower) {
            baseDate = nextWeekday
            hasDay = true
        }
        
        return (baseDate, hasDay)
    }
    
    private func parseNextWeekday(from lower: String) -> Date? {
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
    
    // MARK: - Time period (vague)
    
    private func parseTimePeriod(_ lower: String) -> String? {
        if lower.contains("morning") { return "morning" }
        if lower.contains("afternoon") { return "afternoon" }
        if lower.contains("evening") || lower.contains("tonight") { return "evening" }
        if lower.contains("night") { return "night" }
        return nil
    }
    
    // MARK: - Explicit time
    
    private func hasExplicitTimePattern(_ lower: String) -> Bool {
        let pattern = #"at\s+\d{1,2}(?::\d{2})?\s*(am|pm)?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(lower.startIndex..., in: lower)
        return re.firstMatch(in: lower, range: range) != nil
    }
    
    private func parseExplicitTime(_ lower: String, baseDate: Date) -> Date? {
        let pattern = #"at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(lower.startIndex..., in: lower)
        
        guard let m = re.firstMatch(in: lower, range: range),
              let hrR = Range(m.range(at: 1), in: lower) else { return nil }
        
        let hourRaw = Int(lower[hrR]) ?? 9
        var minute = 0
        if let minR = Range(m.range(at: 2), in: lower) { minute = Int(lower[minR]) ?? 0 }
        
        var hour = hourRaw
        if let ampmR = Range(m.range(at: 3), in: lower) {
            let ampm = lower[ampmR]
            if ampm == "pm", hour < 12 { hour += 12 }
            if ampm == "am", hour == 12 { hour = 0 }
        }
        
        // If no day specified and time already passed -> tomorrow
        let now = Date()
        let (_, hasDay) = parseDayReference(lower)
        if !hasDay {
            if let candidateToday = setTime(on: now, hour: hour, minute: minute), candidateToday <= now {
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
                return setTime(on: tomorrow, hour: hour, minute: minute)
            }
            return setTime(on: now, hour: hour, minute: minute)
        }
        
        return setTime(on: baseDate, hour: hour, minute: minute)
    }
    
    // MARK: - Helpers

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
            #"(?i)\bnight\b"#,
            #"(?i)\bnext\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
            #"(?i)\bin\s+\d+\s*(minute|minutes|hour|hours|day|days)\b"#,
            #"(?i)\bat\s+\d{1,2}(?::\d{2})?\s*(am|pm)?"#,
            // Early alert phrases
            #"(?i)\bwith\s+(?:a\s+)?\d+\s*(?:minute|min|hour)s?\s*(?:warning|alert|heads?\s*up)"#,
            #"(?i)\bwith\s+(?:an?\s+)?early\s*(?:alert|warning|heads?\s*up)"#,
            #"(?i)\b(?:warn|alert|remind)\s+me\s+\d+\s*(?:minute|min|hour)s?\s*(?:before|early|earlier)"#,
        ]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
