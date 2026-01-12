import Foundation
import SwiftData

@Model
final class ReminderItem {
    enum Status: String, Codable, CaseIterable {
        case open
        case completed
    }
    
    var id: UUID
    var title: String
    var createdAt: Date

    // Persist enum via raw string for SwiftData compatibility
    var statusRaw: String

    // Optional dates referenced by the app
    var dueAt: Date?
    var completedAt: Date?
    var alertAt: Date?

    // Computed convenience for working with enum type
    var status: Status {
        get { Status(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = .now,
        status: Status = .open,
        dueAt: Date? = nil,
        completedAt: Date? = nil,
        alertAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.statusRaw = status.rawValue
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.alertAt = alertAt
    }
}
