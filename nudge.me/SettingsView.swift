import SwiftUI
import EventKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: AppSettings
    @ObservedObject private var tipsManager = TipsManager.shared
    @State private var calendarAccessGranted = false
    @State private var showingSyncAlert = false
    @State private var syncMessage = ""
    @State private var isSyncing = false

    var body: some View {
        Form {
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
                        get: { dateFromMinutesSinceMidnight(settings.dailyCloseoutMinutes) },
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
                    .disabled(isSyncing)
                    .onChange(of: settings.calendarSyncEnabled) { _, enabled in
                        if enabled {
                            Task {
                                isSyncing = true
                                calendarAccessGranted = await CalendarSync.shared.requestAccess()
                                
                                if calendarAccessGranted {
                                    let result = await CalendarSync.shared.syncAllReminders(from: modelContext)
                                    syncMessage = "Synced \(result.synced) reminder\(result.synced == 1 ? "" : "s") to Calendar"
                                    if result.failed > 0 {
                                        syncMessage += " (\(result.failed) failed)"
                                    }
                                    showingSyncAlert = true
                                    // Start auto-sync
                                    CalendarSync.shared.startAutoSync(frequency: settings.calendarSyncFrequency, context: modelContext)
                                } else {
                                    syncMessage = "Calendar access denied. Please enable in Settings > Privacy > Calendars."
                                    showingSyncAlert = true
                                    settings.calendarSyncEnabled = false
                                }
                                isSyncing = false
                            }
                        } else {
                            // Stop auto-sync when disabled
                            CalendarSync.shared.stopAutoSync()
                        }
                    }
                
                if isSyncing {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Syncing...").font(.footnote).foregroundStyle(.secondary)
                    }
                } else if settings.calendarSyncEnabled {
                    Picker("Auto-sync frequency", selection: $settings.calendarSyncFrequency) {
                        Text("Every 15 minutes").tag(15)
                        Text("Every 30 minutes").tag(30)
                        Text("Every hour").tag(60)
                    }
                    .onChange(of: settings.calendarSyncFrequency) { _, newFrequency in
                        // Restart auto-sync with new frequency
                        CalendarSync.shared.startAutoSync(frequency: newFrequency, context: modelContext)
                    }
                    
                    Text("Reminders sync to a \"Nudge Reminders\" calendar in Apple Calendar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button("Sync Now") {
                        Task {
                            isSyncing = true
                            let result = await CalendarSync.shared.syncAllReminders(from: modelContext)
                            syncMessage = "Synced \(result.synced) reminder\(result.synced == 1 ? "" : "s")"
                            if result.failed > 0 { syncMessage += " (\(result.failed) failed)" }
                            showingSyncAlert = true
                            isSyncing = false
                        }
                    }
                } else {
                    Text("When enabled, reminders are added to Apple Calendar so you can see them alongside your events. A separate \"Nudge Reminders\" calendar is created.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Calendar Integration")
            }

            Section {
                Picker("Default early warning", selection: $settings.defaultEarlyAlertMinutes) {
                    Text("None").tag(0)
                    Text("5 minutes before").tag(5)
                    Text("15 minutes before").tag(15)
                    Text("30 minutes before").tag(30)
                    Text("1 hour before").tag(60)
                }
                
                Text("Receive a heads-up notification before each reminder. Useful for tasks that need preparation time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Early Alerts")
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

            Section {
                Button {
                    openFeedbackEmail()
                } label: {
                    Label("Send Feedback", systemImage: "envelope")
                }
            } header: {
                Text("Feedback")
            }
            
            Section("Advanced") {
                Button("Reset Tips") { tipsManager.resetAllTips() }
                Button("Reset Onboarding") { settings.didCompleteOnboarding = false }
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Settings")
        .alert("Calendar Sync", isPresented: $showingSyncAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(syncMessage)
        }
        .task {
            if settings.calendarSyncEnabled {
                calendarAccessGranted = await CalendarSync.shared.requestAccess()
            }
        }
    }

    private func openFeedbackEmail() {
        let email = "jna312@gmail.com"
        let subject = "NUDGE FEEDBACK: "
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        
        if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") {
            UIApplication.shared.open(url)
        }
    }
    
}

struct SiriShortcutsInfoView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle").font(.title3).foregroundStyle(.blue).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Create a Reminder").font(.subheadline).fontWeight(.medium)
                            Text("\"Hey Siri, Nudge me\"").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("Siri will ask:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. \"What do you want to be reminded about?\"")
                        Text("2. \"When should I remind you?\"")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Add a Nudge")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "list.bullet").font(.title3).foregroundStyle(.blue).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("List Reminders by Date").font(.subheadline).fontWeight(.medium)
                            Text("\"Hey Siri, list my Nudges for...\"").font(.caption).foregroundStyle(.secondary)
                            Text("\"Hey Siri, what are my Nudges for...\"").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• \"...for today\"")
                        Text("• \"...for tomorrow\"")
                        Text("• \"...for Friday\"")
                        Text("• \"...for January 20th\"")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
                }
                .padding(.vertical, 4)
            } header: {
                Text("List Nudges")
            }
            
            Section {
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Open Shortcuts App", systemImage: "arrow.up.forward.app")
                }
            } footer: {
                Text("Run the app once to register shortcuts with Siri.")
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
            Image(systemName: icon).font(.title3).foregroundStyle(.blue).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(phrase).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
