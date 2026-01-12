import Foundation
import SwiftData
import Combine

enum CaptureStep: Equatable {
    case idle
    case gotTask(title: String)
    case needsTime(title: String, baseDate: Date, periodHint: String?)
}

@MainActor
final class CaptureFlow: ObservableObject {
    @Published var prompt: String = "What do you want me to remind you about?"
    @Published var lastHeard: String = ""
    @Published var step: CaptureStep = .idle
    @Published var lastSavedReminder: ReminderItem?

    private let parser = ReminderParser()
    
    func reset() {
        step = .idle
        prompt = "What do you want me to remind you about?"
        lastHeard = ""
    }

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
            let result = parser.parse(t)

            switch result {
            case .complete(let draft):
                if let due = draft.dueAt {
                    await saveReminder(
                        title: draft.title,
                        dueAt: due,
                        settings: settings,
                        modelContext: modelContext
                    )
                } else {
                    step = .gotTask(title: draft.title)
                    prompt = "When? (e.g. \"at 3 PM\" or \"in 30 minutes\")"
                }

            case .needsWhen(let title, _):
                step = .gotTask(title: title)
                prompt = "When? (e.g. \"tomorrow at 3 PM\" or \"in 30 minutes\")"
                
            case .needsTime(let title, let baseDate, let periodHint):
                step = .needsTime(title: title, baseDate: baseDate, periodHint: periodHint)
                prompt = promptForTime(periodHint: periodHint)
            }

        case .gotTask(let title):
            // User is providing the time separately
            let result = parser.parse(t)
            
            switch result {
            case .complete(let draft):
                if let due = draft.dueAt {
                    await saveReminder(
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
            // User should be providing a specific time now
            if let time = parseTimeOnly(t) {
                let due = combineDateAndTime(baseDate: baseDate, time: time)
                await saveReminder(
                    title: title,
                    dueAt: due,
                    settings: settings,
                    modelContext: modelContext
                )
            } else {
                prompt = "What time? (e.g. \"9 AM\" or \"3:30 PM\")"
            }
        }
    }
    
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
        
        // Match patterns like "9", "9 AM", "9:30 PM", "at 3"
        let patterns = [
            #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)"#,  // with AM/PM
            #"(?:at\s+)?(\d{1,2})(?::(\d{2}))?"#              // without AM/PM
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
        prompt = "Saved! What's next?"
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
