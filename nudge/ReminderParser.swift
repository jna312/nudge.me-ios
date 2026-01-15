import Foundation

enum ParseResult {
    case complete(ReminderDraft)
    case needsWhen(title: String, raw: String)
    case needsTime(title: String, baseDate: Date, periodHint: String?)
}

final class ReminderParser {
    func parse(_ text: String) -> ParseResult {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return .needsWhen(title: "", raw: text) }

        let lower = cleaned.normalizeNumberWords()
        let title = stripSchedulingPhrases(from: cleaned)
        let finalTitle = title.isEmpty ? cleaned : title
        
        let earlyAlertMinutes = parseEarlyAlertPhrase(lower)
        
        if let relativeDate = parseRelativeTime(lower) {
            return .complete(ReminderDraft(
                rawTranscript: cleaned,
                title: finalTitle,
                dueAt: relativeDate,
                wantsAlert1: true,
                earlyAlertMinutes: earlyAlertMinutes
            ))
        }
        
        let hasExplicitTime = hasExplicitTimePattern(lower)
        let (baseDate, hasDay) = parseDayReference(lower)
        let periodHint = parseTimePeriod(lower)
        
        if hasExplicitTime {
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
            return .needsTime(title: finalTitle, baseDate: baseDate, periodHint: periodHint)
        }
        
