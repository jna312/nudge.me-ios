# Capture regression checks

Run `./Tests/CaptureRegression/run.sh` from the repository root on macOS with Xcode installed.

The runner compiles the actual parser, conversation flow, model, command detection, search and formatting code. It uses in-memory SwiftData and replaces external notification, Calendar, widget and briefing services with no-op test doubles. Its 20 assertions cover ambiguous spoken times, field preservation through clarification, proper names, explicit follow-up dates, elapsed durations, invalid clocks, confirmation routing and save ordering.

This is a focused logic regression suite, not a microphone accuracy benchmark. Real audio, permission prompts, interruptions, notification delivery and CloudKit still require iPhone integration tests. The full audit's unrelated date/year, recurrence, calendar identity and sync findings are not claimed fixed by this suite.
