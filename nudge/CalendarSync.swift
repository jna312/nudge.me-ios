import Foundation
import EventKit
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

final class CalendarSync {
    static let shared = CalendarSync()
    
    private var eventStore = EKEventStore()
    private var nudgeCalendar: EKCalendar?
    
    private init() {}
    
    // MARK: - Permission
    
    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        print("📅 Current calendar authorization status: \(status.rawValue)")
        
        switch status {
        case .authorized, .fullAccess:
            print("📅 Already have calendar access")
            return true
            
        case .denied, .restricted:
            print("📅 Calendar access denied or restricted")
            return false
            
        case .notDetermined, .writeOnly:
            print("📅 Requesting calendar access...")
            return await requestNewAccess()
            
        @unknown default:
            return await requestNewAccess()
        }
    }
    
    private func requestNewAccess() async -> Bool {
        do {
            let granted: Bool
            
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
            
            if granted {
                eventStore = EKEventStore()
                print("📅 Calendar access granted!")
            } else {
                print("📅 Calendar access denied by user")
            }
            return granted
        } catch {
            print("📅 Calendar access error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Calendar Setup
    
    private func getOrCreateNudgeCalendar() -> EKCalendar? {
        if let cached = nudgeCalendar, eventStore.calendar(withIdentifier: cached.calendarIdentifier) != nil {
            return cached
        }
        
        let calendars = eventStore.calendars(for: .event)
        print("📅 Available calendars: \(calendars.map { $0.title })")
        
        if let existing = calendars.first(where: { $0.title == "Nudge Reminders" }) {
            print("📅 Found existing Nudge Reminders calendar")
            nudgeCalendar = existing
            return existing
        }
        
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "Nudge Reminders"
        calendar.cgColor = UIColor.systemBlue.cgColor
        
        let sources = eventStore.sources
        print("📅 Available sources: \(sources.map { "\($0.title) - \($0.sourceType.rawValue)" })")
        
        if let iCloudSource = sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
            calendar.source = iCloudSource
            print("📅 Using iCloud source")
        } else if let localSource = sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
            print("📅 Using local source")
        } else if let defaultCal = eventStore.defaultCalendarForNewEvents {
            calendar.source = defaultCal.source
            print("📅 Using default calendar source")
        } else if let firstSource = sources.first {
            calendar.source = firstSource
            print("📅 Using first available source")
        } else {
            print("📅 ERROR: No calendar source available")
            return nil
        }
        
        do {
            try eventStore.saveCalendar(calendar, commit: true)
            print("📅 Created Nudge Reminders calendar successfully")
            nudgeCalendar = calendar
            return calendar
        } catch {
            print("📅 ERROR: Failed to create calendar: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Sync Reminder to Calendar
    
    @discardableResult
    func syncToCalendar(reminder: ReminderItem) async -> Bool {
        print("📅 Syncing reminder: \(reminder.title)")
        
        guard await requestAccess() else {
            print("📅 ERROR: No calendar access")
            return false
        }
        
        guard let calendar = getOrCreateNudgeCalendar() else {
            print("📅 ERROR: Could not get/create Nudge calendar")
            return false
        }
        
        guard let dueAt = reminder.dueAt else {
            print("📅 ERROR: Reminder has no due date")
            return false
        }
        
        let existingEvent = findEvent(for: reminder)
        
        if let event = existingEvent {
            event.title = reminder.title
            event.startDate = dueAt
            event.endDate = dueAt.addingTimeInterval(1800)
            
            do {
                try eventStore.save(event, span: .thisEvent)
                print("📅 Updated calendar event for: \(reminder.title)")
                return true
            } catch {
                print("📅 ERROR: Failed to update event: \(error.localizedDescription)")
                return false
            }
        } else {
            let event = EKEvent(eventStore: eventStore)
            event.title = reminder.title
            event.startDate = dueAt
            event.endDate = dueAt.addingTimeInterval(1800)
            event.calendar = calendar
            event.notes = "Created by Nudge\nID: \(reminder.id.uuidString)"
            
            let alarm = EKAlarm(relativeOffset: -900)
            event.addAlarm(alarm)
            
            do {
                try eventStore.save(event, span: .thisEvent)
                print("📅 Created calendar event for: \(reminder.title)")
                return true
            } catch {
                print("📅 ERROR: Failed to create event: \(error.localizedDescription)")
                return false
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
        
        let startDate = dueAt.addingTimeInterval(-86400)
        let endDate = dueAt.addingTimeInterval(86400)
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        return events.first { event in
            event.notes?.contains(reminder.id.uuidString) == true
        }
    }
    
    // MARK: - Sync All Reminders
    
    func syncAllReminders(from context: ModelContext) async -> (synced: Int, failed: Int) {
        print("📅 Starting sync of all reminders...")
        
        guard await requestAccess() else {
            print("📅 ERROR: No calendar access for sync all")
            return (0, 0)
        }
        
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" }
        )
        
        guard let reminders = try? context.fetch(descriptor) else {
            print("📅 ERROR: Could not fetch reminders")
            return (0, 0)
        }
        
        let remindersWithDue = reminders.filter { $0.dueAt != nil }
        print("📅 Found \(remindersWithDue.count) reminders to sync")
        
        var synced = 0
        var failed = 0
        
        for reminder in remindersWithDue {
            let success = await syncToCalendar(reminder: reminder)
            if success {
                synced += 1
            } else {
                failed += 1
            }
        }
        
        print("📅 Sync complete: \(synced) synced, \(failed) failed")
        return (synced, failed)
    }
    
    // MARK: - Import from Calendar
    
    func importFromCalendar(in context: ModelContext) async -> [ReminderItem] {
        guard await requestAccess() else { return [] }
        
        var imported: [ReminderItem] = []
        
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate)!
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        let existingDescriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" }
        )
        let existingReminders = (try? context.fetch(existingDescriptor)) ?? []
        let existingTitles = Set(existingReminders.map { $0.title.lowercased() })
        
        for event in events {
            guard !event.isAllDay else { continue }
            if event.notes?.contains("Created by Nudge") == true { continue }
            
            let eventTitle = event.title ?? "Calendar Event"
            
            if existingTitles.contains(eventTitle.lowercased()) {
                continue
            }
            
            let reminder = ReminderItem(
                title: eventTitle,
                dueAt: event.startDate,
                alertAt: event.startDate
            )
            
            context.insert(reminder)
            imported.append(reminder)
            
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
}
