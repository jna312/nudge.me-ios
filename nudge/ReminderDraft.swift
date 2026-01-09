import Foundation

struct ReminderDraft {
    var rawTranscript: String
    var title: String
    var dueAt: Date?
    var wantsAlert1: Bool
    var alert2OffsetSeconds: TimeInterval?
}
