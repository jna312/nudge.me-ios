import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            // Quick Start
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Hold the mic button and speak", systemImage: "1.circle.fill")
                    Label("Say what and when (e.g. \"Call mom tomorrow at 3 PM\")", systemImage: "2.circle.fill")
                    Label("Release to save — that's it!", systemImage: "3.circle.fill")
                }
                .padding(.vertical, 8)
            } header: {
                Label("Quick Start", systemImage: "sparkles")
            }
            
            // Voice Commands
            Section {
                HelpRow(
                    title: "Create a reminder",
                    examples: [
                        "\"Call dentist tomorrow at 3 PM\"",
                        "\"Buy groceries in 30 minutes\"",
                        "\"Meeting next Monday at 9 AM\""
                    ]
                )
                
                HelpRow(
                    title: "Add an early warning",
                    examples: [
                        "\"Meeting at 2 PM with a 15 minute warning\"",
                        "\"Doctor at 10 AM with an early alert\"",
                        "\"Call mom at 5 PM, warn me 30 minutes before\""
                    ]
                )
                
                HelpRow(
                    title: "Edit a reminder",
                    examples: [
                        "\"Change dentist to 4 PM\"",
                        "\"Move groceries to tomorrow\"",
                        "\"Reschedule meeting to 10 AM\"",
                        "\"Move groceries 30 minutes later\""
                    ]
                )
                
                HelpRow(
                    title: "Cancel reminders",
                    examples: [
                        "\"Cancel my last reminder\"",
                        "\"Delete the dentist reminder\"",
                        "\"Cancel all reminders for tomorrow\""
                    ]
                )
            } header: {
                Label("Voice Commands", systemImage: "mic.fill")
            }
            
            // Time Formats
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    TimeFormatRow(format: "at 3 PM", description: "Specific time")
                    TimeFormatRow(format: "in 30 minutes", description: "Relative time")
                    TimeFormatRow(format: "tomorrow at 9 AM", description: "Day + time")
                    TimeFormatRow(format: "next Monday at 2 PM", description: "Weekday + time")
                    TimeFormatRow(format: "in 2 hours", description: "Hours from now")
                }
                .padding(.vertical, 4)
            } header: {
                Label("Time Formats", systemImage: "clock")
            } footer: {
                Text("Always include AM or PM when saying a time — Nudge will ask if you forget.")
            }
            
            // Input Methods
            Section {
                FeatureRow(
                    icon: "hand.tap.fill",
                    title: "Hold to Speak",
                    description: "Hold the mic button, speak your reminder with a time, then release to save."
                )
                
                FeatureRow(
                    icon: "mic.badge.plus",
                    title: "Auto-Listen",
                    description: "When Nudge asks a follow-up question (like confirming a conflict), the mic activates automatically."
                )
                
                FeatureRow(
                    icon: "keyboard",
                    title: "Type Instead",
                    description: "Tap \"Type instead\" to add reminders with the keyboard. You can also set an early warning from this screen."
                )
            } header: {
                Label("Input Methods", systemImage: "rectangle.and.pencil.and.ellipsis")
            }
            
            // Notifications
            Section {
                FeatureRow(
                    icon: "bell.badge",
                    title: "Early Warnings",
                    description: "Get a heads-up notification before your reminder (e.g. \"⏰ 15 minutes warning — Call mom at 3:30 PM\")."
                )
                
                FeatureRow(
                    icon: "bell.and.waves.left.and.right",
                    title: "Default Early Alert",
                    description: "Set a default warning time in Settings so every reminder gets a heads-up automatically."
                )
                
                FeatureRow(
                    icon: "timer",
                    title: "Snooze from Notification",
                    description: "Snooze a reminder for 5, 15, or 30 minutes right from the notification."
                )
                
                FeatureRow(
                    icon: "moon.fill",
                    title: "Daily Closeout",
                    description: "At 9 PM, Nudge reminds you to review any uncompleted reminders for the day."
                )
                
                FeatureRow(
                    icon: "sunrise.fill",
                    title: "Morning Briefing",
                    description: "Start your day with a quick summary of today's reminders."
                )
            } header: {
                Label("Notifications", systemImage: "bell.fill")
            }
            
            // Managing Reminders
            Section {
                FeatureRow(
                    icon: "checkmark.circle",
                    title: "Complete",
                    description: "Tap the circle next to any reminder to mark it done."
                )
                
                FeatureRow(
                    icon: "hand.draw",
                    title: "Swipe Actions",
                    description: "Swipe left to delete, swipe right to snooze for 10 minutes, 30 minutes, 1 hour, or 1 day."
                )
                
                FeatureRow(
                    icon: "arrow.uturn.backward",
                    title: "Undo",
                    description: "Made a mistake? Tap \"Undo\" within 5 seconds after creating a reminder."
                )
            } header: {
                Label("Managing Reminders", systemImage: "checklist")
            }
            
            // Smart Features
            Section {
                FeatureRow(
                    icon: "doc.on.doc",
                    title: "Duplicate Detection",
                    description: "Nudge warns you if you're creating a reminder similar to an existing one."
                )
                
                FeatureRow(
                    icon: "calendar.badge.exclamationmark",
                    title: "Calendar Conflicts",
                    description: "Get a heads-up if your reminder overlaps with a calendar event. You can merge, change time, or save anyway."
                )
                
                FeatureRow(
                    icon: "lightbulb",
                    title: "Smart Suggestions",
                    description: "Nudge learns your preferred times and suggests them when you create reminders."
                )
            } header: {
                Label("Smart Features", systemImage: "brain")
            }
            
            // Siri Shortcuts
            Section {
                FeatureRow(
                    icon: "mic.circle.fill",
                    title: "\"Hey Siri, Nudge me\"",
                    description: "Create a reminder using only your voice. Siri asks what you want to be reminded about, then when to remind you."
                )
            } header: {
                Label("Siri Shortcuts", systemImage: "apple.intelligence")
            } footer: {
                Text("Run the app once to register shortcuts with Siri")
            }
            
            // Optional Features
            Section {
                FeatureRow(
                    icon: "calendar",
                    title: "Calendar Sync",
                    description: "Automatically sync reminders to Apple Calendar when you add, edit, delete, or complete them. Enable in Settings."
                )
                
                FeatureRow(
                    icon: "envelope",
                    title: "Send Feedback",
                    description: "Have suggestions or found a bug? Use the Feedback option in Settings to email us."
                )
            } header: {
                Label("Optional Features", systemImage: "gearshape.2")
            } footer: {
                Text("Configure these in Settings (tap the gear icon)")
            }
            
            // Pro Tips
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    TipRow(tip: "Always say AM or PM — \"3 PM\" is clearer than just \"3\"")
                    TipRow(tip: "Include the day if it's not today — \"tomorrow\", \"next Friday\"")
                    TipRow(tip: "Use \"in X minutes\" for quick reminders")
                    TipRow(tip: "Say \"with a 15 minute warning\" for important reminders")
                    TipRow(tip: "Use the keyboard option to set early alerts when typing")
                    TipRow(tip: "If the mic gets stuck, the app will automatically reset it")
                }
                .padding(.vertical, 4)
            } header: {
                Label("Pro Tips", systemImage: "lightbulb.fill")
            }
        }
        .navigationTitle("How to Use Nudge")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper Views

struct HelpRow: View {
    let title: String
    let examples: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(examples, id: \.self) { example in
                Text(example)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TimeFormatRow: View {
    let format: String
    let description: String
    
    var body: some View {
        HStack {
            Text(format)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
            Spacer()
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TipRow: View {
    let tip: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text(tip)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        HelpView()
    }
}
