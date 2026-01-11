import Foundation
import SwiftData

@Model
final class ReminderItem {
    enum Status: String, Codable, CaseIterable {
        case open
        case completed
    }
    enum RepeatRule: String, Codable, CaseIterable {
        case none
        case daily
        case weekly
        case weekdays
    }
    
    var repeatRuleRaw: String
    var repeatRule: RepeatRule {
        get { RepeatRule(rawValue: repeatRuleRaw) ?? .none }
        set { repeatRuleRaw = newValue.rawValue }
    }
    var id: UUID
    var title: String
    var createdAt: Date

    // Persist enum via raw string for SwiftData compatibility
    var statusRaw: String

    // Optional dates referenced by the app
    var dueAt: Date?
    var completedAt: Date?
    var alert1At: Date?
    var alert2At: Date?

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
        alert1At: Date? = nil,
        alert2At: Date? = nil,
        repeatRule: RepeatRule = .none
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.statusRaw = status.rawValue
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.alert1At = alert1At
        self.alert2At = alert2At
        self.repeatRuleRaw = repeatRule.rawValue
    }
}
