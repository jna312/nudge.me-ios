import Foundation
import SwiftData
import Combine
import UserNotifications

enum CaptureStep: Equatable {
    case idle
    case gotTask(title: String)
    case needsTime(title: String, baseDate: Date, periodHint: String?)
    case confirmDuplicate(title: String, dueAt: Date, existingReminder: ReminderItem)
    case confirmEdit(reminder: ReminderItem, newTime: Date?, newTitle: String?)
    case confirmCancel(reminders: [ReminderItem])
    case calendarConflict(title: String, dueAt: Date, conflictingEvents: [String])
}

// Make ReminderItem Equatable for CaptureStep
extension ReminderItem: Equatable {
    static func == (lhs: ReminderItem, rhs: ReminderItem) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class CaptureFlow: ObservableObject {
    @Published var prompt: String = "What do you want me to remind you about?"
    @Published var lastHeard: String = ""
    @Published var step: CaptureStep = .idle
    @Published var lastSavedReminder: ReminderItem?
    @Published var conflictWarning: String? = nil
    @Published var timeSuggestions: [Date] = []
    @Published var needsFollowUp: Bool = false  // Signals ContentView to auto-listen
    
    // Track AM/PM context for consecutive reminder creation
    private var lastUsedPeriod: TimePeriod? = nil
    private var lastReminderTime: Date? = nil
    
    enum TimePeriod {
        case am, pm
    }

    private let parser = ReminderParser()
    
    func reset(preserveTimeContext: Bool = true) {
        step = .idle
        prompt = String(localized: "What do you want me to remind you about?")
        lastHeard = ""
        conflictWarning = nil
        timeSuggestions = []
        needsFollowUp = false
        pendingEarlyAlertMinutes = nil
        
        // Preserve time context for consecutive reminders, but expire after 5 minutes
        if !preserveTimeContext {
            lastUsedPeriod = nil
            lastReminderTime = nil
        } else if let lastTime = lastReminderTime,
                  Date().timeIntervalSince(lastTime) > 300 { // 5 minutes
            lastUsedPeriod = nil
            lastReminderTime = nil
        }
    }
    
    /// Fully reset including time context (e.g., when app goes to background)
    func fullReset() {
        reset(preserveTimeContext: false)
    }

    func handleTranscript(
        _ transcript: String,
        settings: AppSettings,
        modelContext: ModelContext
    ) async {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lastHeard = t
        
        // Reset needsFollowUp so onChange can detect when it's set to true again
        needsFollowUp = false

        // First, check if this is a command (edit/cancel) vs new reminder
        let command = CommandDetector.detect(t)
        
        switch command {
        case .cancelLast:
            await handleCancelLast(modelContext: modelContext)
            return
            
        case .cancelByName(let searchTerm):
            await handleCancelByName(searchTerm, modelContext: modelContext)
            return
            
        case .cancelAllForDate(let date):
            await handleCancelAllForDate(date, modelContext: modelContext)
            return
            
        case .editReminder(let searchTerm, let newTime, let newTitle):
            await handleEditReminder(searchTerm, newTime: newTime, newTitle: newTitle, modelContext: modelContext)
            return
            
        case .createReminder:
            break // Continue with normal flow
        }
        
        // Handle based on current step
        switch step {

        case .idle:
            let result = parser.parse(t)

            switch result {
            case .complete(let draft):
                if let due = draft.dueAt {
                    await prepareToSave(
                        title: draft.title,
                        dueAt: due,
                        earlyAlertMinutes: draft.earlyAlertMinutes,
                        settings: settings,
                        modelContext: modelContext
                    )
                } else {
                    step = .gotTask(title: draft.title)
                    timeSuggestions = TimeSuggestionEngine.getSuggestions(for: draft.title, in: modelContext)
                    prompt = String(localized: "When? (e.g. \"at 3 PM\" or \"in 30 minutes\")")
                }

            case .needsWhen(let title, _):
                step = .gotTask(title: title)
                timeSuggestions = TimeSuggestionEngine.getSuggestions(for: title, in: modelContext)
                prompt = String(localized: "When? (e.g. \"tomorrow at 3 PM\" or \"in 30 minutes\")")
                needsFollowUp = true
                
            case .needsTime(let title, let baseDate, let periodHint):
                step = .needsTime(title: title, baseDate: baseDate, periodHint: periodHint)
                prompt = promptForTime(periodHint: periodHint)
                needsFollowUp = true
            }

        case .gotTask(let title):
            let result = parser.parse(t)
            
            switch result {
            case .complete(let draft):
                if let due = draft.dueAt {
                    await prepareToSave(
                        title: title,
                        dueAt: due,
                        earlyAlertMinutes: draft.earlyAlertMinutes,
                        settings: settings,
                        modelContext: modelContext
                    )
                } else {
                    prompt = String(localized: "I need a specific time. Try: \"at 3 PM\" or \"in 2 hours\"")
                }
                
            case .needsTime(_, let baseDate, let periodHint):
                step = .needsTime(title: title, baseDate: baseDate, periodHint: periodHint)
                prompt = promptForTime(periodHint: periodHint)
                needsFollowUp = true
                
            case .needsWhen:
                prompt = String(localized: "I need a specific time. Try: \"at 3 PM\" or \"in 2 hours\"")
            }
            
        case .needsTime(let title, let baseDate, _):
            if let time = parseTimeOnly(t) {
                let due = combineDateAndTime(baseDate: baseDate, time: time)
                await prepareToSave(
                    title: title,
                    dueAt: due,
                    settings: settings,
                    modelContext: modelContext
                )
            } else {
                prompt = String(localized: "What time? (e.g. \"9 AM\" or \"3:30 PM\")")
                needsFollowUp = true
            }
            
        case .confirmDuplicate(let title, let dueAt, _):
            if parseYes(t) {
                await saveReminder(title: title, dueAt: dueAt, earlyAlertMinutes: pendingEarlyAlertMinutes, settings: settings, modelContext: modelContext)
            } else if parseNo(t) {
                reset()
                prompt = String(localized: "Okay, cancelled. What else?")
            } else {
                prompt = String(localized: "Say \"yes\" to save anyway, or \"no\" to cancel.")
            }
            
        case .confirmEdit(let reminder, let newTime, let newTitle):
            if parseYes(t) {
                await applyEdit(reminder: reminder, newTime: newTime, newTitle: newTitle, modelContext: modelContext)
            } else if parseNo(t) {
                reset()
                prompt = String(localized: "Okay, no changes made.")
            } else {
                prompt = String(localized: "Say \"yes\" to confirm or \"no\" to cancel.")
            }
            
        case .confirmCancel(let reminders):
            if parseYes(t) {
                await deleteReminders(reminders, modelContext: modelContext)
            } else if parseNo(t) {
                reset()
                prompt = String(localized: "Okay, nothing deleted.")
            } else {
                prompt = String(localized: "Say \"yes\" to delete or \"no\" to keep.")
            }
            
        case .calendarConflict(let title, let dueAt, let conflictingEvents):
            if parseMerge(t) {
                // Merge: combine reminder with calendar event names
                let mergedTitle = "\(title) + \(conflictingEvents.joined(separator: " & "))"
                await saveReminder(title: mergedTitle, dueAt: dueAt, earlyAlertMinutes: pendingEarlyAlertMinutes, settings: settings, modelContext: modelContext)
            } else if parseChangeTime(t) {
                // Change time: go back to gotTask step
                step = .gotTask(title: title)
                timeSuggestions = TimeSuggestionEngine.getSuggestions(for: title, in: modelContext)
                prompt = String(localized: "What time works better?")
                needsFollowUp = true
            } else if parseSaveAnyway(t) || parseYes(t) {
                // Save anyway: proceed with original reminder
                await saveReminder(title: title, dueAt: dueAt, earlyAlertMinutes: pendingEarlyAlertMinutes, settings: settings, modelContext: modelContext)
            } else if parseNo(t) || parseCancel(t) {
                reset()
                prompt = String(localized: "Okay, cancelled. What else?")
            } else {
                prompt = String(localized: "Say \"merge\", \"change time\", \"save anyway\", or \"cancel\".")
                needsFollowUp = true
            }
        }
    }
    
    // MARK: - Prepare to Save (with duplicate & conflict checking)
    
    private var pendingEarlyAlertMinutes: Int? = nil
    
    private func prepareToSave(
        title: String,
        dueAt: Date,
        earlyAlertMinutes: Int? = nil,
        settings: AppSettings,
        modelContext: ModelContext
    ) async {
        // Store for potential use after duplicate confirmation
        pendingEarlyAlertMinutes = earlyAlertMinutes
        
        // Check for duplicates
        if let duplicate = DuplicateDetector.findDuplicate(title: title, dueAt: dueAt, in: modelContext) {
            step = .confirmDuplicate(title: title, dueAt: dueAt, existingReminder: duplicate)
            let timeStr = formatTime(duplicate.dueAt ?? dueAt)
            prompt = "You already have \"\(duplicate.title)\" at \(timeStr). Save anyway?"
            needsFollowUp = true
            return
        }
        
        // Check for calendar conflicts
        let conflicts = await CalendarConflictDetector.checkConflicts(at: dueAt)
        if !conflicts.isEmpty {
            // Show conflict resolution options
            step = .calendarConflict(title: title, dueAt: dueAt, conflictingEvents: conflicts)
            let eventNames = conflicts.joined(separator: ", ")
            prompt = "You have \"\(eventNames)\" at that time. Say \"merge\" to combine, \"change time\", or \"save anyway\"."
            needsFollowUp = true
            return
        }
        
        // Save the reminder
        await saveReminder(title: title, dueAt: dueAt, earlyAlertMinutes: earlyAlertMinutes, settings: settings, modelContext: modelContext)
    }
    
    // MARK: - Command Handlers
    
    private func handleCancelLast(modelContext: ModelContext) async {
        guard let last = ReminderSearch.findLast(in: modelContext) else {
            prompt = String(localized: "No reminders to cancel.")
            return
        }
        
        step = .confirmCancel(reminders: [last])
        prompt = "Cancel \"\(last.title)\"?"
    }
    
    private func handleCancelByName(_ searchTerm: String, modelContext: ModelContext) async {
        let matches = ReminderSearch.find(matching: searchTerm, in: modelContext)
        
        if matches.isEmpty {
            prompt = "I couldn't find a reminder matching \"\(searchTerm)\"."
            return
        }
        
        if matches.count == 1 {
            step = .confirmCancel(reminders: matches)
            prompt = "Cancel \"\(matches[0].title)\"?"
        } else {
            step = .confirmCancel(reminders: matches)
            prompt = "Found \(matches.count) reminders matching \"\(searchTerm)\". Cancel all?"
        }
    }
    
    private func handleCancelAllForDate(_ date: Date, modelContext: ModelContext) async {
        let reminders = ReminderSearch.findForDate(date, in: modelContext)
        
        if reminders.isEmpty {
            let dayStr = Calendar.current.isDateInToday(date) ? "today" : "tomorrow"
            prompt = "No reminders for \(dayStr)."
            return
        }
        
        step = .confirmCancel(reminders: reminders)
        let dayStr = Calendar.current.isDateInToday(date) ? "today" : "tomorrow"
        prompt = "Cancel all \(reminders.count) reminders for \(dayStr)?"
    }
    
    private func handleEditReminder(_ searchTerm: String, newTime: Date?, newTitle: String?, modelContext: ModelContext) async {
        let matches = ReminderSearch.find(matching: searchTerm, in: modelContext)
        
        if matches.isEmpty {
            prompt = "I couldn't find a reminder matching \"\(searchTerm)\"."
            return
        }
        
        let reminder = matches[0]
        step = .confirmEdit(reminder: reminder, newTime: newTime, newTitle: newTitle)
        
        if let time = newTime {
            prompt = "Move \"\(reminder.title)\" to \(formatTime(time))?"
        } else if let title = newTitle {
            prompt = "Change \"\(reminder.title)\" to \"\(title)\"?"
        } else {
            prompt = "What would you like to change about \"\(reminder.title)\"?"
        }
    }
    
    private func applyEdit(reminder: ReminderItem, newTime: Date?, newTitle: String?, modelContext: ModelContext) async {
        if let time = newTime {
            reminder.dueAt = time
            reminder.alertAt = time
            
            // Reschedule notification
            await NotificationsManager.shared.schedule(reminder: reminder)
        }
        
        if let title = newTitle {
            reminder.title = title
        }
        
        try? modelContext.save()
        reset()
        prompt = String(localized: "Updated! What's next?")
    }
    
    private func deleteReminders(_ reminders: [ReminderItem], modelContext: ModelContext) async {
        for reminder in reminders {
            // Cancel notification
            let notificationID = "\(reminder.id.uuidString)-alert"
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
            
            modelContext.delete(reminder)
        }
        
        try? modelContext.save()
        reset()
        
        if reminders.count == 1 {
            prompt = String(localized: "Deleted. What's next?")
        } else {
            prompt = "Deleted \(reminders.count) reminders. What's next?"
        }
    }
    
    // MARK: - Helpers
    
    private func promptForTime(periodHint: String?) -> String {
        switch periodHint {
        case "morning":
            return String(localized: "What time in the morning? (e.g. \"9 AM\")")
        case "afternoon":
            return String(localized: "What time in the afternoon? (e.g. \"2 PM\")")
        case "evening":
            return String(localized: "What time in the evening? (e.g. \"7 PM\")")
        case "night":
            return String(localized: "What time at night? (e.g. \"9 PM\")")
        default:
            return String(localized: "What time? (e.g. \"3 PM\")")
        }
    }
    
    private func parseTimeOnly(_ s: String) -> (hour: Int, minute: Int)? {
        var lower = normalizeNumberWords(s.lowercased())
        
        // Normalize various speech-to-text outputs
        lower = lower
            .replacingOccurrences(of: "p.m.", with: "pm")
            .replacingOccurrences(of: "a.m.", with: "am")
            .replacingOccurrences(of: "p. m.", with: "pm")
            .replacingOccurrences(of: "a. m.", with: "am")
            .replacingOccurrences(of: " o'clock", with: "")
            .replacingOccurrences(of: " oclock", with: "")
            .replacingOccurrences(of: "in the morning", with: "am")
            .replacingOccurrences(of: "in the afternoon", with: "pm")
            .replacingOccurrences(of: "in the evening", with: "pm")
            .replacingOccurrences(of: "at night", with: "pm")
            .replacingOccurrences(of: "tonight", with: "pm")
        
        print("🕐 Parsing time from: '\(lower)'")
        
        // Multiple patterns to try (most specific first)
        let patterns = [
            #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#,  // "6 pm", "6:30 pm"
            #"(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#,             // No "at" prefix
        ]
        
        for pattern in patterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(lower.startIndex..., in: lower)
                if let m = re.firstMatch(in: lower, range: range),
                   let hrR = Range(m.range(at: 1), in: lower) {
                    
                    var hour = Int(lower[hrR]) ?? 0
                    var minute = 0
                    
                    if m.numberOfRanges > 2, let minR = Range(m.range(at: 2), in: lower) {
                        minute = Int(lower[minR]) ?? 0
                    }
                    
                    if m.numberOfRanges > 3, let ampmR = Range(m.range(at: 3), in: lower) {
                        let ampm = String(lower[ampmR]).lowercased()
                        if ampm == "pm" && hour < 12 { hour += 12 }
                        if ampm == "am" && hour == 12 { hour = 0 }
                    }
                    
                    if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 {
                        print("🕐 Parsed time: \(hour):\(String(format: "%02d", minute))")
                        return (hour, minute)
                    }
                }
            }
        }
        
