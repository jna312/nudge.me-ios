# Widget update — September 18, 2026

## Delivered

- All three Home Screen sizes use the app's periwinkle colors and simple typography. Shared colors compile into both targets.
- Small: voice shortcut and open/overdue status. Medium: two actionable rows, full open count, and voice shortcut. Large: five actionable rows, full count, remaining-item link, and voice shortcut. Accessibility text sizes reduce visible row counts.
- Counts come from the complete open set, not a five-item preview. Overdue reminders remain visible first; future and undated reminders remain available. Unknown or corrupt data shows an open-app state instead of claiming there are no reminders.
- Reminder titles open the exact reminder. Completion circles invoke an App Intent in the containing app's process, update both completion fields, save before notification cleanup/publication, and retain the app's existing SwiftData/CloudKit configuration and location. No new CloudKit capability or storage migration is introduced.
- Completion is idempotent. A stale deleted ID refreshes the snapshot. A failure leaves the reminder visible and exposes an open-app error link. Any legacy pending completion is cleared only after a successful action.
- The existing complete-by-title Siri intent and notification completion action reuse the new completion action. Snapshot updates also cover Siri creation, notification snooze/closeout, foreground refresh, and reminder changes observed by the running app.
- Timelines include due-time transitions and calendar-based local midnight rather than assuming every day is 86,400 seconds. iOS still controls refresh scheduling.
- Tinted/clear rendering uses a monochrome microphone with a translucent circle; full-color modes retain the periwinkle orb. Overdue state has a text label as well as color.

## Verification

- Signed Debug iOS Simulator build succeeded for app and widget extension. Existing `UIRequiresFullScreen` deprecation remains.
- Release iPhoneOS build succeeded for app and widget extension before the App Store Connect upload. Signing and distribution are handled by the existing Xcode Cloud workflow.
- 27 widget regressions passed; the existing 20 capture regressions also passed.
- Added small, medium and large widgets through the actual Home Screen gallery on the isolated `Nudge Compact UI` iPhone 13 mini / iOS 26.4 simulator.
- Verified all sizes in the gallery and on the Home Screen. Six synthetic open reminders displayed a total of six; large displayed five rows and `1 more`; overdue, upcoming and tomorrow dates were visible.
- Completed a reminder from the medium widget without opening the app. Both widgets refreshed; opening the list showed it under Completed. Reopening it restored the widget.
- Terminated the app, then completed another reminder from the large widget. The action launched the app in the background, left the Home Screen visible, and updated both widget counts.
- Tapping `Review the notes` opened that exact reminder's edit sheet with September 19, 2026 at 11 AM.
- Inspected large/medium widgets in light, dark, tinted and clear modes. Saved unedited Simulator screenshots under the task's `widgets` artifacts directory.

Physical-device voice input, locked-screen alert delivery, two-device CloudKit behavior, maximum accessibility sizes and a VoiceOver session were not established by this pass. This adds no Lock Screen widget family. The widget changes ship with the capture and parser changes described in `CAPTURE_UI_IMPLEMENTATION.md`.

## Apple references

- [Interactive widgets and execution context](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [App Intent supported modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
- [Dynamic foreground mode](https://developer.apple.com/documentation/appintents/intentmodes/foregroundmode/dynamic)
- [Accented rendering and Liquid Glass](https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass)
