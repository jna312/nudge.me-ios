import SwiftUI
import AudioToolbox
import AVFAudio

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var lastTapped: String = "None"
    @State private var showingAlert = false

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

            Section("Defaults") {
                DatePicker(
                    "Date-only default time",
                    selection: Binding(
                        get: { dateFromMinutes(settings.defaultDateOnlyMinutes) },
                        set: { settings.defaultDateOnlyMinutes = minutesFromMidnight($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )

                Text("If you don't specify a time, we'll automatically set the reminder for \(formattedTime(from: settings.defaultDateOnlyMinutes)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(NotificationSoundOption.allCases) { option in
                    HStack {
                        Text(option.displayName)
                        Spacer()
                        if settings.notificationSound == option.rawValue {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        lastTapped = option.displayName
                        settings.notificationSound = option.rawValue
                        playSound(option)
                    }
                }
            } header: {
                Text("Notification Sound")
            } footer: {
                Text("Last tapped: \(lastTapped)")
                    .foregroundStyle(.orange)
            }

            Section("Writing style") {
                Picker("Reminder text", selection: $settings.writingStyle) {
                    Text("Sentence Case").tag("sentence")
                    Text("Title Case").tag("title")
                    Text("ALL CAPS").tag("caps")
                }
            }

            Section("Debug") {
                Text("Test Sound (ID 1007)")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        print("🔊 Testing sound...")
                        do {
                            let session = AVAudioSession.sharedInstance()
                            try session.setCategory(.ambient)
                            try session.setActive(true)
                        } catch {
                            print("🔊 Error: \(error)")
                        }
                        AudioServicesPlayAlertSound(1007)
                    }
                
                Text("Reset onboarding")
                    .foregroundStyle(.red)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        settings.didCompleteOnboarding = false
                    }
            }
        }
        .navigationTitle("Settings")
        .alert("Sound Tapped", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You tapped: \(lastTapped)")
        }
    }
    
    private func playSound(_ option: NotificationSoundOption) {
        showingAlert = true
        
        guard option != .silent else { return }
        
        let soundID = option.systemSoundID
        
        // Force reset audio session to allow playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
        } catch {
            // Ignore errors
        }
        
        // Play alert sound
        AudioServicesPlayAlertSound(soundID)
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

    private func formattedTime(from minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let date = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())!
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

