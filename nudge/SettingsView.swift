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
            
            Section {
                Toggle("Require \(BiometricAuth.shared.biometricType)", isOn: $settings.biometricLockEnabled)
                    .onChange(of: settings.biometricLockEnabled) { _, enabled in
                        if enabled {
                            Task {
                                let success = await BiometricAuth.shared.authenticate()
                                if !success {
                                    settings.biometricLockEnabled = false
                                }
                            }
                        }
                    }
                Text("Require \(BiometricAuth.shared.biometricType) to open Nudge.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Security")
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
                                } else {
                                    syncMessage = "Calendar access denied. Please enable in Settings > Privacy > Calendars."
                                    showingSyncAlert = true
                                    settings.calendarSyncEnabled = false
                                }
                                isSyncing = false
                            }
                        }
                    }
                
                if isSyncing {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Syncing...").font(.footnote).foregroundStyle(.secondary)
                    }
                } else if settings.calendarSyncEnabled {
                    Text("Reminders sync to \"Nudge Reminders\" calendar.")
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
                
                Text("Get a \"Coming Up\" notification before your main reminder alert.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Early Alerts")
            }
            
            Section {
                NavigationLink {
                    RingtonePickerView(selectedRingtone: $settings.selectedRingtone)
                } label: {
                    HStack {
                        Text("Reminder Sound")
                        Spacer()
                        Text(getRingtoneName(settings.selectedRingtone))
                            .foregroundStyle(.secondary)
                    }
                }
                
                Toggle("Alarm Mode", isOn: $settings.useAlarmMode)
                    .onChange(of: settings.useAlarmMode) { _, enabled in
                        if enabled {
                            Task {
                                await NotificationsManager.shared.requestAlarmKitPermission()
                            }
                        }
                    }
                
                if settings.useAlarmMode {
                    AlarmModeStatusView()
                } else {
                    Text("Sound plays once for up to 30 seconds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sound")
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

    private func minutesFromMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func dateFromMinutes(_ m: Int) -> Date {
        let h = m / 60
        let min = m % 60
        return Calendar.current.date(bySettingHour: h, minute: min, second: 0, of: Date())!
    }
    
    private func formatEarlyAlert(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hour"
        }
        return "\(minutes) minute"
    }
    
    private func openFeedbackEmail() {
        let email = "jna312@gmail.com"
        let subject = "NUDGE FEEDBACK: "
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        
        if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func getRingtoneName(_ id: String) -> String {
        if let ringtone = RingtoneManager.ringtone(for: id) {
            return ringtone.displayName
        }
        return "Standard"
    }
}

/// Shows AlarmKit status and capabilities
struct AlarmModeStatusView: View {
    @StateObject private var alarmManager = AlarmKitManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if alarmManager.isAlarmKitAvailable {
                if alarmManager.isAuthorized {
                    Label("Alarm Mode Active", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                    Text("Reminders will ring until you dismiss them, even on lock screen and silent mode.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Permission Required", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Text("Enable alarm permissions in Settings to use this feature.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.footnote)
                }
            } else {
                Label("Requires iOS 26+", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Alarm Mode requires iOS 26 or later. Standard notifications will play sound for up to 30 seconds.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SiriShortcutsInfoView: View {
    var body: some View {
        List {
            Section {
                ShortcutRow(title: "Add a Nudge", phrase: "\"Hey Siri, add a nudge\"", icon: "plus.circle")
                ShortcutRow(title: "List My Nudges", phrase: "\"Hey Siri, show my nudges\"", icon: "list.bullet")
                ShortcutRow(title: "Quick Nudge", phrase: "\"Hey Siri, quick nudge\" (1 hour)", icon: "clock")
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
            Image(systemName: icon).font(.title3).foregroundStyle(.blue).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(phrase).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
