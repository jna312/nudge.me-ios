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
    private var syncTimer: Timer?
    private var modelContext: ModelContext?
    
    private init() {}
    
    // MARK: - Auto-Sync Timer
    
    /// Start automatic sync with the specified frequency (in minutes)
    func startAutoSync(frequency: Int, context: ModelContext) {
        stopAutoSync()
        modelContext = context
        
        let interval = TimeInterval(frequency * 60)
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self, let ctx = self.modelContext else { return }
            Task {
                await self.syncAllReminders(from: ctx)
            }
        }
    }
    
    /// Stop automatic sync
    func stopAutoSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        modelContext = nil
    }
    
    /// Check if auto-sync is running
    var isAutoSyncRunning: Bool {
        syncTimer != nil
    }
    
    // MARK: - Permission
    
    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .authorized, .fullAccess:
            return true
            
        case .denied, .restricted:
            return false
            
        case .notDetermined, .writeOnly:
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
            } else {
            }
            return granted
        } catch {
            return false
        }
    }
    
    // MARK: - Calendar Setup
    
    private func getOrCreateNudgeCalendar() -> EKCalendar? {
        if let cached = nudgeCalendar, eventStore.calendar(withIdentifier: cached.calendarIdentifier) != nil {
            return cached
        }
        
        let calendars = eventStore.calendars(for: .event)
        
        if let existing = calendars.first(where: { $0.title == "Nudge Reminders" }) {
            nudgeCalendar = existing
            return existing
        }
        
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "Nudge Reminders"
        calendar.cgColor = UIColor.systemBlue.cgColor
        
        let sources = eventStore.sources
        
        if let iCloudSource = sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }) {
            calendar.source = iCloudSource
        } else if let localSource = sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        } else if let defaultCal = eventStore.defaultCalendarForNewEvents {
            calendar.source = defaultCal.source
        } else if let firstSource = sources.first {
            calendar.source = firstSource
        } else {
            return nil
        }
        
        do {
            try eventStore.saveCalendar(calendar, commit: true)
            nudgeCalendar = calendar
            return calendar
        } catch {
            return nil
        }
    }
    
    // MARK: - Sync Reminder to Calendar
    
    @discardableResult
    func syncToCalendar(reminder: ReminderItem) async -> Bool {
        
        guard await requestAccess() else {
            return false
        }
        
        guard let calendar = getOrCreateNudgeCalendar() else {
            return false
        }
        
        guard let dueAt = reminder.dueAt else {
            return false
        }
        
        let existingEvent = findEvent(for: reminder)
        
        if let event = existingEvent {
            event.title = reminder.title
            event.startDate = dueAt
            event.endDate = dueAt.addingTimeInterval(1800)
            
            do {
                try eventStore.save(event, span: .thisEvent)
                return true
            } catch {
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
                return true
            } catch {
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
            } catch {
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
        
        guard await requestAccess() else {
            return (0, 0)
        }
        
        let descriptor = FetchDescriptor<ReminderItem>(
            predicate: #Predicate { $0.statusRaw == "open" }
        )
        
        guard let reminders = ErrorLogger.attempt("Fetching reminders for calendar sync", operation: {
            try context.fetch(descriptor)
        }) else {
            return (0, 0)
        }
        
        let remindersWithDue = reminders.filter { $0.dueAt != nil }
        
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
        let existingReminders = ErrorLogger.attempt("Fetching existing calendar reminders", operation: { try context.fetch(existingDescriptor) }) ?? []
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
            context.saveWithLogging(context: "Saving calendar import")
        }
        
        return imported
    }
}
