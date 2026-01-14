import Foundation

// MARK: - Time Constants

/// Common time intervals in seconds for readability
enum Duration {
    static let tenMinutes: Double = 600
    static let thirtyMinutes: Double = 1800
    static let oneHour: Double = 3600
    static let threeHours: Double = 10800
    static let oneDay: Double = 86400
}

// MARK: - Shared Helper Functions

/// Convert a Date to minutes since midnight (for time picker storage)
func minutesFromMidnight(_ date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

/// Get tomorrow at 9 AM
func tomorrowAt9AM() -> Date {
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
    return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
}

/// Get tomorrow at 6 PM
func tomorrowAt6PM() -> Date {
    let calendar = Calendar.current
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
    return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow)!
}

/// Format a date as a readable time string (short)
func formatTimeShort(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

/// Format a date with context (today, tomorrow, or date + time)
func formatTimeWithContext(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    
    if Calendar.current.isDateInToday(date) {
        return formatter.string(from: date)
    } else if Calendar.current.isDateInTomorrow(date) {
        return String(localized: "tomorrow at \(formatter.string(from: date))")
    } else {
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

/// Format minutes as human-readable duration
func formatMinutes(_ minutes: Int) -> String {
    if minutes >= 60 {
        let hours = minutes / 60
        return hours == 1 ? String(localized: "1 hour") : String(localized: "\(hours) hours")
    }
    return String(localized: "\(minutes) min")
}

/// Convert minutes since midnight to a Date at that time today (for time pickers)
func dateFromMinutesSinceMidnight(_ minutes: Int) -> Date {
    let h = minutes / 60
    let min = minutes % 60
    return Calendar.current.date(bySettingHour: h, minute: min, second: 0, of: Date())!
}

/// Apply writing style capitalization to a string
func applyWritingStyle(_ text: String, style: String) -> String {
    switch style {
    case "Lowercase":
        return text.lowercased()
    case "UPPERCASE":
        return text.uppercased()
    case "Title Case":
        return text.capitalized
    default: // "Sentence case"
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst().lowercased()
    }
}
