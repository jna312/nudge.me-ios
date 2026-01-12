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
                        "\"Call mom at 5, warn me 30 minutes before\""
                    ]
                )
                
                HelpRow(
                    title: "Edit a reminder",
                    examples: [
                        "\"Change dentist to 4 PM\"",
                        "\"Move groceries to tomorrow\"",
                        "\"Reschedule meeting to 10 AM\""
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
                Text("Always specify a time — Nudge will ask if you forget!")
            }
            
            // Features
            Section {
                FeatureRow(
                    icon: "hand.tap.fill",
                    title: "Hold to Speak",
                    description: "Hold the mic button, speak your reminder, release to save."
                )
                
                FeatureRow(
                    icon: "mic.badge.plus",
                    title: "Auto-Listen",
                    description: "When Nudge asks a follow-up question, the mic starts automatically and stops when you finish speaking."
                )
                
                FeatureRow(
                    icon: "bell.badge",
                    title: "Early Alerts",
                    description: "Get a \"heads up\" notification before your reminder. Say \"with a 15 minute warning\" or set a default in Settings."
                )
                
                FeatureRow(
                    icon: "keyboard",
                    title: "Type Instead",
                    description: "Tap \"Type instead\" to add reminders manually with the keyboard."
                )
                
                FeatureRow(
                    icon: "arrow.uturn.backward",
                    title: "Undo",
                    description: "Made a mistake? Tap \"Undo\" within 5 seconds to delete."
                )
                
                FeatureRow(
                    icon: "checkmark.circle",
                    title: "Complete Reminders",
                    description: "Tap the circle next to any reminder to mark it done."
                )
                
                FeatureRow(
                    icon: "hand.draw",
                    title: "Swipe Actions",
                    description: "Swipe left to delete, swipe right to snooze."
                )
            } header: {
                Label("Features", systemImage: "star.fill")
            }
            
            // Smart Features
            Section {
                FeatureRow(
                    icon: "doc.on.doc",
                    title: "Duplicate Detection",
                    description: "Nudge warns you if you're creating a similar reminder."
                )
                
                FeatureRow(
                    icon: "calendar.badge.exclamationmark",
                    title: "Calendar Conflicts",
                    description: "Get a heads up if your reminder overlaps with calendar events."
                )
                
                FeatureRow(
                    icon: "lightbulb",
                    title: "Smart Suggestions",
                    description: "Nudge learns your preferred times and suggests them."
                )
            } header: {
                Label("Smart Features", systemImage: "brain")
            }
            
            // Optional Features
            Section {
                FeatureRow(
                    icon: "bell.and.waves.left.and.right",
                    title: "Default Early Alert",
                    description: "Set a default warning time in Settings so every reminder gets a heads up automatically."
                )
                
                FeatureRow(
                    icon: "waveform",
                    title: "\"Hey Nudge\"",
                    description: "Enable in Settings to start recording hands-free by saying \"Hey Nudge\"."
                )
                
                FeatureRow(
                    icon: "calendar",
                    title: "Calendar Sync",
                    description: "Sync reminders to Apple Calendar as events. Enable in Settings."
                )
                
                FeatureRow(
                    icon: "faceid",
                    title: "Face ID / Touch ID",
                    description: "Lock Nudge with biometrics. Enable in Settings → Security."
                )
                
                FeatureRow(
                    icon: "apps.iphone",
                    title: "Siri Shortcuts",
                    description: "Say \"Hey Siri, add a nudge\" to create reminders from anywhere."
                )
            } header: {
                Label("Optional Features", systemImage: "gearshape.2")
            } footer: {
                Text("Configure these in Settings (tap the gear icon)")
            }
            
            // Tips
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    TipRow(tip: "Be specific with times — \"3 PM\" works better than \"afternoon\"")
                    TipRow(tip: "Include the day if it's not today — \"tomorrow\", \"next Friday\"")
                    TipRow(tip: "Use \"in X minutes\" for quick reminders")
                    TipRow(tip: "Add \"with a 15 minute warning\" to get a heads up before important reminders")
                    TipRow(tip: "Set a default early alert in Settings so you never miss anything")
                    TipRow(tip: "The daily closeout at 9 PM helps you review uncompleted reminders")
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
