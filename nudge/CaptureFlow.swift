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
    @Published var prompt: String = ""
    @Published var lastHeard: String = ""
    @Published var step: CaptureStep = .idle
    @Published var lastSavedReminder: ReminderItem?
    @Published var conflictWarning: String? = nil
    @Published var timeSuggestions: [Date] = []
    @Published var needsFollowUp: Bool = false  // Signals ContentView to auto-listen

    private let parser = ReminderParser()
    
    init() {
        prompt = String(localized: "What do you want me to remind you about?")
    }
    
    func reset() {
        step = .idle
        prompt = String(localized: "What do you want me to remind you about?")
        lastHeard = ""
        conflictWarning = nil
        timeSuggestions = []
        needsFollowUp = false
        pendingEarlyAlertMinutes = nil
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
            let timeStr = formatTimeWithContext(duplicate.dueAt ?? dueAt)
            prompt = String(localized: "You already have \"\(duplicate.title)\" at \(timeStr). Save anyway?"
            needsFollowUp = true
            return
        }
        
        // Check for calendar conflicts
        let conflicts = await CalendarConflictDetector.checkConflicts(at: dueAt)
        if !conflicts.isEmpty {
            // Show conflict resolution options
            step = .calendarConflict(title: title, dueAt: dueAt, conflictingEvents: conflicts)
            let eventNames = conflicts.joined(separator: ", ")
            prompt = String(localized: "You have \"\(eventNames)\" at that time. Say \"merge\" to combine, \"change time\", or \"save anyway\"."
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
        prompt = String(localized: "Cancel \"\(last.title)\"?")
    }
    
    private func handleCancelByName(_ searchTerm: String, modelContext: ModelContext) async {
        let matches = ReminderSearch.find(matching: searchTerm, in: modelContext)
        
        if matches.isEmpty {
            prompt = String(localized: "I couldn't find a reminder matching \"\(searchTerm)\"."
            return
        }
        
        if matches.count == 1 {
            step = .confirmCancel(reminders: matches)
            prompt = String(localized: "Cancel \"(matches[0].title)\"?")
        } else {
            step = .confirmCancel(reminders: matches)
            prompt = String(localized: "Found \(matches.count) reminders matching \"\(searchTerm)\". Cancel all?"
        }
    }
    
    private func handleCancelAllForDate(_ date: Date, modelContext: ModelContext) async {
        let reminders = ReminderSearch.findForDate(date, in: modelContext)
        
        if reminders.isEmpty {
            let dayStr = Calendar.current.isDateInToday(date) ? "today" : "tomorrow"
            prompt = String(localized: "No reminders for \(dayStr)."
            return
        }
        
        step = .confirmCancel(reminders: reminders)
        let dayStr = Calendar.current.isDateInToday(date) ? "today" : "tomorrow"
        prompt = String(localized: "Cancel all \(reminders.count) reminders for \(dayStr)?"
    }
    
    private func handleEditReminder(_ searchTerm: String, newTime: Date?, newTitle: String?, modelContext: ModelContext) async {
        let matches = ReminderSearch.find(matching: searchTerm, in: modelContext)
        
        if matches.isEmpty {
            prompt = String(localized: "I couldn't find a reminder matching \"\(searchTerm)\"."
            return
        }
        
        let reminder = matches[0]
        step = .confirmEdit(reminder: reminder, newTime: newTime, newTitle: newTitle)
        
        if let time = newTime {
            prompt = String(localized: "Move \"\(reminder.title)\" to \(formatTimeWithContext(time))?")
        } else if let title = newTitle {
            prompt = String(localized: "Change \"\(reminder.title)\" to \"\(title)\"?")
        } else {
            prompt = String(localized: "What would you like to change about \"\(reminder.title)\"?")
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
        
        modelContext.saveWithLogging(context: "Saving reminder")
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
        
        modelContext.saveWithLogging(context: "Saving reminder")
        reset()
        
        if reminders.count == 1 {
            prompt = String(localized: "Deleted. What's next?")
        } else {
            prompt = String(localized: "Deleted \(reminders.count) reminders. What's next?"
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
        var lower = s.normalizeNumberWords()
        
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
                        return (hour, minute)
                    }
                }
            }
        }
        
        // Pattern without AM/PM (only use if no am/pm in input)
        if !lower.contains("am") && !lower.contains("pm") {
            let simplePattern = #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?"#
            if let re = try? NSRegularExpression(pattern: simplePattern, options: [.caseInsensitive]) {
                let range = NSRange(lower.startIndex..., in: lower)
                if let m = re.firstMatch(in: lower, range: range),
                   let hrR = Range(m.range(at: 1), in: lower) {
                    
                    let hour = Int(lower[hrR]) ?? 0
                    var minute = 0
                    
                    if let minR = Range(m.range(at: 2), in: lower) {
                        minute = Int(lower[minR]) ?? 0
                    }
                    // For ambiguous hours (1-12), don't guess - ask the user to specify AM or PM
                    if hour >= 1 && hour <= 12 {
                        return nil  // Will prompt user to specify AM or PM
                    }
                    
                    // Unambiguous hours (0, 13-23) can be used directly
                    if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 {
                        return (hour, minute)
                    }
                }
            }
        }
        
        return nil
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
        modelContext.saveWithLogging(context: "Saving reminder")

        await NotificationsManager.shared.schedule(reminder: item)
        await DailyCloseoutManager.shared.scheduleIfNeeded(settings: settings, modelContext: modelContext)

        reset()
        
        // Build confirmation message
        var confirmMsg = String(localized: "Saved!")
        if let early = finalEarlyAlert {
            confirmMsg += " (\(String(localized: "with")) \(formatMinutes(early)) \(String(localized: "warning")))"
        }
        if let warning = conflictWarning {
            confirmMsg += " \(warning)"
            conflictWarning = nil
        } else {
            confirmMsg += " \(String(localized: "What's next?"))"
        }
        prompt = confirmMsg
    }
}

