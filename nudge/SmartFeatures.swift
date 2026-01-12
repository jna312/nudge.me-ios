import Foundation
import SwiftData
import EventKit

// MARK: - Command Detection

enum VoiceCommand {
    case createReminder
    case editReminder(searchTerm: String, newTime: Date?, newTitle: String?)
    case cancelLast
    case cancelByName(searchTerm: String)
    case cancelAllForDate(date: Date)
}

struct CommandDetector {
    
    /// Detect if the transcript is a command (edit/cancel) vs a new reminder
    static func detect(_ transcript: String) -> VoiceCommand {
        let lower = transcript.lowercased()
        
        // Cancel commands
        if lower.contains("cancel") || lower.contains("delete") || lower.contains("remove") {
            if lower.contains("last") || lower.contains("previous") {
                return .cancelLast
            }
            if lower.contains("all") {
                if lower.contains("tomorrow") {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
                    return .cancelAllForDate(date: tomorrow)
                }
                if lower.contains("today") {
                    return .cancelAllForDate(date: Date())
                }
            }
            // Try to extract what to cancel: "cancel the dentist reminder"
            let searchTerm = extractSearchTerm(from: lower, afterWords: ["cancel", "delete", "remove"])
            if !searchTerm.isEmpty {
                return .cancelByName(searchTerm: searchTerm)
            }
        }
        
        // Edit commands
        if lower.contains("change") || lower.contains("move") || lower.contains("reschedule") || lower.contains("update") {
            let (searchTerm, newTime, newTitle) = parseEditCommand(lower)
            if !searchTerm.isEmpty {
                return .editReminder(searchTerm: searchTerm, newTime: newTime, newTitle: newTitle)
            }
        }
        
        return .createReminder
    }
    
