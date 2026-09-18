# Native capture redesign

Implemented September 17, 2026 against local main `ccd9b692eb1a7292c84e99363f3c16eec5eda570` (working-tree changes).

## Delivered

- Minimal SwiftUI capture with periwinkle accents, adaptive light/dark surfaces, one short idle prompt, and a compact upcoming-reminder row. Removed slogans, hero headings, sample sentences, and decorative empty-state cards after design feedback.
- Reminders uses native navigation and toolbar actions. Typing and save confirmation show only the necessary fields, status, and actions.
- The microphone is anchored above the bottom navigation in a thumb-friendly dock. Tap starts/stops; holding records until release. A single accessible UIKit control separates long presses from taps and supports accessibility activation.
- Compact clarification dock keeps Save reachable beside the mic. Editable reminder title, exact date, AM/PM and early-warning details persist through clarification. Capture cancellation is available in the header.
- Natural-language typing uses the same flow. Add remains above the software keyboard; manual date/time entry remains available.
- Saved receipt includes exact date/time and checked notification status, plus Edit and Undo. List completion/reopen controls have explicit accessibility labels; completion, deletion and Undo cancel both reminder alert identifiers in the changed UI paths.
- Capture has one owner. The Reminders tab opens Speak instead of maintaining a second recorder and follow-up timer. Recording awaits a final recognition result with a bounded timeout; stale sessions are rejected, interruptions are surfaced, and idle audio is not preactivated.
- Related fixes cover follow-up duration/date parsing, retaining ambiguous clocks and early warnings, clock range checks, explicit creation prefixes, exact confirmation answers, sentence-case names, and publishing save success after persistence/scheduling. Spoken “four thirty” and “fifteen-minute warning” are supported.
- Removed the obstructive tip overlays and their now-unused reset setting/timer code. Updated help for tap/hold behavior.

## Verification

- Debug iOS Simulator build: passed on Xcode 26.6. Existing `UIRequiresFullScreen` deprecation remains.
- `Tests/CaptureRegression/run.sh`: 20 checks passed against production logic with isolated service doubles.
- iPhone 17 / iOS 26.4 simulator: capture and list in light/dark, permission-denied recovery, natural-language typing, AM/PM clarification, exact saved receipt with disabled notifications, Undo, complete and reopen.
- iPhone 13 mini / iOS 26.4 simulator: bottom mic placement, software-keyboard creation action, clarification with all fields and pinned Save, plus two increases in preferred text size with scrolling content and persistent controls.
- Accessibility tree exposes the microphone as a state-labeled button rather than an always-recording image.
- After simplifying the UI: rebuilt successfully and checked the iPhone 13 mini capture screen, typing sheet, AM/PM selection, saved details, and native reminders list. The low microphone remains visible with an upcoming reminder.

## Remaining validation and audit work

Physical-device speech quality, long-press ergonomics, finalization latency, route interruptions, VoiceOver/Switch Control, maximum accessibility text sizes, locked-screen alerts and two-device synchronization have not been established by these checks. No accuracy percentage is claimed.

This change implements the capture UI and its supporting behavior. It does not complete the broader research roadmap: SpeechAnalyzer/model benchmarking, recurrence, comprehensive temporal parsing, remote CloudKit alert reconciliation, Calendar event identity and general mutation-service consolidation remain separate work. Subsequent widget work and related Siri/notification completion fixes are documented in `WIDGET_UI_IMPLEMENTATION.md`. Existing data/storage schema is unchanged.
