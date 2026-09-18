import AppIntents
import Foundation
#if !NUDGE_WIDGET_EXTENSION
import SwiftData
#endif

struct CompleteWidgetReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete reminder"
    static let isDiscoverable = false
    // The iOS 26 replacement for ForegroundContinuableIntent. Runs in the app
    // process in the background, where the existing SwiftData store is owned.
    static var supportedModes: IntentModes { .foreground(.dynamic) }

    @Parameter(title: "Reminder ID") var reminderID: String

    init() {}
    init(id: UUID) { reminderID = id.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if NUDGE_WIDGET_EXTENSION
        // This body must not mutate a snapshot or claim a successful completion
        // if the system cannot route the action to the containing app.
        WidgetSharedStore.defaults?.set(true, forKey: WidgetSharedStore.completionErrorKey)
        #else
        do {
            guard let id = UUID(uuidString: reminderID) else { throw InvalidReminderID() }
            try await WidgetReminderActions.complete(id: id, context: NudgePersistence.shared.mainContext)
        } catch {
            WidgetSharedStore.defaults?.set(true, forKey: WidgetSharedStore.completionErrorKey)
            ErrorLogger.log(error, context: "Completing reminder from widget")
        }
        #endif
        return .result()
    }
}

private struct InvalidReminderID: Error {}
