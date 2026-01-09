import Foundation
import SwiftData

@Model
final class ReminderItem {
    var id: UUID
    var title: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}
