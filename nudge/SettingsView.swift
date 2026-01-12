import SwiftUI
import EventKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var calendarAccessGranted = false
    @State private var showingImportAlert = false
    @State private var importedCount = 0

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
            
            Section {
                Toggle("\"Hey Nudge\" Wake Word", isOn: $settings.wakeWordEnabled)
                Text("Say \"Hey Nudge\" to start recording hands-free. Requires microphone access in background.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Voice Activation")
            }
            
            Section {
                Toggle("Sync with Calendar", isOn: $settings.calendarSyncEnabled)
                    .onChange(of: settings.calendarSyncEnabled) { _, enabled in
                        if enabled {
                            Task {
                                calendarAccessGranted = await CalendarSync.shared.requestAccess()
                                if !calendarAccessGranted {
                                    settings.calendarSyncEnabled = false
                                }
                            }
                        }
                    }
                
                if settings.calendarSyncEnabled {
                    Text("Reminders will be added to a \"Nudge Reminders\" calendar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button("Import from Calendar") {
                        importFromCalendar()
                    }
                }
            } header: {
                Text("Calendar Integration")
            }

            Section("Writing style") {
                Picker("Reminder text", selection: $settings.writingStyle) {
                    Text("Sentence Case").tag("sentence")
                    Text("Title Case").tag("title")
                    Text("ALL CAPS").tag("caps")
                }
            }
            
            Section {
                NavigationLink("Siri Shortcuts") {
                    SiriShortcutsInfoView()
                }
            } header: {
                Text("Shortcuts")
            }

            Section("Debug") {
                Button("Reset onboarding") {
                    settings.didCompleteOnboarding = false
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Settings")
        .alert("Imported \(importedCount) events", isPresented: $showingImportAlert) {
            Button("OK", role: .cancel) { }
        }
        .task {
            if settings.calendarSyncEnabled {
                calendarAccessGranted = await CalendarSync.shared.requestAccess()
            }
        }
    }
    
    private func importFromCalendar() {
        Task {
            // Need to get model context - this should be passed in or use environment
            // For now, show info about how to import
            showingImportAlert = true
        }
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

struct SiriShortcutsInfoView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Add a Nudge", systemImage: "plus.circle")
                        .font(.headline)
                    Text("\"Hey Siri, add a nudge in Nudge\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("List My Nudges", systemImage: "list.bullet")
                        .font(.headline)
                    Text("\"Hey Siri, show my nudges in Nudge\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Quick Nudge", systemImage: "clock")
                        .font(.headline)
                    Text("\"Hey Siri, quick nudge in Nudge\"")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Available Shortcuts")
            } footer: {
                Text("You can also find these in the Shortcuts app under \"Nudge\".")
            }
            
            Section {
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Open Shortcuts App", systemImage: "arrow.up.forward.app")
                }
            }
        }
        .navigationTitle("Siri Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
