import SwiftUI

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings

    @State private var closeoutTime: Date = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
    @State private var style: String = "sentence"
    @State private var wakeWordEnabled: Bool = false
    @State private var calendarSyncEnabled: Bool = false
    @State private var earlyAlertMinutes: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("\"Hey Nudge\" Voice Activation", isOn: $wakeWordEnabled)
                    Text("Say \"Hey Nudge\" to start recording hands-free.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Voice Activation")
                }
                
                Section {
                    Toggle("Sync with Calendar", isOn: $calendarSyncEnabled)
                    Text("Add reminders to Apple Calendar so you can see them alongside your events.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Calendar Integration")
                }
                
                Section {
                    Picker("Default early warning", selection: $earlyAlertMinutes) {
                        Text("None").tag(0)
                        Text("5 minutes before").tag(5)
                        Text("15 minutes before").tag(15)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                    }
                    Text("Get a heads-up notification before each reminder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Early Alerts")
                }
                
                Section("Daily Closeout") {
                    DatePicker("Closeout time", selection: $closeoutTime, displayedComponents: .hourAndMinute)
                    Text("Review uncompleted reminders at end of day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Writing Style") {
                    Picker("Reminder text", selection: $style) {
                        Text("Sentence Case").tag("sentence")
                        Text("Title Case").tag("title")
                        Text("ALL CAPS").tag("caps")
                    }
                }

                Section {
                    Button("Get Started") {
                        saveSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Set up Nudge")
        }
        .onAppear {
            style = settings.writingStyle
            closeoutTime = dateFromMinutesSinceMidnight(settings.dailyCloseoutMinutes)
            wakeWordEnabled = settings.wakeWordEnabled
            calendarSyncEnabled = settings.calendarSyncEnabled
            earlyAlertMinutes = settings.defaultEarlyAlertMinutes
        }
    }
    
    private func saveSettings() {
        settings.dailyCloseoutMinutes = minutesFromMidnight(closeoutTime)
        settings.writingStyle = style
        settings.wakeWordEnabled = wakeWordEnabled
        settings.defaultEarlyAlertMinutes = earlyAlertMinutes
        
        // Handle calendar sync with permission request
        if calendarSyncEnabled {
            Task {
                let granted = await CalendarSync.shared.requestAccess()
                await MainActor.run {
                    settings.calendarSyncEnabled = granted
                    settings.didCompleteOnboarding = true
                }
            }
        } else {
            settings.calendarSyncEnabled = false
            settings.didCompleteOnboarding = true
        }
    }
}
