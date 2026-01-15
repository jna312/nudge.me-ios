import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings

    @State private var closeoutTime: Date = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
    @State private var style: String = "sentence"

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily closeout") {
                    DatePicker("Closeout time", selection: $closeoutTime, displayedComponents: .hourAndMinute)
                    Text("Only triggers if you created reminders for that day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Writing style") {
                    Picker("Reminder text", selection: $style) {
                        Text("Sentence Case").tag("sentence")
                        Text("Title Case").tag("title")
                        Text("ALL CAPS").tag("caps")
                    }
                }

                Section {
                    Button("Continue") {
                        settings.dailyCloseoutMinutes = minutesFromMidnight(closeoutTime)
                        settings.writingStyle = style
                        settings.didCompleteOnboarding = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Set up Nudge")
        }
        .onAppear {
            style = settings.writingStyle
            closeoutTime = dateFromMinutesSinceMidnight(settings.dailyCloseoutMinutes)
        }
    }

}
