import SwiftUI
import EventKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var tipsManager = TipsManager.shared
    @State private var calendarAccessGranted = false
    @State private var showingImportAlert = false
    @State private var importedCount = 0

    var body: some View {
        Form {
            // Help & Instructions - At the top for visibility
            Section {
                NavigationLink {
                    HelpView()
                } label: {
                    Label("How to Use Nudge", systemImage: "questionmark.circle")
                }
            }
            
            Section("Daily closeout") {
                DatePicker(
                    "Closeout time",
                    selection: Binding(
                        get: { dateFromMinutes(settings.dailyCloseoutMinutes) },
                        set: { settings.dailyCloseoutMinutes = minutesFromMidnight($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                Text("Review uncompleted reminders at end of day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                Toggle("\"Hey Nudge\" Wake Word", isOn: $settings.wakeWordEnabled)
                Text("Say \"Hey Nudge\" to start recording hands-free.")
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
                    Text("Reminders sync to \"Nudge Reminders\" calendar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

            Section("Advanced") {
                Button("Reset Tips") {
                    tipsManager.resetAllTips()
                }
                
                Button("Reset Onboarding") {
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
                ShortcutRow(
                    title: "Add a Nudge",
                    phrase: "\"Hey Siri, add a nudge in Nudge\"",
                    icon: "plus.circle"
                )
                
                ShortcutRow(
                    title: "List My Nudges",
                    phrase: "\"Hey Siri, show my nudges\"",
                    icon: "list.bullet"
                )
                
                ShortcutRow(
                    title: "Quick Nudge",
                    phrase: "\"Hey Siri, quick nudge\" (1 hour)",
                    icon: "clock"
                )
            } header: {
                Text("Available Shortcuts")
            } footer: {
                Text("Find these in the Shortcuts app under \"Nudge\".")
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

struct ShortcutRow: View {
    let title: String
    let phrase: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(phrase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
