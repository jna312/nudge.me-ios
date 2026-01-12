import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Daily closeout") {
                DatePicker(
                    "Closeout time",
                    selection: Binding(
                        get: { dateFromMinutes(settings.dailyCloseoutMinutes) },
                        set: { settings.dailyCloseoutMinutes = minutesFromMidnight($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                Text("Only triggers if you created reminders for that day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Writing style") {
                Picker("Reminder text", selection: $settings.writingStyle) {
                    Text("Sentence Case").tag("sentence")
                    Text("Title Case").tag("title")
                    Text("ALL CAPS").tag("caps")
                }
            }

            Section("Debug") {
                Button("Reset onboarding") {
                    settings.didCompleteOnboarding = false
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Settings")
    }

    private func minutesFromMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func dateFromMinutes(_ m: Int) -> Date {
        let h = m / 60
        let min = m % 60
        return Calendar.current.date(bySettingHour: h, minute: min, second: 0, of: Date())!
    }
}