        // Pattern without AM/PM - use context to infer
        if !lower.contains("am") && !lower.contains("pm") {
            let simplePattern = #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?"#
            if let re = try? NSRegularExpression(pattern: simplePattern, options: [.caseInsensitive]) {
                let range = NSRange(lower.startIndex..., in: lower)
                if let m = re.firstMatch(in: lower, range: range),
                   let hrR = Range(m.range(at: 1), in: lower) {
                    
                    var hour = Int(lower[hrR]) ?? 0
                    var minute = 0
                    
                    if let minR = Range(m.range(at: 2), in: lower) {
                        minute = Int(lower[minR]) ?? 0
                    }
                    
                    // Apply AM/PM inference for ambiguous hours (1-12)
                    if hour >= 1 && hour <= 12 {
                        hour = inferHourWithContext(hour)
                        print("🕐 Inferred hour with context: \(hour)")
                    }
                    
                    if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 {
                        print("🕐 Parsed time with context: \(hour):\(String(format: "%02d", minute))")
                        return (hour, minute)
                    }
                }
            }
        }
        
        print("🕐 Failed to parse time from: '\(lower)'")
        return nil
    }
    
    /// Infer whether an ambiguous hour (1-12) should be AM or PM
    /// Uses: 1) Recent context from consecutive reminders, 2) Current time of day, 3) Common sense defaults
    private func inferHourWithContext(_ hour: Int) -> Int {
        let currentHour = Calendar.current.component(.hour, from: Date())
        
        // Priority 1: Use recent context if available (within 5 minutes)
        if let lastTime = lastReminderTime,
           Date().timeIntervalSince(lastTime) < 300,
           let period = lastUsedPeriod {
            print("🕐 Using recent context: \(period)")
            switch period {
            case .pm:
                return hour < 12 ? hour + 12 : hour
            case .am:
                return hour == 12 ? 0 : hour
            }
        }
        
        // Priority 2: Smart inference based on current time and the hour mentioned
        // If user says "3" and it's currently 2 PM, they probably mean 3 PM
        // If user says "9" and it's currently 8 AM, they probably mean 9 AM
        
        // If it's currently afternoon/evening (12 PM - 11 PM)
        if currentHour >= 12 {
            // Hours 1-11 are likely PM if we're in PM territory
            if hour >= 1 && hour <= 11 {
                // But if the PM time has already passed today, might mean tomorrow AM
                let pmHour = hour + 12
                if pmHour <= currentHour && hour >= 6 {
                    // e.g., it's 5 PM and user says "3" - they might mean 3 PM (passed) or tomorrow 3 PM
                    // For convenience, assume they mean PM today/tomorrow
                    return pmHour
                }
                return pmHour
            }
            return hour // hour 12 stays as 12 (noon)
        }
        
        // If it's currently morning (12 AM - 11 AM)
        if currentHour < 12 {
            // Common sense: 
            // - Hours 1-6 early morning are usually AM
            // - Hours 7-11 morning/late morning are usually AM  
            // - But if current time is close to noon and hour is small (1-5), might be PM
            
            if hour >= 1 && hour <= 5 && currentHour >= 10 {
                // It's late morning (10-11 AM) and user says 1-5, probably means PM
                return hour + 12
            }
            
            // Default to AM for morning context
            return hour == 12 ? 0 : hour
        }
        
        return hour
    }
    
    private func combineDateAndTime(baseDate: Date, time: (hour: Int, minute: Int)) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: baseDate)
        comps.hour = time.hour
        comps.minute = time.minute
        return Calendar.current.date(from: comps) ?? baseDate
    }
    
    private func parseYes(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains("yes") || lower == "yeah" || lower == "yep" || lower == "sure" || lower == "okay" || lower == "ok"
    }
    
    private func parseNo(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains("no") || lower == "nope" || lower == "nah" || lower == "cancel"
    }
    
    private func parseMerge(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains("merge") || lower.contains("combine") || lower.contains("join")
    }
    
    private func parseChangeTime(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains("change time") || lower.contains("different time") || 
               lower.contains("another time") || lower.contains("reschedule") ||
               lower.contains("new time") || lower.contains("pick another")
    }
    
    private func parseSaveAnyway(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains("save anyway") || lower.contains("save it anyway") ||
               lower.contains("keep it") || lower.contains("save both") ||
               lower.contains("that's fine") || lower.contains("it's fine")
    }
    
    private func parseCancel(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains("cancel") || lower.contains("delete") || 
               lower.contains("nevermind") || lower.contains("never mind") ||
               lower.contains("forget it")
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        if Calendar.current.isDateInToday(date) {
            return formatter.string(from: date)
        } else if Calendar.current.isDateInTomorrow(date) {
            return "tomorrow at \(formatter.string(from: date))"
        } else {
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }

    // MARK: - Save

    private func saveReminder(
        title: String,
        dueAt: Date,
        earlyAlertMinutes: Int? = nil,
        settings: AppSettings,
        modelContext: ModelContext
    ) async {
        let styledTitle = applyWritingStyle(title, style: settings.writingStyle)
        
        // Use parsed early alert, or fall back to default setting
        let finalEarlyAlert = earlyAlertMinutes ?? (settings.defaultEarlyAlertMinutes > 0 ? settings.defaultEarlyAlertMinutes : nil)

        let item = ReminderItem(
            title: styledTitle,
            dueAt: dueAt,
            alertAt: dueAt,
            earlyAlertMinutes: finalEarlyAlert
        )

        modelContext.insert(item)
        lastSavedReminder = item
        try? modelContext.save()
        
        // Track the AM/PM period for context in consecutive reminders
        let hour = Calendar.current.component(.hour, from: dueAt)
        lastUsedPeriod = hour >= 12 ? .pm : .am
        lastReminderTime = Date()
        print("🕐 Saved reminder for \(hour >= 12 ? "PM" : "AM"), tracking context")

        await NotificationsManager.shared.schedule(reminder: item)
        await DailyCloseoutManager.shared.scheduleIfNeeded(settings: settings, modelContext: modelContext)

        reset()
        
        // Build confirmation message
        var confirmMsg = "Saved!"
        if let early = finalEarlyAlert {
            confirmMsg += " (with \(formatEarlyAlert(early)) warning)"
        }
        if let warning = conflictWarning {
            confirmMsg += " \(warning)"
            conflictWarning = nil
        } else {
            confirmMsg += " What's next?"
        }
        prompt = confirmMsg
    }
    
    private func formatEarlyAlert(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hour"
        }
        return "\(minutes) min"
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

