import Foundation
import SwiftData
import UserNotifications

@MainActor
final class MorningBriefingManager {
    static let shared = MorningBriefingManager()
    private let briefingRequestID = "MORNING_BRIEFING"
    
    func scheduleIfNeeded(settings: AppSettings, modelContext: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        
        guard settings.morningBriefingEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [briefingRequestID])
            return
        }
        
        let now = Date()
        let minutes = settings.morningBriefingMinutes
        let hour = minutes / 60
        let minute = minutes % 60
        
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        
        guard let scheduledDate = Calendar.current.date(from: comps) else { return }
        let fireDate = scheduledDate > now
            ? scheduledDate
            : Calendar.current.date(byAdding: .day, value: 1, to: scheduledDate)!
        
        let dayStart = Calendar.current.startOfDay(for: fireDate)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { item in
                item.statusRaw == "open"
            }
        )
        
        let count = ErrorLogger.attempt("Counting reminders for morning briefing", operation: {
            let items = try modelContext.fetch(descriptor)
            return items.filter { item in
                guard let dueAt = item.dueAt else { return false }
                return dueAt >= dayStart && dueAt < dayEnd
            }.count
        }) ?? 0
        
        if count == 0 {
            center.removePendingNotificationRequests(withIdentifiers: [briefingRequestID])
            return
        }
        
        center.removePendingNotificationRequests(withIdentifiers: [briefingRequestID])
        
        let title = String(localized: "Morning Briefing")
        let countText = count == 1
            ? String(localized: "You have 1 nudge today.")
            : String(format: String(localized: "You have %lld nudges today."), Int64(count))
        let body = "\(countText) \(String(localized: "Open Nudge to review."))"
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let triggerComps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        
        let req = UNNotificationRequest(identifier: briefingRequestID, content: content, trigger: trigger)
        do {
            try await center.add(req)
        } catch {
            ErrorLogger.log(error, context: "Scheduling morning briefing notification")
        }
    }
    
    func scheduleUsingStoredSettings() async {
        let settings = AppSettings()
        guard let container = ErrorLogger.attempt("Creating model container", operation: {
            try ModelContainer(for: ReminderItem.self)
        }) else { return }
        
        let context = ModelContext(container)
        await scheduleIfNeeded(settings: settings, modelContext: context)
    }
}
