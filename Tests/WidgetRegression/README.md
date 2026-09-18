# Widget regression checks

Run `Tests/WidgetRegression/run.sh` on macOS with Xcode selected. It compiles the production widget snapshot rules, reminder model, and completion action, and runs 27 assertions against an in-memory SwiftData store.

Coverage: counts beyond five, retained overdue/future/undated reminders, completion filtering, deterministic ordering, 23/25-hour DST days, midnight and deadline timeline entries, bounded timeline size, absent/corrupt/legacy payloads, error state, exact-ID completion, persistence of both status fields, idempotence, stale deleted IDs, cleanup invocation, and refreshed widget data.

Notification, Calendar, briefing and widget publication dependencies are test doubles. These checks do not assert actual alert delivery or CloudKit propagation. Actual WidgetKit rendering and App Intent routing were separately checked on the iPhone 13 mini / iOS 26.4 simulator, including completion while the app is running and after terminating it.
