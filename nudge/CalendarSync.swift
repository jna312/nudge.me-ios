import Foundation
import EventKit
import SwiftData

final class CalendarSync {
    static let shared = CalendarSync()
    
    private let eventStore = EKEventStore()
    private var nudgeCalendar: EKCalendar?
    
    private init() {}
    
    // MARK: - Permission
    
    func requestAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            print("📅 Calendar access error: \(error)")
            return false
        }
    }
    
    // MARK: - Calendar Setup
    
    private func getOrCreateNudgeCalendar() -> EKCalendar? {
        // Check if we already have a Nudge calendar
        let calendars = eventStore.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == "Nudge Reminders" }) {
            return existing
        }
        
        // Create a new calendar
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "Nudge Reminders"
        calendar.cgColor = UIColor.systemBlue.cgColor
        
        // Find a source to use
        if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else if let iCloudSource = eventStore.sources.first(where: { $0.sourceType == .calDAV }) {
            calendar.source = iCloudSource
        } else if let defaultSource = eventStore.defaultCalendarForNewEvents?.source {
            calendar.source = defaultSource
        } else {
            print("📅 No calendar source available")
            return nil
        }
        
        do {
            try eventStore.saveCalendar(calendar, commit: true)
            print("📅 Created Nudge Reminders calendar")
            return calendar
        } catch {
            print("📅 Failed to create calendar: \(error)")
            return nil
        }
    }
    
    // MARK: - Sync Reminder to Calendar
    
    func syncToCalendar(reminder: ReminderItem) async {
        guard await requestAccess() else { return }
        
        guard let calendar = getOrCreateNudgeCalendar(),
              let dueAt = reminder.dueAt else { return }
        
        // Check if event already exists
        let existingEvent = findEvent(for: reminder)
        
        if let event = existingEvent {
            // Update existing event
            event.title = reminder.title
            event.startDate = dueAt
            event.endDate = dueAt.addingTimeInterval(1800) // 30 min duration
            
            do {
                try eventStore.save(event, span: .thisEvent)
                print("📅 Updated calendar event for: \(reminder.title)")
            } catch {
                print("📅 Failed to update event: \(error)")
            }
        } else {
            // Create new event
            let event = EKEvent(eventStore: eventStore)
            event.title = reminder.title
            event.startDate = dueAt
            event.endDate = dueAt.addingTimeInterval(1800) // 30 min duration
            event.calendar = calendar
            event.notes = "Created by Nudge\nID: \(reminder.id.uuidString)"
            
            // Add alert 15 minutes before
            let alarm = EKAlarm(relativeOffset: -900) // 15 min before
            event.addAlarm(alarm)
            
            do {
                try eventStore.save(event, span: .thisEvent)
                print("📅 Created calendar event for: \(reminder.title)")
            } catch {
                print("📅 Failed to create event: \(error)")
            }
        }
    }
    
    // MARK: - Remove from Calendar
    
    func removeFromCalendar(reminder: ReminderItem) async {
        guard await requestAccess() else { return }
        
        if let event = findEvent(for: reminder) {
            do {
                try eventStore.remove(event, span: .thisEvent)
                print("📅 Removed calendar event for: \(reminder.title)")
            } catch {
                print("📅 Failed to remove event: \(error)")
            }
        }
    }
    
    // MARK: - Find Event
    
    private func findEvent(for reminder: ReminderItem) -> EKEvent? {
        guard let dueAt = reminder.dueAt else { return nil }
        
        let startDate = dueAt.addingTimeInterval(-86400) // 1 day before
        let endDate = dueAt.addingTimeInterval(86400)    // 1 day after
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        // Find event with matching Nudge ID in notes
        return events.first { event in
            event.notes?.contains(reminder.id.uuidString) == true
        }
    }
    
    // MARK: - Import from Calendar
    
    func importFromCalendar(in context: ModelContext) async -> [ReminderItem] {
        guard await requestAccess() else { return [] }
        
        var imported: [ReminderItem] = []
        
        // Get events for the next 7 days
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        for event in events {
            // Skip all-day events
            guard !event.isAllDay else { continue }
            
            // Skip events already from Nudge
            if event.notes?.contains("Created by Nudge") == true { continue }
            
            // Check if we already have this reminder
            let existingDescriptor = FetchDescriptor<ReminderItem>(
                predicate: #Predicate { item in
                    item.statusRaw == "open" && item.title == event.title
                }
            )
            
            if let existing = try? context.fetch(existingDescriptor), !existing.isEmpty {
                continue // Already exists
            }
            
            // Create reminder from event
            let reminder = ReminderItem(
                title: event.title ?? "Calendar Event",
                dueAt: event.startDate,
                alertAt: event.startDate
            )
            
            context.insert(reminder)
            imported.append(reminder)
            
            // Schedule notification
            Task {
                await NotificationsManager.shared.schedule(reminder: reminder)
            }
        }
        
        if !imported.isEmpty {
            try? context.save()
            print("📅 Imported \(imported.count) events from calendar")
        }
        
        return imported
    }
    
    // MARK: - Sync All Reminders
    
    func syncAllReminders(from context: ModelContext) async {
        guard await requestAccess() else { return }
        
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" && $0.dueAt != nil }
        )
        
        guard let reminders = try? context.fetch(descriptor) else { return }
        
        for reminder in reminders {
            await syncToCalendar(reminder: reminder)
        }
        
        print("📅 Synced \(reminders.count) reminders to calendar")
    }
}
