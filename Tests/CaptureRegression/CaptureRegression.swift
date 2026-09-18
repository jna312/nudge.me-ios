import Foundation
import SwiftData

@main
struct CaptureRegression {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ description: String) {
            guard condition else { fatalError("FAIL: \(description)") }
            checks += 1
            print("PASS: \(description)")
        }
        let calendar = Calendar.current
        let parser = ReminderParser()
        let spoken = "Call Maya tomorrow at four thirty, and give me a fifteen-minute warning"
        check(parser.ambiguousClockTime(in: spoken) == "4:30", "spoken ambiguous clock retained")
        check(parser.earlyWarning(in: spoken) == 15, "spoken hyphenated warning recognized")
        if case .complete(let draft) = parser.parse("Call NASA tomorrow at sixteen") {
            check(draft.title == "Call NASA", "spoken clock stripping respects number-word boundaries")
        } else { check(false, "spoken 24-hour clock parses") }

        func newContext() throws -> ModelContext {
            let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return ModelContext(try ModelContainer(for: ReminderItem.self, configurations: config))
        }
        let settings = AppSettings()
        let context = try newContext()
        let flow = CaptureFlow()
        await flow.handleTranscript(spoken, settings: settings, modelContext: context)
        check(flow.draftTitle == "Call Maya", "title excludes spoken scheduling phrases")
        check(flow.draftDate.map { calendar.isDateInTomorrow($0) } == true, "clarification keeps tomorrow")
        check(flow.ambiguousTime == "4:30", "clarification exposes AM/PM choice")
        check(flow.pendingEarlyAlertMinutes == 15, "clarification retains early warning")
        flow.updateDraftTitle("Call NASA and John")
        await flow.handleTranscript("PM", settings: settings, modelContext: context)
        let saved = flow.lastSavedReminder
        check(saved?.title == "Call NASA and John", "editing draft preserves proper names")
        check(saved?.dueAt.map { calendar.isDateInTomorrow($0) && calendar.component(.hour, from: $0) == 16 && calendar.component(.minute, from: $0) == 30 } == true, "PM resolves exact original day and clock")
        check(saved?.earlyAlertMinutes == 15, "saved reminder retains early warning")
        check(saved.map { NotificationsManager.shared.scheduledIDs.contains($0.id) } == true, "receipt published after alert scheduling")
        check(try context.fetch(FetchDescriptor<ReminderItem>()).count == 1, "exactly one reminder persisted")

        let relative = CaptureFlow()
        let relativeContext = try newContext()
        await relative.handleTranscript("Call mom", settings: settings, modelContext: relativeContext)
        let before = Date()
        await relative.handleTranscript("in 20 minutes", settings: settings, modelContext: relativeContext)
        let interval = relative.lastSavedReminder?.dueAt?.timeIntervalSince(before) ?? 0
        check((1199...1203).contains(interval), "follow-up duration means twenty minutes, not 20:00")

        let explicit = CaptureFlow()
        await explicit.handleTranscript("Call mom", settings: settings, modelContext: try newContext())
        await explicit.handleTranscript("tomorrow at 11 PM", settings: settings, modelContext: try newContext())
        check(explicit.lastSavedReminder?.dueAt.map { calendar.isDateInTomorrow($0) && calendar.component(.hour, from: $0) == 23 } == true, "follow-up explicit day is not discarded")

        let warning = CaptureFlow()
        let warningContext = try newContext()
        await warning.handleTranscript("Call mom tomorrow with a 30 minute warning", settings: settings, modelContext: warningContext)
        await warning.handleTranscript("3 PM", settings: settings, modelContext: warningContext)
        check(warning.lastSavedReminder?.earlyAlertMinutes == 30, "warning survives a missing-time answer")

        let invalid = CaptureFlow()
        await invalid.handleTranscript("Call mom tomorrow at 25:99", settings: settings, modelContext: try newContext())
        check(invalid.lastSavedReminder == nil, "invalid clock cannot create a reminder")

        let cancellation = CaptureFlow()
        let cancellationContext = try newContext()
        let existing = ReminderItem(title: "Keep this reminder", dueAt: .now.addingTimeInterval(3600))
        cancellationContext.insert(existing)
        try cancellationContext.save()
        cancellation.step = .confirmCancel(reminders: [existing])
        await cancellation.handleTranscript("yesterday", settings: settings, modelContext: cancellationContext)
        check(try cancellationContext.fetch(FetchDescriptor<ReminderItem>()).count == 1, "yesterday is not a yes confirmation")

        let creation = CaptureFlow()
        await creation.handleTranscript("Remind me to cancel Netflix tomorrow at 3 PM", settings: settings, modelContext: try newContext())
        check(creation.lastSavedReminder?.title == "Cancel Netflix", "explicit creation phrase is not a delete command")
        check(applyWritingStyle("Call NASA and John", style: "sentence") == "Call NASA and John", "sentence case preserves names")
        check(applyWritingStyle("Call Maya", style: "caps") == "CALL MAYA", "configured uppercase style works")
        print("\(checks) capture regression checks passed. Audio, notifications and Calendar use test doubles.")
    }
}
