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

    private let parser = ReminderParser()
    
    func reset() {
        step = .idle
        prompt = "What do you want me to remind you about?"
        lastHeard = ""
        conflictWarning = nil
        timeSuggestions = []
    }

    func handleTranscript(
        _ transcript: String,
        settings: AppSettings,
        modelContext: ModelContext
    ) async {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lastHeard = t

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
                        settings: settings,
                        modelContext: modelContext
                    )
                } else {
                    step = .gotTask(title: draft.title)
                    timeSuggestions = TimeSuggestionEngine.getSuggestions(for: draft.title, in: modelContext)
                    prompt = "When? (e.g. \"at 3 PM\" or \"in 30 minutes\")"
                }

            case .needsWhen(let title, _):
                step = .gotTask(title: title)
                timeSuggestions = TimeSuggestionEngine.getSuggestions(for: title, in: modelContext)
                prompt = "When? (e.g. \"tomorrow at 3 PM\" or \"in 30 minutes\")"
                
            case .needsTime(let title, let baseDate, let periodHint):
                step = .needsTime(title: title, baseDate: baseDate, periodHint: periodHint)
                prompt = promptForTime(periodHint: periodHint)
            }

        case .gotTask(let title):
            let result = parser.parse(t)
            
            switch result {
            case .complete(let draft):
                if let due = draft.dueAt {
                    await prepareToSave(
                        title: title,
                        dueAt: due,
                        settings: settings,
                        modelContext: modelContext
                    )
                } else {
                    prompt = "I need a specific time. Try: \"at 3 PM\" or \"in 2 hours\""
                }
                
            case .needsTime(_, let baseDate, let periodHint):
                step = .needsTime(title: title, baseDate: baseDate, periodHint: periodHint)
                prompt = promptForTime(periodHint: periodHint)
                
            case .needsWhen:
                prompt = "I need a specific time. Try: \"at 3 PM\" or \"in 2 hours\""
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
                prompt = "What time? (e.g. \"9 AM\" or \"3:30 PM\")"
            }
            
        case .confirmDuplicate(let title, let dueAt, _):
            if parseYes(t) {
                await saveReminder(title: title, dueAt: dueAt, settings: settings, modelContext: modelContext)
            } else if parseNo(t) {
                reset()
                prompt = "Okay, cancelled. What else?"
            } else {
                prompt = "Say \"yes\" to save anyway, or \"no\" to cancel."
            }
            
        case .confirmEdit(let reminder, let newTime, let newTitle):
            if parseYes(t) {
                await applyEdit(reminder: reminder, newTime: newTime, newTitle: newTitle, modelContext: modelContext)
            } else if parseNo(t) {
                reset()
                prompt = "Okay, no changes made."
            } else {
                prompt = "Say \"yes\" to confirm or \"no\" to cancel."
            }
            
        case .confirmCancel(let reminders):
            if parseYes(t) {
                await deleteReminders(reminders, modelContext: modelContext)
            } else if parseNo(t) {
                reset()
                prompt = "Okay, nothing deleted."
            } else {
                prompt = "Say \"yes\" to delete or \"no\" to keep."
            }
        }
    }
    
    // MARK: - Prepare to Save (with duplicate & conflict checking)
    
    private func prepareToSave(
        title: String,
        dueAt: Date,
        settings: AppSettings,
        modelContext: ModelContext
    ) async {
        // Check for duplicates
        if let duplicate = DuplicateDetector.findDuplicate(title: title, dueAt: dueAt, in: modelContext) {
            step = .confirmDuplicate(title: title, dueAt: dueAt, existingReminder: duplicate)
            let timeStr = formatTime(duplicate.dueAt ?? dueAt)
            prompt = "You already have \"\(duplicate.title)\" at \(timeStr). Save anyway?"
            return
        }
        
        // Check for calendar conflicts
        let conflicts = await CalendarConflictDetector.checkConflicts(at: dueAt)
        if !conflicts.isEmpty {
            conflictWarning = "Heads up: You have \"\(conflicts.first!)\" around that time."
        }
        
        // Save the reminder
        await saveReminder(title: title, dueAt: dueAt, settings: settings, modelContext: modelContext)
    }
    
    // MARK: - Command Handlers
    
    private func handleCancelLast(modelContext: ModelContext) async {
        guard let last = ReminderSearch.findLast(in: modelContext) else {
            prompt = "No reminders to cancel."
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
        prompt = "Updated! What's next?"
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
            prompt = "Deleted. What's next?"
        } else {
            prompt = "Deleted \(reminders.count) reminders. What's next?"
        }
    }
    
    // MARK: - Helpers
    
    private func promptForTime(periodHint: String?) -> String {
        switch periodHint {
        case "morning":
            return "What time in the morning? (e.g. \"9 AM\")"
        case "afternoon":
            return "What time in the afternoon? (e.g. \"2 PM\")"
        case "evening":
            return "What time in the evening? (e.g. \"7 PM\")"
        case "night":
            return "What time at night? (e.g. \"9 PM\")"
        default:
            return "What time? (e.g. \"3 PM\")"
        }
    }
    
    private func parseTimeOnly(_ s: String) -> (hour: Int, minute: Int)? {
        let lower = normalizeNumberWords(s.lowercased())
        
        let patterns = [
            #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#,
            #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?"#
        ]
        
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(lower.startIndex..., in: lower)
            
            if let m = re.firstMatch(in: lower, range: range),
               let hrR = Range(m.range(at: 1), in: lower) {
                
                var hour = Int(lower[hrR]) ?? 0
                var minute = 0
                
                if let minR = Range(m.range(at: 2), in: lower) {
                    minute = Int(lower[minR]) ?? 0
                }
                
                if let ampmR = Range(m.range(at: 3), in: lower) {
                    let ampm = String(lower[ampmR]).lowercased()
                    if ampm == "pm" && hour < 12 { hour += 12 }
                    if ampm == "am" && hour == 12 { hour = 0 }
                }
                
                if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 {
                    return (hour, minute)
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
        settings: AppSettings,
        modelContext: ModelContext
    ) async {
        let styledTitle = applyWritingStyle(title, style: settings.writingStyle)

        let item = ReminderItem(
            title: styledTitle,
            dueAt: dueAt,
            alertAt: dueAt
        )

        modelContext.insert(item)
        lastSavedReminder = item
        try? modelContext.save()

        await NotificationsManager.shared.schedule(reminder: item)
        await DailyCloseoutManager.shared.scheduleIfNeeded(settings: settings, modelContext: modelContext)

        reset()
        
        if let warning = conflictWarning {
            prompt = "Saved! \(warning)"
            conflictWarning = nil
        } else {
            prompt = "Saved! What's next?"
        }
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