        return .needsWhen(title: finalTitle, raw: cleaned)
    }
    
    // MARK: - Early Alert Parsing
    
    private func parseEarlyAlertPhrase(_ lower: String) -> Int? {
        let patterns: [(String, Int?)] = [
            (#"with\s+(?:a\s+)?(\d+)\s*(?:minute|min)\s*(?:warning|alert|heads?\s*up)"#, nil),
            (#"with\s+(?:a\s+)?(\d+)\s*hour\s*(?:warning|alert|heads?\s*up)"#, nil),
            (#"(?:warn|alert|remind)\s+me\s+(\d+)\s*(?:minute|min)s?\s*(?:before|early|earlier)"#, nil),
            (#"(?:warn|alert|remind)\s+me\s+(\d+)\s*hours?\s*(?:before|early|earlier)"#, nil),
            (#"with\s+(?:an?\s+)?early\s*(?:alert|warning|heads?\s*up)"#, 15),
        ]
        
        for (pattern, defaultMinutes) in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(lower.startIndex..., in: lower)
            
            if let match = re.firstMatch(in: lower, range: range) {
                if match.numberOfRanges > 1, let numRange = Range(match.range(at: 1), in: lower) {
                    if let num = Int(lower[numRange]) {
                        return pattern.contains("hour") ? num * 60 : num
                    }
                }
                if let defaultMinutes = defaultMinutes { return defaultMinutes }
            }
        }
        return nil
    }
    
    // MARK: - Relative time
    
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
        
        if let specificDate = parseSpecificDate(from: lower) {
            return (specificDate, true)
        }
        
        if lower.contains("tomorrow") {
            return (Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now, true)
        }
        if lower.contains("today") {
            return (now, true)
        }
        if let weekdayDate = parseWeekday(from: lower) {
            return (weekdayDate, true)
        }
        
        return (now, false)
    }
    
    private func parseSpecificDate(from lower: String) -> Date? {
        let cal = Calendar.current
        let now = Date()
        let currentYear = cal.component(.year, from: now)
        
        let months: [(String, Int)] = [
            ("january", 1), ("jan", 1), ("february", 2), ("feb", 2),
            ("march", 3), ("mar", 3), ("april", 4), ("apr", 4),
            ("may", 5), ("june", 6), ("jun", 6), ("july", 7), ("jul", 7),
            ("august", 8), ("aug", 8), ("september", 9), ("sep", 9), ("sept", 9),
            ("october", 10), ("oct", 10), ("november", 11), ("nov", 11),
            ("december", 12), ("dec", 12)
        ]
        
        for (monthName, monthNum) in months {
            let pattern = #"\b"# + monthName + #"\s+(\d{1,2})(?:st|nd|rd|th)?\b"#
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let dayRange = Range(match.range(at: 1), in: lower),
               let day = Int(lower[dayRange]) {
                
                var comps = DateComponents()
                comps.year = currentYear
                comps.month = monthNum
                comps.day = day
                
                if let date = cal.date(from: comps) {
                    if date < now {
                        comps.year = currentYear + 1
                        return cal.date(from: comps)
                    }
                    return date
                }
            }
        }
        
        let slashPattern = #"(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?"#
        if let re = try? NSRegularExpression(pattern: slashPattern, options: []),
           let match = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let monthRange = Range(match.range(at: 1), in: lower),
           let dayRange = Range(match.range(at: 2), in: lower),
           let month = Int(lower[monthRange]),
           let day = Int(lower[dayRange]) {
            
            var comps = DateComponents()
            comps.month = month
            comps.day = day
            
            if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound,
               let yearRange = Range(match.range(at: 3), in: lower) {
                var year = Int(lower[yearRange]) ?? currentYear
                if year < 100 { year += 2000 }
                comps.year = year
            } else {
                comps.year = currentYear
            }
            
            if let date = cal.date(from: comps) {
                if date < now && comps.year == currentYear {
                    comps.year = currentYear + 1
                    return cal.date(from: comps)
                }
                return date
            }
        }
        
        return nil
    }
    
    private func parseWeekday(from lower: String) -> Date? {
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
    
    // MARK: - Time period
    
    private func parseTimePeriod(_ lower: String) -> String? {
        if lower.contains("morning") { return "morning" }
        if lower.contains("afternoon") { return "afternoon" }
        if lower.contains("evening") || lower.contains("tonight") { return "evening" }
        if lower.contains("night") { return "night" }
        return nil
    }
    
    // MARK: - Explicit time
    
    private func hasExplicitTimePattern(_ lower: String) -> Bool {
        let pattern = #"(?:at|by)\s*\d{1,2}(?::\d{2})?\s*(a\.?m\.?|p\.?m\.?)?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
        return re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil
    }
    
    private func parseExplicitTime(_ lower: String, baseDate: Date) -> Date? {
        let pattern = #"(?:at|by)\s*(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        
        guard let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let hrR = Range(m.range(at: 1), in: lower) else { return nil }
        
        let hourRaw = Int(lower[hrR]) ?? 9
        var minute = 0
        if let minR = Range(m.range(at: 2), in: lower) { minute = Int(lower[minR]) ?? 0 }
        
        var hour = hourRaw
        let hasExplicitAmPm = m.range(at: 3).location != NSNotFound
        
        if hasExplicitAmPm, let ampmR = Range(m.range(at: 3), in: lower) {
            let ampm = lower[ampmR].lowercased().replacingOccurrences(of: ".", with: "")
            if ampm == "pm", hour < 12 { hour += 12 }
            if ampm == "am", hour == 12 { hour = 0 }
        } else if hourRaw >= 1 && hourRaw <= 12 {
            return nil
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

    private func stripSchedulingPhrases(from s: String) -> String {
        var t = s
        let patterns = [
            // Strip "remind me" variations at start
            #"(?i)^\s*remind\s+me\s+(?:to|about|on|that)\s+"#,
            #"(?i)^\s*remind\s+me\s+"#,
            #"(?i)^\s*don'?t\s+forget\s+(?:to\s+)?"#,
            #"(?i)^\s*don'?t\s+let\s+me\s+forget\s+(?:to\s+)?"#,
            #"(?i)^\s*i\s+need\s+to\s+"#,
            #"(?i)^\s*i\s+have\s+to\s+"#,
            #"(?i)^\s*i\s+should\s+"#,
            #"(?i)^\s*i\s+want\s+to\s+"#,
            
            // Specific dates: "on monday, january 19" or "january 19"
            #"(?i)\bon\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*,?\s*"#,
            #"(?i)\bon\s+(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\s+\d{1,2}(?:st|nd|rd|th)?\b"#,
            #"(?i)\b(january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\s+\d{1,2}(?:st|nd|rd|th)?\b"#,
            
            // Weekday names
            #"(?i)\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*,?\s*"#,
            #"(?i)\bnext\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
            
            // Slash dates
            #"(?i)\bon\s+\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#,
            #"\b\d{1,2}/\d{1,2}(?:/\d{2,4})?\b"#,
            
            // Other time references
            #"(?i)\btomorrow\b"#,
            #"(?i)\btoday\b"#,
            #"(?i)\btonight\b"#,
            #"(?i)\b(?:this\s+)?morning\b"#,
            #"(?i)\b(?:this\s+)?afternoon\b"#,
            #"(?i)\b(?:this\s+)?evening\b"#,
            #"(?i)\b(?:at\s+)?night\b"#,
            #"(?i)\bin\s+\d+\s*(?:minute|minutes|hour|hours|day|days)\b"#,
            
            // Times: "at 11 am" or "by 3pm"
            #"(?i)\b(?:at|by)\s*\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?\b"#,
            
            // Early alert phrases
            #"(?i)\bwith\s+(?:a\s+)?\d+\s*(?:minute|min|hour)s?\s*(?:warning|alert|heads?\s*up)"#,
            #"(?i)\bwith\s+(?:an?\s+)?early\s*(?:alert|warning|heads?\s*up)"#,
            #"(?i)\b(?:warn|alert|remind)\s+me\s+\d+\s*(?:minute|min|hour)s?\s*(?:before|early|earlier)"#,
            
            // Clean up "that" at the start of what remains
            #"(?i)^\s*that\s+"#,
        ]
        for p in patterns { t = t.replacingOccurrences(of: p, with: "", options: .regularExpression) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