    private static func extractSearchTerm(from text: String, afterWords: [String]) -> String {
        var result = text
        for word in afterWords {
            if let range = result.range(of: word) {
                result = String(result[range.upperBound...])
            }
        }
        // Clean up common words
        let cleanupWords = ["the", "my", "reminder", "for", "about"]
        for word in cleanupWords {
            result = result.replacingOccurrences(of: "\\b\(word)\\b", with: "", options: .regularExpression)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func parseEditCommand(_ text: String) -> (searchTerm: String, newTime: Date?, newTitle: String?) {
        // Pattern: "change/move [reminder name] to [new time/title]"
        var searchTerm = ""
        var newTime: Date? = nil
        var newTitle: String? = nil
        
        // Extract "X to Y" pattern
        let patterns = [
            #"(?:change|move|reschedule|update)\s+(?:the\s+)?(.+?)\s+to\s+(.+)"#
        ]
        
        for pattern in patterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                
                if let searchRange = Range(match.range(at: 1), in: text) {
                    searchTerm = String(text[searchRange])
                        .replacingOccurrences(of: "reminder", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                if let targetRange = Range(match.range(at: 2), in: text) {
                    let target = String(text[targetRange])
                    // Try to parse as time
                    newTime = parseSimpleTime(target)
                    if newTime == nil {
                        // It's a new title
                        newTitle = target.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        
        return (searchTerm, newTime, newTitle)
    }
    
    private static func parseSimpleTime(_ text: String) -> Date? {
        let lower = text.lowercased()
        let now = Date()
        var baseDate = now
        
        if lower.contains("tomorrow") {
            baseDate = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        }
        
        // "3 PM", "3:30 PM", "at 3"
        let pattern = #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let hrRange = Range(match.range(at: 1), in: lower) else { return nil }
        
        var hour = Int(lower[hrRange]) ?? 0
        var minute = 0
        
        if let minRange = Range(match.range(at: 2), in: lower) {
            minute = Int(lower[minRange]) ?? 0
        }
        
        if let ampmRange = Range(match.range(at: 3), in: lower) {
            let ampm = String(lower[ampmRange])
            if ampm == "pm" && hour < 12 { hour += 12 }
            if ampm == "am" && hour == 12 { hour = 0 }
        }
        
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)
    }
}

// MARK: - Duplicate Detection

struct DuplicateDetector {
    
    /// Check if a similar reminder already exists
    static func findDuplicate(
        title: String,
        dueAt: Date,
        in context: ModelContext
    ) -> ReminderItem? {
        let normalizedTitle = title.lowercased()
        
        // Fetch open reminders
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" }
        )
        
        guard let reminders = try? context.fetch(descriptor) else { return nil }
        
        for reminder in reminders {
            // Check title similarity (contains key words)
            let existingTitle = reminder.title.lowercased()
            let similarity = calculateSimilarity(normalizedTitle, existingTitle)
            
            if similarity > 0.6 {
                // Also check if due dates are close (within 2 hours)
                if let existingDue = reminder.dueAt {
                    let timeDiff = abs(dueAt.timeIntervalSince(existingDue))
                    if timeDiff < 7200 { // 2 hours
                        return reminder
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Simple word-based similarity score
    private static func calculateSimilarity(_ s1: String, _ s2: String) -> Double {
        let words1 = Set(s1.components(separatedBy: .whitespaces).filter { $0.count > 2 })
        let words2 = Set(s2.components(separatedBy: .whitespaces).filter { $0.count > 2 })
        
        guard !words1.isEmpty && !words2.isEmpty else { return 0 }
        
        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count
        
        return Double(intersection) / Double(union)
    }
}

// MARK: - Smart Time Suggestions

struct TimeSuggestionEngine {
    
    /// Get suggested times based on user history
    static func getSuggestions(for title: String, in context: ModelContext) -> [Date] {
        var suggestions: [Date] = []
        let now = Date()
        let calendar = Calendar.current
        
        // Fetch completed reminders to learn patterns
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "completed" }
        )
        
        guard let history = try? context.fetch(descriptor) else {
            return defaultSuggestions()
        }
        
        // Analyze what times the user typically uses
        var hourCounts: [Int: Int] = [:]
        for reminder in history {
            if let due = reminder.dueAt {
                let hour = calendar.component(.hour, from: due)
                hourCounts[hour, default: 0] += 1
            }
        }
        
        // Get top 3 most used hours
        let topHours = hourCounts.sorted { $0.value > $1.value }.prefix(3).map { $0.key }
        
        // Create suggestions for today/tomorrow at those times
        for hour in topHours {
            // Today (if not past)
            if let todaySuggestion = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now),
               todaySuggestion > now {
                suggestions.append(todaySuggestion)
            }
            
            // Tomorrow
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            if let tomorrowSuggestion = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) {
                suggestions.append(tomorrowSuggestion)
            }
        }
        
        if suggestions.isEmpty {
            return defaultSuggestions()
        }
        
        return Array(suggestions.prefix(4))
    }
    
    private static func defaultSuggestions() -> [Date] {
        let now = Date()
        let calendar = Calendar.current
        var suggestions: [Date] = []
        
        // In 1 hour
        suggestions.append(now.addingTimeInterval(3600))
        
        // Today at 6 PM (if not past)
        if let sixPM = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now), sixPM > now {
            suggestions.append(sixPM)
        }
        
        // Tomorrow at 9 AM
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        if let nineAM = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) {
            suggestions.append(nineAM)
        }
        
        return suggestions
    }
}

// MARK: - Calendar Conflict Detection

struct CalendarConflictDetector {
    
    /// Check if there's a calendar event at the proposed reminder time
    static func checkConflicts(at date: Date) async -> [String] {
        let eventStore = EKEventStore()
        
        // Request access
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            guard granted else { return [] }
        } catch {
            return []
        }
        
        // Check for events in a 30-minute window around the reminder
        let startDate = date.addingTimeInterval(-900) // 15 min before
        let endDate = date.addingTimeInterval(900)    // 15 min after
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        return events.map { $0.title ?? "Event" }
    }
}

// MARK: - Reminder Search

struct ReminderSearch {
    
    /// Find reminders matching a search term
    static func find(matching searchTerm: String, in context: ModelContext) -> [ReminderItem] {
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" }
        )
        
        guard let reminders = try? context.fetch(descriptor) else { return [] }
        
        let normalizedSearch = searchTerm.lowercased()
        
        return reminders.filter { reminder in
            reminder.title.lowercased().contains(normalizedSearch)
        }
    }
    
    /// Find the most recently created reminder
    static func findLast(in context: ModelContext) -> ReminderItem? {
        var descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        
        return try? context.fetch(descriptor).first
    }
    
    /// Find all reminders for a specific date
    static func findForDate(_ date: Date, in context: ModelContext) -> [ReminderItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { item in
                item.statusRaw == "open" &&
                item.dueAt != nil &&
                item.dueAt! >= startOfDay &&
                item.dueAt! < endOfDay
            }
        )
        
        return (try? context.fetch(descriptor)) ?? []
    }
}

