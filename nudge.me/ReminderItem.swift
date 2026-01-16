import Foundation
import SwiftData

@Model
final class ReminderItem {
    enum Status: String, Codable, CaseIterable {
        case open
        case completed
    }
    
    // CloudKit requires all properties to be optional OR have default values
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date.now

    // Persist enum via raw string for SwiftData compatibility
    var statusRaw: String = "open"

    // Optional dates referenced by the app
    var dueAt: Date?
    var completedAt: Date?
    var alertAt: Date?
    
    // Early alert (minutes before due time, nil = no early alert)
    var earlyAlertMinutes: Int?

    // Computed convenience for working with enum type
    var status: Status {
        get { Status(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
    
    // Computed early alert date
    var earlyAlertAt: Date? {
        guard let due = dueAt, let minutes = earlyAlertMinutes, minutes > 0 else { return nil }
        return due.addingTimeInterval(-Double(minutes * 60))
    }

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        status: Status = .open,
        dueAt: Date? = nil,
        completedAt: Date? = nil,
        alertAt: Date? = nil,
        earlyAlertMinutes: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.statusRaw = status.rawValue
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.alertAt = alertAt
        self.earlyAlertMinutes = earlyAlertMinutes
    }
}
