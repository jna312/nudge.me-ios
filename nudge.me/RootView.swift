import SwiftUI
import SwiftData

enum AppTab: Int {
    case speak = 0
    case reminders = 1
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: AppSettings
    @StateObject private var notificationsManager = NotificationsManager.shared
    @StateObject private var sharedFlow = CaptureFlow()
    @StateObject private var sharedTranscriber = SpeechTranscriber()
    @State private var selectedTab: AppTab = .speak
    @State private var showSettings = false
    @State private var shouldAutoStartMic = false
    @State private var selectedReminderID: UUID?
    @Query(sort: \ReminderItem.createdAt) private var widgetItems: [ReminderItem]

    private var widgetValues: [SharedWidgetReminder] {
        widgetItems.map { SharedWidgetReminder(id: $0.id, title: $0.title, dueAt: $0.dueAt,
                                               isCompleted: $0.status != .open) }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // MAIN UI (Speak)
            NavigationStack {
                ContentView(isSettingsOpen: $showSettings, autoStartMic: $shouldAutoStartMic,
                    flow: sharedFlow, transcriber: sharedTranscriber,
                    onShowReminders: { selectedTab = .reminders })
                    .environmentObject(settings)
                    .sheet(isPresented: $showSettings) {
                        NavigationStack {
                            SettingsView(settings: settings)
                                .navigationTitle("Settings")
                        }
                    }
            }
            .tabItem { Label("Speak", systemImage: "mic.fill") }
            .tag(AppTab.speak)

            // Reminders
            NavigationStack {
                RemindersView(selectedReminderID: $selectedReminderID, onCapture: {
                    selectedTab = .speak
                    shouldAutoStartMic = true
                })
                    .environmentObject(settings)
            }
            .tabItem { Label("Reminders", systemImage: "list.bullet.circle") }
            .tag(AppTab.reminders)
        }
        .tint(NudgeDesign.accent)
        .onChange(of: widgetValues) { _, _ in
            // Includes edits and CloudKit changes observed while the app is running.
            WidgetDataProvider.shared.syncReminders(from: modelContext)
        }
        .onChange(of: notificationsManager.shouldNavigateToReminders) { _, shouldNavigate in
            if shouldNavigate {
                selectedTab = .reminders
                notificationsManager.shouldNavigateToReminders = false
            }
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .task {
            // Sync reminders to widget
            WidgetDataProvider.shared.syncReminders(from: modelContext)
            
            // Check for widget completions
            await WidgetDataProvider.shared.checkForWidgetCompletions(in: modelContext)
            
            await MorningBriefingManager.shared.scheduleIfNeeded(settings: settings, modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Check for widget completions when app becomes active
            Task {
                await WidgetDataProvider.shared.checkForWidgetCompletions(in: modelContext)
                WidgetDataProvider.shared.syncReminders(from: modelContext)
                await MorningBriefingManager.shared.scheduleIfNeeded(settings: settings, modelContext: modelContext)
            }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "nudgeme" else { return }
        
        switch url.host {
        case "voice":
            // Open to speak tab and auto-start mic
            selectedTab = .speak
            shouldAutoStartMic = true
            
        case "reminder":
            // Open specific reminder
            if let idString = url.pathComponents.last,
               let uuid = UUID(uuidString: idString) {
                selectedTab = .reminders
                selectedReminderID = uuid
            }
            
        case "reminders":
            // Just open reminders tab
            selectedTab = .reminders
            
        default:
            break
        }
    }
}
